-- вложенная процедура и попытка коммита
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

call test_excep(1);
table mytab;


-- Безопасный цикл с перехватом исключений:
CREATE OR REPLACE FUNCTION safe_dynamic_loop()
RETURNS TABLE(success BOOLEAN, table_name TEXT, message TEXT) AS $$
DECLARE
    tbl_name TEXT;
    dynamic_query TEXT;
    result_count INTEGER;
BEGIN
    -- Цикл по заранее определенному списку таблиц
    FOREACH tbl_name IN ARRAY ARRAY['users', 'mytab', 'orders', 'invalid_table']
    LOOP
        BEGIN
            -- Динамический запрос с проверкой существования таблицы
            dynamic_query := format('
                SELECT COUNT(*) as cnt 
                FROM %I 
                WHERE created_at > CURRENT_DATE - INTERVAL ''7 days''
            ', tbl_name);
            
            EXECUTE dynamic_query INTO result_count;
            
            success := true;
            table_name := tbl_name;
            message := format('Processed %s rows', result_count);
            RETURN NEXT;
            
        EXCEPTION
            WHEN undefined_table THEN
                success := false;
                table_name := tbl_name;
                message := 'Table does not exist';
                RETURN NEXT;
                
            WHEN others THEN
                success := false;
                table_name := tbl_name;
                message := format('Error: %s', SQLERRM);
                RETURN NEXT;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select safe_dynamic_loop(); 