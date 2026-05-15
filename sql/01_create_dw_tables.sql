-- ============================================================
-- FILE: 01_create_dw_tables.sql
-- PURPOSE: Create all Data Warehouse tables for the
--          Movie Rental Data Warehouse
-- SOURCE OLTP: Sakila Database
-- SCHEMA TYPE: Star Schema with Bridge Tables (Hybrid)
-- AUTHOR: Data Warehouse Design Assignment
-- ============================================================

-- Drop existing DW database and recreate clean
DROP DATABASE IF EXISTS movie_rental_dw;
CREATE DATABASE movie_rental_dw
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE movie_rental_dw;

-- ============================================================
-- STEP 1: DIMENSION TABLES
-- Dimensions must be created before fact tables
-- because fact tables reference dimension surrogate keys
-- ============================================================

-- ------------------------------------------------------------
-- dim_date
-- Generated programmatically — not extracted from OLTP
-- Covers the full date range of rental and payment data
-- Special row: date_key = -1 for unreturned films (NULL return_date)
-- ------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        INT             NOT NULL,   -- YYYYMMDD format e.g. 20050715
    full_date       DATE            NULL,        -- NULL for special row date_key = -1
    day_of_week     INT             NULL,        -- 1=Monday ... 7=Sunday
    day_name        VARCHAR(10)     NULL,        -- 'Monday', 'Tuesday', ...
    day_of_month    INT             NULL,        -- 1-31
    month_number    INT             NULL,        -- 1-12
    month_name      VARCHAR(10)     NULL,        -- 'January', 'February', ...
    quarter         INT             NULL,        -- 1-4
    year            INT             NULL,        -- Four-digit year e.g. 2005
    is_weekend      TINYINT(1)      NULL,        -- 1 if Saturday or Sunday, else 0
    PRIMARY KEY (date_key)
) COMMENT = 'Date dimension — covers all dates in rental and payment data. date_key=-1 represents unreturned films.';


-- ------------------------------------------------------------
-- dim_customer
-- Built from: customer + address + city + country
-- Geographic hierarchy flattened into single row
-- ------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_key    INT             NOT NULL AUTO_INCREMENT,
    customer_id     SMALLINT        NOT NULL,    -- Original OLTP customer_id (for traceability)
    full_name       VARCHAR(91)     NOT NULL,    -- CONCAT(first_name, ' ', last_name)
    email           VARCHAR(50)     NOT NULL,    -- 'N/A' if NULL in source
    active_status   VARCHAR(10)     NOT NULL,    -- 'Active' or 'Inactive'
    address         VARCHAR(50)     NOT NULL,
    address2        VARCHAR(50)     NULL,
    district        VARCHAR(20)     NOT NULL,
    city            VARCHAR(50)     NOT NULL,
    country         VARCHAR(50)     NOT NULL,
    postal_code     VARCHAR(10)     NULL,
    phone           VARCHAR(20)     NOT NULL,
    customer_since  DATE            NOT NULL,    -- Derived from customer.create_date
    PRIMARY KEY (customer_key),
    UNIQUE KEY uq_customer_id (customer_id)
) COMMENT = 'Customer dimension — source: customer, address, city, country. SCD Type 1.';


-- ------------------------------------------------------------
-- dim_film
-- Built from: film + language
-- Language embedded (not a separate dimension)
-- ------------------------------------------------------------
CREATE TABLE dim_film (
    film_key                INT             NOT NULL AUTO_INCREMENT,
    film_id                 SMALLINT        NOT NULL,   -- Original OLTP film_id
    title                   VARCHAR(128)    NOT NULL,
    description             TEXT            NULL,
    release_year            YEAR            NULL,
    language                VARCHAR(20)     NOT NULL,   -- Joined from language.name
    original_language       VARCHAR(20)     NULL,       -- NULL if not dubbed
    rental_rate             DECIMAL(4,2)    NOT NULL,
    rental_duration_days    TINYINT         NOT NULL,   -- Allowed rental duration
    length_minutes          SMALLINT        NULL,
    replacement_cost        DECIMAL(5,2)    NOT NULL,
    rating                  VARCHAR(10)     NULL,       -- G, PG, PG-13, R, NC-17
    special_features        VARCHAR(100)    NULL,       -- Trailers, Commentaries, etc.
    PRIMARY KEY (film_key),
    UNIQUE KEY uq_film_id (film_id)
) COMMENT = 'Film dimension — source: film, language. Language embedded to avoid unnecessary join.';


-- ------------------------------------------------------------
-- dim_category
-- Built from: category
-- ------------------------------------------------------------
CREATE TABLE dim_category (
    category_key    INT             NOT NULL AUTO_INCREMENT,
    category_id     TINYINT         NOT NULL,   -- Original OLTP category_id
    category_name   VARCHAR(25)     NOT NULL,
    PRIMARY KEY (category_key),
    UNIQUE KEY uq_category_id (category_id)
) COMMENT = 'Category dimension — source: category. 16 film categories in Sakila.';


-- ------------------------------------------------------------
-- dim_actor
-- Built from: actor
-- ------------------------------------------------------------
CREATE TABLE dim_actor (
    actor_key       INT             NOT NULL AUTO_INCREMENT,
    actor_id        SMALLINT        NOT NULL,   -- Original OLTP actor_id
    full_name       VARCHAR(91)     NOT NULL,   -- CONCAT(first_name, ' ', last_name)
    PRIMARY KEY (actor_key),
    UNIQUE KEY uq_actor_id (actor_id)
) COMMENT = 'Actor dimension — source: actor. 200 actors in Sakila.';


-- ------------------------------------------------------------
-- dim_store
-- Built from: store + staff (manager) + address + city + country
-- Manager name embedded to avoid extra join at query time
-- ------------------------------------------------------------
CREATE TABLE dim_store (
    store_key           INT             NOT NULL AUTO_INCREMENT,
    store_id            TINYINT         NOT NULL,   -- Original OLTP store_id
    manager_full_name   VARCHAR(91)     NOT NULL,   -- Joined from staff
    address             VARCHAR(50)     NOT NULL,
    address2            VARCHAR(50)     NULL,
    district            VARCHAR(20)     NOT NULL,
    city                VARCHAR(50)     NOT NULL,
    country             VARCHAR(50)     NOT NULL,
    postal_code         VARCHAR(10)     NULL,
    phone               VARCHAR(20)     NOT NULL,
    PRIMARY KEY (store_key),
    UNIQUE KEY uq_store_id (store_id)
) COMMENT = 'Store dimension — source: store, staff, address, city, country. SCD Type 1.';


-- ------------------------------------------------------------
-- dim_staff
-- Built from: staff
-- ------------------------------------------------------------
CREATE TABLE dim_staff (
    staff_key       INT             NOT NULL AUTO_INCREMENT,
    staff_id        TINYINT         NOT NULL,   -- Original OLTP staff_id
    full_name       VARCHAR(91)     NOT NULL,   -- CONCAT(first_name, ' ', last_name)
    email           VARCHAR(50)     NOT NULL,   -- 'N/A' if NULL in source
    active_status   VARCHAR(10)     NOT NULL,   -- 'Active' or 'Inactive'
    store_id        TINYINT         NOT NULL,   -- Store the staff belongs to
    PRIMARY KEY (staff_key),
    UNIQUE KEY uq_staff_id (staff_id)
) COMMENT = 'Staff dimension — source: staff. SCD Type 1.';


-- ============================================================
-- STEP 2: BRIDGE TABLES
-- Resolve many-to-many relationships between dim_film
-- and dim_category / dim_actor
-- Must be created after dim_film, dim_category, dim_actor
-- ============================================================

-- ------------------------------------------------------------
-- bridge_film_category
-- Resolves M:M between dim_film and dim_category
-- Source: film_category (OLTP)
-- ------------------------------------------------------------
CREATE TABLE bridge_film_category (
    film_key        INT     NOT NULL,
    category_key    INT     NOT NULL,
    PRIMARY KEY (film_key, category_key),
    CONSTRAINT fk_bfc_film     FOREIGN KEY (film_key)     REFERENCES dim_film(film_key),
    CONSTRAINT fk_bfc_category FOREIGN KEY (category_key) REFERENCES dim_category(category_key)
) COMMENT = 'Bridge table — resolves many-to-many between dim_film and dim_category.';


-- ------------------------------------------------------------
-- bridge_film_actor
-- Resolves M:M between dim_film and dim_actor
-- Source: film_actor (OLTP)
-- ------------------------------------------------------------
CREATE TABLE bridge_film_actor (
    film_key    INT     NOT NULL,
    actor_key   INT     NOT NULL,
    PRIMARY KEY (film_key, actor_key),
    CONSTRAINT fk_bfa_film  FOREIGN KEY (film_key)  REFERENCES dim_film(film_key),
    CONSTRAINT fk_bfa_actor FOREIGN KEY (actor_key) REFERENCES dim_actor(actor_key)
) COMMENT = 'Bridge table — resolves many-to-many between dim_film and dim_actor.';


-- ============================================================
-- STEP 3: FACT TABLES
-- Must be created AFTER all dimension tables
-- ============================================================

-- ------------------------------------------------------------
-- fact_rental
-- Grain: One row per rental transaction
-- Source: rental + inventory (to resolve film_id and store_id)
-- ------------------------------------------------------------
CREATE TABLE fact_rental (
    -- Degenerate Dimension (original OLTP ID kept for traceability)
    rental_id               INT             NOT NULL,

    -- Foreign Keys to Dimensions
    date_key_rental         INT             NOT NULL,   -- FK to dim_date (rental date)
    date_key_return         INT             NOT NULL,   -- FK to dim_date (-1 if not yet returned)
    customer_key            INT             NOT NULL,   -- FK to dim_customer
    film_key                INT             NOT NULL,   -- FK to dim_film (via inventory)
    store_key               INT             NOT NULL,   -- FK to dim_store (via inventory)
    staff_key               INT             NOT NULL,   -- FK to dim_staff

    -- Measures
    rental_duration_days    INT             NULL,       -- Actual days kept (NULL if not returned)
    expected_duration_days  INT             NOT NULL,   -- Allowed days from film.rental_duration
    days_overdue            INT             NULL,       -- 0 if on time, >0 if late, NULL if not returned
    is_late_return          TINYINT(1)      NULL,       -- 1=late, 0=on time, NULL=not returned
    is_returned             TINYINT(1)      NOT NULL,   -- 1=returned, 0=not yet returned
    rental_count            INT             NOT NULL DEFAULT 1, -- Always 1, used for aggregation

    PRIMARY KEY (rental_id),

    CONSTRAINT fk_fr_date_rental  FOREIGN KEY (date_key_rental) REFERENCES dim_date(date_key),
    CONSTRAINT fk_fr_date_return  FOREIGN KEY (date_key_return) REFERENCES dim_date(date_key),
    CONSTRAINT fk_fr_customer     FOREIGN KEY (customer_key)    REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_fr_film         FOREIGN KEY (film_key)        REFERENCES dim_film(film_key),
    CONSTRAINT fk_fr_store        FOREIGN KEY (store_key)       REFERENCES dim_store(store_key),
    CONSTRAINT fk_fr_staff        FOREIGN KEY (staff_key)       REFERENCES dim_staff(staff_key)
) COMMENT = 'Fact table — one row per rental transaction. Grain: individual rental.';


-- ------------------------------------------------------------
-- fact_payment
-- Grain: One row per payment transaction
-- Source: payment
-- store_key derived via: payment -> staff -> store
-- ------------------------------------------------------------
CREATE TABLE fact_payment (
    -- Degenerate Dimension
    payment_id      SMALLINT        NOT NULL,

    -- Foreign Keys to Dimensions
    date_key        INT             NOT NULL,   -- FK to dim_date (payment date)
    customer_key    INT             NOT NULL,   -- FK to dim_customer
    staff_key       INT             NOT NULL,   -- FK to dim_staff
    store_key       INT             NOT NULL,   -- FK to dim_store (derived via staff)

    -- Soft reference to rental (not enforced FK — rental may be NULL in source)
    rental_id       INT             NULL,       -- Reference to original rental

    -- Measures
    payment_amount  DECIMAL(5,2)    NOT NULL,   -- Amount paid
    payment_count   INT             NOT NULL DEFAULT 1, -- Always 1, used for aggregation

    PRIMARY KEY (payment_id),

    CONSTRAINT fk_fp_date       FOREIGN KEY (date_key)      REFERENCES dim_date(date_key),
    CONSTRAINT fk_fp_customer   FOREIGN KEY (customer_key)  REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_fp_staff      FOREIGN KEY (staff_key)     REFERENCES dim_staff(staff_key),
    CONSTRAINT fk_fp_store      FOREIGN KEY (store_key)     REFERENCES dim_store(store_key)
) COMMENT = 'Fact table — one row per payment transaction. Grain: individual payment.';


-- ============================================================
-- VERIFICATION: List all created tables
-- ============================================================
SELECT
    table_name,
    table_comment
FROM information_schema.tables
WHERE table_schema = 'movie_rental_dw'
ORDER BY table_name;
