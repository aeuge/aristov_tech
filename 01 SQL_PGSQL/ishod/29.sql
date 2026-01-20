-- базовый триггер мониторинга
CREATE OR REPLACE FUNCTION ddl_event_trigger_function()
RETURNS event_trigger AS $$
DECLARE
    r RECORD;
BEGIN
    -- Получаем информацию о событии
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands() 
    LOOP
        RAISE NOTICE 'DDL команда: %, объект: %, схема: %', 
                     r.command_tag, 
                     r.object_identity,
                     r.schema_name;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Создание DDL триггера
DROP EVENT TRIGGER IF EXISTS ddl_monitor_trigger;
CREATE EVENT TRIGGER ddl_monitor_trigger
    ON ddl_command_end
    EXECUTE FUNCTION ddl_event_trigger_function();

create table if not exists test_ddl();
truncate test_ddl; -- not work !!!


-- логирование изменений схемы
-- Таблица для логов DDL операций
CREATE TABLE ddl_audit_log (
    id SERIAL PRIMARY KEY,
    event_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    username TEXT DEFAULT CURRENT_USER,
    command_tag TEXT,
    object_type TEXT,
    object_identity TEXT,
    schema_name TEXT,
    ddl_command TEXT
);

-- Функция для логирования DDL
CREATE OR REPLACE FUNCTION log_ddl_changes()
RETURNS event_trigger AS $$
DECLARE
    obj record;
    ddl_text text;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() 
    LOOP
        -- Получаем текст DDL команды
        SELECT current_query() INTO ddl_text
        FROM pg_stat_activity 
        WHERE pid = pg_backend_pid();
        
        INSERT INTO ddl_audit_log (
            command_tag, 
            object_type, 
            object_identity, 
            schema_name,
            ddl_command
        ) VALUES (
            obj.command_tag,
            obj.object_type,
            obj.object_identity,
            obj.schema_name,
            ddl_text
        );
        
        RAISE NOTICE 'Записано в лог: %', obj.object_identity;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

table ddl_audit_log;
drop table if exists test_ddl;
-- why not work?

-- Триггер для логирования
CREATE EVENT TRIGGER ddl_audit_trigger
    ON ddl_command_end
    EXECUTE FUNCTION log_ddl_changes();

table ddl_audit_log;
create table if not exists test_ddl();
drop table if exists test_ddl;

CREATE EVENT TRIGGER ddl_audit_trigger2
    ON ddl_command_start
    EXECUTE FUNCTION log_ddl_changes();

-- whaaatt??
-- https://www.postgresql.org/docs/current/event-trigger-definition.html#EVENT-TRIGGER-DDL_COMMAND_END

CREATE OR REPLACE FUNCTION log_ddl_changes2()
RETURNS event_trigger AS $$
DECLARE
    obj record;
    ddl_text text;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() 
    LOOP
        -- Получаем текст DDL команды
        SELECT current_query() INTO ddl_text
        FROM pg_stat_activity 
        WHERE pid = pg_backend_pid();
        
        INSERT INTO ddl_audit_log (
            command_tag, 
            object_type, 
            object_identity, 
            schema_name,
            ddl_command
        ) VALUES (
            obj.command_tag,
            obj.object_type,
            obj.object_identity,
            obj.schema_name,
            ddl_text
        );
        
        RAISE NOTICE 'Записано в лог: %', obj.object_identity;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER ddl_audit_trigger3
    ON ddl_command_start
    EXECUTE FUNCTION log_ddl_changes2();

table ddl_audit_log;
create table if not exists test_ddl();
drop table if exists test_ddl;

-- ERROR: pg_event_trigger_dropped_objects() can only be called in a sql_drop event trigger function
DROP EVENT TRIGGER ddl_audit_trigger3;

CREATE EVENT TRIGGER ddl_audit_trigger3
    ON sql_drop
    EXECUTE FUNCTION log_ddl_changes2();

table ddl_audit_log;
create table if not exists test_ddl();
drop table if exists test_ddl;


/* ERROR: record "obj" has no field "command_tag"
  Where: SQL statement "INSERT INTO ddl_audit_log (
            command_tag, 
            object_type, 
            object_identity, 
            schema_name,
            ddl_command
        ) VALUES (
            obj.command_tag,
            obj.object_type,
            obj.object_identity,
            obj.schema_name,
            ddl_text
        )"
 */

CREATE OR REPLACE FUNCTION log_ddl_changes2()
RETURNS event_trigger AS $$
DECLARE
    obj record;
    ddl_text text;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() 
    LOOP
        -- Получаем текст DDL команды
        SELECT current_query() INTO ddl_text
        FROM pg_stat_activity 
        WHERE pid = pg_backend_pid();
        
        INSERT INTO ddl_audit_log (
            command_tag, 
            object_type, 
            object_identity, 
            schema_name,
            ddl_command
        ) VALUES (
            'drop table',
            obj.object_type,
            obj.object_identity,
            obj.schema_name,
            ddl_text
        );
        
        RAISE NOTICE 'Записано в лог: drop %', obj.object_identity;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

table ddl_audit_log;
create table if not exists test_ddl();
drop table if exists test_ddl;


-- Запрет удаления критических таблиц
-- Функция для защиты таблиц
-- pg_event_trigger_dropped_objects
CREATE OR REPLACE FUNCTION prevent_critical_drops()
RETURNS event_trigger AS $$
DECLARE
    obj record;
    protected_tables TEXT[] := ARRAY['users', 'products', 'orders'];
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects() 
    LOOP
        -- Проверяем, является ли объект защищенной таблицей
        IF obj.object_type = 'table' 
           AND obj.schema_name = 'public' 
           AND obj.object_name = ANY(protected_tables) 
        THEN
            RAISE EXCEPTION 'Удаление таблицы % запрещено!', obj.object_name;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Триггер для защиты от удаления
CREATE EVENT TRIGGER prevent_drop_trigger
    ON sql_drop
    EXECUTE FUNCTION prevent_critical_drops();

create table if not exists users();
drop table users;


-- Автоматическое назначение прав
-- Функция для автоматического GRANT
CREATE OR REPLACE FUNCTION auto_grant_permissions()
RETURNS event_trigger AS $$
DECLARE
    obj record;
BEGIN
    FOR obj IN SELECT * FROM pg_event_trigger_ddl_commands() 
    LOOP
        -- Для новых таблиц автоматически даем права
        IF obj.command_tag = 'CREATE TABLE' THEN
            EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %s TO app_user', 
                          obj.object_identity);
            EXECUTE format('GRANT USAGE ON SEQUENCE %s_id_seq TO app_user', 
                          obj.object_identity);
            
            RAISE NOTICE 'Автоматически выданы права на таблицу: %', obj.object_identity;
        END IF;
        
        -- Для новых представлений
        IF obj.command_tag = 'CREATE VIEW' THEN
            EXECUTE format('GRANT SELECT ON %s TO readonly_user', obj.object_identity);
            RAISE NOTICE 'Автоматически выданы права на представление: %', obj.object_identity;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE EVENT TRIGGER auto_grant_trigger
    ON ddl_command_end
    EXECUTE FUNCTION auto_grant_permissions();

create user app_user;
drop table if exists test_grant;
create table test_grant(id serial);
-- !!! difference with generated always as identity !!!

