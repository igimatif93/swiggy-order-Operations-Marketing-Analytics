-- =====================================================================
-- Swiggy SQL Analytics — Section C: Advanced Practice Questions
-- 10 questions covering multi-table JOINs, window functions, CTEs,
-- and data-quality checks. Solutions are in 03_solutions.sql.
-- =====================================================================

-- ---------------------------------------------------------------------
-- C1 — Enriched Order View (Multi-table JOIN)
-- Create a fully enriched order view by joining fact_transactions with
-- all 5 dimension tables (dim_customer, dim_geo, dim_restaurant_product,
-- dim_coupon, dim_campaign). Include all transaction details + all
-- dimension fields. LIMIT 50.
-- Hint: Use LEFT JOIN for all 5 dimensions with aliases f, dc, dg, drp, dco, dca.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C2 — Data Quality Orphan Check
-- Identify orphan fact records — transactions with no matching row in a
-- dimension table. Check dim_customer, dim_geo, dim_restaurant_product
-- always; check dim_coupon only where coupon_used_flag = true; check
-- dim_campaign only where campaign_exposed_flag = true.
-- Output: dim_name, orphan_fact_rows
-- Hint: Five separate LEFT JOIN + WHERE dim_id IS NULL checks, combined with UNION ALL.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C3 — Top 5 Cuisines per City per Month (CTE + Window Function)
-- Find the top 5 cuisines by net revenue for each city + month.
-- Output: city, year_month, cuisine_tag, net_revenue, orders
-- Hint: CTE to aggregate revenue by cuisine, then ROW_NUMBER() OVER
-- (PARTITION BY city, year_month ORDER BY net_revenue DESC).
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C4 — Restaurant Leaderboard, Last 365 Days (JOIN + Date Filter)
-- Top performers by net revenue, split by city, for the last 365 days.
-- Output: city, restaurant_name, orders, net_revenue, avg_delivery_minutes
-- Order by city, then net revenue descending.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C5 — Coupon Performance Analysis (JOIN + Aggregation)
-- For each coupon: number of orders, total coupon burn, avg gross/net
-- amount when the coupon was used.
-- Hint: Filter WHERE coupon_used_flag before joining.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C6 — Campaign Performance Enriched (CTE + LEFT JOIN)
-- Exposed orders, clicked orders, CTR %, net revenue from exposed
-- orders, coupon burn from exposed orders, revenue-per-coupon-burn.
-- Hint: CTE to aggregate campaign metrics, then LEFT JOIN dim_campaign
-- for metadata. Use NULLIF on both denominators.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C7 — Geo Drill-Down Analysis (JOIN + Geo)
-- For each city + state + pincode: orders, net revenue, avg delivery
-- time, delivery success rate (%).
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C8 — Customer Demographic Segmentation (CTE + CASE WHEN)
-- Segment by gender and age band (0-17, 18-24, 25-34, 35-44, 45-54, 55+).
-- For each city + gender + age_band: orders, unique customers, net
-- revenue, AOV, coupon usage %.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C9 — Product Basket Analysis (JOIN + Basket)
-- Top products by net revenue, with quantity sold and order count,
-- split by city.
-- Output: city, product_name, total_qty, net_revenue, order_lines
-- LIMIT 50.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- C10 — Price Realization Check (Price Audit)
-- Audit charged prices vs. list price from dim_restaurant_product, per
-- city + product: avg_list_price, avg_realized_gross_per_unit,
-- avg_realized_minus_list (should be 0), lines.
-- Hint: NULLIF(f.quantity, 0) in the denominator to avoid divide-by-zero.
-- ---------------------------------------------------------------------
