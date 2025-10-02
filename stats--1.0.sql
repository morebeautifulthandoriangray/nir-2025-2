-- stats--1.0.sql
-- Набор статистических функций для PostgreSQL

-- Убедимся, что язык PL/pgSQL доступен
CREATE EXTENSION IF NOT EXISTS plpgsql;

----------------------------------------------------------------------
-- χ²-тест независимости
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_chi2_test(
    table_name TEXT,
    col1 TEXT,
    col2 TEXT
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    observed RECORD;
    total INT;
    row_totals RECORD;
    col_totals RECORD;
    expected DOUBLE PRECISION;
    chi2 DOUBLE PRECISION := 0;
BEGIN
    -- Общее количество наблюдений
    EXECUTE format('SELECT count(*) FROM %I', table_name)
    INTO total;

    -- Временные таблицы
    CREATE TEMP TABLE tmp_obs (r TEXT, c TEXT, obs INT) ON COMMIT DROP;
    CREATE TEMP TABLE tmp_row_totals (r TEXT, total INT) ON COMMIT DROP;
    CREATE TEMP TABLE tmp_col_totals (c TEXT, total INT) ON COMMIT DROP;

    -- Заполняем наблюдаемые частоты
    EXECUTE format(
        'INSERT INTO tmp_obs
         SELECT %I::TEXT, %I::TEXT, count(*) FROM %I GROUP BY 1,2',
         col1, col2, table_name
    );

    -- Суммы по строкам
    EXECUTE format(
        'INSERT INTO tmp_row_totals
         SELECT %I::TEXT, count(*) FROM %I GROUP BY 1',
         col1, table_name
    );

    -- Суммы по столбцам
    EXECUTE format(
        'INSERT INTO tmp_col_totals
         SELECT %I::TEXT, count(*) FROM %I GROUP BY %I',
         col2, table_name, col2
    );

    -- Вычисляем χ²
    FOR observed IN SELECT * FROM tmp_obs LOOP
        SELECT total INTO row_totals.total FROM tmp_row_totals WHERE r = observed.r;
        SELECT total INTO col_totals.total FROM tmp_col_totals WHERE c = observed.c;

        expected := (row_totals.total::DOUBLE PRECISION * col_totals.total::DOUBLE PRECISION) / total;

        IF expected > 0 THEN
            chi2 := chi2 + power(observed.obs - expected, 2) / expected;
        END IF;
    END LOOP;

    RETURN chi2;
END; $$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Одновыборочный t-тест Стьюдента
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_ttest_one_sample(
    table_name TEXT,
    col TEXT,
    mu0 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    mean_val DOUBLE PRECISION;
    stddev_val DOUBLE PRECISION;
    n INT;
    t_stat DOUBLE PRECISION;
BEGIN
    EXECUTE format('SELECT avg(%I), stddev_samp(%I), count(*) FROM %I', col, col, table_name)
    INTO mean_val, stddev_val, n;

    t_stat := (mean_val - mu0) / (stddev_val / sqrt(n));
    RETURN t_stat;
END; $$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Двувыборочный t-тест Стьюдента (равные дисперсии)
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_ttest_two_sample(
    table1 TEXT,
    col1 TEXT,
    table2 TEXT,
    col2 TEXT
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    mean1 DOUBLE PRECISION;
    mean2 DOUBLE PRECISION;
    var1 DOUBLE PRECISION;
    var2 DOUBLE PRECISION;
    n1 INT;
    n2 INT;
    pooled_var DOUBLE PRECISION;
    t_stat DOUBLE PRECISION;
BEGIN
    EXECUTE format('SELECT avg(%I), var_samp(%I), count(*) FROM %I', col1, col1, table1)
    INTO mean1, var1, n1;

    EXECUTE format('SELECT avg(%I), var_samp(%I), count(*) FROM %I', col2, col2, table2)
    INTO mean2, var2, n2;

    pooled_var := ((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2);

    t_stat := (mean1 - mean2) / sqrt(pooled_var * (1.0/n1 + 1.0/n2));

    RETURN t_stat;
END; $$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- F-тест (сравнение дисперсий)
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_f_test(
    table1 TEXT,
    col1 TEXT,
    table2 TEXT,
    col2 TEXT
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    var1 DOUBLE PRECISION;
    var2 DOUBLE PRECISION;
    f_stat DOUBLE PRECISION;
BEGIN
    EXECUTE format('SELECT var_samp(%I) FROM %I', col1, table1) INTO var1;
    EXECUTE format('SELECT var_samp(%I) FROM %I', col2, table2) INTO var2;

    f_stat := var1 / var2;
    RETURN f_stat;
END; $$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- Критерий корреляции Спирмана
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_spearman_corr(
    table_name TEXT,
    col1 TEXT,
    col2 TEXT
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    rho DOUBLE PRECISION;
BEGIN
    EXECUTE format(
        'WITH ranks AS (
            SELECT %I,
                   %I,
                   rank() OVER (ORDER BY %I) AS r1,
                   rank() OVER (ORDER BY %I) AS r2
            FROM %I
        )
        SELECT corr(r1::DOUBLE PRECISION, r2::DOUBLE PRECISION) FROM ranks',
        col1, col2, col1, col2, table_name
    ) INTO rho;

    RETURN rho;
END; $$ LANGUAGE plpgsql;

----------------------------------------------------------------------
-- ANOVA (однофакторный дисперсионный анализ)
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION stats_anova(
    table_name TEXT,
    group_col TEXT,
    value_col TEXT
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
    grand_mean DOUBLE PRECISION;
    ssb DOUBLE PRECISION := 0;
    ssw DOUBLE PRECISION := 0;
    f_stat DOUBLE PRECISION;
    n_total INT;
    groups RECORD;
    n_g DOUBLE PRECISION;
BEGIN
    -- Общее среднее
    EXECUTE format('SELECT avg(%I), count(*) FROM %I', value_col, table_name)
    INTO grand_mean, n_total;

    -- Межгрупповая и внутригрупповая дисперсии
    FOR groups IN EXECUTE format(
        'SELECT %I::TEXT as g, avg(%I) as mean_g, count(*) as n_g
         FROM %I GROUP BY %I',
         group_col, value_col, table_name, group_col
    )
    LOOP
        ssb := ssb + groups.n_g * power(groups.mean_g - grand_mean, 2);

        EXECUTE format('SELECT sum(power(%I - %L, 2)) FROM %I WHERE %I = %L',
            value_col, groups.mean_g, table_name, group_col, groups.g
        )
        INTO n_g;

        ssw := ssw + coalesce(n_g,0);
    END LOOP;

    f_stat := (ssb / ((SELECT count(DISTINCT %I) FROM %I) - 1)) /
              (ssw / (n_total - (SELECT count(DISTINCT %I) FROM %I)));
    RETURN f_stat;
END; $$ LANGUAGE plpgsql;