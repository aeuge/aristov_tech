SELECT current_database();

-- вывод notice в DBeaver
shift+ctrl+o  
/*
  тоже комментарий
*/

-- простые примеры 
-- язык SQL
-- DDL
-- immutable - значение будет закешировано для одних и тех же аргументов
-- экранируем с использованием кавычек
drop function if exists add;
CREATE FUNCTION add(integer, integer) RETURNS integer
    AS 'SELECT $1 + $2;'
LANGUAGE SQL
IMMUTABLE
RETURNS NULL ON NULL INPUT;

-- 2 варианта обращения к функции
SELECT add(3,4);
SELECT * from add(3,4);

SELECT add(null,20);

-- если дефолтное значение и вызов с NULL INPUT
drop function add2;
CREATE or replace FUNCTION add2(integer, integer default 42) RETURNS integer
    AS 'SELECT $1 + $2;'
LANGUAGE SQL
IMMUTABLE
RETURNS NULL ON NULL INPUT;

SELECT add2(20, null);
SELECT add2(20);

-- посмотрим на поведение STRICT
CREATE or REPLACE FUNCTION add3(integer, integer default 42) RETURNS integer
    AS 'SELECT $1 + $2;'
LANGUAGE SQL
IMMUTABLE
STRICT;

SELECT add3(20, null);


-- Функция увеличения целого числа на 1, использующая именованный аргумент, на языке PL/pgSQL:
-- обратим внимание на OR REPLACE
-- экранируем с использованием $$
CREATE or REPLACE FUNCTION increment(integer) RETURNS integer
    AS $$ SELECT $1 + 1; $$
LANGUAGE SQL;

SELECT increment(3);


-- экранируем с использованием $имя_функции$
CREATE OR REPLACE FUNCTION increment2(i integer) RETURNS integer AS 
$increment2$ SELECT $1 + 1; $increment2$ 
LANGUAGE sql;

SELECT increment2(33);

-- где конкретно указывать параметры функции не важно, но обычно в конце
CREATE OR REPLACE FUNCTION increment3(i integer) RETURNS integer 
LANGUAGE sql AS $increment3$
    SELECT i + 1;
$increment3$;

SELECT increment3(299);

-- можно писать всё и в 1 строку - но очень не рекомендовано, из-за неудобства чтения
CREATE FUNCTION add(integer, integer) RETURNS integer AS 'SELECT $1 + $2;' LANGUAGE SQL IMMUTABLE RETURNS NULL ON NULL INPUT;
