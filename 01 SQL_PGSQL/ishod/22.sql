-- УЯЗВИМЫЙ КОД
CREATE OR REPLACE FUNCTION vulnerable_login(username TEXT, password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    query TEXT;
    result BOOLEAN;
BEGIN
    query := 'SELECT EXISTS(SELECT 1 FROM users WHERE username = ''' || 
             username || ''' AND password = ''' || password || ''')';
    EXECUTE query INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- АТАКА
SELECT vulnerable_login('admin', 'anything'' OR ''1''=''1');
-- Сгенерированный запрос:
-- SELECT EXISTS(SELECT 1 FROM users WHERE username = 'admin' AND password = 'anything' OR '1'='1')



-- Инъекция в динамический SQL (тема 23):
-- УЯЗВИМЫЙ КОД
CREATE OR REPLACE FUNCTION search_products(category TEXT, price_limit NUMERIC)
RETURNS SETOF products AS $$
DECLARE
    query TEXT;
BEGIN
    query := 'SELECT * FROM products WHERE category = ''' || category || 
             ''' AND price <= ' || price_limit;
    RETURN QUERY EXECUTE query;
END;
$$ LANGUAGE plpgsql;

-- АТАКА
SELECT * FROM search_products('electronics', '100; DROP TABLE users --');
-- Сгенерированный запрос:
-- SELECT * FROM products WHERE category = 'electronics' AND price <= 100; DROP TABLE users 

-- Защита от SQL инъекций
-- Использование параметризованных запросов:

-- БЕЗОПАСНЫЙ КОД
CREATE OR REPLACE FUNCTION safe_login(username TEXT, password TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM users 
        WHERE username = safe_login.username 
        AND password = safe_login.password
    ) INTO result;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Или с EXECUTE USING
CREATE OR REPLACE FUNCTION safe_dynamic_search(category TEXT, price_limit NUMERIC)
RETURNS SETOF products AS $$
BEGIN
    RETURN QUERY EXECUTE '
        SELECT * FROM products 
        WHERE category = $1 AND price <= $2'
    USING category, price_limit;
END;
$$ LANGUAGE plpgsql;

-- Использование форматирования с экранированием:
-- БЕЗОПАСНОЕ ФОРМАТИРОВАНИЕ
CREATE OR REPLACE FUNCTION safe_table_operation(table_name TEXT, id_value INTEGER)
RETURNS VOID AS $$
DECLARE
    query TEXT;
BEGIN
    -- Экранирование идентификаторов
    query := format('SELECT * FROM %I WHERE id = $1', table_name);
    EXECUTE query USING id_value;
END;
$$ LANGUAGE plpgsql;

-- Для значений используем %L
CREATE OR REPLACE FUNCTION safe_value_insert(table_name TEXT, value TEXT)
RETURNS VOID AS $$
BEGIN
    EXECUTE format('INSERT INTO %I (data) VALUES (%L)', table_name, value);
END;
$$ LANGUAGE plpgsql;

-- безопасная аутентификация
CREATE OR REPLACE FUNCTION secure_authenticate(
    input_username TEXT,
    input_password TEXT
) RETURNS TABLE(user_id INTEGER, username TEXT, role TEXT) AS $$
DECLARE
    hashed_password TEXT;
    user_salt TEXT;
    stored_hash TEXT;
BEGIN
    -- Получаем соль и хеш из базы
    SELECT id, password_hash, password_salt 
    INTO user_id, stored_hash, user_salt
    FROM users 
    WHERE username = input_username AND is_active = true;
    
    IF NOT FOUND THEN
        RETURN;  -- Пользователь не найден
    END IF;
    
    -- Хешируем введенный пароль с солью
    hashed_password := crypt(input_password, user_salt);
    
    -- Сравниваем хеши
    IF hashed_password = stored_hash THEN
        -- Успешная аутентификация
        RETURN QUERY 
        SELECT u.id, u.username, r.name as role
        FROM users u
        JOIN roles r ON u.role_id = r.id
        WHERE u.id = secure_authenticate.user_id;
    ELSE
        -- Неудачная аутентификация
        RETURN;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Дополнительные меры защиты
-- Валидация входных данных:
CREATE OR REPLACE FUNCTION validate_and_process_user_input(
    user_input TEXT,
    expected_type TEXT DEFAULT 'text'
) RETURNS TEXT AS $$
BEGIN
    -- Проверка на NULL
    IF user_input IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- Валидация в зависимости от типа
    CASE expected_type
        WHEN 'email' THEN
            IF user_input !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
                RAISE EXCEPTION 'Invalid email format';
            END IF;
            
        WHEN 'integer' THEN
            IF user_input !~ '^-?\d+$' THEN
                RAISE EXCEPTION 'Invalid integer format';
            END IF;
            
        WHEN 'alphanumeric' THEN
            IF user_input !~ '^[A-Za-z0-9_]+$' THEN
                RAISE EXCEPTION 'Invalid alphanumeric format';
            END IF;
            
        WHEN 'name' THEN
            IF user_input !~ '^[A-Za-zА-Яа-я\s\-]+$' THEN
                RAISE EXCEPTION 'Invalid name format';
            END IF;
            
        ELSE
            -- Базовая проверка для текста
            IF length(user_input) > 1000 THEN
                RAISE EXCEPTION 'Input too long';
            END IF;
    END CASE;
    
    -- Экранирование специальных символов
    RETURN trim(user_input);
END;
$$ LANGUAGE plpgsql;

-- Ограничение прав доступа:

-- Создание пользователя с ограниченными правами
CREATE ROLE web_user WITH LOGIN PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE myapp TO web_user;
GRANT USAGE ON SCHEMA public TO web_user;

-- Только SELECT на конкретные таблицы
GRANT SELECT ON users, products TO web_user;

-- Только EXECUTE на безопасные функции
GRANT EXECUTE ON FUNCTION safe_product_search TO web_user;
GRANT EXECUTE ON FUNCTION secure_authenticate TO web_user;

-- ЗАПРЕТ на опасные операции
REVOKE ALL ON TABLE system_tables FROM web_user;
REVOKE EXECUTE ON FUNCTION dangerous_operations FROM web_user;