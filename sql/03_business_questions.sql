/* =====================================================================
   OLIST E-COMMERCE PROJECT: BUSINESS QUESTIONS  (MySQL 8)
   Dataset: Brazilian E-Commerce Public Dataset by Olist (Kaggle)
   https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

   Tables: customers, orders, order_items, payments, reviews,
           products, sellers, category_translation

   Definitions used throughout
   - Sales are counted for delivered orders only.
   - Revenue = item price + freight (Q3, Q4 and Q10 use item price
     only, since freight is a shipping fee, not product sales).
   - customer_unique_id identifies a person; customer_id changes
     with every order.
   - Reviews are averaged per order so no order is counted twice.

   Skills shown: multi-table JOINs, LEFT JOIN, CTEs, CASE WHEN,
   window functions (LAG, ROW_NUMBER, SUM OVER), COALESCE, NULLIF.
   ===================================================================== */

USE olist;


/* =====================================================================
   Q1. How did revenue and order volume trend by month?
   Revenue = item price + freight, delivered orders only.
   ===================================================================== */
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id)                       AS orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)       AS revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY order_month
ORDER BY order_month;
-- Note: the first months (2016) and last months (late 2018) are
-- incomplete. Mention this in your write-up.
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q2. What was month-over-month revenue growth?  (window function: LAG)
   ===================================================================== */
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        SUM(oi.price + oi.freight_value)                 AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY order_month
)
SELECT
    order_month,
    ROUND(revenue, 2) AS revenue,
    ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
          / NULLIF(LAG(revenue) OVER (ORDER BY order_month), 0), 1) AS mom_growth_pct
FROM monthly
ORDER BY order_month;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q3. Which 10 product categories bring in the most revenue,
       and what share of total revenue does each represent?
   ===================================================================== */
WITH category_revenue AS (
    SELECT
        COALESCE(ct.product_category_name_english,
                 p.product_category_name, 'unknown') AS category,
        SUM(oi.price)                                AS revenue
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN category_translation ct
           ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY category
)
SELECT
    category,
    ROUND(revenue, 2)                                AS revenue,
    ROUND(100 * revenue / SUM(revenue) OVER (), 1)   AS pct_of_total
FROM category_revenue
ORDER BY revenue DESC
LIMIT 10;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q4. What are the top 3 products in each of the top 5 categories?
       (window function: ROW_NUMBER with PARTITION BY)
   ===================================================================== */
WITH product_sales AS (
    SELECT
        COALESCE(ct.product_category_name_english, 'unknown') AS category,
        oi.product_id,
        COUNT(*)      AS units_sold,
        SUM(oi.price) AS revenue
    FROM order_items oi
    JOIN orders o   ON o.order_id = oi.order_id
    JOIN products p ON p.product_id = oi.product_id
    LEFT JOIN category_translation ct
           ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY category, oi.product_id
),
top_categories AS (
    SELECT category
    FROM product_sales
    GROUP BY category
    ORDER BY SUM(revenue) DESC
    LIMIT 5
),
ranked AS (
    SELECT
        ps.*,
        ROW_NUMBER() OVER (PARTITION BY ps.category ORDER BY ps.revenue DESC) AS rank_in_category
    FROM product_sales ps
    JOIN top_categories tc ON tc.category = ps.category
)
SELECT category, rank_in_category, product_id, units_sold,
       ROUND(revenue, 2) AS revenue
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q5. Which states have the most orders, and what is the
       average order value (AOV) in each?
   ===================================================================== */
WITH order_totals AS (
    SELECT order_id, SUM(price + freight_value) AS order_value
    FROM order_items
    GROUP BY order_id
)
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id) AS customers,
    COUNT(DISTINCT o.order_id)           AS orders,
    ROUND(AVG(ot.order_value), 2)        AS avg_order_value
FROM orders o
JOIN customers c     ON c.customer_id = o.customer_id
JOIN order_totals ot ON ot.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY orders DESC;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q6. How fast are deliveries, and what percent arrive late, by state?
   Late = delivered after the estimated delivery date.
   ===================================================================== */
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1) AS avg_days_to_deliver,
    ROUND(100 * AVG(CASE WHEN o.order_delivered_customer_date
                                > o.order_estimated_delivery_date
                         THEN 1 ELSE 0 END), 1)         AS pct_late
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY pct_late DESC;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q7. Do late deliveries lead to lower review scores?
   (Reviews are averaged per order first, because some orders have
    more than one review row.)
   ===================================================================== */
WITH order_reviews AS (
    SELECT order_id, AVG(review_score) AS review_score
    FROM reviews
    GROUP BY order_id
)
SELECT
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 'Late' ELSE 'On time' END                       AS delivery_status,
    COUNT(*)                                                  AS orders,
    ROUND(AVG(r.review_score), 2)                             AS avg_review_score,
    ROUND(100 * AVG(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END), 1)
                                                              AS pct_bad_reviews
FROM orders o
JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q8. How do customers pay? Share of payment value by payment type,
       and average number of installments.
   ===================================================================== */
SELECT
    payment_type,
    COUNT(DISTINCT order_id)                                  AS orders,
    ROUND(SUM(payment_value), 2)                              AS total_paid,
    ROUND(100 * SUM(payment_value) / SUM(SUM(payment_value)) OVER (), 1)
                                                              AS pct_of_value,
    ROUND(AVG(payment_installments), 1)                       AS avg_installments
FROM payments
GROUP BY payment_type
ORDER BY total_paid DESC;
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q9. How many customers come back? Repeat purchase rate.
   (Uses customer_unique_id, not customer_id.)
   ===================================================================== */
WITH customer_orders AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                             AS total_customers,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)    AS repeat_customers,
    ROUND(100 * SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                 AS repeat_rate_pct
FROM customer_orders;
-- Expect a low repeat rate. That is itself an insight worth discussing
-- (contrast with Costco, whose model depends on ~90% member renewal).
-- INSIGHT: [write 1-2 sentences about what this result shows]


/* =====================================================================
   Q10. Who are the top 10 sellers by revenue, and how do their
        customers rate them?
   ===================================================================== */
WITH order_reviews AS (
    SELECT order_id, AVG(review_score) AS review_score
    FROM reviews
    GROUP BY order_id
)
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id)    AS orders,
    ROUND(SUM(oi.price), 2)        AS revenue,
    ROUND(AVG(r.review_score), 2)  AS avg_review_score
FROM order_items oi
JOIN orders o  ON o.order_id = oi.order_id
JOIN sellers s ON s.seller_id = oi.seller_id
LEFT JOIN order_reviews r ON r.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_state
ORDER BY revenue DESC
LIMIT 10;
-- INSIGHT: [write 1-2 sentences about what this result shows]
