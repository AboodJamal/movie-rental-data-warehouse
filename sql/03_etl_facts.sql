-- ============================================================
-- FILE: 03_etl_facts.sql
-- PURPOSE: ETL — Extract from Sakila OLTP and Load both
--          Fact Tables into the Data Warehouse
-- RUN AFTER: 02_etl_dimensions.sql
-- SOURCE DB: sakila
-- TARGET DB: movie_rental_dw
-- ============================================================
-- LOADING ORDER:
--   10. fact_rental   (depends on ALL dimensions)
--   11. fact_payment  (depends on dim_date, dim_customer,
--                      dim_staff, dim_store)
-- ============================================================

USE movie_rental_dw;

-- ============================================================
-- STEP 10: fact_rental
-- Source: sakila.rental + inventory (resolves film_id + store_id)
-- Grain: One row per individual rental transaction
--
-- Key Transformations:
--   1. rental -> inventory -> film_id  (get the film rented)
--   2. rental -> inventory -> store_id (get which store it came from)
--   3. Derive rental_duration_days  = DATEDIFF(return_date, rental_date)
--   4. Derive expected_duration     = film.rental_duration
--   5. Derive days_overdue          = MAX(0, actual - expected)
--   6. Derive is_late_return        = 1 if overdue, else 0
--   7. Handle NULL return_date      -> is_returned=0, date_key_return=-1
--   8. Replace OLTP IDs with DW surrogate keys
-- ============================================================

INSERT INTO fact_rental (
    rental_id,
    date_key_rental,
    date_key_return,
    customer_key,
    film_key,
    store_key,
    staff_key,
    rental_duration_days,
    expected_duration_days,
    days_overdue,
    is_late_return,
    is_returned,
    rental_count
)
SELECT
    r.rental_id,

    -- Rental date key (always present — rental_date is NOT NULL in source)
    CAST(DATE_FORMAT(DATE(r.rental_date), '%Y%m%d') AS UNSIGNED)    AS date_key_rental,

    -- Return date key: -1 if film not yet returned (NULL return_date)
    CASE
        WHEN r.return_date IS NULL
        THEN -1
        ELSE CAST(DATE_FORMAT(DATE(r.return_date), '%Y%m%d') AS UNSIGNED)
    END                                                              AS date_key_return,

    -- Surrogate keys from dimension tables
    dc.customer_key,
    df.film_key,
    ds.store_key,
    dst.staff_key,

    -- Actual rental duration (NULL if not yet returned)
    CASE
        WHEN r.return_date IS NULL
        THEN NULL
        ELSE DATEDIFF(r.return_date, r.rental_date)
    END                                                              AS rental_duration_days,

    -- Expected duration from film definition
    f.rental_duration                                                AS expected_duration_days,

    -- Days overdue (0 if returned on time, NULL if not yet returned)
    CASE
        WHEN r.return_date IS NULL
        THEN NULL
        WHEN DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
        THEN DATEDIFF(r.return_date, r.rental_date) - f.rental_duration
        ELSE 0
    END                                                              AS days_overdue,

    -- Late return flag (NULL if not yet returned)
    CASE
        WHEN r.return_date IS NULL
        THEN NULL
        WHEN DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
        THEN 1
        ELSE 0
    END                                                              AS is_late_return,

    -- Is returned flag
    CASE
        WHEN r.return_date IS NULL THEN 0
        ELSE 1
    END                                                              AS is_returned,

    -- Always 1 — used for aggregation COUNT
    1                                                                AS rental_count

FROM sakila.rental r

-- Resolve film_id and store_id via inventory
JOIN sakila.inventory i     ON r.inventory_id   = i.inventory_id
JOIN sakila.film      f     ON i.film_id         = f.film_id

-- Map OLTP IDs to DW surrogate keys
JOIN dim_customer  dc       ON r.customer_id     = dc.customer_id
JOIN dim_film      df       ON i.film_id         = df.film_id
JOIN dim_store     ds       ON i.store_id        = ds.store_id
JOIN dim_staff     dst      ON r.staff_id        = dst.staff_id;

SELECT CONCAT('fact_rental loaded: ', COUNT(*), ' rows') AS status FROM fact_rental;


-- ============================================================
-- STEP 11: fact_payment
-- Source: sakila.payment
-- Grain: One row per payment transaction
--
-- Key Transformations:
--   1. payment -> staff -> store_id  (resolve store for this payment)
--   2. Convert payment_date to date_key (YYYYMMDD integer)
--   3. Replace OLTP IDs with DW surrogate keys
--   4. rental_id kept as soft reference (not enforced FK)
--      because payment.rental_id is nullable in source
-- ============================================================

INSERT INTO fact_payment (
    payment_id,
    date_key,
    customer_key,
    staff_key,
    store_key,
    rental_id,
    payment_amount,
    payment_count
)
SELECT
    p.payment_id,

    -- Payment date key
    CAST(DATE_FORMAT(DATE(p.payment_date), '%Y%m%d') AS UNSIGNED)   AS date_key,

    -- Surrogate keys
    dc.customer_key,
    dst.staff_key,
    ds.store_key,

    -- Soft reference to rental (may be NULL)
    p.rental_id,

    -- Payment amount measure
    p.amount                                                          AS payment_amount,

    -- Always 1 — used for aggregation COUNT
    1                                                                 AS payment_count

FROM sakila.payment p

-- Resolve store via staff (payment has no direct store_id)
JOIN sakila.staff   st      ON p.staff_id       = st.staff_id

-- Map OLTP IDs to DW surrogate keys
JOIN dim_customer  dc       ON p.customer_id    = dc.customer_id
JOIN dim_staff     dst      ON p.staff_id       = dst.staff_id
JOIN dim_store     ds       ON st.store_id      = ds.store_id;

SELECT CONCAT('fact_payment loaded: ', COUNT(*), ' rows') AS status FROM fact_payment;


-- ============================================================
-- FINAL RECONCILIATION CHECK
-- Total payment in DW must match total in OLTP source
-- ============================================================
SELECT
    'OLTP Total Payment Amount' AS source,
    SUM(amount)                 AS total_amount,
    COUNT(*)                    AS total_records
FROM sakila.payment

UNION ALL

SELECT
    'DW Total Payment Amount',
    SUM(payment_amount),
    COUNT(*)
FROM fact_payment;


-- ============================================================
-- FINAL ROW COUNT CHECK
-- ============================================================
SELECT 'fact_rental'    AS table_name, COUNT(*) AS row_count FROM fact_rental
UNION ALL
SELECT 'fact_payment',                 COUNT(*) FROM fact_payment;
