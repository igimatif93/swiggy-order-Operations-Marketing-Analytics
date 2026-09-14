# Swiggy Business Analytics — Case Study

A walkthrough of 10 real business questions answered against Swiggy's
order data (customers, restaurants/products, geography, coupons, and
marketing campaigns), each framed the way it would come up on the job:
a business question, the analytical approach, the query, the finding,
and the recommendation it supports.

Underlying data: ~158K transactions across 6,000 customers, 116
restaurant/product listings, 20 pincodes, 6 coupons, and 5 campaigns.
Full runnable SQL is in `sql/03_solutions.sql`; table definitions in
`sql/01_schema.sql`.

---

## 1. Building a unified 360° order view

**Business question:** Reporting and downstream dashboards need every
order enriched with customer, location, product, coupon, and campaign
context in one place — not five tables joined ad hoc every time.

**Approach:** Five-way `LEFT JOIN` from the transaction fact table out
to all five dimension tables, keeping every fact row even where a
dimension is missing (e.g., no coupon or campaign was involved).

```sql
SELECT f.transaction_id, f.transaction_date, dc.customer_name, dc.gender,
       drp.restaurant_name, drp.cuisine_tag, dg.city, dg.state,
       dco.coupon_name, dca.campaign_name, f.net_amount, f.rating
FROM fact_transactions f
LEFT JOIN dim_customer dc ON f.customer_id = dc.customer_id
LEFT JOIN dim_geo dg ON f.geo_id = dg.geo_id
LEFT JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
LEFT JOIN dim_coupon dco ON f.coupon_id = dco.coupon_id
LEFT JOIN dim_campaign dca ON f.campaign_id = dca.campaign_id;
```

**Why it matters:** `LEFT JOIN` (not `INNER JOIN`) is the difference
between an analytics view that's accurate and one that silently drops
every order without a coupon or campaign — a common source of
under-reported revenue in real dashboards.

---

## 2. Validating data quality before trusting the numbers

**Business question:** Before publishing revenue figures, can we trust
that every transaction actually maps to a real customer, restaurant,
pincode, coupon, and campaign — or are there orphaned records that
would silently understate joined metrics?

**Approach:** Five `LEFT JOIN ... WHERE dim_id IS NULL` orphan checks,
unioned into a single audit result.

```sql
SELECT 'dim_customer' AS dim_name, COUNT(*) AS orphan_fact_rows
FROM fact_transactions f
LEFT JOIN dim_customer d ON f.customer_id = d.customer_id
WHERE d.customer_id IS NULL
UNION ALL
-- ...repeated for dim_geo, dim_restaurant_product,
--    dim_coupon (where coupon_used_flag), dim_campaign (where campaign_exposed_flag)
```

**Finding:** All five checks returned zero orphan rows — the dataset
is referentially clean, so downstream joins can be trusted without
additional defensive filtering.

**Why it matters:** This is the check I'd run before every reporting
cycle in a real pipeline — it catches broken foreign keys (deleted
restaurants, bad coupon codes) before they quietly skew a revenue
report.

---

## 3. Which cuisines to prioritize by city, month over month

**Business question:** Which cuisines should marketing prioritize for
city-specific promotions each month, based on where the revenue is
actually concentrated?

**Approach:** A CTE aggregates net revenue by city, month, and cuisine;
`ROW_NUMBER() OVER (PARTITION BY city, year_month ORDER BY net_revenue DESC)`
ranks cuisines within each city-month so only the top 5 surface.

```sql
WITH base AS (
    SELECT f.city, date_format(f.transaction_date, 'yyyy-MM') AS year_month,
           drp.cuisine_tag, SUM(f.net_amount) AS net_revenue, COUNT(*) AS orders
    FROM fact_transactions f
    JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
    GROUP BY f.city, date_format(f.transaction_date, 'yyyy-MM'), drp.cuisine_tag
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY city, year_month ORDER BY net_revenue DESC) AS rn
    FROM base
)
SELECT city, year_month, cuisine_tag, ROUND(net_revenue, 2) AS net_revenue, orders
FROM ranked WHERE rn <= 5;
```

**Finding:** Andhra cuisine led Bangalore's December revenue at
₹33,408 across 119 orders — a candidate for a featured promotion slot
the following month.

**Business impact:** Feeds a recurring "top cuisines" report that
marketing can use to time city-specific promotions instead of running
the same national campaign everywhere.

---

## 4. Restaurant leaderboard and delivery trade-offs

**Business question:** Which restaurants are driving the most revenue
per city over the last year, and are any of the top earners also
dragging down delivery experience?

**Approach:** Join to `dim_restaurant_product`, filter to a rolling
365-day window, and aggregate revenue alongside average delivery time
so both metrics sit side by side.

```sql
SELECT f.city, drp.restaurant_name, COUNT(*) AS orders,
       ROUND(SUM(f.net_amount), 2) AS net_revenue,
       ROUND(AVG(f.delivery_minutes), 2) AS avg_delivery_minutes
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
WHERE f.transaction_date >= date_sub(current_date(), 365)
GROUP BY f.city, drp.restaurant_name
ORDER BY f.city, net_revenue DESC;
```

**Business impact:** This is the query behind a monthly business
review — it lets ops flag high-revenue restaurants with slow delivery
times as priority candidates for logistics support, rather than
treating revenue and delivery as separate reports.

---

## 5. Which coupons are actually worth running

**Business question:** For each coupon in market, how many orders is
it driving, how much discount is it burning, and is it net-positive
for order value?

**Approach:** Filter to orders where a coupon was actually applied,
then join to coupon metadata and aggregate burn and average order
value in the same pass.

```sql
SELECT dco.coupon_id, dco.coupon_name, dco.discount_type, dco.discount_value,
       COUNT(*) AS coupon_orders,
       ROUND(SUM(f.coupon_discount_amount), 2) AS total_coupon_burn,
       ROUND(AVG(f.gross_amount), 2) AS avg_gross_with_coupon,
       ROUND(AVG(f.net_amount), 2) AS avg_net_with_coupon
FROM fact_transactions f
JOIN dim_coupon dco ON f.coupon_id = dco.coupon_id
WHERE f.coupon_used_flag
GROUP BY dco.coupon_id, dco.coupon_name, dco.discount_type, dco.discount_value, dco.max_discount, dco.min_order
ORDER BY total_coupon_burn DESC;
```

**Business impact:** Ranks coupons by burn vs. the order value they
generate — the kind of table a growth or finance team would use to
decide which coupons to renew, cap, or retire next quarter.

---

## 6. Marketing campaign ROI

**Business question:** Of the campaigns customers were exposed to,
which ones actually convert (click-through) and which generate the
most revenue per rupee of coupon discount spent?

**Approach:** A CTE aggregates exposure, clicks, revenue, and coupon
burn per campaign; the outer query joins campaign metadata and
computes CTR and a revenue-per-burn efficiency ratio, guarding both
divisions with `NULLIF`.

```sql
WITH exposed AS (
    SELECT campaign_id, COUNT(*) AS exposed_orders,
           SUM(CASE WHEN ad_clicked_flag THEN 1 ELSE 0 END) AS clicked_orders,
           SUM(net_amount) AS net_revenue_exposed,
           SUM(coupon_discount_amount) AS coupon_burn_exposed
    FROM fact_transactions
    WHERE campaign_exposed_flag
    GROUP BY campaign_id
)
SELECT dca.campaign_name, dca.channel, dca.objective,
       e.exposed_orders, e.clicked_orders,
       ROUND(100.0 * e.clicked_orders / NULLIF(e.exposed_orders, 0), 2) AS ctr_pct,
       ROUND(e.net_revenue_exposed / NULLIF(e.coupon_burn_exposed, 0), 2) AS revenue_per_coupon_burn
FROM exposed e
LEFT JOIN dim_campaign dca ON e.campaign_id = dca.campaign_id
ORDER BY ctr_pct DESC;
```

**Finding:** The "Weekend Special" email campaign had a 22.26%
click-through rate and the best revenue-per-coupon-burn ratio of
₹23.74 — the most efficient campaign in the set.

**Business impact:** Gives marketing a defensible, ROI-ranked view of
where to reallocate campaign budget next cycle.

---

## 7. Where delivery performance and revenue diverge geographically

**Business question:** Which pincodes are our highest-value delivery
zones, and where is delivery reliability weakest — so ops knows where
to invest first?

**Approach:** Join to `dim_geo` and aggregate revenue, average
delivery time, and delivery success rate per city/state/pincode.

```sql
SELECT f.city AS order_city, dg.state, dg.pincode, COUNT(*) AS orders,
       ROUND(SUM(f.net_amount), 2) AS net_revenue,
       ROUND(AVG(f.delivery_minutes), 2) AS avg_delivery_minutes,
       ROUND(100.0 * AVG(CASE WHEN f.delivery_success_flag THEN 1 ELSE 0 END), 2) AS delivery_success_pct
FROM fact_transactions f
JOIN dim_geo dg ON f.geo_id = dg.geo_id
GROUP BY f.city, dg.state, dg.pincode
ORDER BY net_revenue DESC;
```

**Finding:** Pincode 560103 (Bangalore, Karnataka) is the single
highest-value delivery zone — 7,960 orders and ₹18.3L in revenue —
making it a priority area for maintaining delivery SLAs.

---

## 8. Which customer segments to target for retention or upsell

**Business question:** Which combinations of city, gender, and age
band generate the most revenue and highest average order value — the
segments worth a targeted retention or loyalty push?

**Approach:** A CTE buckets customers into age bands with `CASE WHEN`,
then the outer query aggregates orders, unique customers, revenue,
average order value, and coupon usage per segment.

```sql
WITH cust_enriched AS (
    SELECT f.city, dc.gender,
           CASE WHEN dc.age < 18 THEN '0-17'
                WHEN dc.age BETWEEN 18 AND 24 THEN '18-24'
                WHEN dc.age BETWEEN 25 AND 34 THEN '25-34'
                WHEN dc.age BETWEEN 35 AND 44 THEN '35-44'
                WHEN dc.age BETWEEN 45 AND 54 THEN '45-54'
                ELSE '55+' END AS age_band,
           f.customer_id, f.net_amount, f.coupon_used_flag
    FROM fact_transactions f
    JOIN dim_customer dc ON f.customer_id = dc.customer_id
)
SELECT city, gender, age_band, COUNT(*) AS orders,
       COUNT(DISTINCT customer_id) AS customers,
       ROUND(SUM(net_amount), 2) AS net_revenue,
       ROUND(AVG(net_amount), 2) AS aov,
       ROUND(100.0 * AVG(CASE WHEN coupon_used_flag THEN 1 ELSE 0 END), 2) AS coupon_usage_pct
FROM cust_enriched
GROUP BY city, gender, age_band
ORDER BY city, net_revenue DESC;
```

**Finding:** Bangalore males aged 25-34 are the highest-value segment
— ₹39.2L in net revenue at a ₹225 average order value.

**Business impact:** This segmentation is what a CRM or lifecycle
marketing team would use to prioritize which audience to build a
loyalty campaign around first.

---

## 9. Best-selling products by city for inventory and negotiation

**Business question:** Which products actually drive the most revenue
in each city — the ones worth prioritizing in restaurant-partner
negotiations or featured placements?

**Approach:** Join to product metadata and aggregate both units sold
and order-line count, being careful to distinguish the two.

```sql
SELECT f.city, drp.product_name,
       SUM(f.quantity) AS total_qty,
       ROUND(SUM(f.net_amount), 2) AS net_revenue,
       COUNT(*) AS order_lines
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
GROUP BY f.city, drp.product_name
ORDER BY net_revenue DESC
LIMIT 50;
```

**Why it matters:** `SUM(quantity)` and `COUNT(*)` answer different
questions — units sold vs. number of orders containing the product —
and conflating them is a common analyst mistake when a single order
line can carry a quantity greater than 1.

---

## 10. Auditing whether customers are being charged correctly

**Business question:** Is the price customers are actually charged
consistent with the restaurant's listed catalog price, or is there
billing leakage (undercharging, surcharges, or pricing bugs) that
finance should know about?

**Approach:** Compare the average realized price per unit
(`gross_amount / quantity`) against the catalog `list_price` per
city/product, guarding against division by zero.

```sql
SELECT f.city, drp.product_name,
       ROUND(AVG(drp.list_price), 2) AS avg_list_price,
       ROUND(AVG(f.gross_amount / NULLIF(f.quantity, 0)), 2) AS avg_realized_gross_per_unit,
       ROUND(AVG((f.gross_amount / NULLIF(f.quantity, 0)) - drp.list_price), 2) AS avg_realized_minus_list,
       COUNT(*) AS lines
FROM fact_transactions f
JOIN dim_restaurant_product drp ON f.restaurant_product_id = drp.restaurant_product_id
GROUP BY f.city, drp.product_name
ORDER BY lines DESC, avg_realized_minus_list DESC;
```

**Finding:** `avg_realized_minus_list` came out to 0 across every
product — confirms clean, consistent pricing with no billing leakage
in this dataset. In a live system, a non-zero result here is exactly
how you'd catch a pricing bug or an undisclosed surcharge before
finance does.

---

## Summary of techniques demonstrated

Multi-table `LEFT JOIN`s across a 5-dimension star schema · data
quality / referential integrity auditing · CTEs · `ROW_NUMBER()`
window functions for top-N-per-group · date filtering on rolling
windows · `CASE WHEN` bucketing · `NULLIF` for safe division ·
distinguishing `SUM` vs `COUNT` semantics · price/billing reconciliation.
