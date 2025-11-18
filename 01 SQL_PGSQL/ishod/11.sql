\echo :AUTOCOMMIT
SELECT txid_current();

begin;
SELECT txid_current();
SELECT txid_current();
-- Категории изменчивости и изоляция
-- В целом использование функций внутри запросов не нарушает установленный уровень изоляции транзакции, но есть аномалии
-- Функции с изменчивостью volatile на уровне изоляции read committed могут приводить к рассогласованию данных 
-- внутри одного запроса.
CREATE TABLE t(n integer);
INSERT INTO t VALUES (1), (2), (3);

CREATE FUNCTION cnt() RETURNS bigint AS $$
SELECT count(*) FROM t;
$$ VOLATILE LANGUAGE SQL;

-- Теперь вызовем ее несколько раз с задержкой, 
-- а в параллельном сеансе вставим в таблицу дополнительную строку.

BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT (SELECT count(*) FROM t), cnt(), pg_sleep(1) FROM generate_series(1,4);

-- в параллельном сеансе
INSERT INTO t VALUES (4);

 count | cnt | pg_sleep 
-------+-----+----------
     3 |   3 | 
     3 |   3 | 
     3 |   4 | 
     3 |   4 | 

-- При изменчивости sTABLE или immuTABLE, либо использовании более строгих уровней изоляции, такого не происходит.

ALTER FUNCTION cnt() STABLE;
TRUNCATE t;
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT (SELECT count(*) FROM t), cnt(), pg_sleep(1) FROM generate_series(1,4);

-- в 2 окне
INSERT INTO t VALUES (4);

 count | cnt | pg_sleep 
-------+-----+----------
     0 |   0 | 
     0 |   0 | 
     0 |   0 | 
     0 |   0 | 

-- Второй момент связан с видимостью изменений, сделанных собственной транзакцией.
-- Функции с изменчивостью volatile видят все изменения, в том числе сделанные текущим, 
--еще не завершенным оператором SQL.

ALTER FUNCTION cnt() VOLATILE;
TRUNCATE t;
INSERT INTO t SELECT cnt() FROM generate_series(1,5);
SELECT * FROM t;

 n 
---
 0
 1
 2
 3
 4

-- Это верно для любых уровней изоляции.
-- Функции с изменчивостью stable или immutable видят изменения только уже завершенных операторов.

ALTER FUNCTION cnt() STABLE;
TRUNCATE t;
INSERT INTO t SELECT cnt() FROM generate_series(1,5);
SELECT * FROM t;

 n 
---
 0
 0
 0
 0
 0

-- не видят внесенных изменений

-- Категории изменчивости и оптимизация
-- Благодаря дополнительной информации о поведении функции,
-- которую дает указание категории изменчивости, 
-- оптимизатор может сэкономить на вызовах функции.
-- Для экспериментов создадим функцию, возвращающую случайное число:

CREATE FUNCTION rnd() RETURNS float AS $$
SELECT random();
$$ VOLATILE LANGUAGE SQL;

EXPLAIN(COSTS OFF) SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

-- В этом можно убедиться и воочию (ожидаем в среднем получить 5 строк):
SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

 generate_series 
-----------------
               1
               2
               3
               5
               9

-- Функция с изменчивостью STABLE будет вызвана всего один раз - поскольку мы фактически указали,
-- что ее значение не может измениться в пределах оператора:

ALTER FUNCTION rnd() STABLE;
EXPLAIN(COSTS OFF) SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

-- Наконец, изменчивость IMMUTABLE позволяет вычислить функции еще на этапе планирования, 
-- поэтому во время выполнения никакие фильтры не нужны:

ALTER FUNCTION rnd() IMMUTABLE;
EXPLAIN(COSTS OFF) SELECT * FROM generate_series(1,10) WHERE rnd() > 0.5;

-- Ответственность "за дачу заведомо ложных показаний" лежит на разработчике.



-- сайд эффект рандома
psql -d thai
\timing
select floor(random()*5000000) as r \gset
\echo :r
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets WHERE id = :r;

-- 500ms
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets WHERE id = floor(random()*5000000);
   id    | fkride |      fio       |          contact          | fkseat
---------+--------+----------------+---------------------------+--------
  674871 | 103825 | VLASOV MARYAM  | {"phone": "+74275419139"} |     16
 4116828 |  62023 | STEPANOV MURAD | {"phone": "+79194823817"} |     96
(2 rows)

-- volitile
\df+ random


create function cc() returns int as
$$
  select floor(random()*5000000)
$$ language sql immutable;

-- 0.7ms
SELECT id, fkRide, fio, contact, fkSeat FROM book.tickets b WHERE id = cc();


-- но в рамках одного потока есть нюанс
-- планировщик может поменять её сам
begin;
select cc();
select cc();
rollback;

begin transaction isolation level repeatable read;
select cc();
select cc();
commit;

begin transaction isolation level serializable;
select cc();
select cc();
commit;
