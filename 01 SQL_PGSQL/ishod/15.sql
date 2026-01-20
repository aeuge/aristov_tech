-- Составной тип как тип строки таблицы
-- При создании таблицы неявно создается одноименный тип 
drop table if exists seats cascade;
drop type if exists seats cascade;
CREATE TABLE seats(
    line   text,
    number integer,
    vip    boolean
);


-- Команда \dT "прячет" такие неявные типы, но при желании их можно увидеть непосредственно в таблице pg_type.
-- можно объявить как RETURNS seats:
drop function make_seat;
CREATE FUNCTION make_seat(line text, number integer, vip boolean DEFAULT false) RETURNS seats AS $$
SELECT ROW(line, number, vip)::seats;
$$ IMMUTABLE LANGUAGE SQL;

SELECT make_seat('A',32);

-- Функцию можно вызывать не только в списке выборки запроса или в условиях, как часть выражения. 
-- К функции можно обратиться и в предложении FROM, как к таблице:
SELECT * FROM make_seat('A',32);
-- при этом постгрес знает имена и типы возвращаемых данных

-- кортежи %ROWTYPE
-- Создадим тестовую таблицу
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    salary NUMERIC(10,2),
    department TEXT,
    hire_date DATE DEFAULT CURRENT_DATE
);
insert into employees(name,salary,department) values ('Ivan',100,'IT');


-- Функция с использованием ROWTYPE
CREATE OR REPLACE FUNCTION get_employee_info(emp_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    emp_record employees%ROWTYPE;  -- Объявление переменной типа строки таблицы
BEGIN
    -- Получаем всю строку в переменную
    SELECT * INTO emp_record 
    FROM employees 
    WHERE id = emp_id;
    
    IF NOT FOUND THEN
        RETURN 'Сотрудник не найден';
    END IF;
    
    -- Доступ к полям через точку
    RETURN format('Сотрудник: %s, Зарплата: %s, Отдел: %s', 
                 emp_record.name, 
                 emp_record.salary, 
                 emp_record.department);
END;
$$ LANGUAGE plpgsql;

-- Использование в циклах: (24 тема)
CREATE OR REPLACE FUNCTION increase_salary_all(department_filter TEXT, percent NUMERIC)
RETURNS TABLE(emp_name TEXT, old_salary NUMERIC, new_salary NUMERIC) AS $$
DECLARE
    emp employees%ROWTYPE;
BEGIN
    FOR emp IN 
        SELECT * FROM employees 
        WHERE department = department_filter 
        OR department_filter IS NULL
    LOOP
        old_salary := emp.salary;
        emp.salary := emp.salary * (1 + percent/100);
        
        -- Обновляем запись в базе
        UPDATE employees 
        SET salary = emp.salary 
        WHERE id = emp.id;
        
        -- Возвращаем результат
        emp_name := emp.name;
        new_salary := emp.salary;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Работа с триггерами: (28 тема)
-- Таблица для аудита
CREATE TABLE employees_audit (
    id SERIAL PRIMARY KEY,
    operation CHAR(1),  -- I, U, D
    employee_id INTEGER,
    old_data employees%ROWTYPE,  -- Вся старая строка
    new_data employees%ROWTYPE,  -- Вся новая строка
    changed_by TEXT DEFAULT CURRENT_USER,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Триггерная функция
CREATE OR REPLACE FUNCTION log_employee_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO employees_audit (operation, employee_id, new_data)
        VALUES ('I', NEW.id, NEW);
        
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO employees_audit (operation, employee_id, old_data, new_data)
        VALUES ('U', NEW.id, OLD, NEW);
        
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO employees_audit (operation, employee_id, old_data)
        VALUES ('D', OLD.id, OLD);
    END IF;
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Создание триггера
CREATE TRIGGER employees_audit_trigger
    AFTER INSERT OR UPDATE OR DELETE ON employees
    FOR EACH ROW EXECUTE FUNCTION log_employee_changes();

-- Массовые операции:
CREATE OR REPLACE FUNCTION transfer_employees(
    from_department TEXT, 
    to_department TEXT
) RETURNS INTEGER AS $$
DECLARE
    emp employees%ROWTYPE;
    updated_count INTEGER := 0;
BEGIN
    FOR emp IN 
        SELECT * FROM employees 
        WHERE department = from_department
        FOR UPDATE  -- Блокировка для конкурентного доступа
    LOOP
        -- Изменяем поле в ROWTYPE переменной
        emp.department := to_department;
        
        -- Обновляем всю строку
        UPDATE employees 
        SET department = emp.department 
        WHERE id = emp.id;
        
        updated_count := updated_count + 1;
    END LOOP;
    
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;    

-- Копирование между разными таблицами:
CREATE TABLE employees_archive (
    LIKE employees INCLUDING ALL,  -- Такая же структура
    archived_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION archive_old_employees(years_old INTEGER)
RETURNS INTEGER AS $$
DECLARE
    emp employees%ROWTYPE;
    archived_count INTEGER := 0;
BEGIN
    FOR emp IN 
        SELECT * FROM employees 
        WHERE hire_date < CURRENT_DATE - (years_old * INTERVAL '1 year')
        FOR UPDATE
    LOOP
        -- Вставка в архивную таблицу
        INSERT INTO employees_archive 
        VALUES (emp.*, CURRENT_TIMESTAMP);
        
        -- Удаление из основной таблицы
        DELETE FROM employees WHERE id = emp.id;
        
        archived_count := archived_count + 1;
    END LOOP;
    
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql;


