# PostgreSQL Extension: stats

Расширение `stats` добавляет в PostgreSQL базовые статистические функции, такие как χ²-тест, t-тест Стьюдента, F-тест, корреляция Спирмана и однофакторный ANOVA.  

---

## Установка

1. Скопируйте файлы в каталог расширений PostgreSQL (путь зависит от версии, пример для PostgreSQL 16):

```bash
sudo cp stats.control /usr/share/postgresql/16/extension/
sudo cp stats--1.0.sql /usr/share/postgresql/16/extension/

2. Подключите расширение в вашей базе данных:

CREATE EXTENSION stats;

---

## Использование

1. Доступные функции

**χ²-тест независимости**
SELECT stats_chi2_test('table_name', 'col1', 'col2');

**Одновыборочный t-тест**
SELECT stats_ttest_one_sample('table_name', 'col', mu0);

**Двувыборочный t-тест**
SELECT stats_ttest_two_sample('table1', 'col1', 'table2', 'col2');

**F-тест**
SELECT stats_f_test('table1', 'col1', 'table2', 'col2');

**Корреляция Спирмана**
SELECT stats_spearman_corr('table_name', 'col1', 'col2');

**ANOVA**
SELECT stats_anova('table_name', 'group_col', 'value_col');
