-- caveat search_path
show search_path;
select * from pg_class limit 10;
create table pg_class(i int);
select * from pg_class limit 10;
\dt
select * from public.pg_class;
create schema postgres;
create table pg_class(i int);
\dt+
select * from postgres.pg_class;
create temp table pg_class(i int);

-- общая тенденция выпиливать схему паблик, но некоторые миграторы без неё не могут
-- хорошее решение - указывать полное имя - схема.таблица
-- Защита от атак подмены схем:
-- ОПАСНО: пользователь может создать объект в public схеме
SET search_path TO public, hr;

-- БЕЗОПАСНО: убираем public из search_path
SET search_path TO hr;

-- ИЛИ явно указываем в конце
SET search_path TO hr, "$user", public;


-- неочидный кейс про search_path
\timing on
CREATE OR REPLACE FUNCTION f() RETURNS int AS 'SELECT 0' LANGUAGE SQL;
DO 'BEGIN PERFORM f() FROM generate_series(1, 10_000_000); END';
-- Time: 3031.713 ms (00:03.032)

ALTER FUNCTION f SET search_path = a,b,c;
DO 'BEGIN PERFORM f() FROM generate_series(1, 10_000_000); END';
-- Time: 18003.809 ms (00:18.004)

ALTER FUNCTION f SET search_path = thai;
--Time: 16365.469 ms (00:16.365)

ALTER FUNCTION f SET search_path = '';
-- Time: 15463.186 ms (00:15.463)

CREATE FUNCTION f2() RETURNS int AS 'SELECT 0' LANGUAGE SQL set search_path='';
DO 'BEGIN PERFORM f2() FROM generate_series(1, 10_000_000); END';
DO 'BEGIN PERFORM f2() FROM generate_series(1, 10_000_000); END';
-- Time: 14941.552 ms (00:14.942)
-- не включаем search_path, если он нам не нужен
