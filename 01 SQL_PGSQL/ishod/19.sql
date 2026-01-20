-- В код PL/pgSQL можно встраивать команды SQL. Наверное, наиболее часто используемый вариант - 
-- команда SELECT, возвращающая одну строку. 
-- Пример, который не получилось бы выполнить с помощью выражения с подзапросом (потому что возвращаются сразу два значения):
DROP TABLE IF EXISTS t;
CREATE TABLE t(id integer, code text);
INSERT INTO t VALUES (1, 'Один'), (3, 'Три');

-- анонимная процедура
DO $$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO r FROM t WHERE id = 1;
    RAISE NOTICE '%', r;
END;
$$;

CREATE OR REPLACE FUNCTION fmt_out_2 (IN phone text, OUT code text, OUT num text)
-- RETURNS можно не писать, предполагается RETURNS record
AS $$
BEGIN
    IF phone ~ '^[0-9]*$' AND length(phone) = 10 THEN
    --  ^[0-9]{10}$ - сразу проверить и количество символов
        code := substr(phone,1,3);
        num  := substr(phone,4);
    ELSE
        code := NULL;
        num  := NULL;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Условный оператор CASE (анонимный блок)
DO $$
DECLARE
    code text := (fmt_out_2('9992128506')).code; -- сразу обращаемся к возвращаемой переменной из функции через .
BEGIN
    CASE code
    WHEN '495', '499' THEN
        RAISE NOTICE '% - Москва', code;
    WHEN '812' THEN
        RAISE NOTICE '% - Санкт-Петербург', code;
    WHEN '384' THEN
        RAISE NOTICE '% - Кемеровская область', code;
    END CASE;
END;
$$;



-- варианты с использованием OUT переменных из процедур сразу в переменную 
-- Процедура, возвращающая несколько значений:
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (id serial, order_id int, quantity int, unit_price numeric);
insert into order_items values (1,1,10,100),(2,123,20,200),(3,123,30,50);

CREATE OR REPLACE PROCEDURE calculate_order_stats(
    order_id INTEGER,
    OUT total_amount NUMERIC,
    OUT item_count INTEGER,
    OUT average_price NUMERIC
)
AS $$
BEGIN
    SELECT 
        SUM(oi.quantity * oi.unit_price),
        COUNT(oi.id),
        AVG(oi.unit_price)
    INTO
        total_amount,
        item_count,
        average_price
    FROM order_items oi
    WHERE oi.order_id = calculate_order_stats.order_id;
    
    IF total_amount IS NULL THEN
        RAISE EXCEPTION 'Заказ с ID % не найден', order_id;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Вызов с получением выходных параметров
-- вывод на экран
CALL calculate_order_stats(123, NULL, NULL, NULL);

-- вопрос как использовать полученные значения? 
-- для этого вызов должен быть из другой процедуры или анонимной процедуры(следующая лекция)
DO $$
DECLARE
    total NUMERIC;
    count INTEGER;
    avg_price NUMERIC;
    i int;
BEGIN
    i = 123;
    CALL calculate_order_stats(i, total, count, avg_price);
    RAISE NOTICE 'Заказ %: сумма=%, товаров=%, средняя цена=%',i, total, count, avg_price;
END $$;

-- С указанием языка:
DO $$
BEGIN
    INSERT INTO log_messages (message, created_at) 
    VALUES ('Анонимная процедура выполнена', CURRENT_TIMESTAMP);
END $$ LANGUAGE plpgsql;


-- Разовая очистка данных:
DO $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Удаляем старые логи
    DELETE FROM audit_log 
    WHERE created_at < CURRENT_DATE - INTERVAL '1 year';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Удалено % старых записей из audit_log', deleted_count;
    
    -- Очищаем временные данные
    DELETE FROM temp_sessions 
    WHERE expires_at < CURRENT_TIMESTAMP;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Удалено % просроченных сессий', deleted_count;
END $$;

-- Проверка и обслуживание:
DO $$
DECLARE
    db_size TEXT;
    table_count INTEGER;
    index_count INTEGER;
    table_name TEXT;
    table_size TEXT;
BEGIN
    -- Статистика базы данных
    SELECT 
        pg_size_pretty(pg_database_size(current_database())),
        COUNT(*) FILTER (WHERE t.schemaname = 'public'),
        COUNT(*) FILTER (WHERE t.schemaname = 'public' AND indexname IS NOT NULL)
    INTO db_size, table_count, index_count
    FROM pg_tables t
    FULL JOIN pg_indexes i ON t.tablename = i.indexname;
    
    RAISE NOTICE 'Размер БД: %', db_size;
    RAISE NOTICE 'Таблиц: %, Индексов: %', table_count, index_count;
    
END $$;


-- Транзакции в DO блоке:
DO $$
BEGIN
    -- Начало транзакции (неявно)
    
    -- Резервное копирование перед изменением
    CREATE TEMP TABLE users_backup AS 
    SELECT * FROM users WHERE department = 'HR';
    
    RAISE NOTICE 'Создана резервная копия: % записей', 
                 (SELECT COUNT(*) FROM users_backup);
    
    -- Массовое обновление
    UPDATE users 
    SET salary = salary * 1.1 
    WHERE department = 'HR';
    
    RAISE NOTICE 'Обновлены зарплаты для HR отдела';
    
    -- Проверка целостности
    IF EXISTS(SELECT 1 FROM users WHERE salary > 1000000) THEN
        RAISE EXCEPTION 'Обнаружена некорректная зарплата';
    END IF;
    
    -- Если дойдем сюда, COMMIT выполнится автоматически
    RAISE NOTICE 'Транзакция завершена успешно';
    
EXCEPTION
    WHEN others THEN
        RAISE NOTICE 'Ошибка: %, откат транзакции', SQLERRM;
        -- ROLLBACK выполнится автоматически
END $$;

-- Работа с файловой системой:
\! mkdir '/var/lib/postgresql/postgres_export/'
\! rm -rf '/var/lib/postgresql/postgres_export/'

DO $$
DECLARE
    export_path TEXT := '/var/lib/postgresql/postgres_export/';
    export_file TEXT;
    table_record RECORD;
    copy_result TEXT;
BEGIN
    -- содержимое каталога
    PERFORM FROM pg_ls_dir(export_path);
    
    RAISE NOTICE 'Экспорт данных в %', export_path;
    
    -- Экспорт каждой таблицы
    FOR table_record IN 
        SELECT tablename FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename
    LOOP
        export_file := export_path || table_record.tablename || '.csv';
        
        RAISE NOTICE 'Экспорт таблицы % в %', 
                     table_record.tablename, export_file;
        
        BEGIN
            EXECUTE format(
                'COPY %I TO %L WITH CSV HEADER',
                table_record.tablename,
                export_file
            );
            
            RAISE NOTICE '  ✓ Успешно';
            
        EXCEPTION
            WHEN others THEN
                RAISE NOTICE '  ✗ Ошибка: %', SQLERRM;
        END;
    END LOOP;
    
    RAISE NOTICE 'Экспорт завершен';
END $$;

\! ls -la '/var/lib/postgresql/postgres_export/'