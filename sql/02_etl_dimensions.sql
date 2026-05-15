-- ============================================================
-- FILE: 02_etl_dimensions.sql
-- PURPOSE: ETL — Extract from Sakila OLTP and Load all
--          Dimension Tables into the Data Warehouse
-- RUN AFTER: 01_create_dw_tables.sql
-- RUN BEFORE: 03_etl_facts.sql
-- SOURCE DB: sakila
-- TARGET DB: movie_rental_dw
-- ============================================================
-- LOADING ORDER (dimensions must load before fact tables):
--   1. dim_date          (no dependencies)
--   2. dim_customer      (no dimension dependencies)
--   3. dim_film          (no dimension dependencies)
--   4. dim_category      (no dimension dependencies)
--   5. dim_actor         (no dimension dependencies)
--   6. bridge_film_category (depends on dim_film + dim_category)
--   7. bridge_film_actor    (depends on dim_film + dim_actor)
--   8. dim_store         (no dimension dependencies)
--   9. dim_staff         (no dimension dependencies)
-- ============================================================

USE movie_rental_dw;

-- ============================================================
-- STEP 1: dim_date
-- Generated programmatically using a recursive CTE
-- Covers full date range from earliest rental to latest payment
-- Special row: date_key = -1 for unreturned films
-- ============================================================

-- Insert special "Not Yet Returned" row first
INSERT INTO dim_date (
    date_key, full_date, day_of_week, day_name,
    day_of_month, month_number, month_name,
    quarter, year, is_weekend
) VALUES (
    -1, NULL, NULL, 'Not Yet Returned',
    NULL, NULL, NULL, NULL, NULL, NULL
);

-- Generate one row per calendar date across the Sakila data range
-- Using a recursive CTE (MySQL 8.0+)
INSERT INTO dim_date (
    date_key,
    full_date,
    day_of_week,
    day_name,
    day_of_month,
    month_number,
    month_name,
    quarter,
    year,
    is_weekend
)
WITH RECURSIVE date_series AS (
    -- Start from the earliest rental date in Sakila
    SELECT MIN(DATE(rental_date)) AS gen_date
    FROM sakila.rental
    UNION ALL
    -- Add one day at a time until we reach the latest payment date
    SELECT gen_date + INTERVAL 1 DAY
    FROM date_series
    WHERE gen_date < (SELECT MAX(DATE(payment_date)) FROM sakila.payment)
)
SELECT
    CAST(DATE_FORMAT(gen_date, '%Y%m%d') AS UNSIGNED)   AS date_key,
    gen_date                                             AS full_date,
    DAYOFWEEK(gen_date)                                  AS day_of_week,    -- 1=Sunday in MySQL
    DAYNAME(gen_date)                                    AS day_name,
    DAY(gen_date)                                        AS day_of_month,
    MONTH(gen_date)                                      AS month_number,
    MONTHNAME(gen_date)                                  AS month_name,
    QUARTER(gen_date)                                    AS quarter,
    YEAR(gen_date)                                       AS year,
    IF(DAYOFWEEK(gen_date) IN (1, 7), 1, 0)             AS is_weekend      -- 1=Sunday, 7=Saturday
FROM date_series;

SELECT CONCAT('dim_date loaded: ', COUNT(*), ' rows') AS status FROM dim_date;


-- ============================================================
-- STEP 2: dim_customer
-- Source: sakila.customer + address + city + country
-- Transformations:
--   - Concatenate first_name + last_name -> full_name
--   - Flatten address -> city -> country hierarchy
--   - Convert active tinyint -> 'Active'/'Inactive'
--   - COALESCE email NULL -> 'N/A'
--   - TRIM all text fields
-- ============================================================

INSERT INTO dim_customer (
    customer_id,
    full_name,
    email,
    active_status,
    address,
    address2,
    district,
    city,
    country,
    postal_code,
    phone,
    customer_since
)
SELECT
    c.customer_id,
    CONCAT(TRIM(c.first_name), ' ', TRIM(c.last_name))     AS full_name,
    COALESCE(TRIM(c.email), 'N/A')                         AS email,
    CASE WHEN c.active = 1 THEN 'Active' ELSE 'Inactive' END AS active_status,
    TRIM(a.address)                                         AS address,
    TRIM(a.address2)                                        AS address2,
    TRIM(a.district)                                        AS district,
    TRIM(ci.city)                                           AS city,
    TRIM(co.country)                                        AS country,
    a.postal_code,
    a.phone,
    DATE(c.create_date)                                     AS customer_since
FROM sakila.customer c
JOIN sakila.address a   ON c.address_id  = a.address_id
JOIN sakila.city    ci  ON a.city_id     = ci.city_id
JOIN sakila.country co  ON ci.country_id = co.country_id;

SELECT CONCAT('dim_customer loaded: ', COUNT(*), ' rows') AS status FROM dim_customer;


-- ============================================================
-- STEP 3: dim_film
-- Source: sakila.film + language (joined twice for language + original_language)
-- Transformations:
--   - Join language table twice (language + original_language)
--   - Keep replacement_cost for future unreturned film analysis
-- ============================================================

INSERT INTO dim_film (
    film_id,
    title,
    description,
    release_year,
    language,
    original_language,
    rental_rate,
    rental_duration_days,
    length_minutes,
    replacement_cost,
    rating,
    special_features
)
SELECT
    f.film_id,
    TRIM(f.title)                               AS title,
    f.description,
    f.release_year,
    TRIM(l.name)                                AS language,
    TRIM(ol.name)                               AS original_language,   -- NULL if not dubbed
    f.rental_rate,
    f.rental_duration                           AS rental_duration_days,
    f.length                                    AS length_minutes,
    f.replacement_cost,
    f.rating,
    f.special_features
FROM sakila.film f
JOIN sakila.language l              ON f.language_id          = l.language_id
LEFT JOIN sakila.language ol        ON f.original_language_id = ol.language_id;

SELECT CONCAT('dim_film loaded: ', COUNT(*), ' rows') AS status FROM dim_film;


-- ============================================================
-- STEP 4: dim_category
-- Source: sakila.category
-- Simple direct load — no complex transformations needed
-- ============================================================

INSERT INTO dim_category (
    category_id,
    category_name
)
SELECT
    category_id,
    TRIM(name) AS category_name
FROM sakila.category;

SELECT CONCAT('dim_category loaded: ', COUNT(*), ' rows') AS status FROM dim_category;


-- ============================================================
-- STEP 5: dim_actor
-- Source: sakila.actor
-- Transformation: Concatenate first_name + last_name
-- ============================================================

INSERT INTO dim_actor (
    actor_id,
    full_name
)
SELECT
    actor_id,
    CONCAT(
        UPPER(SUBSTRING(LOWER(TRIM(first_name)), 1, 1)),
        LOWER(SUBSTRING(TRIM(first_name), 2)),
        ' ',
        UPPER(SUBSTRING(LOWER(TRIM(last_name)), 1, 1)),
        LOWER(SUBSTRING(TRIM(last_name), 2))
    ) AS full_name   -- Proper case: 'PENELOPE GUINESS' -> 'Penelope Guiness'
FROM sakila.actor;

SELECT CONCAT('dim_actor loaded: ', COUNT(*), ' rows') AS status FROM dim_actor;


-- ============================================================
-- STEP 6: bridge_film_category
-- Source: sakila.film_category
-- Replace OLTP natural keys with DW surrogate keys
-- Depends on: dim_film + dim_category already loaded
-- ============================================================

INSERT INTO bridge_film_category (
    film_key,
    category_key
)
SELECT
    df.film_key,
    dc.category_key
FROM sakila.film_category fc
JOIN dim_film     df ON fc.film_id     = df.film_id
JOIN dim_category dc ON fc.category_id = dc.category_id;

SELECT CONCAT('bridge_film_category loaded: ', COUNT(*), ' rows') AS status FROM bridge_film_category;


-- ============================================================
-- STEP 7: bridge_film_actor
-- Source: sakila.film_actor
-- Replace OLTP natural keys with DW surrogate keys
-- Depends on: dim_film + dim_actor already loaded
-- ============================================================

INSERT INTO bridge_film_actor (
    film_key,
    actor_key
)
SELECT
    df.film_key,
    da.actor_key
FROM sakila.film_actor fa
JOIN dim_film  df ON fa.film_id  = df.film_id
JOIN dim_actor da ON fa.actor_id = da.actor_id;

SELECT CONCAT('bridge_film_actor loaded: ', COUNT(*), ' rows') AS status FROM bridge_film_actor;


-- ============================================================
-- STEP 8: dim_store
-- Source: sakila.store + staff (manager) + address + city + country
-- Transformations:
--   - Join manager name from staff table
--   - Flatten address hierarchy
-- ============================================================

INSERT INTO dim_store (
    store_id,
    manager_full_name,
    address,
    address2,
    district,
    city,
    country,
    postal_code,
    phone
)
SELECT
    s.store_id,
    CONCAT(TRIM(st.first_name), ' ', TRIM(st.last_name))   AS manager_full_name,
    TRIM(a.address)                                         AS address,
    TRIM(a.address2)                                        AS address2,
    TRIM(a.district)                                        AS district,
    TRIM(ci.city)                                           AS city,
    TRIM(co.country)                                        AS country,
    a.postal_code,
    a.phone
FROM sakila.store s
JOIN sakila.staff   st  ON s.manager_staff_id = st.staff_id
JOIN sakila.address a   ON s.address_id       = a.address_id
JOIN sakila.city    ci  ON a.city_id          = ci.city_id
JOIN sakila.country co  ON ci.country_id      = co.country_id;

SELECT CONCAT('dim_store loaded: ', COUNT(*), ' rows') AS status FROM dim_store;


-- ============================================================
-- STEP 9: dim_staff
-- Source: sakila.staff
-- Transformations:
--   - Concatenate name
--   - Convert active flag to readable string
--   - COALESCE NULL email -> 'N/A'
-- ============================================================

INSERT INTO dim_staff (
    staff_id,
    full_name,
    email,
    active_status,
    store_id
)
SELECT
    staff_id,
    CONCAT(TRIM(first_name), ' ', TRIM(last_name))          AS full_name,
    COALESCE(TRIM(email), 'N/A')                            AS email,
    CASE WHEN active = 1 THEN 'Active' ELSE 'Inactive' END  AS active_status,
    store_id
FROM sakila.staff;

SELECT CONCAT('dim_staff loaded: ', COUNT(*), ' rows') AS status FROM dim_staff;


-- ============================================================
-- FINAL CHECK: Row counts for all dimension tables
-- ============================================================
SELECT 'dim_date'             AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'dim_customer',                        COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_film',                            COUNT(*) FROM dim_film
UNION ALL
SELECT 'dim_category',                        COUNT(*) FROM dim_category
UNION ALL
SELECT 'dim_actor',                           COUNT(*) FROM dim_actor
UNION ALL
SELECT 'bridge_film_category',                COUNT(*) FROM bridge_film_category
UNION ALL
SELECT 'bridge_film_actor',                   COUNT(*) FROM bridge_film_actor
UNION ALL
SELECT 'dim_store',                           COUNT(*) FROM dim_store
UNION ALL
SELECT 'dim_staff',                           COUNT(*) FROM dim_staff;
