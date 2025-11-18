-- простейший пример
-- В код PL/pgSQL можно встраивать команды SQL. Наверное, наиболее часто используемый вариант - 
-- команда SELECT, возвращающая одну строку. Пример, который не получилось бы выполнить 
-- с помощью выражения с подзапросом (потому что возвращаются сразу два значения):
drop table if exists t;
CREATE TABLE t(id integer, code text);
INSERT INTO t VALUES (1, 'Раз'), (2, 'Два');
DO $$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO r FROM t WHERE id = 1;
    RAISE NOTICE '%', r;
END;
$$;

DO $$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO r FROM t order by id desc;
    RAISE NOTICE '%', r;
END;
$$;


-- * STRICT - ровно 1 значение. в варианте SELECT в зависимости от order by будет возвращена 1 запись
-- если order by нет - результат непредсказуем, какая строчка вернется
-- в варианте insert, UPDATE - если больше 1 записи - будет ошибка

DO $$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO STRICT r FROM t;
    RAISE NOTICE '%', r;
END;
$$;

DO $$
DECLARE
    r record;
BEGIN
    SELECT id, code INTO STRICT r FROM t WHERE id = 1;
    RAISE NOTICE '%', r;
END;
$$;

-- вариант - использовать не одну переменную составного типа, а несколько скалярных переменных для каждого поля
-- как думаете сработает?
DO $$
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT id, code INTO id, code FROM t WHERE id = id;
    RAISE NOTICE '%, %', id, code;
END;
$$;
-- Не получится из-за неоднозначности в SELECT: id может означать и имя столбца, и имя переменной

-- Варианты устранения неоднозначностей
-- Есть несколько подходов к устранению неоднозначностей.

-- Первый состоит в том, чтобы неоднозначностей не допускать. Для этого к переменным добавляют префикс, 
-- который обычно выбирается в зависимости от "класса" переменной, например:

DO $$
DECLARE
    l_id   integer := 1;
    l_code text;
BEGIN
    SELECT id, code INTO l_id, l_code FROM t WHERE id = l_id;
    RAISE NOTICE '%, %', l_id, l_code;
END;
$$;

-- Второй способ состоит в использовании квалифицированных имен - к имени объекта через точку 
-- дописывается уточняющий квалификатор:

DO $$
<<local>>
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT t.id, t.code INTO local.id, local.code FROM t WHERE t.id = local.id;
    RAISE NOTICE '%, %', id, code;
END;
$$;


-- Третий вариант - установить приоритет переменных над столбцами или наоборот, столбцов над переменными. 
-- За это отвечает конфигурационный параметр plpgsql.variable_conflict.

Здесь устанавливается приоритет переменных, поэтому достаточно квалифицировать только столбцы таблицы:

=> SET plpgsql.variable_conflict = use_variable;
SET
=> DO $$
DECLARE
    id   integer := 1;
    code text;
BEGIN
    SELECT t.id, t.code INTO id, code FROM t WHERE t.id = id;
    RAISE NOTICE '%, %', id, code;
END;
$$;

RESET plpgsql.variable_conflict;

-- еще примеры
drop table if exists users;
create table if not exists users (
    id int, 
    name text, 
    email text,
    created_at date default current_timestamp
);
insert into users values (1,'Ivan','i@i.i');
table users;


CREATE OR REPLACE FUNCTION get_user_name(user_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    user_name TEXT;
BEGIN
    SELECT name INTO user_name
    FROM users
    WHERE id = user_id;
    
    RETURN user_name;
END;
$$ LANGUAGE plpgsql;

select get_user_name(1);


-- SELECT INTO с несколькими переменными
-- Получить данные профиля пользователя.
--    Обработка строк в циклах (24 тема):

CREATE OR REPLACE FUNCTION get_user_profile(user_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    user_name TEXT;
    user_email TEXT;
    user_created_date DATE;
BEGIN
    -- обратите внимание на несовпадение имён в таблице и переменных
    SELECT name, email, created_at INTO user_name, user_email, user_created_date
    FROM users
    WHERE id = user_id;
    
    RETURN format('Имя: %s, Email: %s, Дата регистрации: %s', 
                 user_name, user_email, user_created_date);
END;
$$ LANGUAGE plpgsql;

select get_user_profile(1);


drop table emp;
CREATE TABLE IF NOT EXISTS emp (empname text);
INSERT INTO emp VALUES ('Ivan'), ('Ivan'), ('Petr');


-- обработка, если не нашли значение
CREATE OR REPLACE FUNCTION s1 (name text) returns void as $$
DECLARE 
	myrec record;
BEGIN
    SELECT * INTO myrec FROM emp WHERE empname = name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сотрудник % не найден', name; -- 26 тема
    END IF;
END;
$$ language plpgsql;

select s1('Ivan');
select s1('Ivan2');


-- STRICT
-- если не нашли
CREATE OR REPLACE FUNCTION s2 (name text) returns void as $$
DECLARE 
	myrec record;
BEGIN
    SELECT * INTO STRICT myrec FROM emp WHERE empname = name;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE EXCEPTION 'Сотрудник % не найден', name;
        WHEN TOO_MANY_ROWS THEN
            RAISE EXCEPTION 'Сотрудник % уже существует', name;
END;
$$ language plpgsql;

select s2('Ivan');
select s2('Ivan2');
select s2('Petr');

-- Использование с выражением CASE
-- Получить категорию пользователя на основе его активности.
drop table if exists orders;
CREATE TABLE IF NOT EXISTS orders (user_id int);
INSERT INTO orders VALUES (1), (1), (2);

drop function get_user_orders;
CREATE OR REPLACE FUNCTION get_user_orders(id INTEGER)
RETURNS TEXT AS $$
DECLARE
    order_count INTEGER;
    user_category TEXT;
BEGIN
    SELECT COUNT(*) INTO order_count
    FROM orders
    WHERE user_id = id;
    
    SELECT CASE
        WHEN order_count > 10 THEN 'VIP'
        WHEN order_count > 5 THEN 'Активный'
        WHEN order_count > 0 THEN 'Новичок'
        ELSE 'Неактивный'
    END INTO user_category;
    
    RETURN user_category;
END;
$$ LANGUAGE plpgsql;

select get_user_orders(1);
select get_user_orders(2);
