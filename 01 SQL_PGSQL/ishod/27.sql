-- Доступ и модификация элементов массива
CREATE OR REPLACE FUNCTION array_access()
RETURNS TABLE(operation TEXT, result TEXT) AS $$
DECLARE
    fruits TEXT[] := ARRAY['яблоко', 'банан', 'апельсин'];
    first_fruit TEXT;
    last_fruit TEXT;
    sliced_fruits TEXT[];
BEGIN
    -- Доступ к элементам (индексация с 1)
    first_fruit := fruits[1];
    last_fruit := fruits[array_length(fruits, 1)];
    
    -- Изменение элементов
    fruits[2] := 'груша';
    
    -- Срез массива
    sliced_fruits := fruits[1:2];  -- ['яблоко', 'груша']
    
    -- Возврат результатов
    operation := 'Первый элемент'; result := first_fruit; RETURN NEXT;
    operation := 'Последний элемент'; result := last_fruit; RETURN NEXT;
    operation := 'Срез'; result := array_to_string(sliced_fruits, ', '); RETURN NEXT;
    operation := 'Весь массив'; result := array_to_string(fruits, ', '); RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

select array_access();


-- пример цикла по элементам массива
drop function sum(int[]);
CREATE or replace FUNCTION sum(arr text[]) RETURNS text AS $$
DECLARE
  s text := '';
  x text;
BEGIN
  FOREACH x IN ARRAY arr
  LOOP
    s := s || x;
  END LOOP;
	raise notice '%',arr[1]; -- можем обратиться к конкретному элементу	
  RETURN s;
END;
$$ LANGUAGE plpgsql;

SELECT sum(array['1','2','3','4']);

-- Цикл по индексам:
CREATE OR REPLACE FUNCTION array_index_loop()
RETURNS void AS $$
DECLARE
    prices NUMERIC[] := ARRAY[100, 200, 300];
    i INTEGER;
BEGIN
    -- Цикл по индексам
    FOR i IN 1..array_length(prices, 1)
    LOOP
        RAISE NOTICE 'Цена %: % руб.', i, prices[i];
        
        -- Модификация элемента
        prices[i] := prices[i] * 1.1;  -- +10%
    END LOOP;
    
    RAISE NOTICE 'Новые цены: %', prices;
END;
$$ LANGUAGE plpgsql;

select array_index_loop();

-- функции
CREATE OR REPLACE FUNCTION array_operations()
RETURNS void AS $$
DECLARE
    numbers INTEGER[] := ARRAY[1, 2, 3];
    extended_numbers INTEGER[];
    filtered_numbers INTEGER[];
BEGIN
    -- Добавление элементов
    numbers := array_append(numbers, 4);        -- [1, 2, 3, 4]
    numbers := array_prepend(0, numbers);       -- [0, 1, 2, 3, 4]
    numbers := array_cat(numbers, ARRAY[5, 6]); -- [0, 1, 2, 3, 4, 5, 6]
    
    -- Удаление элементов
    numbers := array_remove(numbers, 3);        -- Удалить все 3
    numbers := array_remove(numbers, 999);      -- Ничего не изменится
    
    -- Фильтрация (через unnest)
    SELECT ARRAY(
        SELECT elem 
        FROM unnest(numbers) AS elem 
        WHERE elem % 2 = 0
    ) INTO filtered_numbers;
    
    RAISE NOTICE 'Исходный массив: %', numbers;
    RAISE NOTICE 'Четные числа: %', filtered_numbers;
END;
$$ LANGUAGE plpgsql;

select array_operations();

-- Взаимодействие с другими типами:
CREATE OR REPLACE FUNCTION array_conversion()
RETURNS void AS $$
DECLARE
    text_array TEXT[] := ARRAY['1', '2', '3'];
    int_array INTEGER[];
    csv_text TEXT := 'яблоко,банан,апельсин';
    from_csv TEXT[];
    merged_array TEXT[];
BEGIN
    -- Преобразование типов
    int_array := text_array::INTEGER[];
    
    -- Из строки в массив
    from_csv := string_to_array(csv_text, ',');
    
    -- Из массива в строку
    RAISE NOTICE 'CSV: %', array_to_string(from_csv, '|');
    
    -- Объединение массивов
    merged_array := text_array || from_csv;
    RAISE NOTICE 'Объединенный: %', merged_array;
    
    -- Уникальные значения
    RAISE NOTICE 'Уникальные: %', ARRAY(SELECT DISTINCT unnest(merged_array));
END;
$$ LANGUAGE plpgsql;

select array_conversion();

-- Полезные функции для работы с массивами
CREATE OR REPLACE FUNCTION array_utilities()
RETURNS TABLE(operation TEXT, result TEXT) AS $$
DECLARE
    arr INTEGER[] := ARRAY[5, 3, 8, 1, 9, 3];
    other_arr INTEGER[];
    intersection_arr INTEGER[];
    sorted_arr INTEGER[];
    reversed_arr INTEGER[];
    searched_index INTEGER;
BEGIN
    -- Длина массива
    operation := 'Длина'; 
    result := array_length(arr, 1)::text; 
    RETURN NEXT; -- send to set of current values
    
    -- Поиск элемента
    operation := 'Индекс числа 8'; 
    searched_index := array_position(arr, 8);
    result := COALESCE(searched_index::text, 'не найден'); 
    RETURN NEXT;
    
    -- Содержит ли элемент
    operation := 'Содержит 5?'; 
    result := (5 = ANY(arr))::text; 
    RETURN NEXT;
    
    -- Пересечение массивов
    operation := 'Пересечение с [3,7]'; 
    -- result := array_to_string(arr && ARRAY[3,7], ','); – не сработает, посмотрим на практике
    other_arr = array [3,7];
    IF arr && other_arr THEN
        -- Получаем пересечение через подзапрос
        SELECT ARRAY(
            SELECT UNNEST(arr)
            INTERSECT
            SELECT UNNEST(other_arr)
        ) INTO intersection_arr;
    ELSE
        intersection_arr := '{}';
    END IF;
    result := array_to_string(intersection_arr, ','); 
    RETURN NEXT;
    
    -- Сортировка
    sorted_arr := ARRAY(SELECT unnest(arr) ORDER BY 1);
    operation := 'Отсортированный'; 
    result := array_to_string(sorted_arr, ','); 
    RETURN NEXT;
    
    -- Реверс
    -- reversed_arr := ARRAY(SELECT unnest(arr) ORDER BY ordinality DESC FROM unnest(arr) WITH ORDINALITY); – аналогично нерабочий код
    -- ordinality - присвоить порядочный номер
	reversed_arr := ARRAY(
	    SELECT elem 
	    FROM unnest(arr) WITH ORDINALITY AS t(elem, ordinality)
	    ORDER BY ordinality DESC
	);

    operation := 'Реверс'; 
    result := array_to_string(reversed_arr, ','); 
    RETURN NEXT;
    -- по факту дорого аннестить и собирать обратно - лучше напрямую с массивами работать
END;
$$ LANGUAGE plpgsql;

select array_utilities();


-- многомерные массивы
CREATE OR REPLACE FUNCTION multidimensional_arrays()
RETURNS void AS $$
DECLARE
    matrix INTEGER[][] := ARRAY[
        ARRAY[1, 2, 3],
        ARRAY[4, 5, 6], 
        ARRAY[7, 8, 9]
    ];
    row INTEGER[];
    element INTEGER;
BEGIN

    RAISE NOTICE 'Матрица 2x2: %', matrix;
    RAISE NOTICE 'Элемент [2][3]: %', matrix[2][3];  -- 6
    
    -- Цикл по строкам и элементам
	FOR i IN 1..array_length(matrix, 1) LOOP
        FOR j IN 1..array_length(matrix, 2) LOOP  -- Вторая размерность
            RAISE NOTICE 'matrix[%][%] = %', i, j, matrix[i][j];
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

select multidimensional_arrays();

-- SLICE - результат в dBeaver в окне output
CREATE or replace FUNCTION scan_rows(int[]) RETURNS void AS $$
DECLARE
  x int[];
BEGIN
  FOREACH x SLICE 1 IN ARRAY $1
  LOOP
    RAISE NOTICE 'row = %', x;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

SELECT scan_rows(ARRAY[[1,2,3],[4,5,6],[7,8,9],[10,11,12]]);

-- slice 0,1,2
SELECT scan_rows(ARRAY[[[1,2],[1,2],[1,2]],[[1,2],[2,3],[4,5]],[[1,2],[2,3],[1,2]],[[1,1],[1,1],[1,2]]]);