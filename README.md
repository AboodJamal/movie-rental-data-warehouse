# Movie Rental Data Warehouse

A complete Data Warehouse design and ETL implementation for the Sakila Movie Rental OLTP database, developed as a final assignment for a Data Warehousing course.

---

## Overview

This project transforms the Sakila OLTP database — a normalized relational schema supporting day-to-day movie rental operations — into a fully designed analytical Data Warehouse optimized for business reporting and decision-making.

The project covers the full lifecycle of Data Warehouse development:

- Identifying analytical business questions from operational data
- Designing a dimensional model using star schema principles
- Writing ETL scripts to extract, transform, and load data from the OLTP source
- Implementing data quality validation rules
- Executing analytical queries that answer real business questions

The implementation uses **MySQL** as the OLTP source, **SQLite** as the Data Warehouse target, and **Python (Pandas + Pandera)** for the ETL pipeline.

---

## Source Database

The source system is the **Sakila database** — a sample MySQL database representing a movie rental business. It contains 16 operational tables covering customers, films, inventory, rentals, payments, staff, stores, and geographic data.

| Table | Description |
|---|---|
| `rental` | Individual rental transactions |
| `payment` | Payment records per rental |
| `customer` | Customer profiles |
| `film` | Film catalog |
| `inventory` | Physical film copies per store |
| `store` | Store locations |
| `staff` | Staff members |
| `address` / `city` / `country` | Geographic hierarchy |
| `category` / `film_category` | Film categories (M:M) |
| `actor` / `film_actor` | Film actors (M:M) |
| `language` | Film languages |

---

## Data Warehouse Schema

The warehouse is designed as a **star schema with two bridge tables** to handle many-to-many relationships. It consists of 11 tables in total.

### Fact Tables

| Table | Grain | Key Measures |
|---|---|---|
| `fact_rental` | One row per rental transaction | rental_duration_days, days_overdue, is_late_return, is_returned |
| `fact_payment` | One row per payment transaction | payment_amount |

### Dimension Tables

| Table | Source OLTP Tables | Description |
|---|---|---|
| `dim_date` | Generated | Full calendar dimension covering all rental and payment dates |
| `dim_customer` | customer, address, city, country | Customer profiles with flattened geographic hierarchy |
| `dim_film` | film, language | Film catalog with embedded language |
| `dim_category` | category | Film categories |
| `dim_actor` | actor | Film actors |
| `dim_store` | store, staff, address, city, country | Store locations with embedded manager name |
| `dim_staff` | staff | Staff members |

### Bridge Tables

| Table | Resolves |
|---|---|
| `bridge_film_category` | Many-to-many between dim_film and dim_category |
| `bridge_film_actor` | Many-to-many between dim_film and dim_actor |

### Schema Diagram

The full dimensional model diagram is available in the `diagrams/` directory.

---

## Business Questions Answered

The warehouse is designed to answer 15 analytical business questions across six categories.

**Film Performance**
1. Which films are rented most frequently?
2. Which films generate the highest revenue?
3. Which film categories are most popular among customers?
4. Which actors appear in the most frequently rented films?

**Store Performance**
5. Which stores generate the highest number of rentals?
6. Which stores generate the highest revenue?
7. How does store performance differ by location?

**Customer Behavior**
8. Which customers rent the most films?
9. Which customers generate the highest revenue?

**Time-Based Trends**
10. How does rental activity change over time?
11. How does revenue change by month, quarter, and year?

**Staff Performance**
12. Which staff members process the highest number of rentals and payments?

**Rental Analysis**
13. What is the average rental duration by film category?
14. Which films are returned late most often?

**Geographic Analysis**
15. Which cities and countries have the most active customers?

---

## Repository Structure

```
movie-rental-data-warehouse/
│
├── README.md                              -- Project overview and documentation
├── Data_Warehouse_Assignment.pdf          -- Original assignment specification
│
├── report/
│   └── report.docx                        -- Full written report (7 sections)
│
├── diagrams/
│   └── dimensional_model.svg              -- Star schema dimensional model diagram
│
├── sql/
│   ├── 01_create_dw_tables.sql            -- DDL: create all warehouse tables
│   ├── 02_etl_dimensions.sql              -- ETL: load all dimension tables
│   ├── 03_etl_facts.sql                   -- ETL: load fact tables
│   ├── 04_data_quality_checks.sql         -- Data quality validation queries
│   └── 05_analytical_queries.sql          -- All 15 business question queries
│
└── ETL_MovieRental_DW.ipynb               -- Full ETL pipeline (Python notebook)
```

---

## ETL Pipeline

The ETL pipeline is implemented in `ETL_MovieRental_DW.ipynb` using Python.

### Dependencies

```
pandas
pandera
sqlalchemy
pymysql
```

Install all dependencies:

```bash
pip install pandas pandera sqlalchemy pymysql
```

### Pipeline Stages

| Stage | Description |
|---|---|
| Extract | Read all 15 source tables from Sakila MySQL into Pandas DataFrames |
| EDA | Inspect structure, data types, null counts, and duplicates |
| Transform | Clean, reshape, and enrich data into the dimensional model |
| Validate | Enforce data contracts on every table using Pandera schemas |
| Load | Write all 11 tables to SQLite warehouse in the correct order |
| Verify | Cross-check row counts and revenue totals against OLTP source |
| Query | Execute all 15 analytical business questions against the warehouse |

### Key Transformations

- Name concatenation with proper-case formatting for customer, staff, and actor tables
- Geographic hierarchy flattening: address → city → country collapsed into single dimension rows
- Surrogate key generation for all dimension tables replacing OLTP natural keys
- Programmatic `dim_date` generation covering the full date range of the dataset
- NULL return date handling: unreturned films mapped to `date_key = -1`
- Derived measures: `actual_duration_days`, `expected_duration_days`, `days_overdue`, `is_late_return`
- Many-to-many resolution via bridge tables for film-category and film-actor relationships
- Active status standardization: tinyint flag converted to `"Active"` / `"Inactive"`

### Loading Order

Dimensions must be loaded before fact tables to maintain referential integrity.

```
1.  dim_date
2.  dim_customer
3.  dim_film
4.  dim_category
5.  dim_actor
6.  bridge_film_category
7.  bridge_film_actor
8.  dim_store
9.  dim_staff
10. fact_rental
11. fact_payment
```

---

## Running the Project

### Option A — Python Notebook (Recommended)

1. Install the Sakila database on MySQL and confirm it is running locally.
2. Update the connection string in the Setup cell of the notebook:

```python
MYSQL_USER     = "root"
MYSQL_PASSWORD = "your_password"
MYSQL_HOST     = "127.0.0.1"
MYSQL_PORT     = "3306"
MYSQL_DB       = "sakila"
```

3. Run all cells in order from top to bottom. The notebook will:
   - Extract all source data from Sakila
   - Transform and validate every dimension and fact table
   - Load the warehouse into `movie_rental_dw.db` (SQLite file created automatically)
   - Verify reconciliation against the OLTP source
   - Execute all 15 analytical queries with results displayed inline

### Option B — SQL Scripts

1. Run `01_create_dw_tables.sql` to create the warehouse schema.
2. Ensure both `sakila` and `movie_rental_dw` databases exist on the same MySQL instance.
3. Run scripts in order: `01` → `02` → `03` → `04` → `05`.

---

## Data Quality

The project implements 15 data quality rules across four categories.

| Category | Rules | Examples |
|---|---|---|
| Completeness | DQ-01 to DQ-06 | No NULL rental dates, all FK surrogate keys resolved |
| Validity | DQ-07 to DQ-10, DQ-14 | Payment amount > 0, valid film rating ENUM, active status values |
| Consistency | DQ-10, DQ-15 | rental_duration_days not negative, days_overdue not negative |
| Reconciliation | DQ-11 to DQ-13 | Row count match, total revenue match, no orphaned dimension keys |

All rules are implemented both in `04_data_quality_checks.sql` and inline within the ETL notebook using Pandera schema validation.

---

## Design Decisions

| Decision | Rationale |
|---|---|
| Star schema over snowflake | Fewer joins at query time, faster analytical performance, better BI tool compatibility |
| Two separate fact tables | Rental activity and payment revenue have different grains and serve different analytical purposes |
| Conformed dimensions | dim_date, dim_customer, dim_store, dim_staff are shared between both fact tables enabling cross-process analysis |
| Language embedded in dim_film | Language is a direct film attribute; a separate dim_language table would add joins without analytical benefit |
| Manager name embedded in dim_store | Allows store performance reports to immediately identify the responsible manager without additional joins |
| SCD Type 1 | Changed dimension attributes overwrite existing values; suitable for this dataset where historical attribute tracking is not required |
| date_key = -1 for unreturned films | Maintains referential integrity in fact_rental without discarding active rental records |
| Surrogate keys throughout | Decouples the warehouse from OLTP primary keys, supports SCD, and improves join performance |

---

## Report

The full written report is available in `report/report.docx` and covers:

1. Introduction — OLTP vs Data Warehouse
2. Business Questions — 15 analytical questions with justification
3. Dimensional Model Design — fact tables, dimension tables, grain, measures, and source mapping
4. Dimensional Model Diagram — star schema visualization
5. ETL Design — Extract, Transform, and Load process in detail
6. Data Quality Considerations — 15 rules across 4 categories
7. Conclusion — design decisions summary and business value

---

## Course Information

| Field | Detail |
|---|---|
| Course | Data Warehousing / Data Architecture |
| Assignment | High-Level Data Warehouse Design from an OLTP Movie Rental System |
| Source Database | Sakila MySQL Sample Database |
| Warehouse Target | SQLite (movie_rental_dw.db) |
| Language | Python 3.12, SQL (MySQL 8.0) |
