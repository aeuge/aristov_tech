-- классика - обратите внимание, не пишем RETURNS
CREATE OR REPLACE FUNCTION sales_tax(subtotal real, OUT tax real) AS $$
BEGIN
    tax := subtotal * 0.06;
END;
$$ LANGUAGE plpgsql;

select sales_tax(200);


-- Функция, возвращающая запись с несколькими выходными параметрами:
CREATE FUNCTION dup(in int, out f1 int, out f2 text) AS $$ 
    SELECT $1, CAST($1 AS text) || ' is text' 
$$
LANGUAGE SQL;

SELECT * FROM dup(42);




-- OUT + RETURNS
-- только 1 параметр и тип должен совпадать
CREATE OR REPLACE FUNCTION sales_tax2(subtotal real, OUT tax real) returns int AS $$
BEGIN
    tax := subtotal * 0.06;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sales_tax2(subtotal real, OUT tax real) returns real AS $$
BEGIN
    tax := subtotal * 0.06;
END;
$$ LANGUAGE plpgsql;

select sales_tax2(200);


-- несколько выходных параметров
drop function if exists sum_n_product;
CREATE FUNCTION sum_n_product(x int, IN y int, OUT sum int, OUT prod int) AS $$
BEGIN
    sum := x + y;
    prod := x * y;
END;
$$ LANGUAGE plpgsql;

SELECT sum_n_product(200, 400);
SELECT * from sum_n_product(200, 400);
SELECT prod from sum_n_product(200, 400);

-- пример переменной inout
drop function if exists return_inout;
CREATE or replace function return_inout(inout result1 int, out result2 int)
as $$
begin
    result2 := result1;  
    result1 := 1;
return;
end
$$ language plpgsql; 

SELECT return_inout(6);
select * from return_inout(6);

-- поименованная передача параметра
SELECT * FROM sum_n_product(y => 6, x => 12);



-- использование переменной VARIADIC массив с переменным набором аргументов
-- https://www.postgresql.org/docs/current/functions-srf.html
-- https://stackoverflow.com/questions/10674735/in-postgresql-what-is-gi-in-FROM-generate-subscripts1-1-gi
CREATE or replace FUNCTION mleast(VARIADIC arr numeric[]) RETURNS numeric AS $$
    SELECT min($1[i]) FROM generate_subscripts($1, 1) g(i);
$$ LANGUAGE SQL;

SELECT mleast(100 , 50, -1, 5, 4.4);

-- обратите внимание, что variadic - это обязательно последний параметр - иначе не определить, где заканчиваются входные и начинаются выходные параметры

-- Функция для сложения произвольного количества чисел
CREATE OR REPLACE FUNCTION sum_variadic(VARIADIC numbers NUMERIC[])
RETURNS NUMERIC AS $$
DECLARE
    total NUMERIC := 0;
    num NUMERIC;
BEGIN
    FOREACH num IN ARRAY numbers LOOP
        total := total + num;
    END LOOP;
    RETURN total;
END;
$$ LANGUAGE plpgsql;

SELECT sum_variadic(1, 2, 3);          
SELECT sum_variadic(10, 20, 30, 40);   
SELECT sum_variadic(5);               
SELECT sum_variadic();          

-- Конкатенация строк:
CREATE OR REPLACE FUNCTION concat_strings(
    separator TEXT DEFAULT ', ', 
    VARIADIC texts TEXT[]
) RETURNS TEXT AS $$
BEGIN
    RETURN array_to_string(texts, separator);
END;
$$ LANGUAGE plpgsql;

SELECT concat_strings(' | ', 'Apple', 'Banana', 'Cherry');

-- прод
-- Поиск по нескольким значениям:
CREATE OR REPLACE FUNCTION find_products_by_categories(
    VARIADIC categories TEXT[]
) RETURNS TABLE(product_id INT, product_name TEXT, category TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.name, p.category
    FROM products p
    WHERE p.category = ANY(categories);
END;
$$ LANGUAGE plpgsql;

SELECT * FROM find_products_by_categories('Electronics', 'Books', 'Clothing');

-- Массовое обновление статусов:
CREATE OR REPLACE FUNCTION bulk_update_status(
    new_status TEXT,
    VARIADIC order_ids INT[]
) RETURNS INT AS $$
DECLARE
    updated_count INT;
BEGIN
    UPDATE orders 
    SET status = new_status 
    WHERE id = ANY(order_ids);
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;


SELECT bulk_update_status('shipped', 1, 5, 8, 12);

-- Построение динамического WHERE: (динамический SQL в 23 теме)
CREATE OR REPLACE FUNCTION search_users(
    search_name TEXT DEFAULT NULL,
    VARIADIC statuses TEXT[]
) RETURNS SETOF users AS $$
DECLARE
    query_text TEXT;
BEGIN
    query_text := 'SELECT * FROM users WHERE 1=1';
    
    IF search_name IS NOT NULL THEN
        query_text := query_text || ' AND name ILIKE %1$L';
    END IF;
    
    IF array_length(statuses, 1) > 0 THEN
        query_text := query_text || ' AND status = ANY(%2$L)';
    END IF;
    
    RETURN QUERY EXECUTE format(query_text, '%' || search_name || '%', statuses);
END;
$$ LANGUAGE plpgsql;

-- Вызовы
SELECT * FROM search_users('john', 'active', 'pending');
SELECT * FROM search_users(VARIADIC ARRAY['active','suspended']);


-- Best Practices
-- Всегда указывайте разумные ограничения:
CREATE OR REPLACE FUNCTION safe_variadic(VARIADIC numbers INT[])
RETURNS INT AS $$
BEGIN
    IF array_length(numbers, 1) > 100 THEN
        RAISE EXCEPTION 'Too many arguments (max 100)';
    END IF;
    
    -- Логика функции
    RETURN array_length(numbers, 1);
END;
$$ LANGUAGE plpgsql;

-- Используйте VARIADIC для "вспомогательных" параметров:
-- Хороший пример: tags являются дополнительными фильтрами
CREATE OR REPLACE FUNCTION find_products(
    category TEXT,
    VARIADIC tags TEXT[]  -- опциональные теги
) RETURNS SETOF products AS $$ ... $$;