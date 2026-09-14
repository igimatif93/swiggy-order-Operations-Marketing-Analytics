-- =====================================================================
-- Swiggy SQL Analytics — Section C: Solutions
-- Originally written/run in Databricks SQL against workspace.swiggy.*;
-- table names below are simplified to match sql/01_schema.sql. Adjust
-- date functions (date_sub, date_format) if running on Postgres/MySQL.
-- =====================================================================

-- ---------------------------------------------------------------------
-- C1 — Enriched Order View
-- Key: Always use LEFT JOIN (not INNER JOIN) so no fact rows are
-- dropped when a dimension value is NULL.
-- ---------------------------------------------------------------------
SELECT
    f.transaction_id, f.transaction_date, f.transaction_time,
    f.city AS order_city, f.device_type,
    f.customer_id, dc.customer_name, dc.gender, dc.age,
    dc.signup_date, dc.membership_tier AS customer_membership_tier,
    f.restaurant_product_id, drp.restaurant_name,
    drp.product_name, drp.cuisine_tag, drp.list_price,
    f.geo_id, dg.city AS geo_city, dg.state, dg.pincode,
    f.coupon_used_flag, f.coupon_id, dco.coupon_name,
    dco.discount_type, dco.discount_value,
    dco.max_discount, dco.min_order,
    f.campaign_exposed_flag, f.campaign_id,
    dca.campaign_name, dca.channel AS campaign_channel,
    dca.objective AS campaign_objective,
    f.gross_amount, f.coupon_discount_amount,
    f.membership_benefit_amount, f.total_discount_amount,
    f.net_amount, f.delivery_success_flag,
    f.delivery_minutes, f.rating
FROM fact_transactions f
LEFT JOIN dim_customer dc ON f.customer_id = dc.customer_id
LEFT JOIN dim_geo dg ON f.geo_id = dg.geo_id
LEFT JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
LEFT JOIN dim_coupon dco ON f.coupon_id = dco.coupon_id
LEFT JOIN dim_campaign dca ON f.campaign_id = dca.campaign_id
LIMIT 50;


-- ---------------------------------------------------------------------
-- C2 — Data Quality Orphan Check
-- Expected result: all 5 rows return 0 orphan rows — clean, well-formed
-- dataset.
-- ---------------------------------------------------------------------
SELECT 'dim_customer' AS dim_name, COUNT(*) AS orphan_fact_rows
FROM fact_transactions f
LEFT JOIN dim_customer d ON f.customer_id = d.customer_id
WHERE d.customer_id IS NULL
UNION ALL
SELECT 'dim_geo', COUNT(*)
FROM fact_transactions f
LEFT JOIN dim_geo d ON f.geo_id = d.geo_id
WHERE d.geo_id IS NULL
UNION ALL
SELECT 'dim_restaurant_product', COUNT(*)
FROM fact_transactions f
LEFT JOIN dim_restaurant_product d ON f.restaurant_product_id = d.restaurant_product_id
WHERE d.restaurant_product_id IS NULL
UNION ALL
SELECT 'dim_coupon (coupon_used_flag=true)', COUNT(*)
FROM fact_transactions f
LEFT JOIN dim_coupon d ON f.coupon_id = d.coupon_id
WHERE f.coupon_used_flag AND d.coupon_id IS NULL
UNION ALL
SELECT 'dim_campaign (campaign_exposed_flag=true)', COUNT(*)
FROM fact_transactions f
LEFT JOIN dim_campaign d ON f.campaign_id = d.campaign_id
WHERE f.campaign_exposed_flag AND d.campaign_id IS NULL;


-- ---------------------------------------------------------------------
-- C3 — Top 5 Cuisines per City per Month
-- Sample: Bangalore Dec-2024 top cuisine = Andhra (₹33,408 | 119 orders)
-- ---------------------------------------------------------------------
WITH base AS (
    SELECT
        f.city,
        date_format(f.transaction_date, 'yyyy-MM') AS year_month,
        drp.cuisine_tag,
        SUM(f.net_amount) AS net_revenue,
        COUNT(*) AS orders
    FROM fact_transactions f
    JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
    GROUP BY f.city, date_format(f.transaction_date, 'yyyy-MM'), drp.cuisine_tag
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY city, year_month
            ORDER BY net_revenue DESC
        ) AS rn
    FROM base
)
SELECT city, year_month, cuisine_tag,
       ROUND(net_revenue, 2) AS net_revenue, orders
FROM ranked
WHERE rn <= 5
ORDER BY year_month, city, rn;


-- ---------------------------------------------------------------------
-- C4 — Restaurant Leaderboard (Last 365 Days)
-- Note: useful for monthly business reviews — rank restaurants by
-- revenue and cross-reference with delivery time to spot high-revenue
-- but slow-delivery outliers.
-- ---------------------------------------------------------------------
SELECT
    f.city,
    drp.restaurant_name,
    COUNT(*) AS orders,
    ROUND(SUM(f.net_amount), 2) AS net_revenue,
    ROUND(AVG(f.delivery_minutes), 2) AS avg_delivery_minutes
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
WHERE f.transaction_date >= date_sub(current_date(), 365)
GROUP BY f.city, drp.restaurant_name
ORDER BY f.city, net_revenue DESC;


-- ---------------------------------------------------------------------
-- C5 — Coupon Performance Analysis
-- Note: always GROUP BY every non-aggregated selected column (here, all
-- the dim_coupon fields pulled through directly).
-- ---------------------------------------------------------------------
SELECT
    dco.coupon_id, dco.coupon_name,
    dco.discount_type, dco.discount_value,
    dco.max_discount, dco.min_order,
    COUNT(*) AS coupon_orders,
    ROUND(SUM(f.coupon_discount_amount), 2) AS total_coupon_burn,
    ROUND(AVG(f.gross_amount), 2) AS avg_gross_with_coupon,
    ROUND(AVG(f.net_amount), 2) AS avg_net_with_coupon
FROM fact_transactions f
JOIN dim_coupon dco ON f.coupon_id = dco.coupon_id
WHERE f.coupon_used_flag
GROUP BY dco.coupon_id, dco.coupon_name, dco.discount_type,
         dco.discount_value, dco.max_discount, dco.min_order
ORDER BY total_coupon_burn DESC;


-- ---------------------------------------------------------------------
-- C6 — Campaign Performance Enriched
-- Top result: EMAIL_303 | Email: Weekend Special | CTR 22.26% |
-- revenue/burn ₹23.74 — best efficiency.
-- ---------------------------------------------------------------------
WITH exposed AS (
    SELECT
        campaign_id,
        COUNT(*) AS exposed_orders,
        SUM(CASE WHEN ad_clicked_flag THEN 1 ELSE 0 END) AS clicked_orders,
        SUM(net_amount) AS net_revenue_exposed,
        SUM(coupon_discount_amount) AS coupon_burn_exposed
    FROM fact_transactions
    WHERE campaign_exposed_flag
    GROUP BY campaign_id
)
SELECT
    dca.campaign_id, dca.campaign_name,
    dca.channel, dca.objective,
    e.exposed_orders, e.clicked_orders,
    ROUND(100.0 * e.clicked_orders / NULLIF(e.exposed_orders, 0), 2) AS ctr_pct,
    ROUND(e.net_revenue_exposed, 2) AS net_revenue_exposed,
    ROUND(e.coupon_burn_exposed, 2) AS coupon_burn_exposed,
    ROUND(e.net_revenue_exposed / NULLIF(e.coupon_burn_exposed, 0), 2) AS revenue_per_coupon_burn
FROM exposed e
LEFT JOIN dim_campaign dca ON e.campaign_id = dca.campaign_id
ORDER BY ctr_pct DESC;


-- ---------------------------------------------------------------------
-- C7 — Geo Drill-Down Analysis
-- Top pincode: 560103 (Bangalore, Karnataka) | 7,960 orders |
-- ₹1,830,318 revenue — a premium delivery zone.
-- ---------------------------------------------------------------------
SELECT
    f.city AS order_city,
    dg.state,
    dg.pincode,
    COUNT(*) AS orders,
    ROUND(SUM(f.net_amount), 2) AS net_revenue,
    ROUND(AVG(f.delivery_minutes), 2) AS avg_delivery_minutes,
    ROUND(100.0 * AVG(CASE WHEN f.delivery_success_flag THEN 1 ELSE 0 END), 2) AS delivery_success_pct
FROM fact_transactions f
JOIN dim_geo dg ON f.geo_id = dg.geo_id
GROUP BY f.city, dg.state, dg.pincode
ORDER BY net_revenue DESC;


-- ---------------------------------------------------------------------
-- C8 — Customer Demographic Segmentation
-- Top segment: Bangalore | Male | 25-34 | ₹3,925,695 net revenue |
-- AOV ₹225.45
-- ---------------------------------------------------------------------
WITH cust_enriched AS (
    SELECT
        f.city,
        dc.gender,
        CASE
            WHEN dc.age < 18 THEN '0-17'
            WHEN dc.age BETWEEN 18 AND 24 THEN '18-24'
            WHEN dc.age BETWEEN 25 AND 34 THEN '25-34'
            WHEN dc.age BETWEEN 35 AND 44 THEN '35-44'
            WHEN dc.age BETWEEN 45 AND 54 THEN '45-54'
            ELSE '55+'
        END AS age_band,
        f.customer_id, f.net_amount, f.coupon_used_flag
    FROM fact_transactions f
    JOIN dim_customer dc ON f.customer_id = dc.customer_id
)
SELECT
    city, gender, age_band,
    COUNT(*) AS orders,
    COUNT(DISTINCT customer_id) AS customers,
    ROUND(SUM(net_amount), 2) AS net_revenue,
    ROUND(AVG(net_amount), 2) AS aov,
    ROUND(100.0 * AVG(CASE WHEN coupon_used_flag THEN 1 ELSE 0 END), 2) AS coupon_usage_pct
FROM cust_enriched
GROUP BY city, gender, age_band
ORDER BY city, net_revenue DESC;


-- ---------------------------------------------------------------------
-- C9 — Product Basket Analysis
-- Note: SUM(quantity) != COUNT(*). Order lines count rows (one per
-- order line); total_qty sums units per line (a line can have qty = 3).
-- ---------------------------------------------------------------------
SELECT
    f.city,
    drp.product_name,
    SUM(f.quantity) AS total_qty,
    ROUND(SUM(f.net_amount), 2) AS net_revenue,
    COUNT(*) AS order_lines
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
GROUP BY f.city, drp.product_name
ORDER BY net_revenue DESC
LIMIT 50;


-- ---------------------------------------------------------------------
-- C10 — Price Realization Check
-- Expected: avg_realized_minus_list = 0 for all products — confirms no
-- pricing discrepancies. In real data, non-zero values reveal pricing
-- bugs or surcharges.
-- ---------------------------------------------------------------------
SELECT
    f.city,
    drp.product_name,
    ROUND(AVG(drp.list_price), 2) AS avg_list_price,
    ROUND(AVG(f.gross_amount / NULLIF(f.quantity, 0)), 2) AS avg_realized_gross_per_unit,
    ROUND(AVG((f.gross_amount / NULLIF(f.quantity, 0)) - drp.list_price), 2) AS avg_realized_minus_list,
    COUNT(*) AS lines
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
GROUP BY f.city, drp.product_name
ORDER BY lines DESC, avg_realized_minus_list DESC;
