-- курсоры
-- варианты объявления
DROP TABLE IF EXISTS t;
CREATE TABLE t(id integer, s text);
drop event trigger if exists auto_grant_trigger; 
INSERT INTO t VALUES (1, 'Раз'), (2, 'Два'), (3, 'Три');

-- 1. Несвязанная переменная cur:
DO $$
DECLARE
    -- объявление переменной
    cur refcursor; 
BEGIN
    -- связывание с запросом и открытие курсора
    OPEN cur FOR SELECT * FROM t;
END;
$$;


-- 2. Связанная переменная связывается с запросом уже при объявлении.
DO $$
DECLARE
    -- объявление и связывание переменной
    cur CURSOR FOR SELECT * FROM t;
BEGIN
    -- открытие курсора
    OPEN cur; 
END;
$$;

-- 3. Связанная переменная может иметь параметры:
DO $$
DECLARE
    -- объявление и связывание переменной
    cur CURSOR(id integer) FOR SELECT * FROM t WHERE t.id = cur.id;
BEGIN
    -- открытие курсора с указанием фактических параметров
    OPEN cur(1);
END;
$$;

-- 4. Переменные PL/pgSQL также являются (неявными) параметрами курсора.

DO $$
<<local>>
DECLARE
    id integer := 3;
    -- объявление и связывание переменной
    cur CURSOR FOR SELECT * FROM t WHERE t.id = local.id;
BEGIN
    id := 1;
    -- открытие курсора (значение id берется на этот момент)
    OPEN cur;
END;
$$;

-- Чтение данных из курсора
-- Чтение выполняется командой FETCH. Если нужно только сдвинуть "окно" курсора, 
-- то можно воспользоваться другой командой - MOVE.

DO $$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR SELECT * FROM t ORDER BY id;
    MOVE cur;
    FETCH cur INTO rec;
    RAISE NOTICE '%', rec;
    CLOSE cur;
END;
$$;
-- Что будет выведено на экран?


-- Обработка курсора в цикле
-- Обычный способ организации цикла:
DO $$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR SELECT * FROM t;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE '%', rec;
    END LOOP;
    CLOSE cur;
END;
$$;

-- Чтобы не писать много команд, можно воспользоваться командой FOR, которая делает ровно то же самое:
DO $$
DECLARE
    cur CURSOR FOR SELECT * FROM t;
BEGIN
    FOR rec IN cur LOOP -- cur должна быть связана с запросом
        RAISE NOTICE '%', rec;
    END LOOP;
END;
$$;

-- Более того, можно вообще обойтись без явной работы с курсором, 
-- если цикл - это все, что требуется. 
-- такой цикл будет работать быстрее highly likely - NO SCROLL + cashing.
DO $$
DECLARE
    rec record; -- надо объявить явно
BEGIN
    FOR rec IN (SELECT * FROM t) LOOP
        RAISE NOTICE '%', rec;
    END LOOP;
END;
$$;

-- lets test
-- \timing
select count(*) from emp;

DO $$
DECLARE
    rec record; -- надо объявить явно
	i int = 0;
BEGIN
    FOR rec IN (SELECT * FROM emp) LOOP
		i = i + 1;
    END LOOP;
	RAISE NOTICE '%', i;
END;
$$;
-- 330

-- with cursor
DO $$
DECLARE
    rec record; -- надо объявить явно
    cur CURSOR FOR SELECT * FROM emp;
	i int = 0;
BEGIN
    FOR rec IN cur LOOP
		i = i + 1;
    END LOOP;
	RAISE NOTICE '%', i;
END;
$$;
-- 330

-- manual
DO $$
DECLARE
    rec record; -- надо объявить явно
    cur CURSOR FOR SELECT * FROM emp;
	i int = 0;
BEGIN
    OPEN cur;
	move cur;
	LOOP
		i = i + 1;
		if not found then 
			exit; 
		else 
			move cur;
		end if;
    END LOOP;
	RAISE NOTICE '%', i;
END;
$$;
-- 330

-- Точно так же, как и цикл LOOP, FOR позволяет указать метку 
-- во вложенных циклах это может оказаться полезным:
-- что делает данная анонимная функция? какой будет вывод на экран?
DO $$
DECLARE
    rec_outer record;
    rec_inner record;
BEGIN
    <<OUTER>>
    FOR rec_outer IN (SELECT * FROM t ORDER BY id) LOOP
        <<INNER>>
        FOR rec_inner IN (SELECT * FROM t ORDER BY id) LOOP
            EXIT OUTER WHEN rec_inner.id = 3;
            RAISE NOTICE '%, %', rec_outer, rec_inner;
        END LOOP INNER;
    END LOOP OUTER;
END;
$$;

-- Переменная FOUND позволяет узнать, была ли обработана хотя бы одна строка:
DO $$
DECLARE
    rec record;
BEGIN
    FOR rec IN (SELECT * FROM t WHERE false) LOOP
        RAISE NOTICE '%', rec;
    END LOOP;
    RAISE NOTICE 'Была ли как минимум одна итерация? %', FOUND;
END;
$$;

-- пример функции конкатенации
CREATE or replace FUNCTION loopcursor() RETURNS text AS $$
declare 
	cur cursor FOR SELECT s FROM t;
	t text;
	r record;
BEGIN
    t = '';
    for r in cur loop
      t = t || ', ' || r.col;
    end loop;
    RETURN t;
END;
$$ LANGUAGE plpgsql;

SELECT loopcursor();

table t;

CREATE or replace FUNCTION loopcursor() RETURNS text AS $$
declare 
	cur cursor FOR SELECT s FROM t;
	t text;
	r record;
BEGIN
    t = '';
    for r in cur loop
      t = t || ', ' || r.s;
    end loop;
    RETURN t;
END;
$$ LANGUAGE plpgsql;

SELECT loopcursor();

-- передача курсора как параметра на сторону клиента 
-- (до этого все было на стороне сервера)
-- Следующий пример показывает один из способов передачи имени курсора вызывающему:

CREATE TABLE test (col text);
INSERT INTO test VALUES ('123');
INSERT INTO test VALUES ('456');
INSERT INTO test VALUES ('789');

CREATE FUNCTION reffunc(refcursor) RETURNS refcursor AS '
BEGIN
    OPEN $1 FOR SELECT col FROM test;
    RETURN $1;
END;
' LANGUAGE plpgsql;

-- для использования курсоров на стороне клиента, необходимо начать транзакцию
BEGIN;
SELECT reffunc('funccursor');
FETCH ALL IN funccursor;
COMMIT;

-- Обновление или удаление текущей строки
-- Продемонстрируем обработку в цикле с обновлением строки, выбранной курсором. Типичный случай - обработка пакета заданий с изменением статуса задания.
DO $$
DECLARE
    cur refcursor;
    rec record;
BEGIN
    OPEN cur FOR SELECT * FROM t FOR UPDATE;
    LOOP
        FETCH cur INTO rec;
        EXIT WHEN NOT FOUND;
        UPDATE t SET s = s || ' (обработано)' WHERE CURRENT OF cur;
    END LOOP;
    CLOSE cur;
END;
$$;

SELECT * FROM t;

-- Использование курсора для больших данных:
drop table if exists users;
drop table if exists users1;
create table users1 (id serial, name text, email text,last_processed timestamp, status text default 'active');
insert into users1 (name,email) values ('ivan','email1'),('petr','email2');

CREATE OR REPLACE FUNCTION cursor_dynamic_loop(batch_size INTEGER DEFAULT 1000)
RETURNS TABLE(processed_count INTEGER, last_id INTEGER) AS $$
DECLARE
    dynamic_cursor REFCURSOR;
    current_query TEXT;
    record_count INTEGER := 0;
    total_processed INTEGER := 0;
    last_processed_id INTEGER := 0;
    user_record RECORD;
BEGIN
    -- Динамическое создание курсора
    current_query := format('
        SELECT id, name, email 
        FROM users1 
        WHERE status = ''active''
        ORDER BY id 
        LIMIT %s
    ', batch_size);
    
    -- Открытие курсора
    OPEN dynamic_cursor FOR EXECUTE current_query;
    
    LOOP
        -- Чтение записи
        FETCH dynamic_cursor INTO user_record;
        EXIT WHEN NOT FOUND;
        
        -- Обработка записи
        UPDATE users1 
        SET last_processed = NOW() 
        WHERE id = user_record.id;
        
        record_count := record_count + 1;
        total_processed := total_processed + 1;
        last_processed_id := user_record.id;
        
        -- Коммит каждые 100 записей (если нужно)
        IF record_count % 100 = 0 THEN
            -- COMMIT; -- раскомментировать если нужно
            record_count := 0;
        END IF;
    END LOOP;
    
    -- Закрытие курсора
    CLOSE dynamic_cursor;
    
    processed_count := total_processed;
    last_id := last_processed_id;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

select cursor_dynamic_loop();

table users1;


-- Мониторинг курсоров
SELECT * FROM pg_cursors;

-- а тперь посмотрим в psql
SELECT * FROM pg_cursors;

-- %)