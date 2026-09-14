-- =====================================================================
-- Swiggy SQL Analytics — Schema
-- Star schema: 1 fact table (fact_transactions) + 5 dimension tables
-- Compatible with PostgreSQL / MySQL / Databricks SQL (minor type tweaks
-- may be needed depending on engine, e.g. BOOLEAN vs TINYINT).
-- =====================================================================

CREATE TABLE dim_customer (
    customer_id      VARCHAR(20) PRIMARY KEY,
    customer_name    VARCHAR(100),
    phone            VARCHAR(20),
    email            VARCHAR(100),
    gender           VARCHAR(10),
    age              INT,
    home_geo_id      VARCHAR(20),
    home_city        VARCHAR(50),
    signup_date      DATE,
    membership_tier  VARCHAR(20)
);

CREATE TABLE dim_geo (
    geo_id   VARCHAR(20) PRIMARY KEY,
    city     VARCHAR(50),
    state    VARCHAR(50),
    pincode  VARCHAR(10)
);

CREATE TABLE dim_restaurant_product (
    restaurant_product_id VARCHAR(20) PRIMARY KEY,
    restaurant_name        VARCHAR(100),
    product_name           VARCHAR(100),
    city                    VARCHAR(50),
    restaurant_geo_id       VARCHAR(20),
    cuisine_tag             VARCHAR(50),
    list_price              DECIMAL(10, 2)
);

CREATE TABLE dim_coupon (
    coupon_id       VARCHAR(20) PRIMARY KEY,
    coupon_name     VARCHAR(100),
    discount_type   VARCHAR(20),
    discount_value  DECIMAL(10, 2),
    max_discount    DECIMAL(10, 2),
    min_order       DECIMAL(10, 2)
);

CREATE TABLE dim_campaign (
    campaign_id    VARCHAR(20) PRIMARY KEY,
    campaign_name  VARCHAR(100),
    channel        VARCHAR(30),
    objective      VARCHAR(50)
);

CREATE TABLE fact_transactions (
    transaction_id            VARCHAR(20) PRIMARY KEY,
    customer_id               VARCHAR(20) REFERENCES dim_customer(customer_id),
    transaction_date          DATE,
    transaction_time          TIME,
    restaurant_product_id     VARCHAR(20) REFERENCES dim_restaurant_product(restaurant_product_id),
    quantity                  INT,
    gross_amount               DECIMAL(10, 2),
    coupon_used_flag           BOOLEAN,
    coupon_id                  VARCHAR(20) REFERENCES dim_coupon(coupon_id),
    coupon_discount_amount     DECIMAL(10, 2),
    membership_tier            VARCHAR(20),
    membership_benefit_amount  DECIMAL(10, 2),
    total_discount_amount      DECIMAL(10, 2),
    net_amount                 DECIMAL(10, 2),
    geo_id                     VARCHAR(20) REFERENCES dim_geo(geo_id),
    city                       VARCHAR(50),
    device_type                VARCHAR(20),
    campaign_exposed_flag      BOOLEAN,
    campaign_id                VARCHAR(20) REFERENCES dim_campaign(campaign_id),
    ad_clicked_flag             BOOLEAN,
    time_to_order_seconds       INT,
    surge_flag                  BOOLEAN,
    raining_flag                 BOOLEAN,
    search_delivery_flag         BOOLEAN,
    delivery_success_flag        BOOLEAN,
    delivery_minutes              INT,
    feedback_left_flag             BOOLEAN,
    rating                          DECIMAL(2, 1),
    feedback_text                   TEXT
);

-- Helpful indexes for the join-heavy analytical queries in 02/03
CREATE INDEX idx_fact_customer   ON fact_transactions(customer_id);
CREATE INDEX idx_fact_geo        ON fact_transactions(geo_id);
CREATE INDEX idx_fact_product    ON fact_transactions(restaurant_product_id);
CREATE INDEX idx_fact_coupon     ON fact_transactions(coupon_id);
CREATE INDEX idx_fact_campaign   ON fact_transactions(campaign_id);
CREATE INDEX idx_fact_date       ON fact_transactions(transaction_date);
