-- Полиморфные функции
-- Здесь нам поможет полиморфный тип anyelement.
-- Удалим все три наши функции и затем создадим новую:

DROP FUNCTION maximum(integer, integer);
DROP FUNCTION maximum(integer, integer, integer);
DROP FUNCTION maximum(real, real);

CREATE FUNCTION maximum(a anyelement, b anyelement) RETURNS anyelement AS $$
    SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE SQL;

SELECT maximum(1,2);

-- попробуем сравнить строки
SELECT maximum('C','B');
-- Получится???


-- Увы, нет. В данном случае строковые литералы могут быть типа char, varchar, text - 
-- конкретный тип нам неизвестен. Но можно применить явное приведение типов:
SELECT maximum('C'::text,'B'::text);

-- Еще пример с другим типом:
SELECT maximum(now(), now() + interval '1 day');

-- Важно, чтобы типы обоих параметров совпадали, иначе будет ошибка:
SELECT maximum(1,'C');


-- Функция, возвращающая первый элемент массива:
CREATE OR REPLACE FUNCTION first_element(anyarray)
RETURNS anyelement AS $$
BEGIN
    IF array_length($1, 1) IS NULL OR array_length($1, 1) = 0 THEN
        RETURN NULL;
    END IF;
    RETURN $1[1];
END;
$$ LANGUAGE plpgsql;

-- Использование с разными типами
SELECT first_element(ARRAY[1, 2, 3]);       
SELECT first_element(ARRAY['a', 'b', 'c']); 
SELECT first_element(ARRAY[true, false]);   
SELECT first_element(ARRAY[1.1, 2.2]::NUMERIC[]);


--Функция для получения типа данных:
CREATE OR REPLACE FUNCTION get_type_info(value anyelement)
RETURNS TABLE(type_name text, type_oid oid) AS $$
BEGIN
    SELECT 
        pg_typeof(value)::text,
        pg_typeof(value)::oid
    INTO type_name, type_oid;
    
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM get_type_info(123);           
SELECT * FROM get_type_info('hello'::text); 
SELECT * FROM get_type_info(3.14::numeric); 

-- возврат anyelement
-- обязательно должен быть задан 1 IN эниэлемент параметр!
CREATE OR REPLACE FUNCTION get_polymorphic_data(OUT id anyelement, OUT data jsonb)
RETURNS SETOF record AS $$
begin
	id = 1;
	data = '{name:Peter}'::jsonb;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION get_polymorphic_data(in i anyelement, OUT id anyelement, OUT data jsonb)
RETURNS SETOF record AS $$
begin
	id = i + 1;
	data = '{name:Peter}'::jsonb;
end;
$$ language plpgsql;
