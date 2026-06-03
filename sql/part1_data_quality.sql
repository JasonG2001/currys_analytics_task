-- ============================================================
-- PART 1.1: DATA COMPLETENESS CHECK
-- ============================================================

-- Quick duplicate-id sanity check
SELECT subscription_id, COUNT(*) FROM stg_subscriptions
GROUP BY subscription_id HAVING COUNT(*) > 1;

SELECT event_id, COUNT(*) FROM stg_usage_events
GROUP BY event_id HAVING COUNT(*) > 1;


-- ------------------------------------------------------------
-- 1a. NULL count and percentage per field in subscriptions
-- end_date NULLs are expected (active subs have no end date);
-- mrr_amount, currency and billing_period NULLs are critical.
-- ------------------------------------------------------------
SELECT 'subscription_id' AS column_name,
       COUNT(*) FILTER (WHERE subscription_id IS NULL) AS null_count,
       ROUND(COUNT(*) FILTER (WHERE subscription_id IS NULL) * 100.0 / COUNT(*), 1) AS pct_null
FROM stg_subscriptions
UNION ALL
SELECT 'account_id',
       COUNT(*) FILTER (WHERE account_id IS NULL),
       ROUND(COUNT(*) FILTER (WHERE account_id IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'plan_type',
       COUNT(*) FILTER (WHERE plan_type IS NULL),
       ROUND(COUNT(*) FILTER (WHERE plan_type IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'status',
       COUNT(*) FILTER (WHERE status IS NULL),
       ROUND(COUNT(*) FILTER (WHERE status IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'mrr_amount',
       COUNT(*) FILTER (WHERE mrr_amount IS NULL),
       ROUND(COUNT(*) FILTER (WHERE mrr_amount IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'currency',
       COUNT(*) FILTER (WHERE currency IS NULL),
       ROUND(COUNT(*) FILTER (WHERE currency IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'start_date',
       COUNT(*) FILTER (WHERE start_date IS NULL),
       ROUND(COUNT(*) FILTER (WHERE start_date IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'end_date',
       COUNT(*) FILTER (WHERE end_date IS NULL),
       ROUND(COUNT(*) FILTER (WHERE end_date IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'trial_end_date',
       COUNT(*) FILTER (WHERE trial_end_date IS NULL),
       ROUND(COUNT(*) FILTER (WHERE trial_end_date IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'billing_period',
       COUNT(*) FILTER (WHERE billing_period IS NULL),
       ROUND(COUNT(*) FILTER (WHERE billing_period IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'customer_segment',
       COUNT(*) FILTER (WHERE customer_segment IS NULL),
       ROUND(COUNT(*) FILTER (WHERE customer_segment IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'payment_method',
       COUNT(*) FILTER (WHERE payment_method IS NULL),
       ROUND(COUNT(*) FILTER (WHERE payment_method IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
UNION ALL
SELECT 'discount_percentage',
       COUNT(*) FILTER (WHERE discount_percentage IS NULL),
       ROUND(COUNT(*) FILTER (WHERE discount_percentage IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_subscriptions
ORDER BY null_count DESC;


-- ------------------------------------------------------------
-- 1b. Records with critical missing fields in subscriptions
-- Missing mrr_amount/currency/billing_period breaks MRR reporting.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    mrr_amount,
    currency,
    billing_period
FROM stg_subscriptions
WHERE mrr_amount IS NULL
    OR currency IS NULL
    OR billing_period IS NULL
ORDER BY subscription_id;


-- ------------------------------------------------------------
-- 1c. NULL count and percentage per field in usage_events
-- ------------------------------------------------------------
SELECT 'event_id' AS column_name,
       COUNT(*) FILTER (WHERE event_id IS NULL) AS null_count,
       ROUND(COUNT(*) FILTER (WHERE event_id IS NULL) * 100.0 / COUNT(*), 1) AS pct_null
FROM stg_usage_events
UNION ALL
SELECT 'account_id',
       COUNT(*) FILTER (WHERE account_id IS NULL),
       ROUND(COUNT(*) FILTER (WHERE account_id IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'event_date',
       COUNT(*) FILTER (WHERE event_date IS NULL),
       ROUND(COUNT(*) FILTER (WHERE event_date IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'active_users',
       COUNT(*) FILTER (WHERE active_users IS NULL),
       ROUND(COUNT(*) FILTER (WHERE active_users IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'api_calls',
       COUNT(*) FILTER (WHERE api_calls IS NULL),
       ROUND(COUNT(*) FILTER (WHERE api_calls IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'storage_gb',
       COUNT(*) FILTER (WHERE storage_gb IS NULL),
       ROUND(COUNT(*) FILTER (WHERE storage_gb IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'projects_created',
       COUNT(*) FILTER (WHERE projects_created IS NULL),
       ROUND(COUNT(*) FILTER (WHERE projects_created IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'integrations_used',
       COUNT(*) FILTER (WHERE integrations_used IS NULL),
       ROUND(COUNT(*) FILTER (WHERE integrations_used IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'support_tickets',
       COUNT(*) FILTER (WHERE support_tickets IS NULL),
       ROUND(COUNT(*) FILTER (WHERE support_tickets IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'feature_a_usage',
       COUNT(*) FILTER (WHERE feature_a_usage IS NULL),
       ROUND(COUNT(*) FILTER (WHERE feature_a_usage IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'feature_b_usage',
       COUNT(*) FILTER (WHERE feature_b_usage IS NULL),
       ROUND(COUNT(*) FILTER (WHERE feature_b_usage IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'feature_c_usage',
       COUNT(*) FILTER (WHERE feature_c_usage IS NULL),
       ROUND(COUNT(*) FILTER (WHERE feature_c_usage IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'session_duration_mins',
       COUNT(*) FILTER (WHERE session_duration_mins IS NULL),
       ROUND(COUNT(*) FILTER (WHERE session_duration_mins IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
UNION ALL
SELECT 'mobile_usage_mins',
       COUNT(*) FILTER (WHERE mobile_usage_mins IS NULL),
       ROUND(COUNT(*) FILTER (WHERE mobile_usage_mins IS NULL) * 100.0 / COUNT(*), 1)
FROM stg_usage_events
ORDER BY null_count DESC;


-- ------------------------------------------------------------
-- 1d. Records with critical missing fields in usage_events
-- Missing active_users/api_calls blocks engagement metrics.
-- ------------------------------------------------------------
SELECT
    event_id,
    account_id,
    event_date,
    active_users,
    api_calls
FROM stg_usage_events
WHERE active_users IS NULL
    OR api_calls IS NULL
ORDER BY event_id;


-- ============================================================
-- PART 1.2: DATA VALIDITY CHECK
-- ============================================================

-- ------------------------------------------------------------
-- 2a. Invalid date formats in subscriptions
-- Most dates are DD/MM/YYYY; a middle segment > 12 means the
-- value is actually MM/DD/YYYY (e.g. '03/20/2024').
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    start_date,
    end_date,
    trial_end_date,
    'Likely MM/DD/YYYY format' AS issue
FROM subscriptions
WHERE CAST(SPLIT_PART(start_date, '/', 2) AS INT) > 12
    OR CAST(SPLIT_PART(end_date, '/', 2) AS INT) > 12
    OR CAST(SPLIT_PART(trial_end_date, '/', 2) AS INT) > 12
ORDER BY subscription_id;


-- ------------------------------------------------------------
-- 2b. Invalid date formats in usage_events (same logic)
-- ------------------------------------------------------------
SELECT
    event_id,
    account_id,
    event_date,
    'Likely MM/DD/YYYY format' AS issue
FROM usage_events
WHERE CAST(SPLIT_PART(event_date, '/', 2) AS INT) > 12
ORDER BY event_id;


-- ------------------------------------------------------------
-- 2c. Impossible dates — end_date before start_date (e.g. SUB-011)
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    start_date,
    end_date,
    'end_date is before start_date' AS issue
FROM stg_subscriptions
WHERE end_date IS NOT NULL
    AND start_date IS NOT NULL
    AND start_date > end_date;


-- ------------------------------------------------------------
-- 2d. Trial end date too far in the future (> 60 days from start)
-- e.g. SUB-045 — likely a year typo (2025 instead of 2024).
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    start_date,
    trial_end_date,
    (trial_end_date - start_date) AS day_difference,
    'Trial end date more than 60 days after start' AS issue
FROM stg_subscriptions
WHERE trial_end_date IS NOT NULL
    AND start_date IS NOT NULL
    AND trial_end_date > start_date + INTERVAL '60 days';


-- ------------------------------------------------------------
-- 2e. Negative or zero MRR on non-trial subscriptions
-- Trials are expected to have zero MRR, so they're excluded.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    mrr_amount,
    CASE
        WHEN mrr_amount < 0 THEN 'Negative MRR'
        WHEN mrr_amount IS NULL THEN 'Zero MRR on non-trial subscription'
        ELSE 'MRR is valid'
    END AS issue
FROM subscriptions
WHERE (mrr_amount IS NULL OR mrr_amount <= 0)
    AND status != 'trial'
ORDER BY mrr_amount;


-- ------------------------------------------------------------
-- 2f. Statistical MRR outliers (mean + 2 standard deviations)
-- e.g. ACC-1029 (99,900). Values beyond the threshold need review.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    mrr_amount,
    ROUND(AVG(mrr_amount) OVER (), 2)    AS avg_mrr,
    ROUND(STDDEV(mrr_amount) OVER (), 1) AS stddev_mrr,
    'MRR exceeds mean + 2 standard deviations' AS issue
FROM subscriptions
WHERE mrr_amount IS NOT NULL
    AND mrr_amount > (
        SELECT AVG(mrr_amount) + 2 * STDDEV(mrr_amount)
        FROM subscriptions
        WHERE mrr_amount IS NOT NULL
    )
ORDER BY mrr_amount DESC;


-- ------------------------------------------------------------
-- 2f (cont). MRR anomalies categorised by type:
-- - extreme outliers (likely data entry errors)
-- - annual totals stored as monthly (e.g. 999 x 12 = 11,988, ACC-1009)
-- - charges above the plan's standard monthly rate
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    billing_period,
    mrr_amount,
    CASE
        WHEN mrr_amount > 50000
            THEN 'Extreme outlier — likely data entry error'
        WHEN plan_type = 'Enterprise'
            AND billing_period = 'annual'
            AND mrr_amount BETWEEN 5000 AND 50000
            THEN 'Annual value stored as MRR — should be monthly (999)'
        WHEN plan_type = 'Basic'        AND mrr_amount > 50   THEN 'Above standard Basic rate (29)'
        WHEN plan_type = 'Starter'      AND mrr_amount > 100  THEN 'Above standard Starter rate (49)'
        WHEN plan_type = 'Professional' AND mrr_amount > 500  THEN 'Above standard Professional rate (299)'
        WHEN plan_type = 'Enterprise'   AND mrr_amount > 2000 THEN 'Above standard Enterprise rate (999)'
        ELSE NULL
    END AS issue
FROM subscriptions
WHERE mrr_amount IS NOT NULL
    AND (
        mrr_amount > 50000
        OR (plan_type = 'Enterprise' AND billing_period = 'annual' AND mrr_amount BETWEEN 5000 AND 50000)
        OR (plan_type = 'Basic'        AND mrr_amount > 50)
        OR (plan_type = 'Starter'      AND mrr_amount > 100)
        OR (plan_type = 'Professional' AND mrr_amount > 500)
        OR (plan_type = 'Enterprise'   AND mrr_amount > 2000)
    )
ORDER BY mrr_amount DESC;


-- ------------------------------------------------------------
-- 2g. Negative active_users — physically impossible
-- ------------------------------------------------------------
SELECT
    event_id,
    account_id,
    event_date,
    active_users,
    'Negative active_users — impossible value' AS issue
FROM usage_events
WHERE active_users < 0;


-- ------------------------------------------------------------
-- 2h. active_users outliers (mean + 2 stddev)
-- The 999 spike (e.g. EVT-00018) is excluded from the stats so
-- it doesn't distort the threshold, then flagged on its own.
-- ------------------------------------------------------------
WITH stats AS (
    SELECT
        AVG(active_users)    AS avg_active_users,
        STDDEV(active_users) AS stddev_active_users
    FROM stg_usage_events
    WHERE active_users IS NOT NULL
        AND active_users < 999
)
SELECT
    u.event_id,
    u.account_id,
    u.active_users,
    ROUND(s.avg_active_users + 2 * s.stddev_active_users, 1) AS threshold,
    CASE
        WHEN u.active_users = 999 THEN 'Spurious spike — inconsistent with other metrics'
        ELSE 'High but consistent — likely genuine large account'
    END AS issue
FROM stg_usage_events u
CROSS JOIN stats s
WHERE u.active_users > s.avg_active_users + 2 * s.stddev_active_users
    OR u.active_users = 999
ORDER BY u.active_users DESC;


-- ------------------------------------------------------------
-- 2i. Status still 'trial' after trial_end_date has passed
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    trial_end_date,
    'Trial period expired but status still shows trial' AS issue
FROM stg_subscriptions
WHERE status = 'trial'
    AND trial_end_date IS NOT NULL
    AND trial_end_date < CURRENT_DATE;


-- ------------------------------------------------------------
-- 2j. Inconsistent billing_period casing ('MONTHLY' vs 'monthly')
-- Must be standardised before any GROUP BY or join.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    billing_period,
    'billing_period has inconsistent casing' AS issue
FROM stg_subscriptions
WHERE billing_period != LOWER(billing_period);


-- ============================================================
-- PART 1.3: DATA CONSISTENCY CHECK
-- ============================================================

-- ------------------------------------------------------------
-- 3a. Duplicate subscription_ids (e.g. SUB-003)
-- Could be a bad load or an intentional re-subscription — confirm.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    COUNT(*) AS occurrences
FROM stg_subscriptions
GROUP BY subscription_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;


-- ------------------------------------------------------------
-- 3b. Orphaned usage_events — account has no subscription (e.g. ACC-8888)
-- ------------------------------------------------------------
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    'Account exists in usage_events but not in subscriptions' AS issue
FROM stg_usage_events u
LEFT JOIN stg_subscriptions s
    ON u.account_id = s.account_id
WHERE s.account_id IS NULL
ORDER BY u.account_id;


-- ------------------------------------------------------------
-- 3c. Subscriptions with no usage events (pipeline gap or inactive customer)
-- ------------------------------------------------------------
SELECT
    s.subscription_id,
    s.account_id,
    s.plan_type,
    s.status,
    s.mrr_amount,
    'Subscription has no usage events recorded' AS issue
FROM stg_subscriptions s
LEFT JOIN stg_usage_events u
    ON s.account_id = u.account_id
WHERE u.account_id IS NULL
ORDER BY s.plan_type, s.mrr_amount DESC;


-- ------------------------------------------------------------
-- 3d. Referential integrity — account_id format consistency
-- Mismatched formats (e.g. 'ACC-1001' vs 'acc-1001') break joins.
-- ------------------------------------------------------------
SELECT 'stg_subscriptions' AS source_table, account_id
FROM stg_subscriptions
WHERE account_id NOT SIMILAR TO 'ACC-[0-9]+'
UNION ALL
SELECT 'stg_usage_events', account_id
FROM stg_usage_events
WHERE account_id NOT SIMILAR TO 'ACC-[0-9]+'
ORDER BY source_table, account_id;


-- ------------------------------------------------------------
-- 3e. Usage events outside the subscription period
-- Only flags accounts that have a subscription but no matching
-- window (orphaned accounts like ACC-8888 are covered by 3b).
-- Known cases: ACC-1011 (inverted dates), ACC-1017 (event after end).
-- ------------------------------------------------------------
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    s.subscription_id,
    s.start_date,
    s.end_date,
    s.status,
    CASE
        WHEN u.event_date < s.start_date
            THEN 'Usage event before subscription start'
        WHEN s.end_date IS NOT NULL AND u.event_date > s.end_date
            THEN 'Usage event after subscription end'
        ELSE 'Outside subscription window'
    END AS issue
FROM stg_usage_events u
-- find events that match no subscription window
LEFT JOIN stg_subscriptions matched
    ON u.account_id = matched.account_id
    AND u.event_date >= matched.start_date
    AND (matched.end_date IS NULL OR u.event_date <= matched.end_date)
-- INNER join keeps only accounts that do have a subscription
JOIN stg_subscriptions s
    ON u.account_id = s.account_id
WHERE matched.subscription_sk IS NULL
ORDER BY u.account_id, u.event_date;
