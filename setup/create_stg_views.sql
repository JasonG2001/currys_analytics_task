-- Staging views: standardise types/formats on the raw tables.
-- Dates are parsed format-aware, blank text becomes NULL, and
-- negative active_users is nulled. Business values (e.g. MRR)
-- pass through unchanged for the Part 1 / Part 2 checks to flag.

DROP VIEW IF EXISTS stg_subscriptions CASCADE;
CREATE OR REPLACE VIEW stg_subscriptions AS
SELECT
    -- Surrogate key: appends a per-lifecycle row number, giving
    -- the duplicate SUB-003 two keys (churned vs re-subscription).
    subscription_id || '-' ||
        ROW_NUMBER() OVER (
            PARTITION BY subscription_id, account_id
            ORDER BY
                CASE
                    WHEN CAST(SPLIT_PART(start_date, '/', 2) AS INT) > 12
                        THEN TO_DATE(start_date, 'MM/DD/YYYY')
                    ELSE TO_DATE(start_date, 'DD/MM/YYYY')
                END
        )                                AS subscription_sk,
    subscription_id,
    account_id,
    plan_type,
    status,
    CASE WHEN mrr_amount < 0 THEN NULL ELSE mrr_amount END AS mrr_amount,
    NULLIF(TRIM(currency), '')           AS currency,
    CASE
        WHEN CAST(SPLIT_PART(start_date, '/', 2) AS INT) > 12
            THEN TO_DATE(start_date, 'MM/DD/YYYY')
        ELSE TO_DATE(start_date, 'DD/MM/YYYY')
    END                                  AS start_date,
    CASE
        WHEN end_date IS NULL THEN NULL
        WHEN CAST(SPLIT_PART(end_date, '/', 2) AS INT) > 12
            THEN TO_DATE(end_date, 'MM/DD/YYYY')
        ELSE TO_DATE(end_date, 'DD/MM/YYYY')
    END                                  AS end_date,
    CASE
        WHEN trial_end_date IS NULL THEN NULL
        WHEN CAST(SPLIT_PART(trial_end_date, '/', 2) AS INT) > 12
            THEN TO_DATE(trial_end_date, 'MM/DD/YYYY')
        ELSE TO_DATE(trial_end_date, 'DD/MM/YYYY')
    END                                  AS trial_end_date,
    created_at,
    updated_at,
    LOWER(NULLIF(TRIM(billing_period), '')) AS billing_period,
    NULLIF(TRIM(customer_segment), '')   AS customer_segment,
    NULLIF(TRIM(payment_method), '')     AS payment_method,
    discount_percentage
FROM subscriptions;


DROP VIEW IF EXISTS stg_usage_events CASCADE;
CREATE OR REPLACE VIEW stg_usage_events AS
SELECT
    event_id,
    account_id,
    CASE
        WHEN CAST(SPLIT_PART(event_date, '/', 2) AS INT) > 12
            THEN TO_DATE(event_date, 'MM/DD/YYYY')
        ELSE TO_DATE(event_date, 'DD/MM/YYYY')
    END                                  AS event_date,
    CASE WHEN active_users < 0 THEN NULL ELSE active_users END AS active_users,
    api_calls,
    storage_gb,
    projects_created,
    integrations_used,
    support_tickets,
    feature_a_usage,
    feature_b_usage,
    feature_c_usage,
    session_duration_mins,
    mobile_usage_mins
FROM usage_events;
