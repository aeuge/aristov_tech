  
-- простейший вариант IF
CREATE OR REPLACE FUNCTION check_value(num INTEGER)
RETURNS TEXT AS $$
BEGIN
    IF num > 100 THEN
        RETURN 'Больше 100';
    END IF;
    
    RETURN 'Меньше или равно 100';
END;
$$ LANGUAGE plpgsql;

SELECT check_value(150);
SELECT check_value(50); 


-- Проверить, существует ли пользователь с данным ID.
drop table users cascade;
CREATE TABLE IF NOT EXISTS users(id int, name text, rating int); 
INSERT INTO users VALUES (1,'Petr',100);
table users;

CREATE OR REPLACE FUNCTION is_user_exists(user_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    user_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count -- более подробна на 9 теме про SELECT INTO
    FROM users
    WHERE id = user_id;
    
    IF user_count > 0 THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

select is_user_exists(1);
select is_user_exists(2);

-- Классифицировать товар по цене.
CREATE OR REPLACE FUNCTION get_price_category(price NUMERIC)
RETURNS TEXT AS $$
BEGIN
    IF price < 1000 THEN
        RETURN 'Бюджетный';
    ELSIF price >= 1000 AND price < 5000 THEN
        RETURN 'Средний';
    ELSIF price >= 5000 AND price < 20000 THEN
        RETURN 'Премиум';
    ELSE
        RETURN 'Люкс';
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Вызов:
SELECT get_price_category(500); 
SELECT get_price_category(3000);
SELECT get_price_category(10000);
SELECT get_price_category(100000);

-- ELSIF
-- Получить статус заказа по его ID и обработать его.
drop table orders;
CREATE TABLE IF NOT EXISTS orders(id int, status text); 
INSERT INTO orders VALUES (1,'new'),(2,'processing');
table orders;


CREATE OR REPLACE FUNCTION process_order(order_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    order_status TEXT;
BEGIN
    -- Получаем статус заказа
    SELECT status INTO order_status
    FROM orders
    WHERE id = order_id;
    
    -- Обрабатываем в зависимости от статуса
    IF order_status = 'new' THEN
        UPDATE orders SET status = 'processing' WHERE id = order_id;
        RETURN 'Заказ взят в обработку';
    ELSIF order_status = 'processing' THEN
        RETURN 'Заказ уже в обработке';
    ELSIF order_status = 'completed' THEN
        RETURN 'Заказ уже завершен';
    ELSE
        RETURN 'Неизвестный статус заказа';
    END IF;
END;
$$ LANGUAGE plpgsql;

select process_order(1);
select process_order(2);
select process_order(3);


-- Проверить возможность скидки для пользователя.
-- вложенный IF

CREATE OR REPLACE FUNCTION apply_discount(user_id INTEGER, total_amount NUMERIC)
RETURNS NUMERIC AS $$
DECLARE
    user_rating INTEGER;
    discount NUMERIC := 0;
BEGIN
    -- Получаем рейтинг пользователя
    SELECT rating INTO user_rating FROM users WHERE id = user_id;
    
    IF user_rating > 50 THEN
        IF total_amount > 10000 THEN
            discount := 15; -- 15% скидка
        ELSIF total_amount > 5000 THEN
            discount := 10; -- 10% скидка
        ELSE
            discount := 5;  -- 5% скидка
        END IF;
    END IF;
    
    RETURN total_amount * (1 - discount / 100);
END;
$$ LANGUAGE plpgsql;

select apply_discount(1,5001);



-- более приближенный вариант к практике
CREATE FUNCTION fmt_out (IN phone text, OUT code text, OUT num text)
-- RETURNS можно не писать, предполагается RETURNS record
AS $$
BEGIN
    IF phone ~ '^[0-9]*$' AND length(phone) = 10 THEN
    --  ^[0-9]{10}$ - сразу проверить и количество символов
        code := substr(phone,1,3);
        num  := substr(phone,4);
    ELSE
        code := NULL;
        num  := NULL;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

select fmt_out('9512955050');

-- CASE
-- Классифицировать товар по типу.

CREATE OR REPLACE FUNCTION get_product_type(type_code CHAR(1))
RETURNS TEXT AS $$
BEGIN
    RETURN CASE type_code
        WHEN 'A' THEN 'Электроника'
        WHEN 'B' THEN 'Одежда'
        WHEN 'C' THEN 'Книги'
        WHEN 'D' THEN 'Мебель'
        ELSE 'Неизвестная категория'
    END;
END;
$$ LANGUAGE plpgsql;

SELECT get_product_type('A'); -- Электроника
SELECT get_product_type('X'); -- Неизвестная категория


--  Поисковый CASE (с сложными условиями)
-- Определить размер скидки в зависимости от суммы покупки и рейтинга клиента.

CREATE OR REPLACE FUNCTION calculate_discount(total_sum NUMERIC, user_rating INTEGER)
RETURNS NUMERIC AS $$
BEGIN
    RETURN CASE
        WHEN total_sum > 10000 AND user_rating > 80 THEN 15.0
        WHEN total_sum > 5000 AND user_rating > 60 THEN 10.0
        WHEN total_sum > 1000 THEN 5.0
        WHEN user_rating > 90 THEN 7.0 -- Скидка за лояльность
        ELSE 0.0
    END;
END;
$$ LANGUAGE plpgsql;

SELECT calculate_discount(12000, 85); -- 15.0
SELECT calculate_discount(3000, 95);  -- 5.0


-- CASE в SELECT внутри функции
-- Получить статус заказа в читаемом формате.
drop function get_order_status;
CREATE OR REPLACE FUNCTION get_order_status(order_id INTEGER)
RETURNS TEXT AS $$
DECLARE
    status_text TEXT = 'new';
BEGIN
    SELECT CASE status
        WHEN status_text THEN 'Новый'
        WHEN 'processing' THEN 'В обработке'
        WHEN 'shipped' THEN 'Отправлен'
        WHEN 'delivered' THEN 'Доставлен'
        WHEN 'cancelled' THEN 'Отменен'
        ELSE 'Неизвестный статус'
    END INTO status_text
    FROM orders
    WHERE id = order_id;
    
    RETURN status_text;
END;
$$ LANGUAGE plpgsql;

SELECT get_order_status(1);
SELECT get_order_status(2);   