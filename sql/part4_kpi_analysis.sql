-- ============================================================
-- PART 4.1: REVENUE METRICS
-- ============================================================
-- All revenue calculations use effective_mrr_usd (post-discount,
-- converted to USD) from fct_subscriptions.
-- Excludes rows with data quality flags (inverted dates,
-- negative MRR, unknown currency) to ensure accurate totals.
-- ACC-1029 (99,900 MRR) is a known outlier — included but
-- worth noting as it significantly skews totals.
-- ============================================================

-- 4.1a. Monthly MRR (clean vs all-rows)
SELECT
    TO_CHAR(d.date_actual, 'YYYY-MM')                          AS year_month,
    COUNT(DISTINCT f.account_id)                               AS active_accounts,
    ROUND(SUM(f.effective_mrr_usd) FILTER (
        WHERE f.data_quality_flag IS NULL
           OR f.data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high', 'mrr_anomaly_vs_plan')
    ), 2)                                                      AS mrr_usd_clean,
    ROUND(SUM(f.effective_mrr_usd), 2)                        AS mrr_usd_all_rows
FROM dim_date d
JOIN fct_subscriptions f
    ON d.date_actual = DATE_TRUNC('month', d.date_actual)
    AND d.date_actual >= f.start_date
    AND (f.end_date IS NULL OR d.date_actual <= f.end_date)
    AND f.status = 'active'
WHERE d.date_actual = DATE_TRUNC('month', d.date_actual)
GROUP BY TO_CHAR(d.date_actual, 'YYYY-MM')
ORDER BY year_month;



-- 4.1b. MRR growth rate (month-over-month on clean MRR)
WITH monthly_mrr AS (
        SELECT
            TO_CHAR(d.date_actual, 'YYYY-MM')                          AS year_month,
            ROUND(SUM(f.effective_mrr_usd) FILTER (
                WHERE f.data_quality_flag IS NULL
                OR f.data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high', 'mrr_anomaly_vs_plan')
            ), 2)                                                      AS mrr_usd_clean,
            ROUND(SUM(f.effective_mrr_usd), 2)                        AS mrr_usd_all_rows
        FROM dim_date d
        JOIN fct_subscriptions f
            ON d.date_actual = DATE_TRUNC('month', d.date_actual)
            AND d.date_actual >= f.start_date
            AND (f.end_date IS NULL OR d.date_actual <= f.end_date)
            AND f.status = 'active'
        WHERE d.date_actual = DATE_TRUNC('month', d.date_actual)
        GROUP BY TO_CHAR(d.date_actual, 'YYYY-MM')
    )
    SELECT
        year_month,
        mrr_usd_clean,
        LAG(mrr_usd_clean) OVER (ORDER BY year_month) AS prev_month_mrr,
        ROUND(
            (mrr_usd_clean - LAG(mrr_usd_clean) OVER (ORDER BY year_month))
            / NULLIF(LAG(mrr_usd_clean) OVER (ORDER BY year_month), 0) * 100
        , 2) AS mrr_growth_pct
    FROM monthly_mrr
    ORDER BY year_month;

-- 4.1c. Average Revenue Per Account (ARPA)
SELECT
    COUNT(DISTINCT account_id)                                              AS active_accounts,
    ROUND(SUM(effective_mrr_usd), 2)                                        AS total_mrr_usd,
    ROUND(SUM(effective_mrr_usd) / NULLIF(COUNT(DISTINCT account_id), 0), 2) AS arpa_usd
FROM fct_subscriptions
WHERE status = 'active'
    AND (data_quality_flag IS NULL
         OR data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high', 'mrr_anomaly_vs_plan'));

-- 4.1d. Revenue by plan type and segment
-- Filters match 4.1a–c for consistent reconciliation.
SELECT
    f.plan_type,
    f.customer_segment,
    COUNT(DISTINCT f.account_id)        AS account_count,
    ROUND(SUM(f.effective_mrr_usd), 2)  AS total_effective_mrr_usd,
    ROUND(AVG(f.effective_mrr_usd), 2)  AS avg_effective_mrr_usd
FROM fct_subscriptions f
WHERE f.status = 'active'
    AND (f.data_quality_flag IS NULL
         OR f.data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high', 'mrr_anomaly_vs_plan'))
GROUP BY f.plan_type, f.customer_segment
ORDER BY total_effective_mrr_usd DESC;


-- ============================================================
-- PART 4.2: CHURN METRICS
-- ============================================================
-- Churn attributed to subscription end_date; base = active at month-start.
-- Filters: date-critical queries exclude inverted_dates; MRR queries exclude MRR flags too.
-- ============================================================

-- 4.2a. Monthly logo (customer) churn rate
WITH months AS (
    SELECT date_actual AS month_start
    FROM dim_date
    WHERE date_actual = DATE_TRUNC('month', date_actual)
)
SELECT
    TO_CHAR(m.month_start, 'YYYY-MM') AS year_month,
    COUNT(DISTINCT f.account_id) FILTER (
        WHERE f.start_date < m.month_start
          AND (f.end_date IS NULL OR f.end_date >= m.month_start)
    ) AS active_at_start,
    COUNT(DISTINCT f.account_id) FILTER (
        WHERE f.status = 'churned'
          AND f.end_date >= m.month_start
          AND f.end_date <  m.month_start + INTERVAL '1 month'
    ) AS churned_in_month,
    ROUND(
        COUNT(DISTINCT f.account_id) FILTER (
            WHERE f.status = 'churned'
              AND f.end_date >= m.month_start
              AND f.end_date <  m.month_start + INTERVAL '1 month'
        ) * 100.0
        / NULLIF(COUNT(DISTINCT f.account_id) FILTER (
            WHERE f.start_date < m.month_start
              AND (f.end_date IS NULL OR f.end_date >= m.month_start)
        ), 0)
    , 2) AS logo_churn_pct
FROM months m
CROSS JOIN fct_subscriptions f
-- Logo churn is a COUNT of accounts, so only exclude flags that corrupt
-- the date/status fields this query relies on. MRR/currency flags are
-- irrelevant to a head-count metric and would needlessly drop churnable
-- accounts from both numerator and denominator.
WHERE (f.data_quality_flag IS NULL OR f.data_quality_flag <> 'inverted_dates')
GROUP BY m.month_start
ORDER BY year_month;

-- 4.2b. Monthly revenue (MRR) churn rate
WITH months AS (
    SELECT date_actual AS month_start
    FROM dim_date
    WHERE date_actual = DATE_TRUNC('month', date_actual)
)
SELECT
    TO_CHAR(m.month_start, 'YYYY-MM') AS year_month,
    ROUND(COALESCE(SUM(f.effective_mrr_usd) FILTER (
        WHERE f.start_date < m.month_start
          AND (f.end_date IS NULL OR f.end_date >= m.month_start)
    ), 0), 2) AS mrr_active_at_start,
    ROUND(COALESCE(SUM(f.effective_mrr_usd) FILTER (
        WHERE f.status = 'churned'
          AND f.end_date >= m.month_start
          AND f.end_date <  m.month_start + INTERVAL '1 month'
    ), 0), 2) AS mrr_churned,
    ROUND(
        COALESCE(SUM(f.effective_mrr_usd) FILTER (
            WHERE f.status = 'churned'
              AND f.end_date >= m.month_start
              AND f.end_date <  m.month_start + INTERVAL '1 month'
        ), 0) * 100.0
        / NULLIF(SUM(f.effective_mrr_usd) FILTER (
            WHERE f.start_date < m.month_start
              AND (f.end_date IS NULL OR f.end_date >= m.month_start)
        ), 0)
    , 2) AS revenue_churn_pct
FROM months m
CROSS JOIN fct_subscriptions f
WHERE f.data_quality_flag IS NULL
    OR f.data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high', 'mrr_anomaly_vs_plan', 'inverted_dates')
GROUP BY m.month_start
ORDER BY year_month;


-- ------------------------------------------------------------
-- 4.2c. Cohort retention analysis
-- Cohort = month a subscription started. Shows, per cohort,
-- how many are still active vs churned.
-- NOTE: with only 3 churn events across the cohorts, this is
-- directional only — a full retention curve (month 1/2/3...)
-- is not viable with this little churn data.
-- ------------------------------------------------------------
WITH cohorts AS (
    SELECT
        DATE_TRUNC('month', start_date)::DATE AS cohort_month,
        subscription_sk,
        status
    FROM fct_subscriptions
    WHERE start_date IS NOT NULL                       -- excludes orphan rows with no start date
      AND (data_quality_flag IS NULL
           OR data_quality_flag = 'suspect_trial_date')
)
SELECT
    TO_CHAR(cohort_month, 'YYYY-MM')                             AS cohort_month,
    COUNT(*)                                                    AS cohort_size,
    COUNT(*) FILTER (WHERE status = 'churned')                  AS churned,
    COUNT(*) FILTER (WHERE status <> 'churned')                 AS retained,
    ROUND(COUNT(*) FILTER (WHERE status <> 'churned') * 100.0
        / NULLIF(COUNT(*), 0), 1)                               AS retention_pct
FROM cohorts
GROUP BY cohort_month
ORDER BY cohort_month;



-- ------------------------------------------------------------
-- Churn by plan type
-- Churn rate per plan = churned subscriptions / total subscriptions
-- ------------------------------------------------------------
SELECT
    plan_type,
    COUNT(*)                                          AS total_subscriptions,
    COUNT(*) FILTER (WHERE status = 'churned')        AS churned_subscriptions,
    ROUND(
        COUNT(*) FILTER (WHERE status = 'churned') * 100.0
        / NULLIF(COUNT(*), 0)
    , 2)                                              AS churn_rate_pct
FROM fct_subscriptions
WHERE plan_type IS NOT NULL
    AND (data_quality_flag IS NULL OR data_quality_flag <> 'inverted_dates')
GROUP BY plan_type
ORDER BY churn_rate_pct DESC;


-- ------------------------------------------------------------
-- 4.2d. Average customer lifetime
-- Customer (account) grain — lifetime = first subscription start
-- to final churn. Restricted to genuinely CHURNED, paying
-- customers: 'cancelled' status (ACC-1013, a zero-revenue 100%
-- discount account) is excluded as it doesn't represent a paying
-- customer lifetime.
--
-- Still-active customers are right-censored (lifetime incomplete)
-- and excluded. ACC-1003 re-subscribed so counts as still active.
-- Only 'inverted_dates' filtered — this is a duration metric.
--
-- NOTE: tiny sample (2-3 customers) — directional only.
-- ------------------------------------------------------------
WITH customer_lifetime AS (
    SELECT
        account_id,
        MIN(start_date)            AS first_start,
        MAX(end_date)              AS last_end,
        BOOL_OR(end_date IS NULL)  AS still_active,
        BOOL_OR(status = 'churned') AS has_churned
    FROM fct_subscriptions
    WHERE (data_quality_flag IS NULL OR data_quality_flag <> 'inverted_dates')
    GROUP BY account_id
)
SELECT
    COUNT(*) FILTER (WHERE has_churned AND NOT still_active)                         AS churned_customers,
    ROUND(AVG(last_end - first_start) FILTER (WHERE has_churned AND NOT still_active), 1)        AS avg_lifetime_days,
    ROUND(AVG(last_end - first_start) FILTER (WHERE has_churned AND NOT still_active) / 30.0, 2) AS avg_lifetime_months
FROM customer_lifetime;


-- ============================================================
-- PART 4.3: USAGE & ENGAGEMENT METRICS
-- ============================================================
-- DAU/WAU/MAU = distinct active accounts per period.
-- Note: no user_id in data; accounts de-duplicated via account_id.
-- Source: stg_usage_events (all product activity).
-- ============================================================


-- 4.3a. Active Users — DAU / WAU / MAU


-- ------------------------------------------------------------
-- DAU — Daily Active Users
-- ------------------------------------------------------------
WITH daily AS (
    SELECT
        event_date,
        account_id,
        MAX(active_users) AS account_active_users
    FROM stg_usage_events
    WHERE event_date IS NOT NULL
      AND (active_users IS NULL OR active_users < 999)
    GROUP BY event_date, account_id
)
SELECT
    d.date_actual,
    COUNT(DISTINCT daily.account_id)                       AS active_accounts,
    ROUND(COALESCE(SUM(daily.account_active_users), 0), 0) AS active_users
FROM dim_date d
LEFT JOIN daily
    ON d.date_actual = daily.event_date
GROUP BY d.date_actual
ORDER BY d.date_actual;


-- ------------------------------------------------------------
-- WAU — Weekly Active Users
-- Aggregated to ISO week via the date dimension
-- ------------------------------------------------------------
WITH daily AS (
    SELECT
        event_date,
        account_id,
        MAX(active_users) AS account_active_users
    FROM stg_usage_events
    WHERE event_date IS NOT NULL
      AND (active_users IS NULL OR active_users < 999)
    GROUP BY event_date, account_id
)
SELECT
    DATE_TRUNC('week', d.date_actual)::DATE                AS week_start,
    COUNT(DISTINCT daily.account_id)                       AS active_accounts,
    ROUND(COALESCE(SUM(daily.account_active_users), 0), 0) AS active_users
FROM dim_date d
LEFT JOIN daily
    ON d.date_actual = daily.event_date
GROUP BY DATE_TRUNC('week', d.date_actual)
ORDER BY week_start;


-- ------------------------------------------------------------
-- MAU — Monthly Active Users (most meaningful grain here)
-- ------------------------------------------------------------
WITH daily AS (
    SELECT
        event_date,
        account_id,
        MAX(active_users) AS account_active_users
    FROM stg_usage_events
    WHERE event_date IS NOT NULL
      AND (active_users IS NULL OR active_users < 999)
    GROUP BY event_date, account_id
)
SELECT
    TO_CHAR(d.date_actual, 'YYYY-MM')                      AS year_month,
    COUNT(DISTINCT daily.account_id)                       AS active_accounts,
    ROUND(COALESCE(SUM(daily.account_active_users), 0), 0) AS active_users
FROM dim_date d
LEFT JOIN daily
    ON d.date_actual = daily.event_date
GROUP BY TO_CHAR(d.date_actual, 'YYYY-MM')
ORDER BY year_month;


-- 4.3b. Feature adoption rates
-- % of subscriptions (with usage) that used each feature at
-- least once. Subscription-level: orphan usage rows (no
-- subscription record) are excluded via subscription_id IS NOT NULL.
-- No subscription quality flags filtered — focus is on feature usage
-- patterns in engaged accounts, not financial quality.
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS subscriptions_with_usage,
    ROUND(COUNT(*) FILTER (WHERE total_feature_a_usage > 0) * 100.0 / COUNT(*), 1) AS feature_a_pct,
    ROUND(COUNT(*) FILTER (WHERE total_feature_b_usage > 0) * 100.0 / COUNT(*), 1) AS feature_b_pct,
    ROUND(COUNT(*) FILTER (WHERE total_feature_c_usage > 0) * 100.0 / COUNT(*), 1) AS feature_c_pct
FROM fct_subscriptions
WHERE has_usage = TRUE
    AND subscription_id IS NOT NULL;


-- ------------------------------------------------------------
-- 4.3c. Usage intensity by subscription tier
-- Average engagement per plan — shows whether higher tiers
-- use the product more heavily. No quality flags filtered;
-- reporting on all subscriptions with usage to capture full engagement picture.
-- ------------------------------------------------------------
SELECT
    plan_type,
    COUNT(*)                                 AS subscriptions,
    ROUND(AVG(avg_active_users), 1)          AS avg_active_users,
    ROUND(AVG(total_api_calls), 0)           AS avg_total_api_calls,
    ROUND(AVG(avg_session_duration_mins), 1) AS avg_session_mins,
    ROUND(AVG(total_projects_created), 1)    AS avg_projects_created,
    ROUND(AVG(avg_integrations_used), 1)     AS avg_integrations,
    ROUND(AVG(total_support_tickets), 1)     AS avg_support_tickets
FROM fct_subscriptions
WHERE has_usage = TRUE
    AND plan_type IS NOT NULL
GROUP BY plan_type
ORDER BY
    CASE plan_type
        WHEN 'Basic'        THEN 1
        WHEN 'Starter'      THEN 2
        WHEN 'Professional' THEN 3
        WHEN 'Enterprise'   THEN 4
    END;


-- ------------------------------------------------------------
-- 4.3d. Correlation between usage and retention
-- Compares average usage between active (retained) and churned
-- subscriptions. Higher usage among active = evidence that
-- engagement is associated with retention. No quality flags filtered;
-- focus is on the engagement differential, not financial quality.
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN status = 'active'  THEN 'Retained (active)'
        WHEN status = 'churned' THEN 'Churned'
    END                                       AS retention_status,
    COUNT(*)                                  AS subscriptions,
    ROUND(AVG(avg_active_users), 1)           AS avg_active_users,
    ROUND(AVG(total_api_calls), 0)            AS avg_total_api_calls,
    ROUND(AVG(avg_session_duration_mins), 1)  AS avg_session_mins,
    ROUND(AVG(usage_event_count), 1)          AS avg_usage_events,
    ROUND(AVG(total_feature_a_usage
            + total_feature_b_usage
            + total_feature_c_usage), 1)      AS avg_total_feature_usage
FROM fct_subscriptions
WHERE status IN ('active', 'churned')
    AND has_usage = TRUE
GROUP BY
    CASE
        WHEN status = 'active'  THEN 'Retained (active)'
        WHEN status = 'churned' THEN 'Churned'
    END
ORDER BY retention_status;


-- ============================================================
-- PART 4.4: CUSTOMER HEALTH SCORE
-- ============================================================
-- Forward-looking churn-risk score (0-100) for LIVE customers
-- (active + trial). Churned/cancelled excluded — already left.
--
-- Components (each 0-1, weights sum to 1):
--   Usage engagement  45%  (active users, session time, integrations)
--   Payment/tenure    20%  (subscription length x (1 - discount))
--   Feature adoption  20%  (% of 3 features used)
--   Support health    15%  (inverted tickets relative to usage)
--
-- DESIGN NOTES:
-- - api_calls excluded from usage: most outlier-prone metric
--   (one account at 50,000 vs ~3,000 mean) plus a NULL. Replaced
--   with active users / session duration / integrations.
-- - Only ACC-1029 / ACC-1009 (mrr_outlier_extreme/high) are left
--   unscored — their USAGE data is untrustworthy. ACC-1042's
--   anomaly is confined to MRR (not used in scoring), so it IS scored.
-- - Trials are scored and banded normally — a trial is still a live
--   account, and the score reflects its likelihood to convert.
-- - active-but-zero-usage accounts are scored (they score low) AND
--   carry an explicit high-risk warning.
-- - Outliers excluded from normalisation bounds so they don't
--   distort the scale.
--
-- LIMITATIONS: weights are reasoned judgement, not calibrated to
-- actual churn; scores are RELATIVE to the scored population.
-- ------------------------------------------------------------

WITH base AS (
    SELECT
        subscription_sk,
        account_id,
        plan_type,
        status,
        effective_mrr_usd,
        subscription_length_days,
        discount_percentage,
        avg_active_users,
        avg_session_duration_mins,
        avg_integrations_used,
        total_support_tickets,
        usage_event_count,
        (CASE WHEN total_feature_a_usage > 0 THEN 1 ELSE 0 END
       + CASE WHEN total_feature_b_usage > 0 THEN 1 ELSE 0 END
       + CASE WHEN total_feature_c_usage > 0 THEN 1 ELSE 0 END) AS features_adopted,
        data_quality_flag,
        -- Only genuine usage/data outliers are unscoreable
        CASE
            WHEN data_quality_flag IN ('mrr_outlier_extreme', 'mrr_outlier_high')
            THEN TRUE ELSE FALSE
        END AS is_outlier,
        -- Active but no usage = strongest churn signal
        CASE
            WHEN status = 'active' AND usage_event_count = 0
            THEN TRUE ELSE FALSE
        END AS active_zero_usage
    FROM fct_subscriptions
    WHERE subscription_id IS NOT NULL
      AND status IN ('active', 'trial')
),
bounds AS (
    -- Normalising max over non-outlier rows only
    SELECT
        NULLIF(MAX(avg_active_users), 0)          AS max_users,
        NULLIF(MAX(avg_session_duration_mins), 0) AS max_session,
        NULLIF(MAX(avg_integrations_used), 0)     AS max_integrations,
        NULLIF(MAX(total_support_tickets), 0)     AS max_tickets,
        NULLIF(MAX(subscription_length_days), 0)  AS max_tenure_days
    FROM base
    WHERE is_outlier = FALSE
),
components AS (
    SELECT
        b.*,
        bd.*,
        -- Usage engagement (45%): active users, session time, integrations
        LEAST((
            COALESCE(b.avg_active_users          / bd.max_users, 0)
          + COALESCE(b.avg_session_duration_mins / bd.max_session, 0)
          + COALESCE(b.avg_integrations_used     / bd.max_integrations, 0)
        ) / 3.0, 1) AS usage_score,

        -- Payment/tenure (20%): tenure scaled by (1 - discount)
        LEAST(
            COALESCE(b.subscription_length_days / bd.max_tenure_days, 0)
            * (1.0 - COALESCE(b.discount_percentage, 0) / 100.0),
            1.0
        ) AS tenure_score,

        -- Feature adoption (20%)
        LEAST(b.features_adopted / 3.0, 1) AS feature_score,

        -- Support health (15%): inverted; neutral 0.5 if no usage baseline
        CASE
            WHEN b.usage_event_count = 0 THEN 0.5
            ELSE GREATEST(
                1.0 - (COALESCE(b.total_support_tickets / bd.max_tickets, 0) * 2.0),
                0.0
            )
        END AS support_score
    FROM base b
    CROSS JOIN bounds bd
)
SELECT
    subscription_sk,
    account_id,
    plan_type,
    status,
    ROUND(usage_score,   3) AS usage_score,
    ROUND(tenure_score,  3) AS tenure_score,
    ROUND(feature_score, 3) AS feature_score,
    ROUND(support_score, 3) AS support_score,

    -- Health score: only genuine outliers unscored (NULL)
    CASE
        WHEN is_outlier THEN NULL
        ELSE ROUND(100 * (
            0.45 * usage_score
          + 0.20 * tenure_score
          + 0.20 * feature_score
          + 0.15 * support_score
        ), 1)
    END AS health_score,

    -- Band / warning label
    CASE
        WHEN is_outlier        THEN 'Unscoreable: data quality issue'
        WHEN active_zero_usage THEN 'HIGH RISK: active but no usage'
        WHEN ROUND(100 * (0.45*usage_score + 0.20*tenure_score + 0.20*feature_score + 0.15*support_score), 1) < 40
            THEN 'At risk'
        WHEN ROUND(100 * (0.45*usage_score + 0.20*tenure_score + 0.20*feature_score + 0.15*support_score), 1) < 70
            THEN 'Moderate'
        ELSE 'Healthy'
    END AS health_band
FROM components;