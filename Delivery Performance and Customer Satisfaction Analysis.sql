/* 
========================================================
Delivery Performance & Customer Satisfaction Analysis
========================================================

Goal:
- Identify patterns in late deliveries, their causes, and their effect on customer reviews.

Key Questions:
1. What percentage of orders are delivered late vs. on time?
2. Which product categories have the highest late delivery rate?
3. How much does lateness impact review scores?
*/ 


/* 
--------------------------------------------------------
Step 1: Initial Exploration of the Orders Table
--------------------------------------------------------
Purpose:
- Understand available columns and sample data.
- Identify relevant delivery date fields for analysis.
*/
SELECT *
FROM orders
LIMIT 10;

/*
Key columns for delivery performance analysis:
- order_estimated_delivery_date → Promised delivery date.
- order_delivered_customer_date → Actual delivery date.

These will be used to determine if deliveries met expectations.
*/


/* 
--------------------------------------------------------
Step 2: Distribution of Order Statuses
--------------------------------------------------------
Purpose:
- Get an overview of order status categories.
- Understand which statuses to include in the analysis.
*/
WITH statuses AS (
    SELECT order_status, COUNT(*) AS order_count
    FROM orders
    GROUP BY order_status
)
SELECT 
    order_status,
    order_count,
    ROUND(order_count / SUM(order_count) OVER () * 100, 2) AS percent_of_orders
FROM statuses
ORDER BY order_count DESC;

/*
Findings:
- ~97% of orders are marked as "delivered."
- Other statuses: shipped, invoiced, created, canceled.
- For delivery timeliness, only orders with both estimated and actual dates will be analyzed.
*/


/* 
--------------------------------------------------------
Step 3: Classifying Orders as On Time or Late
--------------------------------------------------------
Definition:
- "Late" = actual delivery date > estimated delivery date.
- Exclude orders missing either date.
*/
WITH classified AS (
    SELECT *,
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'
            ELSE 'on time'
        END AS on_time_status
    FROM orders
    WHERE order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
)
SELECT order_status, COUNT(*) AS order_count
FROM classified
GROUP BY order_status
ORDER BY order_count DESC;

/*
Observation:
- Some "canceled" orders have delivery dates → they will be included in performance analysis.
*/
SELECT *
FROM orders
WHERE order_estimated_delivery_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_status = 'canceled';


/* 
--------------------------------------------------------
Step 4: Overall Late vs. On-Time Delivery Rate
--------------------------------------------------------
Purpose:
- Measure total percentage of late vs. on-time orders.
*/
WITH stats AS (
    SELECT *,
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'
            ELSE 'on time'
        END AS on_time_status
    FROM orders
    WHERE order_estimated_delivery_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
),
status_count AS (
    SELECT on_time_status, COUNT(*) AS stat_count
    FROM stats
    GROUP BY on_time_status
)
SELECT 
    on_time_status, 
    stat_count, 
    ROUND(stat_count / SUM(stat_count) OVER() * 100, 2) AS percent_of_orders
FROM status_count
ORDER BY stat_count DESC;

/*
Result:
- 91.89% of orders were on time.
- 8.11% of orders were late.
*/


/* 
--------------------------------------------------------
Step 5: Late Rate by Product Category
--------------------------------------------------------
Purpose:
- Identify categories with the highest proportion of late deliveries.
*/
DROP VIEW IF EXISTS orders_ontime_status;
CREATE VIEW orders_ontime_status AS 
SELECT *,
    CASE
        WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 'late'
        ELSE 'on time'
    END AS on_time_status
FROM orders
WHERE order_estimated_delivery_date IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL;

WITH category_orders AS (
    SELECT 
        t.product_category_name_english,
        CASE WHEN o.on_time_status = 'on time' THEN 1 ELSE 0 END AS on_time_flag,
        CASE WHEN o.on_time_status = 'late' THEN 1 ELSE 0 END AS late_flag
    FROM order_items i
    JOIN orders_ontime_status o ON o.order_id = i.order_id
    JOIN products p ON p.product_id = i.product_id
    JOIN product_category_name_translation t ON t.product_category_name = p.product_category_name
)
SELECT 
    product_category_name_english,
    COUNT(*) AS total_orders,
    ROUND(SUM(late_flag)::numeric / COUNT(*) * 100, 2) AS late_rate
FROM category_orders
GROUP BY product_category_name_english
ORDER BY late_rate DESC;

/*
Findings:
- home_comfort_2: 16% late rate (30 orders in total).
- furniture_mattress_and_upholstery: 14% late rate (37 orders in total).
- audio: 13% late rate (362 orders in total).
- Several categories have 0% late rate, but with very low volume.
*/


/* 
--------------------------------------------------------
Step 6: Late Rate by Product Category (High Volume Only)
--------------------------------------------------------
Purpose:
- Remove statistical noise from small-volume categories.
*/
WITH category_orders AS (
    SELECT 
        t.product_category_name_english,
        CASE WHEN o.on_time_status = 'on time' THEN 1 ELSE 0 END AS on_time_flag,
        CASE WHEN o.on_time_status = 'late' THEN 1 ELSE 0 END AS late_flag
    FROM order_items i
    JOIN orders_ontime_status o ON o.order_id = i.order_id
    JOIN products p ON p.product_id = i.product_id
    JOIN product_category_name_translation t ON t.product_category_name = p.product_category_name
)
SELECT 
    product_category_name_english,
    COUNT(*) AS total_orders,
    ROUND(SUM(late_flag)::numeric / COUNT(*) * 100, 2) AS late_rate
FROM category_orders
GROUP BY product_category_name_english
HAVING COUNT(*) >= 500
ORDER BY late_rate DESC;

/*
Result:
- Electronics: highest late rate among high-volume categories (9.75% from 2,729 orders).
- Luggage_accessories: Lowest late rate among high-volume categories (4.39% from 1,077).
*/


/* 
--------------------------------------------------------
Step 7: Late Rate by Review Score
--------------------------------------------------------
Purpose:
- Measure relationship between delivery timeliness and customer satisfaction.
*/
WITH order_speed_reviews AS (
    SELECT 
        review_score,
        CASE WHEN on_time_status = 'on time' THEN 1 ELSE 0 END AS on_time_flag,
        CASE WHEN on_time_status = 'late' THEN 1 ELSE 0 END AS late_flag
    FROM order_reviews r
    JOIN orders_ontime_status o 
        ON r.order_id = o.order_id
)
SELECT 
    review_score, 
    ROUND(SUM(late_flag)::numeric / COUNT(*) * 100, 2) AS late_rate, 
    COUNT(*) AS order_count
FROM order_speed_reviews
GROUP BY review_score
ORDER BY late_rate DESC;

/*
Findings:
- Score 1: highest late rate (37%).
- Late rate decreases as review score increases.
- Score 5: lowest late rate (3%).
*/


/* 
--------------------------------------------------------
Step 8: Late Rate by Review Score Over Time
--------------------------------------------------------
Purpose:
- Identify trends over years for each review score.
*/

SELECT
    EXTRACT(YEAR FROM order_delivered_customer_date) AS order_year,
    review_score,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(
        SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*),
        2
    ) AS late_rate_percent
FROM orders o
JOIN order_reviews r 
    ON o.order_id = r.order_id
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY
    order_year,
    review_score
ORDER BY
    order_year,
    review_score;


/*
Observations:
- Review score 1: consistently highest late rate across all years.
- 2016: 5-star reviews had 0% late rate.
- 2017: 5-star late rate increased to 2%.
- 2018: 5-star late rate increased to 3.68%.
- Order volume increased over time, suggesting scaling challenges may slightly impact delivery timeliness.
*/
