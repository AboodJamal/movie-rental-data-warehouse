-- ============================================================
-- FILE: 04_data_quality_checks.sql
-- PURPOSE: Data Quality Rules — run against OLTP source
--          BEFORE loading, and against DW AFTER loading
-- SOURCE DB: sakila
-- TARGET DB: movie_rental_dw
-- ============================================================
-- Each check returns 0 rows if data is CLEAN.
-- Any rows returned = data quality issue found.
-- ============================================================

-- ============================================================
-- PRE-LOAD CHECKS (run against sakila BEFORE ETL)
-- These validate the source data before it enters the DW
-- ============================================================

-- ------------------------------------------------------------
-- DQ-01: No NULL rental dates
-- rental_date is NOT NULL in source schema but verify anyway
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-01' AS rule_id,
    'NULL rental_date found' AS issue,
    rental_id,
    rental_date
FROM sakila.rental
WHERE rental_date IS NULL;


-- ------------------------------------------------------------
-- DQ-02: Return date must be AFTER rental date
-- A film cannot be returned before it was rented
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-02' AS rule_id,
    'return_date is before rental_date' AS issue,
    rental_id,
    rental_date,
    return_date,
    DATEDIFF(return_date, rental_date) AS days_difference
FROM sakila.rental
WHERE return_date IS NOT NULL
  AND return_date < rental_date;


-- ------------------------------------------------------------
-- DQ-03: Payment amount must be positive
-- Zero or negative payments are logically invalid
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-03' AS rule_id,
    'Payment amount is zero or negative' AS issue,
    payment_id,
    customer_id,
    amount,
    payment_date
FROM sakila.payment
WHERE amount <= 0;


-- ------------------------------------------------------------
-- DQ-04: No orphan rentals
-- Every rental must link to a valid inventory item
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-04' AS rule_id,
    'Rental references non-existent inventory_id' AS issue,
    r.rental_id,
    r.inventory_id
FROM sakila.rental r
LEFT JOIN sakila.inventory i ON r.inventory_id = i.inventory_id
WHERE i.inventory_id IS NULL;


-- ------------------------------------------------------------
-- DQ-05: No orphan payments
-- Every payment must reference a valid customer and staff
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-05' AS rule_id,
    'Payment references non-existent customer or staff' AS issue,
    p.payment_id,
    p.customer_id,
    p.staff_id
FROM sakila.payment p
LEFT JOIN sakila.customer c ON p.customer_id = c.customer_id
LEFT JOIN sakila.staff    s ON p.staff_id    = s.staff_id
WHERE c.customer_id IS NULL
   OR s.staff_id    IS NULL;


-- ------------------------------------------------------------
-- DQ-06: Every rental must resolve to a valid film and store
-- Via the inventory table
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-06' AS rule_id,
    'Rental cannot resolve to a film or store via inventory' AS issue,
    r.rental_id,
    r.inventory_id,
    i.film_id,
    i.store_id
FROM sakila.rental r
LEFT JOIN sakila.inventory i ON r.inventory_id = i.inventory_id
LEFT JOIN sakila.film      f ON i.film_id       = f.film_id
LEFT JOIN sakila.store     s ON i.store_id      = s.store_id
WHERE f.film_id  IS NULL
   OR s.store_id IS NULL;


-- ------------------------------------------------------------
-- DQ-07: No duplicate active customer emails
-- Two active customers should not share the same email
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-07' AS rule_id,
    'Duplicate email found among active customers' AS issue,
    email,
    COUNT(*) AS occurrences
FROM sakila.customer
WHERE active = 1
  AND email IS NOT NULL
GROUP BY email
HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- DQ-08: Film rental rate must be positive
-- Zero or negative rental rate is a data entry error
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-08' AS rule_id,
    'Film rental_rate is zero or negative' AS issue,
    film_id,
    title,
    rental_rate
FROM sakila.film
WHERE rental_rate <= 0;


-- ------------------------------------------------------------
-- DQ-09: Film rating must be a valid ENUM value
-- Allowed: G, PG, PG-13, R, NC-17
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-09' AS rule_id,
    'Film has invalid rating value' AS issue,
    film_id,
    title,
    rating
FROM sakila.film
WHERE rating NOT IN ('G', 'PG', 'PG-13', 'R', 'NC-17')
   OR rating IS NULL;


-- ------------------------------------------------------------
-- DQ-10: rental_duration_days must not be negative
-- If return_date < rental_date the derived measure is invalid
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-10' AS rule_id,
    'rental_duration_days is negative' AS issue,
    rental_id,
    rental_date,
    return_date,
    DATEDIFF(return_date, rental_date) AS rental_duration_days
FROM sakila.rental
WHERE return_date IS NOT NULL
  AND DATEDIFF(return_date, rental_date) < 0;


-- ============================================================
-- POST-LOAD CHECKS (run against movie_rental_dw AFTER ETL)
-- These verify the DW data matches the source
-- ============================================================

USE movie_rental_dw;

-- ------------------------------------------------------------
-- DQ-11: Record count match — fact_rental vs sakila.rental
-- Total rows must be equal
-- Expected result: difference = 0
-- ------------------------------------------------------------
SELECT
    'DQ-11' AS rule_id,
    'Record count check: fact_rental vs sakila.rental' AS check_name,
    (SELECT COUNT(*) FROM sakila.rental)    AS oltp_count,
    (SELECT COUNT(*) FROM fact_rental)      AS dw_count,
    (SELECT COUNT(*) FROM sakila.rental) -
    (SELECT COUNT(*) FROM fact_rental)      AS difference;


-- ------------------------------------------------------------
-- DQ-12: Payment total reconciliation
-- Sum of payment_amount in DW must equal sum in OLTP
-- Expected result: difference = 0.00
-- ------------------------------------------------------------
SELECT
    'DQ-12' AS rule_id,
    'Payment total reconciliation' AS check_name,
    (SELECT SUM(amount)          FROM sakila.payment)   AS oltp_total,
    (SELECT SUM(payment_amount)  FROM fact_payment)     AS dw_total,
    (SELECT SUM(amount)          FROM sakila.payment) -
    (SELECT SUM(payment_amount)  FROM fact_payment)     AS difference;


-- ------------------------------------------------------------
-- DQ-13: No orphaned dimension keys in fact_rental
-- Every FK in fact_rental must resolve to a valid dimension row
-- Expected result: 0 rows for each check
-- ------------------------------------------------------------
-- Check customer_key
SELECT 'DQ-13a' AS rule_id, 'Orphan customer_key in fact_rental' AS issue,
       fr.rental_id, fr.customer_key
FROM fact_rental fr
LEFT JOIN dim_customer dc ON fr.customer_key = dc.customer_key
WHERE dc.customer_key IS NULL;

-- Check film_key
SELECT 'DQ-13b' AS rule_id, 'Orphan film_key in fact_rental' AS issue,
       fr.rental_id, fr.film_key
FROM fact_rental fr
LEFT JOIN dim_film df ON fr.film_key = df.film_key
WHERE df.film_key IS NULL;

-- Check store_key
SELECT 'DQ-13c' AS rule_id, 'Orphan store_key in fact_rental' AS issue,
       fr.rental_id, fr.store_key
FROM fact_rental fr
LEFT JOIN dim_store ds ON fr.store_key = ds.store_key
WHERE ds.store_key IS NULL;

-- Check staff_key
SELECT 'DQ-13d' AS rule_id, 'Orphan staff_key in fact_rental' AS issue,
       fr.rental_id, fr.staff_key
FROM fact_rental fr
LEFT JOIN dim_staff dst ON fr.staff_key = dst.staff_key
WHERE dst.staff_key IS NULL;


-- ------------------------------------------------------------
-- DQ-14: active_status must be only 'Active' or 'Inactive'
-- Validates the tinyint -> string transformation
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT 'DQ-14a' AS rule_id, 'Invalid active_status in dim_customer' AS issue,
       customer_key, full_name, active_status
FROM dim_customer
WHERE active_status NOT IN ('Active', 'Inactive');

SELECT 'DQ-14b' AS rule_id, 'Invalid active_status in dim_staff' AS issue,
       staff_key, full_name, active_status
FROM dim_staff
WHERE active_status NOT IN ('Active', 'Inactive');


-- ------------------------------------------------------------
-- DQ-15: days_overdue must not be negative
-- Validates the overdue calculation logic
-- Expected result: 0 rows
-- ------------------------------------------------------------
SELECT
    'DQ-15' AS rule_id,
    'days_overdue is negative in fact_rental' AS issue,
    rental_id,
    rental_duration_days,
    expected_duration_days,
    days_overdue
FROM fact_rental
WHERE days_overdue < 0;


-- ============================================================
-- SUMMARY REPORT: All DQ checks in one view
-- Run this after all individual checks above
-- ============================================================
SELECT
    check_name,
    oltp_value,
    dw_value,
    status
FROM (
    SELECT
        'Total Rentals'                         AS check_name,
        (SELECT COUNT(*) FROM sakila.rental)    AS oltp_value,
        (SELECT COUNT(*) FROM fact_rental)      AS dw_value,
        CASE
            WHEN (SELECT COUNT(*) FROM sakila.rental) =
                 (SELECT COUNT(*) FROM fact_rental)
            THEN '✓ PASS'
            ELSE '✗ FAIL'
        END AS status

    UNION ALL

    SELECT
        'Total Payments',
        (SELECT COUNT(*) FROM sakila.payment),
        (SELECT COUNT(*) FROM fact_payment),
        CASE
            WHEN (SELECT COUNT(*) FROM sakila.payment) =
                 (SELECT COUNT(*) FROM fact_payment)
            THEN '✓ PASS'
            ELSE '✗ FAIL'
        END

    UNION ALL

    SELECT
        'Payment Amount Match',
        CAST(SUM(amount) AS CHAR)          FROM sakila.payment,
        -- placeholder structure
        CAST((SELECT SUM(payment_amount) FROM fact_payment) AS CHAR),
        CASE
            WHEN ABS((SELECT SUM(amount) FROM sakila.payment) -
                     (SELECT SUM(payment_amount) FROM fact_payment)) < 0.01
            THEN '✓ PASS'
            ELSE '✗ FAIL'
        END
) AS summary_report;
