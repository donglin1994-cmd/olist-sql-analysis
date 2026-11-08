/* =====================================================================
   LOAD OLIST CSV FILES INTO MYSQL
   Run in MySQL Workbench.

   Purpose: create the olist database, define 8 tables and load the
   Kaggle CSV files with LOAD DATA (faster and more reliable than the
   Import Wizard, which skipped rows with blank dates).

   Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

   To run:
   1. In MySQL Workbench, add OPT_LOCAL_INFILE=1 to the connection's
      Advanced > Others settings, then reconnect.
   2. Replace  path/to/olist/  with the folder holding the CSV files
      (use forward slashes / on Windows).
   3. Run the whole script (Ctrl+Shift+Enter).
   ===================================================================== */

-- Allow LOCAL INFILE on the server (needs an admin login; root on your own PC is fine)
SET GLOBAL local_infile = 1;

-- Create the database and switch to it
CREATE DATABASE IF NOT EXISTS olist CHARACTER SET utf8mb4;
USE olist;


/* ---------------------------------------------------------------------
   1. CREATE TABLES
   Zip codes are stored as text so leading zeros are kept.
   --------------------------------------------------------------------- */

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id               VARCHAR(32) PRIMARY KEY,
    customer_unique_id        VARCHAR(32),
    customer_zip_code_prefix  VARCHAR(10),
    customer_city             VARCHAR(100),
    customer_state            CHAR(2)
);

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    order_id                       VARCHAR(32) PRIMARY KEY,
    customer_id                    VARCHAR(32),
    order_status                   VARCHAR(20),
    order_purchase_timestamp       DATETIME,
    order_approved_at              DATETIME NULL,
    order_delivered_carrier_date   DATETIME NULL,
    order_delivered_customer_date  DATETIME NULL,
    order_estimated_delivery_date  DATETIME NULL
);

DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
    order_id             VARCHAR(32),
    order_item_id        INT,
    product_id           VARCHAR(32),
    seller_id            VARCHAR(32),
    shipping_limit_date  DATETIME,
    price                DECIMAL(10,2),
    freight_value        DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

DROP TABLE IF EXISTS payments;
CREATE TABLE payments (
    order_id              VARCHAR(32),
    payment_sequential    INT,
    payment_type          VARCHAR(20),
    payment_installments  INT,
    payment_value         DECIMAL(10,2)
);

-- review_id is NOT unique in this dataset, so no primary key here
DROP TABLE IF EXISTS reviews;
CREATE TABLE reviews (
    review_id                VARCHAR(32),
    order_id                 VARCHAR(32),
    review_score             INT,
    review_comment_title     VARCHAR(255),
    review_comment_message   TEXT,
    review_creation_date     DATETIME,
    review_answer_timestamp  DATETIME
);

-- Note: "lenght" is misspelled in the original dataset; kept as-is
DROP TABLE IF EXISTS products;
CREATE TABLE products (
    product_id                  VARCHAR(32) PRIMARY KEY,
    product_category_name       VARCHAR(100) NULL,
    product_name_lenght         INT NULL,
    product_description_lenght  INT NULL,
    product_photos_qty          INT NULL,
    product_weight_g            INT NULL,
    product_length_cm           INT NULL,
    product_height_cm           INT NULL,
    product_width_cm            INT NULL
);

DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
    seller_id               VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state            CHAR(2)
);

DROP TABLE IF EXISTS category_translation;
CREATE TABLE category_translation (
    product_category_name          VARCHAR(100) PRIMARY KEY,
    product_category_name_english  VARCHAR(100)
);


/* ---------------------------------------------------------------------
   2. LOAD THE CSV FILES
   Empty values are turned into NULL with NULLIF( @variable, '' ).
   --------------------------------------------------------------------- */

LOAD DATA LOCAL INFILE 'path/to/olist/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, @state)
SET customer_state = TRIM(TRAILING '\r' FROM @state);

LOAD DATA LOCAL INFILE 'path/to/olist/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, @purchase, @approved, @carrier, @delivered, @estimated)
SET order_purchase_timestamp      = NULLIF(@purchase, ''),
    order_approved_at             = NULLIF(@approved, ''),
    order_delivered_carrier_date  = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date = NULLIF(TRIM(TRAILING '\r' FROM @estimated), '');

LOAD DATA LOCAL INFILE 'path/to/olist/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, @freight)
SET freight_value = TRIM(TRAILING '\r' FROM @freight);

LOAD DATA LOCAL INFILE 'path/to/olist/olist_order_payments_dataset.csv'
INTO TABLE payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, payment_sequential, payment_type, payment_installments, @value)
SET payment_value = TRIM(TRAILING '\r' FROM @value);

-- Review comments can contain commas and line breaks inside quotes; ENCLOSED BY handles that
LOAD DATA LOCAL INFILE 'path/to/olist/olist_order_reviews_dataset.csv'
INTO TABLE reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(review_id, order_id, review_score, @title, @message, @created, @answered)
SET review_comment_title    = NULLIF(@title, ''),
    review_comment_message  = NULLIF(@message, ''),
    review_creation_date    = NULLIF(@created, ''),
    review_answer_timestamp = NULLIF(TRIM(TRAILING '\r' FROM @answered), '');

LOAD DATA LOCAL INFILE 'path/to/olist/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, @cat, @name_len, @desc_len, @photos, @weight, @length, @height, @width)
SET product_category_name      = NULLIF(@cat, ''),
    product_name_lenght        = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@desc_len, ''),
    product_photos_qty         = NULLIF(@photos, ''),
    product_weight_g           = NULLIF(@weight, ''),
    product_length_cm          = NULLIF(@length, ''),
    product_height_cm          = NULLIF(@height, ''),
    product_width_cm           = NULLIF(TRIM(TRAILING '\r' FROM @width), '');

LOAD DATA LOCAL INFILE 'path/to/olist/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(seller_id, seller_zip_code_prefix, seller_city, @state)
SET seller_state = TRIM(TRAILING '\r' FROM @state);

LOAD DATA LOCAL INFILE 'path/to/olist/product_category_name_translation.csv'
INTO TABLE category_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_category_name, @english)
SET product_category_name_english = TRIM(TRAILING '\r' FROM @english);


/* ---------------------------------------------------------------------
   3. CHECK THE LOAD
   Expected row counts (all matched after loading):
     customers 99,441 | orders 99,441 | order_items 112,650
     payments 103,886 | reviews ~99,224 | products 32,951
     sellers 3,095    | category_translation 71
   --------------------------------------------------------------------- */
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders',               COUNT(*) FROM orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM order_items
UNION ALL SELECT 'payments',             COUNT(*) FROM payments
UNION ALL SELECT 'reviews',              COUNT(*) FROM reviews
UNION ALL SELECT 'products',             COUNT(*) FROM products
UNION ALL SELECT 'sellers',              COUNT(*) FROM sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM category_translation;

-- Quick look at a few rows to confirm dates and text loaded correctly
SELECT * FROM orders  LIMIT 5;
SELECT * FROM reviews LIMIT 5;
