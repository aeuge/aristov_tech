-- Процедуры
-- простая процедура
DROP TABLE IF EXISTS tbl;
CREATE TABLE tbl (i int);

CREATE or replace PROCEDURE insert_data(a integer, b integer)
LANGUAGE SQL
AS $$
INSERT INTO tbl VALUES (a);
INSERT INTO tbl VALUES (b);
$$;


-- вызовем процедуру используя CALL
CALL insert_data(1, 2);

SELECT * FROM tbl;

-- посложнее
DROP TABLE IF EXISTS users;
CREATE TABLE users (name text, email text, department text, created_at timestamp);

CREATE OR REPLACE PROCEDURE add_user(
    user_name TEXT,
    user_email TEXT,
    user_department TEXT DEFAULT 'General'
)
AS $$
BEGIN
    INSERT INTO users (name, email, department, created_at)
    VALUES (user_name, user_email, user_department, CURRENT_TIMESTAMP);
    
    RAISE NOTICE 'Пользователь % добавлен в отдел %', user_name, user_department;
END;
$$ LANGUAGE plpgsql;

-- Вызов процедуры
CALL add_user('Иван Петров', 'ivan@company.com', 'IT');
CALL add_user('Мария Сидорова', 'maria@company.com');

table users;


-- варианты с использованием OUT переменных
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



-- более сложная процедура:
CREATE OR REPLACE PROCEDURE transfer_money(
    from_account INTEGER,
    to_account INTEGER,
    amount NUMERIC(10,2)
)
AS $$
DECLARE
    current_balance NUMERIC(10,2);
BEGIN
    -- Проверяем баланс
    SELECT balance INTO current_balance 
    FROM accounts 
    WHERE id = from_account
    FOR UPDATE;  -- Блокируем запись
    
    IF current_balance < amount THEN
        RAISE EXCEPTION 'Недостаточно средств на счете %', from_account; -- 26 тема
    END IF;
    
    -- Списание
    UPDATE accounts 
    SET balance = balance - amount 
    WHERE id = from_account;
    
    -- Зачисление
    UPDATE accounts 
    SET balance = balance + amount 
    WHERE id = to_account;
    
    -- Логируем операцию
    INSERT INTO transactions (from_account, to_account, amount, created_at)
    VALUES (from_account, to_account, amount, CURRENT_TIMESTAMP);
    
    RAISE NOTICE 'Перевод % со счета % на счет % выполнен', amount, from_account, to_account;
    
    -- COMMIT выполняется автоматически при успешном завершении
END;
$$ LANGUAGE plpgsql;

-- Вызов
CALL transfer_money(1, 2, 1000.00);


-- прод
-- Процедура управления индексами:
CREATE OR REPLACE PROCEDURE rebuild_fragmented_indexes(fragmentation_threshold NUMERIC DEFAULT 30)
AS $$
DECLARE
    index_record RECORD;
    rebuild_sql TEXT;
BEGIN
    FOR index_record IN 
        SELECT 
            schemaname,
            indexname,
            tablename,
            -- Простая эвристика для определения фрагментации
            (random() * 100) as estimated_fragmentation
        FROM pg_indexes 
        WHERE schemaname = 'public'
    LOOP
        IF index_record.estimated_fragmentation > fragmentation_threshold THEN
            RAISE NOTICE 'Перестроение индекса: % (фрагментация: %%)', 
                         index_record.indexname, 
                         index_record.estimated_fragmentation::INTEGER;
            
            rebuild_sql := format(
                'REINDEX INDEX %I.%I',
                index_record.schemaname,
                index_record.indexname
            );
            
            BEGIN
                EXECUTE rebuild_sql;
                RAISE NOTICE 'Индекс % перестроен', index_record.indexname;
                
            EXCEPTION
                WHEN others THEN
                    RAISE NOTICE 'Ошибка перестроения индекса %: %', 
                                 index_record.indexname, SQLERRM;
            END;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;