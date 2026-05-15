-- ============================================================
-- FILE: 05_analytical_queries.sql
-- PURPOSE: Analytical queries that answer the 15 business
--          questions defined in Section 2 of the report.
--          All queries run against the Data Warehouse.
-- TARGET DB: movie_rental_dw
-- ============================================================

USE movie_rental_dw;

-- ============================================================
-- Q1: Which films are rented most frequently?
-- Category: Film Performance
-- ============================================================
SELECT
    df.title                        AS film_title,
    df.rating,
    df.language,
    SUM(fr.rental_count)            AS total_rentals
FROM fact_rental fr
JOIN dim_film df ON fr.film_key = df.film_key
GROUP BY df.film_key, df.title, df.rating, df.language
ORDER BY total_rentals DESC
LIMIT 10;


-- ============================================================
-- Q2: Which films generate the highest revenue?
-- Category: Film Performance
-- ============================================================
SELECT
    df.title                        AS film_title,
    df.rental_rate,
    df.rating,
    SUM(fp.payment_amount)          AS total_revenue,
    COUNT(fp.payment_id)            AS total_payments
FROM fact_payment fp
JOIN fact_rental  fr ON fp.rental_id  = fr.rental_id
JOIN dim_film     df ON fr.film_key   = df.film_key
GROUP BY df.film_key, df.title, df.rental_rate, df.rating
ORDER BY total_revenue DESC
LIMIT 10;


-- ============================================================
-- Q3: Which film categories are most popular among customers?
-- Category: Film Performance
-- ============================================================
SELECT
    dc.category_name,
    SUM(fr.rental_count)            AS total_rentals,
    COUNT(DISTINCT fr.customer_key) AS unique_customers
FROM fact_rental        fr
JOIN bridge_film_category bfc ON fr.film_key      = bfc.film_key
JOIN dim_category         dc  ON bfc.category_key = dc.category_key
GROUP BY dc.category_key, dc.category_name
ORDER BY total_rentals DESC;


-- ============================================================
-- Q4: Which stores generate the highest number of rentals?
-- Category: Store Performance
-- ============================================================
SELECT
    ds.store_id,
    ds.city,
    ds.country,
    ds.manager_full_name,
    SUM(fr.rental_count)            AS total_rentals
FROM fact_rental fr
JOIN dim_store   ds ON fr.store_key = ds.store_key
GROUP BY ds.store_key, ds.store_id, ds.city, ds.country, ds.manager_full_name
ORDER BY total_rentals DESC;


-- ============================================================
-- Q5: Which stores generate the highest revenue?
-- Category: Store Performance
-- ============================================================
SELECT
    ds.store_id,
    ds.city,
    ds.country,
    ds.manager_full_name,
    SUM(fp.payment_amount)          AS total_revenue,
    COUNT(fp.payment_id)            AS total_payments
FROM fact_payment fp
JOIN dim_store    ds ON fp.store_key = ds.store_key
GROUP BY ds.store_key, ds.store_id, ds.city, ds.country, ds.manager_full_name
ORDER BY total_revenue DESC;


-- ============================================================
-- Q6: Which customers rent the most films?
-- Category: Customer Behavior
-- ============================================================
SELECT
    dc.full_name                    AS customer_name,
    dc.city,
    dc.country,
    dc.active_status,
    SUM(fr.rental_count)            AS total_rentals
FROM fact_rental  fr
JOIN dim_customer dc ON fr.customer_key = dc.customer_key
GROUP BY dc.customer_key, dc.full_name, dc.city, dc.country, dc.active_status
ORDER BY total_rentals DESC
LIMIT 10;


-- ============================================================
-- Q7: Which customers generate the highest revenue?
-- Category: Customer Behavior
-- ============================================================
SELECT
    dc.full_name                    AS customer_name,
    dc.city,
    dc.country,
    dc.active_status,
    SUM(fp.payment_amount)          AS total_revenue,
    COUNT(fp.payment_id)            AS total_payments
FROM fact_payment  fp
JOIN dim_customer  dc ON fp.customer_key = dc.customer_key
GROUP BY dc.customer_key, dc.full_name, dc.city, dc.country, dc.active_status
ORDER BY total_revenue DESC
LIMIT 10;


-- ============================================================
-- Q8: How does rental activity change over time?
-- Category: Time-Based Trends
-- Grouped by year and month
-- ============================================================
SELECT
    dd.year,
    dd.month_number,
    dd.month_name,
    SUM(fr.rental_count)            AS total_rentals
FROM fact_rental fr
JOIN dim_date    dd ON fr.date_key_rental = dd.date_key
GROUP BY dd.year, dd.month_number, dd.month_name
ORDER BY dd.year, dd.month_number;


-- ============================================================
-- Q9: How does revenue change by month, quarter, and year?
-- Category: Time-Based Trends
-- ============================================================
SELECT
    dd.year,
    dd.quarter,
    dd.month_number,
    dd.month_name,
    SUM(fp.payment_amount)          AS total_revenue,
    COUNT(fp.payment_id)            AS total_payments
FROM fact_payment fp
JOIN dim_date     dd ON fp.date_key = dd.date_key
GROUP BY dd.year, dd.quarter, dd.month_number, dd.month_name
ORDER BY dd.year, dd.quarter, dd.month_number;


-- ============================================================
-- Q10: Which staff members process the highest number of
--      rentals and payments?
-- Category: Staff Performance
-- ============================================================
SELECT
    dst.full_name                   AS staff_name,
    ds.city                         AS store_city,
    dst.active_status,
    SUM(fr.rental_count)            AS total_rentals_processed,
    SUM(fp_counts.total_payments)   AS total_payments_processed,
    SUM(fp_amounts.total_revenue)   AS total_revenue_collected
FROM dim_staff dst
LEFT JOIN fact_rental  fr   ON dst.staff_key = fr.staff_key
LEFT JOIN dim_store    ds   ON dst.store_id  = ds.store_id
LEFT JOIN (
    SELECT staff_key, COUNT(*) AS total_payments
    FROM fact_payment
    GROUP BY staff_key
) fp_counts ON dst.staff_key = fp_counts.staff_key
LEFT JOIN (
    SELECT staff_key, SUM(payment_amount) AS total_revenue
    FROM fact_payment
    GROUP BY staff_key
) fp_amounts ON dst.staff_key = fp_amounts.staff_key
GROUP BY dst.staff_key, dst.full_name, ds.city, dst.active_status
ORDER BY total_rentals_processed DESC;


-- ============================================================
-- Q11: Which cities and countries have the most active customers?
-- Category: Geographic Analysis
-- ============================================================
SELECT
    dc.country,
    dc.city,
    COUNT(DISTINCT fr.customer_key) AS unique_customers,
    SUM(fr.rental_count)            AS total_rentals,
    SUM(fp.payment_amount)          AS total_revenue
FROM fact_rental  fr
JOIN dim_customer dc ON fr.customer_key  = dc.customer_key
LEFT JOIN fact_payment fp ON fr.customer_key = fp.customer_key
GROUP BY dc.country, dc.city
ORDER BY total_rentals DESC
LIMIT 15;


-- ============================================================
-- Q12: What is the average rental duration by film and category?
-- Category: Rental Analysis
-- ============================================================
SELECT
    dc.category_name,
    df.title,
    df.rental_duration_days         AS allowed_duration,
    ROUND(AVG(fr.rental_duration_days), 2) AS avg_actual_duration,
    COUNT(fr.rental_id)             AS total_rentals
FROM fact_rental        fr
JOIN dim_film           df  ON fr.film_key      = df.film_key
JOIN bridge_film_category bfc ON fr.film_key    = bfc.film_key
JOIN dim_category       dc  ON bfc.category_key = dc.category_key
WHERE fr.is_returned = 1    -- Only count completed rentals
GROUP BY dc.category_name, df.film_key, df.title, df.rental_duration_days
ORDER BY dc.category_name, avg_actual_duration DESC;


-- ============================================================
-- Q13: Which films are returned late most often?
-- Category: Rental Analysis
-- ============================================================
SELECT
    df.title,
    df.rental_duration_days         AS allowed_days,
    COUNT(fr.rental_id)             AS total_rentals,
    SUM(fr.is_late_return)          AS late_returns,
    ROUND(
        SUM(fr.is_late_return) / COUNT(fr.rental_id) * 100, 2
    )                               AS late_return_pct,
    ROUND(AVG(fr.days_overdue), 2)  AS avg_days_overdue
FROM fact_rental fr
JOIN dim_film    df ON fr.film_key = df.film_key
WHERE fr.is_returned = 1
GROUP BY df.film_key, df.title, df.rental_duration_days
HAVING late_returns > 0
ORDER BY late_return_pct DESC
LIMIT 10;


-- ============================================================
-- Q14: Which actors appear in the most frequently rented films?
-- Category: Film Performance
-- ============================================================
SELECT
    da.full_name                    AS actor_name,
    COUNT(DISTINCT bfa.film_key)    AS films_in_warehouse,
    SUM(fr.rental_count)            AS total_rentals_for_their_films
FROM dim_actor         da
JOIN bridge_film_actor bfa ON da.actor_key  = bfa.actor_key
JOIN fact_rental       fr  ON bfa.film_key  = fr.film_key
GROUP BY da.actor_key, da.full_name
ORDER BY total_rentals_for_their_films DESC
LIMIT 10;


-- ============================================================
-- Q15: How does store performance differ by location?
-- Category: Store Performance — combined rental + revenue view
-- ============================================================
SELECT
    ds.store_id,
    ds.city,
    ds.country,
    ds.manager_full_name,
    SUM(fr.rental_count)            AS total_rentals,
    SUM(fp.payment_amount)          AS total_revenue,
    COUNT(DISTINCT fr.customer_key) AS unique_customers,
    ROUND(SUM(fp.payment_amount) /
          NULLIF(SUM(fr.rental_count), 0), 2) AS avg_revenue_per_rental,
    SUM(fr.is_late_return)          AS total_late_returns,
    ROUND(SUM(fr.is_late_return) /
          NULLIF(SUM(fr.rental_count), 0) * 100, 2) AS late_return_pct
FROM fact_rental  fr
JOIN dim_store    ds ON fr.store_key     = ds.store_key
LEFT JOIN fact_payment fp ON fr.store_key = fp.store_key
GROUP BY ds.store_key, ds.store_id, ds.city, ds.country, ds.manager_full_name
ORDER BY total_revenue DESC;


-- ============================================================
-- BONUS: Unreturned Films — Financial Risk Analysis
-- Uses is_returned flag + replacement_cost from dim_film
-- Business question: What is the total replacement value
-- of films not yet returned?
-- ============================================================
SELECT
    df.title,
    df.replacement_cost,
    dc.full_name                    AS customer_name,
    dc.email,
    dc.phone,
    dc.city,
    dd_rental.full_date             AS rental_date,
    DATEDIFF(CURDATE(), dd_rental.full_date) AS days_since_rental
FROM fact_rental  fr
JOIN dim_film     df        ON fr.film_key          = df.film_key
JOIN dim_customer dc        ON fr.customer_key      = dc.customer_key
JOIN dim_date     dd_rental ON fr.date_key_rental   = dd_rental.date_key
WHERE fr.is_returned = 0
ORDER BY days_since_rental DESC;
