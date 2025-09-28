-- примеры объявления параметров
-- безымянные - по номеру входящей переменной
-- int == integer
CREATE OR REPLACE FUNCTION instr(int, integer) RETURNS integer AS $$
BEGIN
    return $1 + $2;
END;
$$ LANGUAGE plpgsql;

select instr('1',2);


-- можно давать алиасы - имхо масло масляное
CREATE OR REPLACE FUNCTION instr2(varchar, integer) RETURNS integer AS $$
DECLARE
    v_string ALIAS FOR $1;
    index ALIAS FOR $2;
BEGIN
    -- вычисления, использующие v_string и index
    	return v_string + index;
-- автопреобразование НЕ сработало - лучше писать явное преобразование в PG style ::	
-- return v_string::int + index;
END;
$$ LANGUAGE plpgsql;

select instr2('1',2);

-- самый корректный вариант - сразу задать имена переменным
CREATE OR REPLACE FUNCTION instr3(i int, y int) RETURNS integer AS $$
BEGIN
    return i + y;
END;
$$ LANGUAGE plpgsql;

select instr3(1,2);

-- или используя OUT переменные - более подробно на 14 лекции
CREATE OR REPLACE FUNCTION instr4(i int, y int, out sum int, out prod int) AS $$
BEGIN
    sum = i + y;
	prod = i*y;
END;
$$ LANGUAGE plpgsql;

select instr4(1,2);
select * from  instr4(1,2);

-- использование дефолтного значения при передаче параметров
CREATE OR REPLACE FUNCTION instr5(i int, y int default 100) returns int AS $$
BEGIN
    return i + y;
END;
$$ LANGUAGE plpgsql;

select instr5(1);



-- DECLARE
-- можем объявлять переменные в каждом блоке (рассмотрим подпробнее на следующей лекции)
-- обратите внимание - создали локальную переменную с таким же именем i
CREATE OR REPLACE FUNCTION decl(i integer) RETURNS text AS $$
DECLARE
    str text = '';
    i integer default 100;
    i2 int;
    d timestamp DEFAULT now();
BEGIN
    i2 := 333;
    RAISE NOTICE 'i, %', i;
    RAISE NOTICE 'local i, %', local.i;
    RAISE NOTICE 'global i, %', decl.i;
    return str || ', ' || i || ', ' || i2 || ', ' || d;
END;
$$ LANGUAGE plpgsql;

select decl(1);
select decl();

-- объявляем МЕТКУ для блока
-- обращаемся уже четко и конкретно
CREATE OR REPLACE FUNCTION decl2(i integer) RETURNS text AS $$
<<metka>>
DECLARE
    i integer default 100;
BEGIN
    RAISE NOTICE 'i, %', i;
    RAISE NOTICE 'local i, %', metka.i;
    RAISE NOTICE 'global i, %', decl.i;
    return i::text;
END;
$$ LANGUAGE plpgsql;

select decl2(1);

-- функции для работы с разными типами данных
-- https://www.postgresql.org/docs/current/functions.html