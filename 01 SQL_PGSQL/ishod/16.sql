-- перегрузка
-- Напишем функцию, возвращающую большее из двух целых чисел
-- (Похожая функция есть в SQL и называется greatest, но мы сделаем ее сами)

CREATE OR REPLACE FUNCTION maximum(a integer, b integer) RETURNS integer AS $$
SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE SQL;


-- Проверим:
SELECT maximum(100,200);

-- Допустим, мы решили сделать аналогичную функцию для трех чисел. 
-- Благодаря перегрузке, не надо придумывать для нее какое-то новое название:

CREATE OR REPLACE FUNCTION maximum(a integer, b integer, c integer) RETURNS integer AS $$
SELECT CASE WHEN a > b THEN maximum(a,c) ELSE maximum(b,c) END;
$$ LANGUAGE SQL;

-- Теперь у нас две функции с одним именем, но разным числом параметров:
\df maximum

-- И обе работают:
SELECT maximum(10,20), maximum(10,20,-100);

-- Пусть наша функция работает не только для целых чисел, но и для вещественных.
CREATE OR REPLACE FUNCTION maximum(a real, b real) RETURNS real AS $$
    SELECT CASE WHEN a > b THEN a ELSE b END;
$$ LANGUAGE SQL;

-- Получение информации о функциях:
\df maximum

-- можем в 1 запросе вызвать разные перегруженые функции
SELECT maximum(10,20), maximum(3.1,3.2);

-- dbeaver
SELECT 
    p.proname as function_name,
    pg_get_function_arguments(p.oid) as arguments,
    pg_get_function_result(p.oid) as return_type
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'maximum'
AND n.nspname = 'public'
ORDER BY p.oid;

-- Детальная информация о конкретной функции
SELECT 
    p.proname,
    p.proargnames,
    p.proargtypes,
    t.typname as return_type
FROM pg_proc p
JOIN pg_type t ON p.prorettype = t.oid
WHERE p.proname = 'maximum';



-- мы использовали составной тип в банковских транзакциях
select * from transactions;
SELECT account_id, multiply(2,debit), multiply(2,credit), date_entered FROM transactions;

SELECT account_id, 1.2 * debit, 2 * credit, date_entered FROM transactions;

-- но в обратную сторону он не работает:
SELECT account_id, debit * 2, date_entered FROM transactions;

-- ипользуя перегрузку создадим еще одну функицю с зеркальным набором аргументов
CREATE OR REPLACE FUNCTION multiply(cur currency, factor numeric) RETURNS currency AS $$
    SELECT ROW(factor * cur.amount, cur.code)::currency;
$$ IMMUTABLE LANGUAGE SQL;


CREATE OPERATOR * (
    PROCEDURE = multiply,
    LEFTARG = currency,
    RIGHTARG = numeric
);

SELECT account_id, debit * 2, 2 * credit, date_entered FROM transactions;
