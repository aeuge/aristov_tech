CREATE OR REPLACE FUNCTION somefunc() RETURNS integer AS $$
<< out_block >>
DECLARE
    quantity integer := 300;
BEGIN
    RAISE NOTICE 'Сейчас quantity = %', quantity;  -- Выводится 300
    quantity := 500;
        --
        -- Вложенный блок
        --
        DECLARE
            quantity integer := 800;
        BEGIN
            RAISE NOTICE 'Сейчас quantity = %', quantity;  -- Выводится 800
            RAISE NOTICE 'Во внешнем блоке quantity = %', out_block.quantity;  -- Выводится 500
        END;

    RAISE NOTICE 'Сейчас quantity = %', quantity;  -- Выводится 500

    RETURN quantity;
END;
$$ LANGUAGE plpgsql;

SELECT somefunc();

-- внутреннему блоку также можно давать метку !!!

CREATE OR REPLACE FUNCTION somefunc2() RETURNS integer AS $$
<< out_block >>
DECLARE
    quantity integer := 300;
BEGIN
    RAISE NOTICE 'Сейчас quantity = %', quantity;  -- Выводится 300
    quantity := 500;
        -- Вложенный блок
        <<inner_block>>
        DECLARE
            quantity integer := 800;
        BEGIN
            RAISE NOTICE 'Сейчас quantity = %', inner_block.quantity;  -- Выводится 800
            RAISE NOTICE 'Во внешнем блоке quantity = %', out_block.quantity;  -- Выводится 500

            -- Вложенный блок2
            <<inner_block2>>
            DECLARE
                quantity integer := 10000;
            BEGIN
                RAISE NOTICE 'Сейчас quantity inner2 = %', inner_block2.quantity;  -- Выводится 10000
            END;
        END;

    RAISE NOTICE 'Сейчас quantity = %', quantity;  -- Выводится 500

    RETURN quantity;
END;
$$ LANGUAGE plpgsql;


SELECT somefunc2();

-- вложенность ограничивается лишь фантазией/юлагоразумием, возможностью переиспользования кода и общим размером в 1 Гб - рекомендации были даны на 2 лекции