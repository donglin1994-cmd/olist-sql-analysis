# olist-sql-analysis
SQL analysis of 100K Brazilian e-commerce orders: data quality checks and 10 business questions

# Olist E-Commerce Analysis (SQL)
Analysis of ~100,000 orders from Olist, a Brazilian online marketplace,
to understand what drives revenue, delivery performance and customer
satisfaction.

## Business Questions
1. How did revenue and order volume trend by month?
2. What was the month-over-month revenue growth?
3. Which product categories bring in the most revenue?
4. What are the top products in the leading categories?
5. Which states have the most orders, and what is the average order value?
6. How fast are deliveries, and what percent arrive late, by state?
7. Do late deliveries lead to lower review scores?
8. How do customers pay?
9. How many customers make a repeat purchase?
10. Who are the top sellers, and how do customers rate them?

## Dataset
[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
- ~100,000 orders placed from 2016 to 2018
- 8 related tables: orders, customers, order items, products, sellers,
  payments, reviews and category translations

## Tools
- MySQL 8 (MySQL Workbench)
- Power BI (dashboard in progress)

## Project Files
| File | Description |
| --- | --- |
| `sql/01_load_data.sql` | Creates the database and tables, and loads the CSV files |
| `sql/02_data_quality_checks.sql` | Completeness, uniqueness, business-rule and orphan checks, plus a cleaning log |
| `sql/03_business_questions.sql` | Queries answering the 10 business questions |

## Process
1. **Loaded the data:** imported 8 CSV files into MySQL with `LOAD DATA`
   and confirmed every table's row count matched the source.
2. **Checked data quality** before analysis:
   - **Completeness:** missing delivery dates belonged mostly to orders
     that were never delivered; products without a category were
     labeled "unknown."
   - **Uniqueness:** no duplicate keys in orders, customers, products or
     sellers. `review_id` repeated 814 times because one review can cover
     several orders, so scores were averaged to one per order to avoid
     double-counting.
   - **Business rules:** no order was delivered before it was purchased;
     6 canceled orders had a delivery date and were excluded from sales.
   - **Referential integrity:** used LEFT JOINs to check for orphan
     records between tables.
   - **Fix:** removed a hidden character (byte order mark) from a column
     name created during import.
3. **Answered the business questions** using multi-table joins, CTEs,
   CASE WHEN and window functions (LAG, ROW_NUMBER, SUM OVER).

## Key Findings
- **Top categories:** health & beauty, watches & gifts, and bed, bath &
  table were the top 3 revenue categories, making up [X]% of revenue
  together.
- **Customers by state:** [state] had the most orders ([X]% of total).
- **Delivery and satisfaction:** [X]% of orders arrived late, and late
  orders averaged a review score of [X] vs. [X] for on-time orders.
- **Repeat customers:** only [X]% of customers ordered more than once.

## Recommendations
- [e.g. Focus marketing and seller recruitment on the top categories.]
- [e.g. Improve delivery times in the states with the highest late rates
  to protect customer ratings.]
- [e.g. Build a loyalty program to raise the low repeat purchase rate.]

## Author
Dongqin Lin · [LinkedIn URL]
