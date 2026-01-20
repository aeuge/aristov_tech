--- триггеры для итоговых продаж
-- Модель измерений / dimensional modeling
-- сравнение моделей
-- https://bilab.ru/sravnitelnyi-analiz-podhodov-k-modelirovaniyu-dwh
--
-- Основные таблицы: таблица временных периодов и таблица фактов продаж
--
DROP TABLE IF EXISTS time_dimension;
DROP TABLE IF EXISTS sales_fact;
DROP TABLE IF EXISTS sales_summary_bytime;

CREATE TABLE time_dimension (
    time_key                    integer NOT NULL,
    day_of_week                 integer NOT NULL,
    day_of_month                integer NOT NULL,
    month                       integer NOT NULL,
    quarter                     integer NOT NULL,
    year                        integer NOT NULL
);
CREATE UNIQUE INDEX time_dimension_key ON time_dimension(time_key);

CREATE TABLE sales_fact (
    time_key                    integer NOT NULL,
    product_key                 integer NOT NULL,
    store_key                   integer NOT NULL,
    amount_sold                 numeric(12,2) NOT NULL,
    units_sold                  integer NOT NULL,
    amount_cost                 numeric(12,2) NOT NULL
);
CREATE INDEX sales_fact_time ON sales_fact(time_key);

--
-- Таблица с итогами продаж по периодам
--
CREATE TABLE sales_summary_bytime (
    time_key                    integer NOT NULL,
    amount_sold                 numeric(15,2) NOT NULL,
    units_sold                  numeric(12) NOT NULL,
    amount_cost                 numeric(15,2) NOT NULL
);
CREATE UNIQUE INDEX sales_summary_bytime_key ON sales_summary_bytime(time_key);

--
-- Функция и триггер для пересчёта столбцов итогов при выполнении
-- команд INSERT, UPDATE, DELETE
--
CREATE OR REPLACE FUNCTION maint_sales_summary_bytime() RETURNS TRIGGER
AS $maint_sales_summary_bytime$
    DECLARE
        delta_time_key          integer;
        delta_amount_sold       numeric(15,2);
        delta_units_sold        numeric(12);
        delta_amount_cost       numeric(15,2);
    BEGIN

        -- Вычислить изменение количества/суммы.
        IF (TG_OP = 'DELETE') THEN

            delta_time_key = OLD.time_key;
            delta_amount_sold = -1 * OLD.amount_sold;
            delta_units_sold = -1 * OLD.units_sold;
            delta_amount_cost = -1 * OLD.amount_cost;

        ELSIF (TG_OP = 'UPDATE') THEN

            -- Запретить изменение time_key -
            -- (это ограничение не должно вызвать неудобств, так как
            -- в основном изменения будут выполняться по схеме DELETE + INSERT).
            IF ( OLD.time_key != NEW.time_key) THEN
                RAISE EXCEPTION 'UPDATE of time_key : % -> % not allowed',
                                                      OLD.time_key, NEW.time_key;
            END IF;

            delta_time_key = OLD.time_key;
            delta_amount_sold = NEW.amount_sold - OLD.amount_sold;
            delta_units_sold = NEW.units_sold - OLD.units_sold;
            delta_amount_cost = NEW.amount_cost - OLD.amount_cost;

        ELSIF (TG_OP = 'INSERT') THEN

            delta_time_key = NEW.time_key;
            delta_amount_sold = NEW.amount_sold;
            delta_units_sold = NEW.units_sold;
            delta_amount_cost = NEW.amount_cost;

        END IF;


        -- Внести новые значения в существующую строку итогов или
        -- добавить новую.
        <<insert_update>>
        LOOP
            UPDATE sales_summary_bytime
                SET amount_sold = amount_sold + delta_amount_sold,
                    units_sold = units_sold + delta_units_sold,
                    amount_cost = amount_cost + delta_amount_cost
                WHERE time_key = delta_time_key;

            EXIT insert_UPDATE WHEN found;

            BEGIN
                INSERT INTO sales_summary_bytime (
                            time_key,
                            amount_sold,
                            units_sold,
                            amount_cost)
                    VALUES (
                            delta_time_key,
                            delta_amount_sold,
                            delta_units_sold,
                            delta_amount_cost
                           );

                EXIT insert_update;

            EXCEPTION
                WHEN UNIQUE_VIOLATION THEN
                    -- ничего не делать
            END;
        END LOOP insert_update;

        RETURN NULL;

    END;
$maint_sales_summary_bytime$ LANGUAGE plpgsql;

CREATE TRIGGER maint_sales_summary_bytime
AFTER INSERT OR UPDATE OR DELETE ON sales_fact
    FOR EACH ROW EXECUTE FUNCTION maint_sales_summary_bytime();

INSERT INTO sales_fact VALUES(1,1,1,10,3,15);
INSERT INTO sales_fact VALUES(1,2,1,20,5,35);
INSERT INTO sales_fact VALUES(2,2,1,40,15,135);
INSERT INTO sales_fact VALUES(2,3,1,10,1,13);
SELECT * FROM sales_summary_bytime;
DELETE FROM sales_fact WHERE product_key = 1;
SELECT * FROM sales_summary_bytime;
UPDATE sales_fact SET units_sold = units_sold * 2;
SELECT * FROM sales_summary_bytime;



-- Маскирование чувствительных данных для тестовых сред
drop table if exists users1;
create table users1 (id serial, name text, email text,last_processed timestamp, status text default 'active');
insert into users1 (name,email) values ('ivan','email1'),('petr','email2');

drop table if exists data_masking_rules;
create table if not exists data_masking_rules(table_schema text,table_name text, column_name text, mask_type text);
insert into data_masking_rules values ('public','users1','email','email');

CREATE OR REPLACE FUNCTION mask_sensitive_data(schema_name TEXT)
RETURNS TABLE(masked_tables TEXT, masked_rows BIGINT) AS $$
DECLARE
    table_record RECORD;
    mask_query TEXT;
    row_count BIGINT;
BEGIN
    FOR table_record IN 
        SELECT table_name, column_name, mask_type
        FROM data_masking_rules 
        WHERE table_schema = schema_name
    LOOP
        mask_query := format(
            'UPDATE %I.%I SET %I = %s WHERE %I IS NOT NULL',
            schema_name, 
            table_record.table_name, 
            table_record.column_name,
            CASE table_record.mask_type
                WHEN 'email' THEN format('''masked-'' || MD5(%I::text) || ''@example.com''', table_record.column_name)
                WHEN 'phone' THEN '''+1-555-'' || LPAD((floor(random()*9999))::INTEGER::TEXT, 4, ''0'')'
                WHEN 'name' THEN format('''Customer-'' || MD5(%I::text)', table_record.column_name)
                WHEN 'address' THEN format('''Address-'' || MD5(%I::text)', table_record.column_name)
                ELSE '''MASKED'''
            END,
            table_record.column_name
        );
        
        EXECUTE mask_query;
        GET DIAGNOSTICS row_count = ROW_COUNT;
        
        masked_tables := schema_name || '.' || table_record.table_name;
        masked_rows := row_count;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select mask_sensitive_data('public');
table public.users1;


-- Умное переиндексирование на основе статистики
CREATE OR REPLACE FUNCTION smart_reindexing()
RETURNS TABLE(reindexed_tables TEXT, index_size TEXT) AS $$
DECLARE
    index_record RECORD;
    reindex_command TEXT;
BEGIN
    FOR index_record IN 
        SELECT 
            schemaname, relname, indexrelname,
            pg_size_pretty(pg_relation_size(indexrelname::regclass)) as size,
            idx_scan, idx_tup_read, idx_tup_fetch
        FROM pg_stat_user_indexes 
        WHERE idx_scan < 1000  -- Редко используемые индексы
        AND pg_relation_size(indexrelname::regclass) > 1000  -- Больше 1KB
        AND schemaname = 'public'
    LOOP
        -- REINDEX CONCURRENTLY чтобы избежать блокировок
        reindex_command := format('REINDEX INDEX CONCURRENTLY %I.%I', 
                                index_record.schemaname, index_record.indexrelname);
        
        BEGIN
            EXECUTE reindex_command;
            
            reindexed_tables := index_record.tablename || '.' || index_record.indexrelname;
            index_size := index_record.size;
            RETURN NEXT;
            
	        EXCEPTION
	            WHEN others THEN
	                RAISE NOTICE 'Не удалось переиндексировать %: %', 
	                            index_record.indexrelname, SQLERRM;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select smart_reindexing();

-- ERROR: REINDEX CONCURRENTLY cannot be executed from a function

CREATE OR REPLACE PROCEDURE smart_reindexing()
AS $$
DECLARE
    index_record RECORD;
    reindex_command TEXT;
	reindexed_tables TEXT;
	index_size INT;
BEGIN
    FOR index_record IN 
        SELECT 
            schemaname, relname, indexrelname,
            pg_size_pretty(pg_relation_size(indexrelname::regclass)) as size,
            idx_scan, idx_tup_read, idx_tup_fetch
        FROM pg_stat_user_indexes 
        WHERE idx_scan < 1000  -- Редко используемые индексы
        AND pg_relation_size(indexrelname::regclass) > 1000  -- Больше 1KB
        AND schemaname = 'public'
    LOOP
        -- REINDEX CONCURRENTLY чтобы избежать блокировок
        reindex_command := format('REINDEX INDEX CONCURRENTLY %I.%I', 
                                index_record.schemaname, index_record.indexrelname);
        
            EXECUTE reindex_command;
            
            reindexed_tables := index_record.tablename || '.' || index_record.indexrelname;
            index_size := index_record.size;
            RAISE NOTICE '%.%', reindexed_tables, index_size;
            
    END LOOP;
END;
$$ LANGUAGE plpgsql;

drop function smart_reindexing();
call smart_reindexing();

-- ERROR: REINDEX CONCURRENTLY cannot run inside a transaction block

-- surprise mazafaka )
-- use autocommit and foreign application

DO $$
BEGIN
	REINDEX INDEX CONCURRENTLY public.ddl_audit_log_pkey;
END;
$$;

create function test_conc() returns void as 
'REINDEX INDEX CONCURRENTLY public.ddl_audit_log_pkey;' language sql;

select test_conc();

-- what to do?
-- 1. Используем dblink для выполнения вне транзакции
            PERFORM dblink_connect('reindex_conn', 'dbname=' || current_database());
            PERFORM dblink_exec('reindex_conn', reindex_command);
            PERFORM dblink_disconnect('reindex_conn');

-- 2. pg_cron
-- sudo apt-get -y install postgresql-16-cron
-- https://github.com/citusdata/pg_cron/releases
PERFORM cron.schedule(
            format('REINDEX INDEX CONCURRENTLY %I.%I', 
                  index_record.schemaname, index_record.indexrelname),
            NOW() + (random() * interval '10 minutes')  -- Случайная задержка
        );




