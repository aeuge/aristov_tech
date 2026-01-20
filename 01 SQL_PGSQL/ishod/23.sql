-- безопасный поиск с защитой от SQL инъекций
drop table if exists products;
create table products (name text, category text, price decimal, quantity decimal);
insert into products values ('apple','fruit',200,10);

CREATE OR REPLACE FUNCTION safe_product_search(
    category_filter TEXT DEFAULT NULL,
    min_price NUMERIC DEFAULT NULL,
    max_price NUMERIC DEFAULT NULL,
    in_stock BOOLEAN DEFAULT NULL
) RETURNS SETOF products AS $$
DECLARE
    base_query TEXT := 'SELECT * FROM products WHERE 1=1';
    where_conditions TEXT[] := '{}';
    query_params TEXT[] := '{}';
    param_count INTEGER := 0;
    final_query TEXT;
BEGIN
    -- Динамическое построение запроса с параметрами
    IF category_filter IS NOT NULL THEN
        param_count := param_count + 1;
        where_conditions := array_append(where_conditions, format('category = $%s', param_count));
        query_params := array_append(query_params, category_filter);
    END IF;
    
    IF min_price IS NOT NULL THEN
        param_count := param_count + 1;
        where_conditions := array_append(where_conditions, format('price >= $%s', param_count));
        query_params := array_append(query_params, min_price::text);
    END IF;
    
    IF max_price IS NOT NULL THEN
        param_count := param_count + 1;
        where_conditions := array_append(where_conditions, format('price <= $%s', param_count));
        query_params := array_append(query_params, max_price::text);
    END IF;
    
    IF in_stock IS NOT NULL THEN
        param_count := param_count + 1;
        where_conditions := array_append(where_conditions, format('quantity > 0 = $%s', param_count));
        query_params := array_append(query_params, in_stock::text);
    END IF;
    
    -- Сборка финального запроса
    IF array_length(where_conditions, 1) > 0 THEN
        base_query := base_query || ' AND ' || array_to_string(where_conditions, ' AND ');
    END IF;
    
    base_query := base_query || ' ORDER BY name;';
    
    -- Безопасное выполнение
    RETURN QUERY EXECUTE base_query USING query_params; -- не выполнится, причём deepseek ошибку сам найти не смог
    /* еще предложенные решения:
    CASE param_count
        WHEN 1 THEN
            RETURN QUERY EXECUTE base_query USING query_params[1];
        WHEN 2 THEN
            RETURN QUERY EXECUTE base_query USING query_params[1], query_params[2];
        WHEN 3 THEN
            RETURN QUERY EXECUTE base_query USING query_params[1], query_params[2], query_params[3];
        ELSE
            RETURN QUERY EXECUTE base_query;
    END CASE;

    3. Способ: Использование отдельных переменных
    IF max_price IS NOT NULL THEN
        param_count := param_count + 1;
        where_conditions := array_append(where_conditions, format('price <= $%s', param_count));
        IF param_count = 2 THEN
            param2 := max_price::text;
        ELSE
            param3 := max_price::text;
        END IF;
    END IF;

    На самом деле решения 3:
    where_conditions := array_append(where_conditions, format('category = %L', category_filter));
    RETURN QUERY EXECUTE base_query;

    -- 2
    RETURN QUERY EXECUTE base_query USING array_to_string(query_params,','); 

    --3
    if len () > 1 then 
        query_params = query_params || ',' || category_filter
    else
        query_params = category_filter
    endif
    */
END;
$$ LANGUAGE plpgsql;

select safe_product_search(category_filter => 'fruit');


--выполнение кода без определения функции или процедуры
drop table if exists table_1;
drop table if exists table_2;

DO $$
DECLARE
	i INTEGER;
BEGIN
		FOR i IN 1 .. 2 
		LOOP
			RAISE Notice 'i = %', i;
			execute ('create table table_' || i || '(id int);');
		END LOOP;
end $$;	

table table_1;
table table_2;


--Процедура копирования определения таблицы 
drop table if exists customer;
create table customer(id serial, name text);
insert into customer(name) values ('Tom'),('Bill');

Create or replace PROCEDURE copy_table(
			name_old text,
			name_new text)
language 'plpgsql'
As $$
declare str_table text;
begin
	str_table:= 'create table ' || name_new || ' as select * from ' || name_old ;
	execute str_table;
	raise notice 'str = %', str_table;
end $$	

--Вызвать процедуру
call copy_table('customer', 'copy_customer');
table copy_customer;

	
--Вывести все таблицы заданной схемы
Create or replace PROCEDURE view_tables(name_sch text)
language 'plpgsql'
as $$
DECLARE
	r record;
	cnt int;
begin
	For r in
	 	select table_name from information_schema.TABLES
	 	where table_schema = name_sch
	 	order by table_name desc
	loop
		execute 'select count(*) cnt from ' ||  r.table_name into cnt;
	  	raise notice '% - %', r.table_name, cnt;
	end loop;
end	$$; 
-- 
call view_tables('public');
-- почему нет вывода?