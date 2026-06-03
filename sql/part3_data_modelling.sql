-- ============================================================
-- INT_SUBSCRIPTIONS (intermediate layer — all business logic)
-- ============================================================
-- One row per subscription lifecycle (subscription_sk):
-- currency conversion to USD, effective MRR after discount,
-- calculated fields (lengths, billing cycle, active flag) and a
-- data_quality_flag surfacing known-dirty rows downstream.
--
-- No renewal/current-period data exists, so days_until_renewal
-- is omitted rather than fabricated; billing_cycle_days is
-- provided as an honest substitute.
-- Date/MRR issues from Parts 1 & 2 (SUB-011 inverted dates,
-- SUB-045 suspect trial, ACC-1005 negative MRR, SUB-044 unknown
-- currency) are nulled and flagged rather than dropped.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS int_subscriptions;
CREATE TABLE int_subscriptions AS
SELECT
    s.subscription_sk,
    s.subscription_id,
    s.account_id,
    s.plan_type,
    s.status,

    -- Negative MRR treated as NULL (invalid)
    CASE WHEN s.mrr_amount < 0 THEN NULL ELSE s.mrr_amount END AS mrr_amount,

    s.currency,
    r.rate_to_usd,

    -- MRR in USD; NULL rate (unknown currency) -> NULL
    CASE
        WHEN s.mrr_amount < 0 THEN NULL
        ELSE ROUND(s.mrr_amount * r.rate_to_usd, 2)
    END AS mrr_usd,

    -- Effective MRR in USD after discount
    CASE
        WHEN s.mrr_amount < 0 THEN NULL
        ELSE ROUND(
            s.mrr_amount * r.rate_to_usd * (1 - COALESCE(s.discount_percentage, 0) / 100),
            2)
    END AS effective_mrr_usd,

    s.discount_percentage,
    s.billing_period,
    s.customer_segment,
    s.payment_method,
    s.start_date,
    s.end_date,
    s.trial_end_date,
    s.created_at,
    s.updated_at,

    CASE WHEN s.status = 'active' THEN TRUE ELSE FALSE END AS is_active,

    -- subscription_length_days (guards inverted dates — SUB-011)
    CASE
        WHEN s.end_date IS NOT NULL AND s.end_date < s.start_date THEN NULL
        WHEN s.end_date IS NOT NULL THEN s.end_date - s.start_date
        ELSE CURRENT_DATE - s.start_date
    END AS subscription_length_days,

    -- trial_length_days (guards SUB-045 suspect trial date)
    CASE
        WHEN s.trial_end_date IS NULL THEN NULL
        WHEN s.trial_end_date < s.start_date THEN NULL
        WHEN s.trial_end_date - s.start_date > 90 THEN NULL
        ELSE s.trial_end_date - s.start_date
    END AS trial_length_days,

    -- billing_cycle_days — length of one billing cycle
    CASE
        WHEN s.billing_period = 'monthly'   THEN 30
        WHEN s.billing_period = 'quarterly' THEN 90
        WHEN s.billing_period = 'annual'    THEN 365
        ELSE NULL
    END AS billing_cycle_days,

    -- data_quality_flag — surfaces known-dirty rows downstream
    CASE
        WHEN s.end_date IS NOT NULL AND s.end_date < s.start_date
            THEN 'inverted_dates'
        WHEN s.trial_end_date IS NOT NULL AND s.trial_end_date - s.start_date > 90
            THEN 'suspect_trial_date'
        WHEN s.mrr_amount = 0 AND s.status = 'active'
            THEN 'zero_mrr_active'
        WHEN r.rate_to_usd IS NULL
            THEN 'unknown_currency'
        WHEN s.mrr_amount IS NULL AND s.status = 'active'
            THEN 'null_mrr_active'
        WHEN s.discount_percentage = 100
            THEN 'full_discount_zero_revenue'
        WHEN s.mrr_amount > 50000
            THEN 'mrr_outlier_extreme'
        WHEN s.mrr_amount > 5000
            THEN 'mrr_outlier_high'
        WHEN s.plan_type = 'Starter'      AND s.mrr_amount > 100  THEN 'mrr_anomaly_vs_plan'
        WHEN s.plan_type = 'Basic'        AND s.mrr_amount > 50   THEN 'mrr_anomaly_vs_plan'
        WHEN s.plan_type = 'Professional' AND s.mrr_amount > 500  THEN 'mrr_anomaly_vs_plan'
        WHEN s.plan_type = 'Enterprise'   AND s.mrr_amount > 2000 THEN 'mrr_anomaly_vs_plan'
        ELSE NULL
    END AS data_quality_flag
FROM stg_subscriptions s
LEFT JOIN seed_exchange_rates r
    ON s.currency = r.currency;


-- ============================================================
-- INT_USAGE_PER_SUBSCRIPTION (intermediate layer)
-- ============================================================
-- Aggregates usage events to subscription grain via a
-- date-bounded join. FULL OUTER JOIN keeps orphaned accounts
-- (usage with no matching sub, e.g. ACC-8888) and flags them:
--   no_subscription_record           — account has no sub at all
--   usage_outside_subscription_window — sub exists, event falls
--     outside its window (ACC-1011 inverted dates, ACC-1017 lag)
-- Grain: one row per subscription_sk (or per orphaned account).
-- ------------------------------------------------------------
DROP TABLE IF EXISTS int_usage_per_subscription;
CREATE TABLE int_usage_per_subscription AS
SELECT
    COALESCE(i.subscription_sk, 'NO_SUB_' || u.account_id) AS subscription_sk,
    COALESCE(i.account_id, u.account_id)                   AS account_id,

    COUNT(u.event_id)              AS usage_event_count,
    SUM(u.api_calls)               AS total_api_calls,
    ROUND(AVG(u.api_calls), 2)               AS avg_api_calls,
    ROUND(AVG(u.active_users), 2)            AS avg_active_users,
    MAX(u.active_users)            AS max_active_users,
    SUM(u.projects_created)        AS total_projects_created,
    ROUND(AVG(u.integrations_used), 2)       AS avg_integrations_used,
    SUM(u.support_tickets)         AS total_support_tickets,
    ROUND(AVG(u.session_duration_mins), 2)   AS avg_session_duration_mins,
    ROUND(AVG(u.mobile_usage_mins), 2)        AS avg_mobile_usage_mins,
    SUM(u.feature_a_usage)         AS total_feature_a_usage,
    SUM(u.feature_b_usage)         AS total_feature_b_usage,
    SUM(u.feature_c_usage)         AS total_feature_c_usage,

    CASE
        WHEN i.subscription_sk IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM int_subscriptions i2
                WHERE i2.account_id = u.account_id
            )
            THEN 'no_subscription_record'
        WHEN i.subscription_sk IS NULL
            THEN 'usage_outside_subscription_window'
        ELSE NULL
    END AS orphan_flag
FROM int_subscriptions i
FULL OUTER JOIN stg_usage_events u
    ON u.account_id = i.account_id
    AND u.event_date >= i.start_date
    AND (i.end_date IS NULL OR u.event_date <= i.end_date)
GROUP BY
    COALESCE(i.subscription_sk, 'NO_SUB_' || u.account_id),
    COALESCE(i.account_id, u.account_id),
    CASE
        WHEN i.subscription_sk IS NULL
            AND NOT EXISTS (
                SELECT 1 FROM int_subscriptions i2
                WHERE i2.account_id = u.account_id
            )
            THEN 'no_subscription_record'
        WHEN i.subscription_sk IS NULL
            THEN 'usage_outside_subscription_window'
        ELSE NULL
    END;

-- ============================================================
-- FCT_SUBSCRIPTIONS (master fact table)
-- ============================================================
-- One row per subscription lifecycle, joining int_subscriptions
-- (attributes + business logic) to int_usage_per_subscription
-- (usage aggregated to grain, orphan logic handled upstream).
-- ACC-8888 appears with subscription columns NULL and
-- orphan_flag = 'no_subscription_record'; ACC-1011/ACC-1017
-- keep their attributes with 'usage_outside_subscription_window'.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fct_subscriptions;
CREATE TABLE fct_subscriptions AS
SELECT
    -- Keys from usage int (handles orphaned accounts)
    u.subscription_sk,
    u.account_id,

    -- Subscription attributes (NULL for ACC-8888)
    i.subscription_id,
    i.plan_type,
    i.status,
    i.mrr_amount,
    i.currency,
    i.rate_to_usd,
    i.mrr_usd,
    i.effective_mrr_usd,
    i.discount_percentage,
    i.billing_period,
    i.customer_segment,
    i.payment_method,
    i.start_date,
    i.end_date,
    i.trial_end_date,
    i.created_at,
    i.updated_at,
    i.is_active,
    i.subscription_length_days,
    i.trial_length_days,
    i.billing_cycle_days,

    -- Usage metrics
    u.usage_event_count, 0)      AS usage_event_count,
    u.total_api_calls,
    ROUND(u.avg_api_calls, 1)             AS avg_api_calls,
    ROUND(u.avg_active_users, 1)          AS avg_active_users,
    u.max_active_users,
    u.total_projects_created,
    ROUND(u.avg_integrations_used, 1)     AS avg_integrations_used,
    u.total_support_tickets,
    ROUND(u.avg_session_duration_mins, 1) AS avg_session_duration_mins,
    ROUND(u.avg_mobile_usage_mins, 1)     AS avg_mobile_usage_mins,
    u.total_feature_a_usage,
    u.total_feature_b_usage,
    u.total_feature_c_usage,

    CASE
        WHEN COALESCE(u.usage_event_count, 0) > 0 THEN TRUE
        ELSE FALSE
    END AS has_usage,

    -- orphan_flag takes priority over subscription-level DQ flags
    CASE
        WHEN u.orphan_flag IS NOT NULL THEN u.orphan_flag
        ELSE i.data_quality_flag
    END AS data_quality_flag
FROM int_usage_per_subscription u
LEFT JOIN int_subscriptions i
    ON u.subscription_sk = i.subscription_sk;

-- ============================================================
-- DIM_ACCOUNT (account dimension)
-- ============================================================
-- One row per account, current state only (latest subscription
-- by start_date). Derived flags (is_active etc.) are computed
-- at query time. Orphaned accounts are unioned in with NULL
-- attributes.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_account;
CREATE TABLE dim_account AS
WITH ranked_subscriptions AS (
    SELECT
        subscription_sk,
        subscription_id,
        account_id,
        plan_type,
        status,
        mrr_amount,
        currency,
        mrr_usd,
        effective_mrr_usd,
        customer_segment,
        payment_method,
        billing_period,
        start_date,
        end_date,
        trial_end_date,
        data_quality_flag,
        ROW_NUMBER() OVER (
            PARTITION BY account_id
            ORDER BY start_date DESC NULLS LAST
        ) AS rn
    FROM fct_subscriptions
    WHERE data_quality_flag IS NULL
        OR data_quality_flag NOT IN ('no_subscription_record')
)
SELECT
    account_id,
    subscription_id       AS current_subscription_id,
    plan_type             AS current_plan_type,
    status                AS current_status,
    mrr_amount            AS current_mrr_amount,
    currency              AS current_currency,
    mrr_usd               AS current_mrr_usd,
    effective_mrr_usd     AS current_effective_mrr_usd,
    customer_segment,
    payment_method,
    billing_period,
    start_date            AS current_subscription_start,
    end_date              AS current_subscription_end,
    trial_end_date,
    data_quality_flag
FROM ranked_subscriptions
WHERE rn = 1

UNION ALL

-- Orphaned accounts (ACC-8888)
SELECT
    account_id,
    NULL AS current_subscription_id,
    NULL AS current_plan_type,
    NULL AS current_status,
    NULL AS current_mrr_amount,
    NULL AS current_currency,
    NULL AS current_mrr_usd,
    NULL AS current_effective_mrr_usd,
    NULL AS customer_segment,
    NULL AS payment_method,
    NULL AS billing_period,
    NULL AS current_subscription_start,
    NULL AS current_subscription_end,
    NULL AS trial_end_date,
    data_quality_flag
FROM fct_subscriptions
WHERE data_quality_flag = 'no_subscription_record';



-- ============================================================
-- DIM_DATE (date dimension)
-- ============================================================
-- One row per day across the dataset range; supports the
-- monthly/quarterly time series in Part 4.
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
SELECT
    date_actual,
    EXTRACT(MONTH FROM date_actual)::INT   AS month_number,
    EXTRACT(QUARTER FROM date_actual)::INT AS quarter_number,
    EXTRACT(YEAR FROM date_actual)::INT    AS year_number,
    TO_CHAR(date_actual, 'YYYY-MM')        AS year_month
FROM GENERATE_SERIES(
    '2024-01-01'::DATE,
    '2024-12-31'::DATE,
    '1 day'::INTERVAL
) AS date_actual;


-- ============================================================
-- DIM_PLAN (plan dimension)
-- ============================================================
-- Derived from the plans present in the data. ELSE branches and
-- COALESCE handle the NULL plan_type rows (orphaned / unmatched
-- usage), preserving referential integrity with the fact table.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_plan;
CREATE TABLE dim_plan AS
SELECT DISTINCT
    COALESCE(plan_type, 'unknown') AS plan_type,
    CASE
        WHEN plan_type = 'Basic'        THEN 1
        WHEN plan_type = 'Starter'      THEN 2
        WHEN plan_type = 'Professional' THEN 3
        WHEN plan_type = 'Enterprise'   THEN 4
        ELSE 0
    END AS plan_tier,
    CASE
        WHEN plan_type = 'Basic'        THEN 29.00
        WHEN plan_type = 'Starter'      THEN 49.00
        WHEN plan_type = 'Professional' THEN 299.00
        WHEN plan_type = 'Enterprise'   THEN 999.00
        ELSE NULL
    END AS list_price_usd_monthly
FROM fct_subscriptions
ORDER BY plan_tier;
