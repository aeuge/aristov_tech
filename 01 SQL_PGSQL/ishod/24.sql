-- простой цикл
drop procedure if exists triple;
CREATE PROCEDURE triple(INOUT x int)
-- CREATE OR REPLACE PROCEDURE triple(INOUT x int) -- отличная практика
LANGUAGE plpgsql
AS $$
BEGIN
	LOOP
    	-- здесь производятся вычисления
    	IF x > 0 THEN
        	EXIT;  -- выход из цикла
    	END IF;
    	x = x + 3;
	END LOOP;
    x = x * 3;
END;
$$;

CALL triple(4);


-- выход из блока сразу
CREATE OR REPLACE PROCEDURE triple(INOUT x int)
LANGUAGE plpgsql
AS $$
<<abc>>
BEGIN
	LOOP
    	-- здесь производятся вычисления
    	IF x > 0 then
	    	--return;
        	exit abc;  -- выход из цикла
    	END IF;
    	x = x + 3;
	END LOOP;
    x = x * 3;
END;
$$;

CALL triple(4);


-- цикл по результатам запроса
drop materialized view if exists mv;
drop table if exists test_mv;
create table test_mv();
create materialized view mv as select * from test_mv;

CREATE or replace FUNCTION refresh_mviews() RETURNS integer AS $$
DECLARE
    mviews RECORD;
    i int = 0;
BEGIN
    RAISE NOTICE 'Refreshing all materialized views...';

    FOR mviews IN
       SELECT n.nspname AS mv_schema,
              c.relname AS mv_name,
              pg_catalog.pg_get_userbyid(c.relowner) AS owner
         FROM pg_catalog.pg_class c
    LEFT JOIN pg_catalog.pg_namespace n ON (n.oid = c.relnamespace)
        WHERE c.relkind = 'm'
     ORDER BY 1
    LOOP

        -- Здесь "mviews" содержит одну запись с информацией о матпредставлении
		i = i + 1;
        RAISE NOTICE 'Refreshing materialized view %.% (owner: %)...',
                     quote_ident(mviews.mv_schema),
                     quote_ident(mviews.mv_name),
                     quote_ident(mviews.owner);
        EXECUTE format('REFRESH MATERIALIZED VIEW %I.%I', mviews.mv_schema, mviews.mv_name);
    END LOOP;

    RAISE NOTICE 'Done refreshing materialized views.';
    RETURN i;
END;
$$ LANGUAGE plpgsql;

SELECT refresh_mviews();


-- пример цикла по элементам массива
CREATE or replace FUNCTION sum(int[]) RETURNS int8 AS $$
DECLARE
  s int8 := 0;
  x int;
BEGIN
  FOREACH x IN ARRAY $1
  LOOP
    s := s + x;
  END LOOP;
  RETURN s;
END;
$$ LANGUAGE plpgsql;

SELECT sum(array[1,2,3,4]);

-- пример цикла по элементам массива
drop function sum(int[]);
CREATE or replace FUNCTION sum(arr text[]) RETURNS text AS $$
DECLARE
  s text := '';
  x text;
BEGIN
  FOREACH x IN ARRAY arr
  LOOP
    s := s || x;
  END LOOP;
	raise notice '%',arr[1]; -- можем обратиться к конкретному элементу	
  RETURN s;
END;
$$ LANGUAGE plpgsql;

SELECT sum(array['1','2','3','4']);

-- Пример использования RETURN NEXT:
drop table if exists foo CASCADE;
CREATE TABLE foo (fooid INT, foosubid INT, fooname TEXT);
INSERT INTO foo VALUES (1, 2, 'three');
INSERT INTO foo VALUES (4, 5, 'six');

CREATE OR REPLACE FUNCTION get_all_foo() RETURNS SETOF foo AS
$BODY$
DECLARE
    r foo%rowtype;
BEGIN
    FOR r IN
        SELECT * FROM foo WHERE fooid > 0
    LOOP
        -- здесь возможна обработка данных
        r.fooid := r.fooid + 10;
        RETURN NEXT r; -- возвращается текущая строка запроса
    END LOOP;
    RETURN;
END
$BODY$
LANGUAGE plpgsql;

SELECT * FROM get_all_foo();
SELECT * FROM foo;

-- цикл по динамическому запросу
CREATE OR REPLACE FUNCTION loop_dynamic_query_example()
RETURNS TABLE(table_name TEXT, row_count BIGINT) AS $$
DECLARE
    table_record RECORD;
    dynamic_query TEXT;
    count_result BIGINT;
BEGIN
    -- Динамический запрос для получения списка таблиц
    dynamic_query := '
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = ''public'' 
        AND table_type = ''BASE TABLE''
    ';
    
    -- Цикл по результатам динамического запроса
    FOR table_record IN EXECUTE dynamic_query
    LOOP
        -- Второй динамический запрос внутри цикла
        EXECUTE format('SELECT COUNT(*) FROM %I', table_record.table_name) 
        INTO count_result;
        
        -- Возврат результата
        table_name := table_record.table_name;
        row_count := count_result;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select loop_dynamic_query_example();

-- Динамический запрос с передачей параметров:
drop table if exists user;
create table user(id serial,name text);
insert into user(name) values ('Denis'),('Eugene'),('Andrew'),('Petr'),('Alexey'),('Ivan'),('Lev');

CREATE OR REPLACE FUNCTION loop_with_parameters(min_id INTEGER, max_id INTEGER)
RETURNS TABLE(user_id INTEGER, user_name TEXT) AS $$
DECLARE
    user_record RECORD;
    batch_size CONSTANT INTEGER := 5;
    current_min INTEGER := min_id;
    dynamic_query TEXT;
BEGIN
    WHILE current_min <= max_id LOOP
        -- Динамический запрос с параметрами
        dynamic_query := '
            SELECT id, name 
            FROM users 
            WHERE id BETWEEN $1 AND $2 
            ORDER BY id 
            LIMIT $3
        ';
        
        -- Цикл по результатам с параметрами
        FOR user_record IN EXECUTE dynamic_query USING current_min, min(current_min + batch_size - 1,max_id), batch_size
        LOOP
            user_id := user_record.id;
            user_name := user_record.name;
            -- подебажим
            RAISE NOTICE 'User % has id %',user_name, user_id;
            RETURN NEXT;
        END LOOP;
        
        current_min := current_min + batch_size;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select loop_with_parameters(1,6);

-- как можно доработать?

create or replace function min(int,int) returns int as 'select min($1,$2);' language sql;
-- SQL Error [54001]: ERROR: stack depth limit exceeded
-- Hint: Increase the configuration parameter "max_stack_depth" (currently 2048kB)


drop function min(int,int);
create or replace function min(int,int) returns int as 'begin if $1> $2 then return $2; else return $1; end if;end;' language plpgsql;

