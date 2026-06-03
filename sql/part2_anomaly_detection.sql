-- ============================================================
-- PART 2 — ANOMALY DETECTION
-- ------------------------------------------------------------
-- Surfaces records that are individually well-formed but
-- behave abnormally against their statistical, business-logic
-- or behavioural context. Anomalies are flagged and reported,
-- not corrected — they are candidates for business review.
--
-- Reads from the staging views (stg_subscriptions,
-- stg_usage_events) defined in setup/create_stg_views.sql.
-- Findings are written up in README.md (Part 2).
-- ============================================================


-- ============================================================
-- PART 2.1: STATISTICAL OUTLIERS
-- ============================================================

-- ------------------------------------------------------------
-- 2.1a. MRR outliers by plan type
-- Compares each subscription's MRR against the mean + 2 stddev
-- of its own plan type — a more nuanced check than a global
-- threshold, since Enterprise plans legitimately have higher
-- MRR. ACC-1042 charges 490 on a Starter plan (normally ~49).
-- ------------------------------------------------------------
WITH plan_stats AS (
    SELECT
        plan_type,
        AVG(mrr_amount)    AS avg_mrr,
        STDDEV(mrr_amount) AS stddev_mrr
    FROM stg_subscriptions
    WHERE mrr_amount > 0
    GROUP BY plan_type
)
SELECT
    s.subscription_id,
    s.account_id,
    s.plan_type,
    s.mrr_amount,
    ROUND(p.avg_mrr::NUMERIC, 2)                       AS plan_avg_mrr,
    ROUND(p.stddev_mrr::NUMERIC, 2)                    AS plan_stddev_mrr,
    ROUND((p.avg_mrr + 2 * p.stddev_mrr)::NUMERIC, 2)  AS plan_upper_threshold,
    'MRR is an outlier within its plan type'           AS issue
FROM stg_subscriptions s
JOIN plan_stats p
    ON s.plan_type = p.plan_type
WHERE s.mrr_amount > (p.avg_mrr + 2 * p.stddev_mrr)
    OR s.mrr_amount < 0
ORDER BY s.plan_type, s.mrr_amount DESC;


-- ------------------------------------------------------------
-- 2.1b. Abnormal usage — api_calls outliers (global)
-- Flags events whose api_calls exceed the global mean + 2 stddev.
-- ACC-1029 is a clear outlier, ~10x the next highest account.
-- ------------------------------------------------------------
WITH api_stats AS (
    SELECT
        AVG(api_calls)    AS avg_api_calls,
        STDDEV(api_calls) AS stddev_api_calls
    FROM stg_usage_events
    WHERE api_calls IS NOT NULL
        AND api_calls > 0
)
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    u.api_calls,
    ROUND(a.avg_api_calls::NUMERIC, 2)                            AS avg_api_calls,
    ROUND(a.stddev_api_calls::NUMERIC, 2)                         AS stddev_api_calls,
    ROUND((a.avg_api_calls + 2 * a.stddev_api_calls)::NUMERIC, 2) AS upper_threshold,
    'api_calls exceeds mean + 2 standard deviations'             AS issue
FROM stg_usage_events u
CROSS JOIN api_stats a
WHERE u.api_calls > (a.avg_api_calls + 2 * a.stddev_api_calls)
ORDER BY u.api_calls DESC;


-- ------------------------------------------------------------
-- 2.1c. Abnormal usage — active_users outliers (global)
-- Flags events whose active_users exceed the global mean + 2
-- stddev. Negative values are already nulled in staging
-- (covered in Part 1.2), so this isolates genuine high spikes.
-- ------------------------------------------------------------
WITH user_stats AS (
    SELECT
        AVG(active_users)    AS avg_users,
        STDDEV(active_users) AS stddev_users
    FROM stg_usage_events
    WHERE active_users IS NOT NULL
        AND active_users > 0
)
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    u.active_users,
    ROUND(us.avg_users::NUMERIC, 2)                         AS avg_active_users,
    ROUND(us.stddev_users::NUMERIC, 2)                      AS stddev_active_users,
    ROUND((us.avg_users + 2 * us.stddev_users)::NUMERIC, 2) AS upper_threshold,
    'active_users exceeds mean + 2 standard deviations'     AS issue
FROM stg_usage_events u
CROSS JOIN user_stats us
WHERE u.active_users > (us.avg_users + 2 * us.stddev_users)
ORDER BY u.active_users DESC;


-- ------------------------------------------------------------
-- 2.1d. Sudden spikes or drops in api_calls (per account)
-- Compares each event to its own account's average, catching
-- account-level anomalies that a global average would miss.
--   spike: > 2x the account average
--   drop : < 0.25x the account average (75% reduction)
-- ------------------------------------------------------------
WITH account_api_stats AS (
    SELECT
        account_id,
        AVG(api_calls) AS avg_api_calls
    FROM stg_usage_events
    WHERE api_calls IS NOT NULL
    GROUP BY account_id
)
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    u.api_calls,
    ROUND(a.avg_api_calls::NUMERIC, 2)                          AS account_avg_api_calls,
    ROUND((u.api_calls / NULLIF(a.avg_api_calls, 0))::NUMERIC, 2) AS ratio_to_avg,
    CASE
        WHEN u.api_calls > a.avg_api_calls * 2
            THEN 'Spike — api_calls more than 2x account average'
        WHEN u.api_calls < a.avg_api_calls * 0.25
            THEN 'Drop — api_calls less than 25% of account average'
    END AS issue
FROM stg_usage_events u
JOIN account_api_stats a
    ON u.account_id = a.account_id
WHERE u.api_calls > a.avg_api_calls * 2
    OR u.api_calls < a.avg_api_calls * 0.25
ORDER BY ratio_to_avg DESC;


-- ------------------------------------------------------------
-- 2.1e. Sudden spikes or drops in active_users (per account)
-- Same per-account spike/drop logic applied to active_users.
-- ------------------------------------------------------------
WITH account_user_stats AS (
    SELECT
        account_id,
        AVG(active_users) AS avg_users
    FROM stg_usage_events
    WHERE active_users IS NOT NULL
        AND active_users > 0
    GROUP BY account_id
)
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    u.active_users,
    ROUND(a.avg_users::NUMERIC, 2)                              AS account_avg_users,
    ROUND((u.active_users / NULLIF(a.avg_users, 0))::NUMERIC, 2) AS ratio_to_avg,
    CASE
        WHEN u.active_users > a.avg_users * 2
            THEN 'Spike — active_users more than 2x account average'
        WHEN u.active_users < a.avg_users * 0.25
            THEN 'Drop — active_users less than 25% of account average'
    END AS issue
FROM stg_usage_events u
JOIN account_user_stats a
    ON u.account_id = a.account_id
WHERE u.active_users IS NOT NULL
    AND (
        u.active_users > a.avg_users * 2
        OR u.active_users < a.avg_users * 0.25
    )
ORDER BY ratio_to_avg DESC;


-- ============================================================
-- PART 2.2: BUSINESS LOGIC VIOLATIONS
-- ============================================================

-- ------------------------------------------------------------
-- 2.2a. end_date before start_date
-- A subscription cannot end before it begins. SUB-011 is the
-- known case (an inverted/typo date pair).
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    end_date,
    end_date - start_date           AS days_difference,
    'end_date is before start_date' AS issue
FROM stg_subscriptions
WHERE end_date IS NOT NULL
    AND end_date < start_date
ORDER BY days_difference;


-- ------------------------------------------------------------
-- 2.2b. Usage events outside any subscription period
-- Date-bounded LEFT JOIN: each event is matched to the
-- subscription window it falls within. Unmatched events
-- (NULL subscription_id) are anomalies.
-- NOTE: ACC-1011's two events surface here as a knock-on of the
-- same root cause as 2.2a/2.2d — its end_date (10 Mar) sits
-- before its start_date (10 Apr), making the window empty so
-- nothing can match. Not three independent issues; one likely
-- bad end_date (see 2.2d) flagged three times.
-- ------------------------------------------------------------
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    s.subscription_id,
    s.start_date,
    s.end_date,
    s.status,
    'No valid subscription window for this event' AS issue
FROM stg_usage_events u
LEFT JOIN stg_subscriptions s
    ON u.account_id = s.account_id
    AND u.event_date >= s.start_date
    AND (s.end_date IS NULL OR u.event_date <= s.end_date)
WHERE s.subscription_id IS NULL
ORDER BY u.account_id, u.event_date;


-- ------------------------------------------------------------
-- 2.2c. Impossible status transitions
-- Churned or cancelled subscriptions with no end_date —
-- terminal states must carry a recorded end date.
-- (Expected to return no rows on this dataset.)
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    end_date,
    'Terminal status with no end_date' AS issue
FROM stg_subscriptions
WHERE status IN ('churned', 'cancelled')
    AND end_date IS NULL
ORDER BY status, subscription_id;


-- ------------------------------------------------------------
-- 2.2d. Active subscriptions with a past end_date
-- An active subscription should not carry a past end_date.
-- The only row here is ACC-1011 — the same root cause as
-- 2.2a/2.2b. The subscription is active, so this looks like a
-- date error rather than a churned account mislabelled as
-- active: most likely the 10 Mar end_date is wrong and should
-- be NULL (start 10 Apr matches created_at and precedes the
-- trial_end_date), but this needs confirmation before fixing.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    end_date,
    'Active status but end_date has passed' AS issue
FROM stg_subscriptions
WHERE status = 'active'
    AND end_date IS NOT NULL
    AND end_date < CURRENT_DATE
ORDER BY end_date;


-- ------------------------------------------------------------
-- 2.2e. Trial expired but status unchanged
-- trial_end_date has passed while status is still 'trial' —
-- accounts stuck mid-onboarding (no paying account set up).
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    trial_end_date,
    CURRENT_DATE - trial_end_date        AS days_since_trial_ended,
    'Trial expired but status unchanged' AS issue
FROM stg_subscriptions
WHERE status = 'trial'
    AND trial_end_date IS NOT NULL
    AND trial_end_date < CURRENT_DATE
ORDER BY days_since_trial_ended DESC;


-- ------------------------------------------------------------
-- 2.2f. Orphaned usage events
-- ACC-8888 has usage data but no subscription record to
-- attribute it to.
-- ------------------------------------------------------------
SELECT
    u.event_id,
    u.account_id,
    u.event_date,
    u.active_users,
    u.api_calls,
    'No matching subscription record' AS issue
FROM stg_usage_events u
LEFT JOIN stg_subscriptions s
    ON u.account_id = s.account_id
WHERE s.account_id IS NULL
ORDER BY u.account_id, u.event_date;


-- ------------------------------------------------------------
-- 2.2g. Contradictory usage — zero users, positive activity
-- active_users = 0 alongside positive api_calls or session
-- time is internally inconsistent — activity implies at least
-- one user. Suggests active_users failed to record rather than
-- genuine zero usage. ACC-1037 (EVT-00073, EVT-00074) is known.
-- ------------------------------------------------------------
SELECT
    event_id,
    account_id,
    event_date,
    active_users,
    api_calls,
    session_duration_mins,
    'Zero active users but positive activity (api_calls/session)' AS issue
FROM stg_usage_events
WHERE active_users = 0
    AND (api_calls > 0 OR session_duration_mins > 0)
ORDER BY account_id, event_date;


-- ============================================================
-- PART 2.3: PATTERN ANOMALIES
-- ============================================================

-- ------------------------------------------------------------
-- 2.3a. Active subscriptions with zero usage
-- Every active paying customer should have some usage. Zero
-- usage may mean a pipeline gap or a disengaged customer at
-- churn risk. Note: ACC-1011 appears here only because its
-- inverted start/end dates (Part 1.2) leave no valid window
-- for the date-bounded join to match — a single upstream
-- defect silently corrupting a downstream metric.
-- ------------------------------------------------------------
SELECT
    s.subscription_id,
    s.account_id,
    s.plan_type,
    s.status,
    s.mrr_amount,
    s.customer_segment,
    s.start_date,
    'Active subscription with no usage events' AS issue
FROM stg_subscriptions s
LEFT JOIN stg_usage_events u
    ON s.account_id = u.account_id
    AND u.event_date >= s.start_date
    AND (s.end_date IS NULL OR u.event_date <= s.end_date)
WHERE s.status = 'active'
    AND u.account_id IS NULL
ORDER BY s.mrr_amount DESC;


-- ------------------------------------------------------------
-- 2.3b. All-zero usage rows
-- EVT-00052 (ACC-1026) and EVT-00082 (ACC-1041) are zero
-- across every metric — likely a failed collection event
-- rather than genuine zero usage. Distinct from 2.3a: the
-- account does have events, they just contain no data.
-- ------------------------------------------------------------
SELECT
    event_id,
    account_id,
    event_date,
    active_users,
    api_calls,
    storage_gb,
    session_duration_mins,
    'All metrics are zero — likely failed data collection' AS issue
FROM stg_usage_events
WHERE active_users = 0
    AND api_calls = 0
    AND storage_gb = 0
    AND session_duration_mins = 0
ORDER BY account_id, event_date;


-- ------------------------------------------------------------
-- 2.3c. Suspicious discount patterns
-- Discounts over 30% materially reduce effective MRR and may
-- indicate unauthorised deals. Reports effective MRR and
-- revenue lost so the commercial impact is explicit.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    customer_segment,
    mrr_amount,
    discount_percentage,
    ROUND(mrr_amount * (1 - discount_percentage / 100), 2) AS effective_mrr,
    ROUND(mrr_amount * (discount_percentage / 100), 2)     AS revenue_lost,
    'High discount — over 30%'                             AS issue
FROM stg_subscriptions
WHERE discount_percentage > 30
ORDER BY discount_percentage DESC;


-- ------------------------------------------------------------
-- 2.3d. Unusual clustering of subscription start dates
-- A disproportionate number of subscriptions starting on the
-- same date can indicate a bulk import or test data mixed in
-- with production.
-- ------------------------------------------------------------
SELECT
    start_date,
    COUNT(*)                            AS subscriptions_started,
    STRING_AGG(subscription_id, ', ')   AS subscription_ids,
    'Unusual clustering of start dates' AS issue
FROM stg_subscriptions
GROUP BY start_date
HAVING COUNT(*) > 2
ORDER BY subscriptions_started DESC;


-- ------------------------------------------------------------
-- 2.3e. Usage dropping to zero after prior activity
-- Compares each event to the account's previous event (LAG).
-- A drop to zero after activity is an early churn signal.
-- ------------------------------------------------------------
WITH usage_with_lag AS (
    SELECT
        event_id,
        account_id,
        event_date,
        api_calls,
        active_users,
        LAG(api_calls) OVER (
            PARTITION BY account_id ORDER BY event_date
        ) AS prev_api_calls,
        LAG(active_users) OVER (
            PARTITION BY account_id ORDER BY event_date
        ) AS prev_active_users
    FROM stg_usage_events
)
SELECT
    event_id,
    account_id,
    event_date,
    active_users,
    api_calls,
    prev_active_users,
    prev_api_calls,
    'Usage dropped to zero after previous activity' AS issue
FROM usage_with_lag
WHERE (api_calls = 0 OR active_users = 0)
    AND (prev_api_calls > 0 OR prev_active_users > 0)
ORDER BY account_id, event_date;


-- ------------------------------------------------------------
-- 2.3f. Long-pending subscriptions
-- SUB-026 has been pending since July 2024 — far beyond a
-- normal onboarding window — suggesting a stalled signup or
-- failed payment that was never resolved.
-- ------------------------------------------------------------
SELECT
    subscription_id,
    account_id,
    plan_type,
    status,
    start_date,
    CURRENT_DATE - start_date                        AS days_pending,
    'Subscription has been pending for over 30 days' AS issue
FROM stg_subscriptions
WHERE status = 'pending'
    AND CURRENT_DATE - start_date > 30
ORDER BY days_pending DESC;


-- ------------------------------------------------------------
-- 2.3g. Unusual clustering of usage-event dates
-- Flags any single day with an unusually high number of usage
-- events (> 2x the average events per day). A spike on one
-- date can indicate a bulk load or backfill rather than real
-- activity.
-- ------------------------------------------------------------
SELECT
    event_date,
    COUNT(*)                                   AS events_on_day,
    COUNT(DISTINCT account_id)                 AS distinct_accounts,
    ROUND(AVG(COUNT(*)) OVER (), 1)            AS avg_events_per_day,
    'Unusually high event volume on this date' AS issue
FROM stg_usage_events
GROUP BY event_date
HAVING COUNT(*) > (
    SELECT AVG(daily_count) * 2
    FROM (
        SELECT COUNT(*) AS daily_count
        FROM stg_usage_events
        GROUP BY event_date
    ) daily
)
ORDER BY events_on_day DESC;
