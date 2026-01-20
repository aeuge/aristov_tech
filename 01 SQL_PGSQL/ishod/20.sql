-- Автоматическое управление транзакциями:
CREATE OR REPLACE PROCEDURE automatic_transaction_example()
AS $$
BEGIN
    -- Начало транзакции (неявно)
    INSERT INTO accounts (id, balance) VALUES (1, 1000);
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;
    
    -- Если все успешно - COMMIT
    -- Если ошибка - ROLLBACK
END;
$$ LANGUAGE plpgsql;

-- drop procedure insert_data();
CREATE or replace PROCEDURE insert_data(a int)
AS $$
BEGIN
    FOR I in 1..10000 LOOP
        INSERT INTO tbl VALUES (I);
        IF a = 1 THEN 
            COMMIT; 
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- вызовем процедуру используя CALL
\echo :AUTOCOMMIT
\timing
CALL insert_data(1);
CALL insert_data(0);


-- Явное управление транзакциями:
CREATE OR REPLACE PROCEDURE explicit_transaction_control()
AS $$
BEGIN
    -- Можно использовать COMMIT и ROLLBACK
    INSERT INTO log_entries (message) VALUES ('Начало процедуры');
    
    COMMIT;  -- Фиксируем первую часть
    
    INSERT INTO important_data (data) VALUES ('Критические данные');
    
    -- В случае ошибки здесь, первая часть уже закоммичена
END;
$$ LANGUAGE plpgsql;



-- Процедура с явным управлением транзакциями:
create table if not exists temporary_data();
create table if not exists products(price decimal, category text);
insert into products values (100,'Electronics');

CREATE OR REPLACE PROCEDURE process_batch_operations()
AS $$
BEGIN
    -- Начало транзакции (неявно)
    
    -- Операция 1
    UPDATE products SET price = price * 1.1 WHERE category = 'Electronics';
    
    -- Сохраняем точку сохранения
    DECLARE
        savepoint_name TEXT := 'before_risky_operation';
    BEGIN
        SAVEPOINT before_risky_operation;
        
        -- Рискованная операция
        DELETE FROM temporary_data WHERE created_at < CURRENT_DATE - INTERVAL '30 days';
        
        -- Если все хорошо, продолжаем
        EXCEPTION -- тема 26
            WHEN others THEN
                ROLLBACK TO SAVEPOINT before_risky_operation;
                RAISE NOTICE 'Откат рискованной операции, продолжаем...';
    END;
    
    -- Операция 3 (выполнится в любом случае)
    INSERT INTO audit_log (operation, details) 
    VALUES ('batch_processing', 'Batch operations completed');
    
    -- COMMIT выполнится автоматически
END;
$$ LANGUAGE plpgsql;

-- Вложенные точки сохранения:
CREATE OR REPLACE PROCEDURE nested_savepoints()
AS $$
BEGIN
    INSERT INTO process_log (step) VALUES ('Начало');
    
    SAVEPOINT sp1;
    BEGIN
        INSERT INTO process_log (step) VALUES ('Шаг 1');
        
        SAVEPOINT sp2;
        BEGIN
            INSERT INTO process_log (step) VALUES ('Шаг 2 - рискованный');
            
            -- Имитация ошибки
            IF random() < 0.5 THEN
                RAISE EXCEPTION 'Случайная ошибка на шаге 2';
            END IF;
            
        EXCEPTION
            WHEN others THEN
                ROLLBACK TO SAVEPOINT sp2;
                INSERT INTO process_log (step) VALUES ('Шаг 2 откатан');
        END;
        
        INSERT INTO process_log (step) VALUES ('Шаг 3');
        
    EXCEPTION
        WHEN others THEN
            ROLLBACK TO SAVEPOINT sp1;
            INSERT INTO process_log (step) VALUES ('Все откатано к sp1');
    END;
    
    INSERT INTO process_log (step) VALUES ('Завершение');
END;
$$ LANGUAGE plpgsql;

-- Гранулярная обработка ошибок:
CREATE OR REPLACE PROCEDURE error_handling_example()
AS $$
BEGIN
    -- Блок 1: Критическая операция
    BEGIN
        INSERT INTO critical_table (data) VALUES ('важные данные');
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'Дубликат в критической таблице';
            -- Можно продолжить или выполнить ROLLBACK
        WHEN others THEN
            RAISE EXCEPTION 'Критическая ошибка: %', SQLERRM;
    END;
    
    -- Блок 2: Не критическая операция
    BEGIN
        INSERT INTO log_table (message) VALUES ('логирование');
    EXCEPTION
        WHEN others THEN
            RAISE NOTICE 'Ошибка логирования проигнорирована: %', SQLERRM;
            -- Продолжаем выполнение
    END;
    
    -- Блок 3: Операция с компенсацией
    DECLARE
        temp_id INTEGER;
    BEGIN
        INSERT INTO temp_data (value) VALUES ('временные данные')
        RETURNING id INTO temp_id;
        
        -- Основная операция
        PERFORM some_risky_operation();
        
        -- Очистка временных данных при успехе
        DELETE FROM temp_data WHERE id = temp_id;
        
    EXCEPTION
        WHEN others THEN
            -- Компенсирующее действие
            DELETE FROM temp_data WHERE id = temp_id;
            RAISE NOTICE 'Временные данные очищены после ошибки';
            RAISE;  -- Пробрасываем ошибку дальше
    END;
    
END;
$$ LANGUAGE plpgsql;

-- Работа с несколькими базами данных:
CREATE OR REPLACE PROCEDURE distributed_operation()
AS $$
DECLARE
    local_result BOOLEAN;
    remote_result BOOLEAN;
BEGIN
    -- Локальная операция
    INSERT INTO local_db.orders (customer_id, amount) 
    VALUES (1, 1000);
    
    -- Операция через dblink (условно)
    -- PERFORM dblink_exec('remote_conn', 
    --     'INSERT INTO remote_db.audit (operation) VALUES (''order_created'')');
    
    -- Проверяем успешность всех операций
    local_result := true;  -- Локальная операция успешна
    remote_result := true; -- Предположим, что удаленная тоже
    
    IF local_result AND remote_result THEN
        RAISE NOTICE 'Все операции успешны';
        -- COMMIT
    ELSE
        RAISE EXCEPTION 'Ошибка в распределенной операции';
        -- ROLLBACK
    END IF;
    
END;
$$ LANGUAGE plpgsql;

-- Процедура для мониторинга активных транзакций:
CREATE OR REPLACE PROCEDURE monitor_transactions()
AS $$
DECLARE
    tx_record RECORD;
BEGIN
    RAISE NOTICE '=== АКТИВНЫЕ ТРАНЗАКЦИИ ===';
    
    FOR tx_record IN 
        SELECT 
            pid,
            usename,
            application_name,
            state,
            now() - xact_start as duration,
            query
        FROM pg_stat_activity 
        WHERE state != 'idle'
        AND xact_start IS NOT NULL
        ORDER BY duration DESC
    LOOP
        RAISE NOTICE 'PID: %, User: %, App: %, State: %, Duration: %, Query: %',
                     tx_record.pid,
                     tx_record.usename,
                     tx_record.application_name,
                     tx_record.state,
                     tx_record.duration,
                     left(tx_record.query, 100);
    END LOOP;
    
    RAISE NOTICE '=== БЛОКИРОВКИ ===';
    
    FOR tx_record IN 
        SELECT 
            locktype,
            relation::regclass,
            mode,
            granted,
            pid
        FROM pg_locks 
        WHERE relation IS NOT NULL
        ORDER BY relation, mode
    LOOP
        RAISE NOTICE 'Lock: % on % (% - %) by PID %',
                     tx_record.locktype,
                     tx_record.relation,
                     tx_record.mode,
                     CASE WHEN tx_record.granted THEN 'granted' ELSE 'waiting' END,
                     tx_record.pid;
    END LOOP;
    
END;
$$ LANGUAGE plpgsql;

CALL monitor_transactions();