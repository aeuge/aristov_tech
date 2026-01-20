-- мы использовали составной тип в транзакциях
select * from transactions;
SELECT account_id, multiply(2,debit), multiply(2,credit), date_entered FROM transactions;

-- но если мы попробуем использовать стандартные методы, то они не сработают
SELECT account_id, 1.2 * debit, 2 * credit, date_entered FROM transactions;

-- Мы можем даже определить оператор умножения:
CREATE OPERATOR * (
    PROCEDURE = multiply,
    LEFTARG = numeric,
    RIGHTARG = currency
);

-- И использовать его в выражениях:
SELECT account_id, 1.2 * debit, 2 * credit, date_entered FROM transactions;

-- но если попробуем сложить две валюты - то опять ничего не получится - нужна функция и переопределение оператора
CREATE FUNCTION summ(cur currency, cur2 currency) RETURNS currency AS $$
    SELECT  case when cur.code = cur2.code
                 then ROW(cur.amount * cur2.amount, cur.code)::currency
                 else ROW(cur.amount * cur2.amount, 'unknown')::currency
            end;
$$ IMMUTABLE LANGUAGE SQL;


SELECT account_id, sum(debit, credit) , date_entered FROM transactions;
SELECT account_id, sum(debit, debit) , date_entered FROM transactions;


-- Мы можем даже определить оператор сложения:
CREATE OPERATOR + (
    PROCEDURE = summ,
    LEFTARG = currency,
    RIGHTARG = currency
);

-- И использовать его в выражениях:
SELECT account_id, debit + credit, date_entered FROM transactions;


-- Создадим тип для комплексных чисел
CREATE TYPE complex AS (
    real DOUBLE PRECISION,
    imag DOUBLE PRECISION
);

-- Функция для сложения
CREATE FUNCTION complex_add(complex, complex)
RETURNS complex AS $$
BEGIN
    RETURN ROW(
        $1.real + $2.real,
        $1.imag + $2.imag
    )::complex;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Связываем функцию с оператором +
CREATE OPERATOR + (
    LEFTARG = complex,
    RIGHTARG = complex,
    PROCEDURE = complex_add,
    COMMUTATOR = +
);

SELECT ROW(3, 4)::complex + ROW(1, 2)::complex;

-- полный набор
-- Вычитание
CREATE FUNCTION complex_subtract(complex, complex)
RETURNS complex AS $$
BEGIN
    RETURN ROW(
        $1.real - $2.real,
        $1.imag - $2.imag
    )::complex;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OPERATOR - (
    LEFTARG = complex,
    RIGHTARG = complex,
    PROCEDURE = complex_subtract
);

-- Умножение
CREATE FUNCTION complex_multiply(complex, complex)
RETURNS complex AS $$
BEGIN
    RETURN ROW(
        $1.real * $2.real - $1.imag * $2.imag,
        $1.real * $2.imag + $1.imag * $2.real
    )::complex;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OPERATOR * (
    LEFTARG = complex,
    RIGHTARG = complex,
    PROCEDURE = complex_multiply,
    COMMUTATOR = *
);

-- Равенство
CREATE FUNCTION complex_equal(complex, complex)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN $1.real = $2.real AND $1.imag = $2.imag;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OPERATOR = (
    LEFTARG = complex,
    RIGHTARG = complex,
    PROCEDURE = complex_equal,
    COMMUTATOR = =,
    NEGATOR = <>
);