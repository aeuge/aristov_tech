-- Обработка ошибок
drop table if exists mytab;
create table mytab(firstname text, lastname text, created_at timestamp);
insert into mytab values ('Tom','Jones','20251029');

drop procedure if exists test_excep;
CREATE PROCEDURE test_excep(INOUT x int)
LANGUAGE plpgsql
AS $$
declare
  y int = 0;
 
BEGIN
    UPDATE mytab SET firstname = 'Joe' WHERE lastname = 'Jones';
    x := x + 1;
    commit;
    y := x / 0;

END;
$$;


drop procedure if exists test_excep2;
CREATE PROCEDURE test_excep2(INOUT x int)
LANGUAGE plpgsql
AS $$
declare x int;
text_var1 text;
 text_var2 text;
 text_var3 text;
 t text;
begin
    call test_excep(x);
	EXCEPTION 
	WHEN OTHERS THEN
	 GET STACKED DIAGNOSTICS text_var1 = MESSAGE_TEXT,
	   text_var2 = PG_EXCEPTION_DETAIL,
	   text_var3 = PG_EXCEPTION_HINT;
	
	 t = text_var1 || '/' || coalesce(text_var2,'') || '/' || coalesce(text_var3,'');
	 RAISE NOTICE 'перехватили ошибку %' , t;
END;
$$;


call test_excep2(1);


-- Процедура с комплексной обработкой ошибок:
CREATE OR REPLACE PROCEDURE safe_data_operation()
AS $$
DECLARE
    error_context TEXT;
BEGIN
    -- Блок 1: Основные операции
    BEGIN
        UPDATE important_table SET status = 'processing';
        CALL critical_operation();
        
    EXCEPTION
        WHEN others THEN
            GET STACKED DIAGNOSTICS error_context = PG_EXCEPTION_CONTEXT;
            RAISE NOTICE 'Ошибка в основном блоке: %, контекст: %', SQLERRM, error_context;
            
            -- Откат всей процедуры
            RAISE EXCEPTION 'Критическая ошибка, откат операции';
    END;
    
    -- Блок 2: Не критические операции
    BEGIN
        CALL non_critical_operation();
        
    EXCEPTION
        WHEN others THEN
            RAISE NOTICE 'Не критическая ошибка проигнорирована: %', SQLERRM;
    END;
    
    -- Блок 3: Логирование (всегда выполняется)
    BEGIN
        INSERT INTO process_log (operation, status, details)
        VALUES ('safe_data_operation', 'completed', 'Process finished at ' || CURRENT_TIMESTAMP);
        
    EXCEPTION
        WHEN others THEN
            RAISE NOTICE 'Ошибка логирования: %', SQLERRM;
    END;
END;
$$ LANGUAGE plpgsql;




-- Получение информации о месте выполнения
CREATE OR REPLACE FUNCTION outer_func() RETURNS integer AS $$
BEGIN
  RETURN inner_func();
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION inner_func() RETURNS integer AS $$
DECLARE
  stack text;
BEGIN
  GET DIAGNOSTICS stack = PG_CONTEXT;
  RAISE NOTICE E'--- Стек вызова ---\n%', stack;
  RETURN 1;
END;
$$ LANGUAGE plpgsql;

SELECT outer_func();

NOTICE:  --- Стек вызова ---
PL/pgSQL function inner_func() line 5 at GET DIAGNOSTICS
PL/pgSQL function outer_func() line 3 at RETURN
CONTEXT:  PL/pgSQL function outer_func() line 3 at RETURN
 outer_func
 ------------
           1
(1 row)

-- на самом деле ошибка также пробрасывается наверх по стеку вызова
CREATE OR REPLACE FUNCTION inner_func() RETURNS integer AS $$
DECLARE
  stack text;
BEGIN
  RAISE EXCEPTION 'oops';
  RETURN 1;
END;
$$ LANGUAGE plpgsql;

SELECT outer_func();


-- проверим значения стектрейса при ошибке
drop procedure if exists test_excep;

CREATE or replace PROCEDURE test_excep(INOUT x int)
LANGUAGE plpgsql
AS $$
declare
  y int = 0;
 text_var1 text;
 text_var2 text;
 text_var3 text;
 t text;

BEGIN
    UPDATE mytab SET firstname = 'Joe' WHERE lastname = 'Jones';
    x := x + 1;
--	commit;
    y := x / 0;
    
    EXCEPTION 
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS text_var1 = MESSAGE_TEXT,
            text_var2 = PG_EXCEPTION_DETAIL,
            text_var3 = PG_EXCEPTION_HINT;

	    t = text_var1 || '/' || coalesce(text_var2,'') || '/' || coalesce(text_var3,'');
        RAISE NOTICE 'перехватили ошибку %' , t;
END;
$$;

call test_excep(1);
SELECT * FROM mytab;

-- попробуем использовать COMMIT && EXCEPTION



-- дебажим запросы из 20 темы
-- Процедура с явным управлением транзакциями:

CREATE OR REPLACE function process_data_with_savepoint() returns void
AS $$
BEGIN
    SAVEPOINT step1_savepoint;
    ROLLBACK TO SAVEPOINT step1_savepoint;
END;
$$ LANGUAGE plpgsql;


CREATE OR replace procedure process_data_with_savepoint() 
AS $$
BEGIN
    SAVEPOINT step1_savepoint;
    ROLLBACK TO SAVEPOINT step1_savepoint;
END;
$$ LANGUAGE plpgsql;

-- !!! В PostgreSQL НЕ допускается использование SAVEPOINT в функциях и процедурах, только в явных транзакциях!!!

-- !!! рабочий вариант - использовать вложенные блоки !!!
CREATE OR REPLACE PROCEDURE safe_data_processing()
AS $$
DECLARE y int;
BEGIN
    -- Начальные операции
    UPDATE mytab SET firstname = 'Joe2' WHERE lastname = 'Jones';    
	-- commit;

    -- Рискованные операции во вложенном блоке
    BEGIN
        y = 1 / 0;
        
    EXCEPTION
        WHEN others THEN
            RAISE NOTICE 'Деление не удалось: %', SQLERRM;
            -- Продолжаем выполнение
    END;
    
    -- Финализирующие операции (выполнятся в любом случае)
    UPDATE mytab SET firstname = 'Joe3' WHERE lastname = 'Jones';    
END;
$$ LANGUAGE plpgsql;

call safe_data_processing();

table mytab;

-- давайте проверим commit в другом блоке