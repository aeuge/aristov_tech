-- использование составного типа
CREATE TYPE currency AS (
    amount numeric,
    code   text
);
drop table if exists transactions;
CREATE TABLE transactions(
    account_id   integer,
    debit        currency,
    credit       currency,
    date_entered date DEFAULT current_date
);

-- Значения составного типа можно формировать либо в виде строки, 
-- внутри которой в скобках перечислены значения
INSERT INTO transactions VALUES(1, NULL, '(7000.00,"RUR")');

-- Либо с помощью табличного конструктора ROW:
INSERT INTO transactions VALUES(2, ROW(350.00,'RUR'), NULL);

-- Если составной тип содержит более одного поля, то слово ROW можно опустить:
INSERT INTO transactions VALUES(3, (20.00,'RUR'), NULL);

SELECT * FROM transactions;


-- Функция для работы с составным типом:

CREATE TYPE dup_result AS (f1 int, f2 text);

CREATE or replace FUNCTION dup2(int) RETURNS dup_result
    AS $$ SELECT $1, CAST($1 AS text) || ' is text' $$
    LANGUAGE SQL;

SELECT * FROM dup2(42);
SELECT dup2(42);


-- Дальше мы можем создать функции для работы с этим типом. Например:
CREATE FUNCTION multiply(factor numeric, cur currency) RETURNS currency AS $$
    SELECT ROW(factor * cur.amount, cur.code)::currency;
$$ IMMUTABLE LANGUAGE SQL;

select * from transactions;
SELECT account_id, multiply(2,debit), multiply(2,credit), date_entered FROM transactions;

-- Хотелось бы, чтобы такая функция не превращала неопределенное значение в пустую запись. 
-- Для этого можно либо явно выполнить необходимую проверку, либо указать для функции свойство STRICT:
ALTER FUNCTION multiply(numeric, currency) STRICT;



-- вычисляемые поля
CREATE FUNCTION textcurrency(tr transactions) RETURNS text AS $$
    SELECT tr.account_id || tr.date_entered::text;
$$ IMMUTABLE LANGUAGE SQL;

SELECT textcurrency(ROW(32,'RUB'));
SELECT t.*, textcurrency(t.*) FROM transactions t;

-- Синтаксисом допускается обращение к функции как к столбцу таблицы (и наоборот, к столбцу как к функции).
SELECT t.*, t.textcurrency FROM transactions t; -- виртуальная колонка - вычисляется каждый раз при вызове функции


-- Создадим еще один составной тип данных
-- место в самолёте
drop type if exists seats cascade;
CREATE type seats as (
    line   text,	
    number integer,
    vip    boolean
);

-- вычисляемые поля
CREATE FUNCTION no(seat seats) RETURNS text AS $$
    SELECT seat.line || seat.number;
$$ IMMUTABLE LANGUAGE SQL;

SELECT no(ROW('A',32,false));
drop table if exists seats cascade;
create table seats (
	line   text,	
    number integer,
    vip    boolean);


SELECT no(ROW('A',32,false));
INSERT INTO seats VALUES ('A',32,true), ('B',3,false), ('C',27,false);
SELECT s.line, s.number, no(s.*) FROM seats s;

-- Синтаксисом допускается обращение к функции как к столбцу таблицы (и наоборот, к столбцу как к функции).
-- number(s) <-> s.number
-- s.no <-> no(s.*)
SELECT s.line, number(s), s.no FROM seats s; 
-- то же самое 
SELECT s.line, s.number, no(s.*) FROM seats s;


-- если совпадает имя поля и имя функции
CREATE FUNCTION line(seat seats) RETURNS text AS $$
    SELECT seat.line || seat.number;
$$ IMMUTABLE LANGUAGE SQL;

SELECT s.line, number(s) FROM seats s;
SELECT s.line, number(s), line(s) FROM seats s;
SELECT s.line, number(s), line(s.*) FROM seats s;

-- Значения составных типов можно сравнивать между собой. Это происходит поэлементно 
-- (примерно так же, так строки сравниваются посимвольно):
SELECT * FROM seats s WHERE s < row('B',52,false)::seats;


-- RECORD
-- вариант - объявить функцию как возвращающую псевдотип record, который обозначает составной тип "вообще", без уточнения его структуры.
DROP FUNCTION make_seat(text, integer, boolean);
CREATE FUNCTION make_seat(line text, number integer, vip boolean DEFAULT false) RETURNS record AS $$
    SELECT line, number, vip;
$$ IMMUTABLE LANGUAGE SQL;

SELECT make_seat('A',42);

-- Но вызвать такую функцию в предложении FROM уже не получится, поскольку возвращаемый составной тип не просто анонимный,
-- но и количество и типы его полей заранее (на этапе разбора запроса) неизвестны:

SELECT * FROM make_seat('A',42);

-- В этом случае при вызове функции структуру составного типа придется уточнить:
SELECT * FROM make_seat('A',42) AS seats(line text, number integer, vip boolean);

-- вернуть множество анонимных записей
DROP FUNCTION if exists make_seat_setof(text, integer, boolean);
CREATE FUNCTION make_seat_setof(line text, number integer, vip boolean DEFAULT false) RETURNS SETOF record AS $$
begin
	return query SELECT line, number, vip, vip;
	return query select line, number, vip, vip;
end;
$$ LANGUAGE plpgSQL;
SELECT make_seat_setof('A',42);

-- одна проблема - нужно все равно указать типы при разборе анонимной записи
SELECT * FROM make_seat_setof('A',42) AS seats(line text, number integer, vip boolean, vip2 boolean);


-- Ещё один способ вернуть несколько столбцов — применить функцию TABLE:
CREATE or replace FUNCTION dup3(int) RETURNS TABLE(f1 int, f2 text)
    AS $$ SELECT $1, CAST($1 AS text) || ' is text' $$
    LANGUAGE SQL;

SELECT * FROM dup3(42);

-- Однако пример с TABLE отличается от предыдущих,
-- так как в нём функция на самом деле возвращает не одну, а набор записей.

SELECT f1 FROM dup3(42);


-- SETOF
-- второй вариант вернуть несколько строк
-- Напишем функцию, которая вернет все места в зале заданного размера (и ближняя половина зала будет считаться vip-зоной).
CREATE FUNCTION make_seats(max_line integer, max_number integer) RETURNS SETOF seats AS $$
    SELECT chr(line+64), number, line <= max_line/2
    FROM generate_series(1,max_line) AS lines(line), generate_series(1,max_number) AS numbers(number);
$$ IMMUTABLE LANGUAGE SQL;

select * from make_seats(5,5);





