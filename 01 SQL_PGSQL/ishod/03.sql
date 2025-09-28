-- Посмотрим разницу с SQL
CREATE or REPLACE FUNCTION increment(integer) RETURNS integer
    AS $$ SELECT $1 + 1; $$
LANGUAGE SQL;

-- необходимо указывать RETURN
-- появляется BEGIN/END
CREATE OR REPLACE FUNCTION increment(i integer) RETURNS integer AS $$
BEGIN
    RETURN i + 1;
END;
$$ LANGUAGE plpgsql;

SELECT increment(3);

-- где язык указывать также бьех разницы, но обычно в конце
CREATE OR REPLACE FUNCTION increment2(i integer) RETURNS integer LANGUAGE plpgsql AS $$
BEGIN
    RETURN i + 1;
END;
$$;

-- можно объявлять параметры - на sql тоже можно, но намного тяжелее их использовать
-- DECLARE
CREATE OR REPLACE FUNCTION increment3(i integer) RETURNS integer AS $$
DECLARE
    inc integer;
BEGIN
    inc = i + 1;
    RETURN inc;
END;
$$ LANGUAGE plpgsql;

SELECT increment3(33);

-- можно преобразовывать переменные, более подробно на 5 лекции
CREATE OR REPLACE FUNCTION increment4(i integer) RETURNS text AS $$
DECLARE
    t text;
BEGIN
    t = (i + 1)::text;
    RETURN t;
END;
$$ LANGUAGE plpgsql;

SELECT increment4(33);

-- обратите внимание, что REPLACE сработает только на если не меняется тип и количество переменных
CREATE OR REPLACE FUNCTION increment4(i integer) RETURNS integer AS $$
DECLARE
    inc integer;
BEGIN
    inc = i + 1;
    RETURN inc;
END;
$$ LANGUAGE plpgsql;

-- SQL Error [42P13]: ERROR: cannot change return type of existing function
-- Hint: Use DROP FUNCTION increment4(integer) first.


-- необходимо будет удалить старый вариант
drop function increment4(int);



-- pl/python

-- Попробуем выполнить запрос 1 миллион раз (в нашем случае 100_000), на разных языках разница будет заметней:
-- На PL/pgSQL:
-- аоннимная процедура (19 лекция)
DO $$
    DECLARE a int; i int;
    BEGIN FOR i IN 0..99999 LOOP
          SELECT count(*) INTO a FROM pg_class;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
-- для 1 млн: 35s

-- в 16 ПГ выключен и нет бинарников по умолчанию...
sudo apt update && sudo apt install postgresql-plpython3-16 -y
sudo -u postgres psql

CREATE EXTENSION plpython3u;

--- На PL/Python 3:
DO $$
     for i in range (0,100000) :
          plpy.execute('SELECT count(*) FROM pg_class')
$$ LANGUAGE plpython3u;
-- для 1 млн: 55s

-- В PL/Python можно явно работать с планами запросов. Например, так:
DO $$
     h = plpy.prepare('SELECT count(*) FROM pg_class')
     for i in range (0,100_000): 
           plpy.execute(h)
$$ LANGUAGE plpython3u;
-- для 1 млн: 42s

-- Итог - если можете писать на SQL - пишите на SQL или если что-то сложнее, то на PL/pgSQL