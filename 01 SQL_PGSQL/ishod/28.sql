-- триггерная функция
-- если несколько триггеров на одно событие, они сортруются по имени
DROP TABLE IF EXISTS shop;
CREATE TABLE shop (id serial, tovar text, kolvo int, price numeric(12,2));
truncate shop;
INSERT INTO shop(tovar,kolvo, price) 
VALUES ('apple', 10, 13.30),
	   ('cherry', 20, 35.99);
SELECT * FROM shop;

DROP TABLE IF EXISTS sales;
CREATE TABLE sales (id serial, tovar text, kolvo int, total numeric(12,2));

CREATE or replace FUNCTION ostatok() RETURNS trigger AS $emp_stamp$
DECLARE
	p numeric(12,2);
BEGIN
   -- уменьшим остатки
   -- предполагаем, что товара хватает и мы это проверили ДО продажи
   -- иначе неплохо было бы сюда добавить проверку, например select for update
   -- еще один из паттернов - CHECK kolvo >= 0 - автоматически проверим при update
   UPDATE shop set kolvo = kolvo - new.kolvo WHERE tovar = new.tovar;

  -- узнаем цену товара
   SELECT price INTO p FROM shop WHERE tovar = new.tovar;

  -- установим сумму продажи
   new.total = new.kolvo*p;
   RETURN NEW;
END;
$emp_stamp$ LANGUAGE plpgsql;

CREATE TRIGGER ostatok BEFORE insert ON sales
    FOR EACH ROW EXECUTE FUNCTION ostatok();

truncate sales;
INSERT INTO sales(tovar,kolvo) 
VALUES ('apple', 1),
	   ('apple', 2),
	   ('cherry', 2);
SELECT * FROM sales;
SELECT * FROM shop;

-- простейший кейс на проверку и дообогащение информацией
drop TABLE if exists emp;
CREATE TABLE emp (
    empname text,
    salary integer,
    last_date timestamp,
    last_USER text
);

CREATE FUNCTION emp_stamp() RETURNS trigger AS $emp_stamp$
    BEGIN
        -- Проверить, что указаны имя сотрудника и зарплата
        IF NEW.empname IS NULL THEN
            RAISE EXCEPTION 'empname cannot be null';
        END IF;
        IF NEW.salary IS NULL THEN
            RAISE EXCEPTION '% cannot have null salary', NEW.empname;
        END IF;

        -- Кто будет работать, если за это надо будет платить?
        IF NEW.salary < 0 THEN
            RAISE EXCEPTION '% cannot have a negative salary', NEW.empname;
        END IF;

        -- Запомнить, кто и когда изменил запись
        NEW.last_date := current_timestamp;
        NEW.last_USER := current_user;
        RETURN NEW;
    END;
$emp_stamp$ LANGUAGE plpgsql;

-- INSERT OR UPDATE
CREATE TRIGGER emp_stamp BEFORE INSERT OR UPDATE ON emp
    FOR EACH ROW EXECUTE FUNCTION emp_stamp();

INSERT INTO emp(empname, salary) VALUES ('Ivan', 100);
SELECT * FROM emp;
update emp set salary = 200;
SELECT * FROM emp;

-- Триггерная функция для аудита в PL/pgSQL
-- !!! AFTER !!!
drop TABLE if exists emp;
CREATE TABLE emp (
    empname           text NOT NULL,
    salary            integer
);

drop TABLE if exists emp_audit;
CREATE TABLE emp_audit(
    operation         char(1)   NOT NULL,
    stamp             timestamp NOT NULL,
    userid            text      NOT NULL,
    empname           text      NOT NULL,
    salary integer
);

CREATE OR REPLACE FUNCTION process_emp_audit() RETURNS TRIGGER AS $emp_audit$
    BEGIN
        --
        -- Добавление строки в emp_audit, которая отражает операцию, выполняемую в emp;
        -- для определения типа операции применяется специальная переменная TG_OP.
        --
        IF (TG_OP = 'DELETE') THEN
            INSERT INTO emp_audit SELECT 'D', now(), user, OLD.*;
        ELSIF (TG_OP = 'UPDATE') THEN
            INSERT INTO emp_audit SELECT 'U', now(), user, NEW.*;
        ELSIF (TG_OP = 'INSERT') THEN
            INSERT INTO emp_audit SELECT 'I', now(), user, NEW.*;
        END IF;
        RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
    END;
$emp_audit$ LANGUAGE plpgsql;

CREATE TRIGGER emp_audit
AFTER INSERT OR UPDATE OR DELETE ON emp
    FOR EACH ROW EXECUTE FUNCTION process_emp_audit();
   
INSERT INTO emp(empname, salary) VALUES ('Ivan', 100);
SELECT * FROM emp;
SELECT * FROM emp_audit;

-- for temp_table processing
CREATE OR REPLACE FUNCTION process_emp_audit2() RETURNS TRIGGER AS $emp_audit$
 declare s int = 0;
    begin
	    select count(*) into s from temp_table;
		raise notice 'count rows for all operations - %', s;
        RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
    END;
$emp_audit$ LANGUAGE plpgsql;

-- триггер на всю операцию
drop trigger if exists emp_audit2 on emp;
create TRIGGER emp_audit2
AFTER INSERT ON emp
referencing new table as temp_table -- создаем временную таблицу с результатами
FOR EACH STATEMENT EXECUTE FUNCTION process_emp_audit2();

INSERT INTO emp(empname, salary) VALUES ('Ivan', 100),('Ivan2', 1000);

CREATE OR REPLACE FUNCTION process_emp_audit3() RETURNS TRIGGER AS $emp_audit$
 declare s record;
    begin
	    for s in select * into s from temp_table
	    loop
			raise notice '%', s;
		end loop;
        RETURN NULL; -- возвращаемое значение для триггера AFTER игнорируется
    END;
$emp_audit$ LANGUAGE plpgsql;

-- триггер на всю операцию
drop trigger emp_audit3 on emp;
create TRIGGER emp_audit3
AFTER update ON emp
referencing new table as temp_table -- создаем временную таблицу с результатами, которую можно потом обработать
FOR EACH STATEMENT EXECUTE FUNCTION process_emp_audit3();

update emp set empname = empname || '2';
-- SQL Error [42P11]: ERROR: cannot open SELECT INTO query as cursor


-- производительность триггеров
sudo -u postgres psql

drop TABLE if exists emp cascade;
CREATE TABLE emp (
    empname text,
    salary integer,
    last_date timestamp
);

drop TABLE if exists emp2 cascade;
CREATE TABLE emp2 (
    empname text,
    salary integer,
    last_date timestamp default now()
);

drop TABLE if exists emp3 cascade;
CREATE TABLE emp3 (
    empname text,
    salary integer,
    last_date timestamp
);

drop TABLE if exists emp4 cascade;
CREATE TABLE emp4 (
    empname text,
    salary integer,
    last_date timestamp
);


CREATE or replace FUNCTION emp_stamp() RETURNS trigger AS $emp_stamp$
    BEGIN
        NEW.last_date := current_timestamp;
        RETURN NEW;
    END;
$emp_stamp$ LANGUAGE plpgsql;

CREATE TRIGGER emp_stamp BEFORE INSERT OR UPDATE ON emp
    FOR EACH ROW EXECUTE FUNCTION emp_stamp();

\timing
-- триггер
DO $$
     BEGIN FOR i IN 0..999999 LOOP
        INSERT INTO emp(empname, salary) 
        VALUES ('Ivan', 100)
        ;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- Time: 5.1

-- default value
DO $$
     BEGIN FOR i IN 0..999999 LOOP
        INSERT INTO emp2(empname, salary) 
        VALUES ('Ivan', 100)
        ;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Time: 3.4

-- сразу значение
DO $$
     BEGIN FOR i IN 0..999999 LOOP
        INSERT INTO emp3(empname, salary,last_date) 
        VALUES ('Ivan', 100,'20250311')
        ;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- Time: 2.0

-- из-за преобразования типов также может незначительно снижаться производительность
-- генерируем значение - вопрос еще по быстродействию функций даты/времени
DO $$
     BEGIN FOR i IN 0..999999 LOOP
        INSERT INTO emp4(empname, salary,last_date) 
        VALUES ('Ivan', 100,now())
        ;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- Time: 1.3 ms 

-- проверяем update
-- generated always - также для update
drop TABLE if exists emp5 cascade;
CREATE TABLE emp5 (
    empname text,
    salary integer,
    last_date timestamp GENERATED ALWAYS AS (now()) STORED
);
ERROR:  generation expression is not immutable

create or replace function mynow() returns timestamp
as 'select now()' language sql immutable;

CREATE TABLE emp5 (
    empname text,
    salary integer,
    last_date timestamp GENERATED ALWAYS AS (mynow()) STORED
);

DO $$
     BEGIN FOR i IN 0..999999 LOOP
        INSERT INTO emp5(empname, salary) 
        VALUES ('Ivan', 100)
        ;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- Time: 17 (00:08.536)
-- !!! также generated timestamp column обновится при восстановлении из pg_dump !!!
pg_dump -d postgres -t emp5 > 1.scv
tail 1.scv
Ivan    100
Ivan    100
Ivan    100
-- при экспорте генерируемые поля не экспортируются

-- update
-- 1
update emp set salary = salary + 1;
-- Time: 4262.549 ms (00:04.263)

--2 и 4 одно и то же
update emp2 set salary = salary + 1, last_date=now();
-- Time: 2494.609 ms (00:02.495)

--3
update emp3 set salary = salary + 1, last_date='20250311 00:00:00';
Time: 2096.003 ms (00:02.096)
-- оижадемо, если в правилььном формате - самый быстры метод


--5
update emp5 set salary = salary + 1;
-- Time: 1775.843 ms (00:01.776)
table emp5 limit 1;
-- а вот это неожиданно - хотя - GENERATED не вызывается, так как поле не участвует в update и значение будет НЕВЕРНОЕ !!!
 Ivan    |    101 | 2025-03-11 15:09:35.840863 - а сейчас 15:16 


-- ещё кейсы
-- Триггерная функция для мягкого удаления
CREATE OR REPLACE FUNCTION soft_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Вместо удаления помечаем запись как удаленную
        EXECUTE format('
            UPDATE %I 
            SET deleted_at = CURRENT_TIMESTAMP 
            WHERE id = $1
        ', TG_TABLE_NAME) USING OLD.id;
        
        RETURN NULL; -- Отменяем фактическое удаление
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER soft_delete_trigger
    BEFORE DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION soft_delete();

-- список существующих триггеров
select * from pg_trigger;



-- если закончилось место
/usr/lib/postgresql/16/bin/pg_resetwal -f -D /var/lib/postgresql/16/main
-- или увеличить в disk manager (ctrl+d) в virtual box
-- далее в Ubuntu 
-- sudo apt install gparted
-- sudo gparted
-- и увеличить раздел