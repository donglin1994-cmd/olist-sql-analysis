/* =====================================================================
   OLIST E-COMMERCE PROJECT: DATA QUALITY CHECKS  (MySQL 8)

   Checks run before analysis, only on the tables and columns the
   business questions use:
     1. Completeness   - row counts and NULL values
     2. Uniqueness     - duplicate keys
     3. Business rules - values and dates that must make sense
     4. Referential integrity - orphan records between tables
     5. Fixes applied

   Raw tables are never modified; problems are handled in the
   analysis queries (filters, COALESCE, one review per order).
   Findings are summarized in the CLEANING LOG at the end.
   ===================================================================== */

USE olist;


/* =====================================================================
   1. COMPLETENESS
   ===================================================================== */

-- 1a. Row counts per table (all matched the source CSV files)
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'payments',             COUNT(*) FROM payments
UNION ALL SELECT 'reviews',              COUNT(*) FROM reviews
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'sellers',              COUNT(*) FROM sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation;

-- 1b. Order status breakdown (analysis uses 'delivered' orders only)
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 1c. NULLs in orders
SELECT COUNT(*)                                   AS total_rows,
       SUM(order_status IS NULL)                  AS null_status,
       SUM(order_purchase_timestamp IS NULL)      AS null_purchase_date,
       SUM(order_delivered_customer_date IS NULL) AS null_delivered_date,
       SUM(order_estimated_delivery_date IS NULL) AS null_estimated_date,
       SUM(order_status = 'delivered'
           AND order_delivered_customer_date IS NULL) AS delivered_but_no_date
FROM orders;

-- 1d. NULLs in order_items (join keys and revenue columns)
SELECT COUNT(*)                   AS total_rows,
       SUM(order_id IS NULL)      AS null_order_id,
       SUM(product_id IS NULL)    AS null_product_id,
       SUM(seller_id IS NULL)     AS null_seller_id,
       SUM(price IS NULL)         AS null_price,
       SUM(freight_value IS NULL) AS null_freight_value
FROM order_items;

-- 1e. NULLs in products (category is used for revenue by category)
SELECT COUNT(*)                           AS total_rows,
       SUM(product_category_name IS NULL) AS null_category
FROM products;

-- 1f. NULLs in customers, reviews, payments and sellers
SELECT 'customers' AS table_name,
       SUM(customer_unique_id IS NULL) + SUM(customer_state IS NULL) AS null_values
FROM customers
UNION ALL
SELECT 'reviews',  SUM(review_score IS NULL)                              FROM reviews
UNION ALL
SELECT 'payments', SUM(payment_type IS NULL) + SUM(payment_value IS NULL) FROM payments
UNION ALL
SELECT 'sellers',  SUM(seller_state IS NULL)                              FROM sellers;


/* =====================================================================
   2. UNIQUENESS
   ===================================================================== */

-- 2a. Duplicate primary keys (expected: 0 for each)
SELECT 'orders.order_id' AS key_column,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicates FROM orders
UNION ALL SELECT 'customers.customer_id',
       COUNT(*) - COUNT(DISTINCT customer_id) FROM customers
UNION ALL SELECT 'products.product_id',
       COUNT(*) - COUNT(DISTINCT product_id) FROM products
UNION ALL SELECT 'sellers.seller_id',
       COUNT(*) - COUNT(DISTINCT seller_id) FROM sellers
UNION ALL SELECT 'reviews.review_id',
       COUNT(*) - COUNT(DISTINCT review_id) FROM reviews;

-- 2b. Composite keys (expected: no rows)
SELECT order_id, order_item_id, COUNT(*) AS cnt
FROM order_items
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

SELECT order_id, payment_sequential, COUNT(*) AS cnt
FROM payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- 2c. Why review_id repeats: one review can cover several orders
SELECT review_id,
       COUNT(*)                 AS row_count,
       COUNT(DISTINCT order_id) AS different_orders
FROM reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 10;

-- 2d. Orders with more than one review (could double-count in joins)
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) multi;


/* =====================================================================
   3. BUSINESS RULES
   ===================================================================== */

-- 3a. Date logic and status consistency
SELECT
    SUM(order_delivered_customer_date IS NOT NULL)                AS orders_with_delivery_date,
    SUM(order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase,
    SUM(order_approved_at < order_purchase_timestamp)             AS approved_before_purchase,
    SUM(order_delivered_carrier_date > order_delivered_customer_date) AS carrier_after_delivery,
    SUM(order_status = 'canceled'
        AND order_delivered_customer_date IS NOT NULL)            AS canceled_but_delivered
FROM orders;

-- 3b. Valid ranges for prices, freight and review scores
SELECT
    (SELECT SUM(price <= 0)                     FROM order_items) AS zero_or_negative_price,
    (SELECT SUM(freight_value < 0)              FROM order_items) AS negative_freight,
    (SELECT SUM(review_score NOT BETWEEN 1 AND 5) FROM reviews)   AS invalid_review_score;

-- 3c. Payments reconcile to order totals (item price + freight)
WITH items AS (
    SELECT order_id, SUM(price + freight_value) AS item_total
    FROM order_items
    GROUP BY order_id
),
pays AS (
    SELECT order_id, SUM(payment_value) AS paid_total
    FROM payments
    GROUP BY order_id
)
SELECT COUNT(*)                                  AS orders_compared,
       SUM(ABS(i.item_total - p.paid_total) > 1) AS mismatched_orders
FROM items i
JOIN pays p ON p.order_id = i.order_id;


/* =====================================================================
   4. REFERENTIAL INTEGRITY (orphan records)
   A LEFT JOIN keeps every child row; a NULL parent key means no match.
   An INNER JOIN would drop these rows silently.
   ===================================================================== */

SELECT 'order_items -> orders' AS relationship, COUNT(*) AS orphans
FROM order_items oi LEFT JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_items -> products', COUNT(*)
FROM order_items oi LEFT JOIN products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'order_items -> sellers', COUNT(*)
FROM order_items oi LEFT JOIN sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'orders -> customers', COUNT(*)
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'payments -> orders', COUNT(*)
FROM payments pa LEFT JOIN orders o ON o.order_id = pa.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'reviews -> orders', COUNT(*)
FROM reviews r LEFT JOIN orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'products -> category_translation (categories)',
       COUNT(DISTINCT p.product_category_name)
FROM products p
LEFT JOIN category_translation ct
       ON ct.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL;


/* =====================================================================
   5. FIX APPLIED: hidden byte order mark in a column name
   A table imported with the Import Wizard got a first column named
   'ï»¿product_category_name' (a hidden UTF-8 marker from the CSV).
   Fix: copy the rows into a table with correct column names.
   (Not needed if the table was loaded with 01_load_data.sql.)
   ===================================================================== */

-- CREATE TABLE category_translation_clean (
--     product_category_name          VARCHAR(100),
--     product_category_name_english  VARCHAR(100)
-- );
-- INSERT INTO category_translation_clean SELECT * FROM category_translation;
-- DROP TABLE category_translation;
-- RENAME TABLE category_translation_clean TO category_translation;


/* =====================================================================
   CLEANING LOG  (fill in the numbers from your results)

   Completeness
   - All 8 tables loaded with row counts matching the source files.
   - Missing delivery dates belong mostly to orders that were never
     delivered (canceled, unavailable, in transit), which is expected.
     [X] delivered orders had no delivery date: kept for sales
     analysis, excluded from delivery-time calculations.
   - [X] products had no category: labeled 'unknown' with COALESCE.
   - Review comments are mostly empty; scores are complete. Not used.

   Uniqueness
   - No duplicate keys in orders, customers, products or sellers.
   - review_id repeated 814 times because one review can cover
     several orders; kept. Orders with more than one review are
     averaged to one score per order to avoid double-counting.
   - Repeated order_id in order_items and payments is expected
     (several items or split payments per order).

   Business rules
   - No order was delivered before it was purchased.
   - 6 canceled orders had a delivery date (likely canceled after
     delivery); excluded from sales because only delivered orders
     are counted.
   - [Add results for carrier dates, prices, review scores and the
     payment reconciliation.]

   Referential integrity
   - [X] orphan records found between the main tables.
   - [X] product categories had no English translation; the
     Portuguese name is shown instead.
   ===================================================================== */
