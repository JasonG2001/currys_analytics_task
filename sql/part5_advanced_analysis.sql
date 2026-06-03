-- ============================================================
-- PART 5: ADVANCED ANALYSIS — PRODUCT-MARKET FIT
-- ============================================================
-- Where does the product fit best, and which accounts represent
-- the clearest product-market fit (PMF)?
--   5.1  Usage patterns by customer segment
--   5.2  Power users (top usage quartile)
--   5.3  Power-user profile (who the best-fit customers are)
--
-- All queries read from fct_subscriptions. Orphaned accounts
-- (subscription_id IS NULL) and the known MRR outliers
-- (mrr_outlier_extreme / mrr_outlier_high, principally ACC-1029)
-- are excluded so engagement figures stay trustworthy.
-- ============================================================


-- ------------------------------------------------------------
-- 5.1  Usage patterns by customer segment
-- Average engagement per segment — shows which segments use the
-- product most intensively, i.e. where PMF is strongest.
-- ------------------------------------------------------------
SELECT
    customer_segment,
    COUNT(*)                                  AS accounts,
    ROUND(AVG(avg_active_users), 1)           AS avg_active_users,
    ROUND(AVG(avg_session_duration_mins), 1)  AS avg_session_mins,
    ROUND(AVG(avg_integrations_used), 1)      AS avg_integrations,
    ROUND(AVG(usage_event_count), 1)          AS avg_usage_events,
    ROUND(AVG(total_feature_a_usage
            + total_feature_b_usage
            + total_feature_c_usage), 1)      AS avg_total_feature_usage,
    -- adoption breadth: avg number of the 3 features used
    ROUND(AVG(
        CASE WHEN total_feature_a_usage > 0 THEN 1 ELSE 0 END
      + CASE WHEN total_feature_b_usage > 0 THEN 1 ELSE 0 END
      + CASE WHEN total_feature_c_usage > 0 THEN 1 ELSE 0 END
    ), 2)                                     AS avg_features_adopted
FROM fct_subscriptions
WHERE subscription_id IS NOT NULL
    AND customer_segment IS NOT NULL
    AND (data_quality_flag IS NULL
         OR data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high'))
GROUP BY customer_segment
ORDER BY avg_usage_events DESC;


-- ------------------------------------------------------------
-- 5.2  Power users
-- The most engaged accounts — the top tier of usage. Active and
-- trial accounts are split into quartiles by a composite measure
-- (active users + scaled session time + usage events); the top
-- quartile is the power-user cohort and represents the clearest PMF.
-- ------------------------------------------------------------
WITH engaged AS (
    SELECT
        account_id,
        plan_type,
        customer_segment,
        status,
        avg_active_users,
        avg_session_duration_mins,
        usage_event_count,
        CASE WHEN total_feature_a_usage > 0 THEN 1 ELSE 0 END
      + CASE WHEN total_feature_b_usage > 0 THEN 1 ELSE 0 END
      + CASE WHEN total_feature_c_usage > 0 THEN 1 ELSE 0 END AS features_adopted,
        NTILE(4) OVER (
            ORDER BY
                COALESCE(avg_active_users, 0)
              + COALESCE(avg_session_duration_mins, 0) / 60.0   -- scale mins into a comparable range
              + usage_event_count
        ) AS usage_quartile
    FROM fct_subscriptions
    WHERE subscription_id IS NOT NULL
        AND status IN ('active', 'trial')
        AND (data_quality_flag IS NULL
             OR data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high'))
)
SELECT
    account_id,
    plan_type,
    customer_segment,
    status,
    avg_active_users,
    avg_session_duration_mins,
    features_adopted,
    usage_event_count
FROM engaged
WHERE usage_quartile = 4          -- top quartile = power users
ORDER BY usage_event_count DESC, avg_active_users DESC;


-- ------------------------------------------------------------
-- 5.3  Power-user profile — what do power users have in common?
-- Summarises the top quartile by segment and plan to characterise
-- who the best-fit customers are.
-- ------------------------------------------------------------
WITH engaged AS (
    SELECT
        plan_type,
        customer_segment,
        NTILE(4) OVER (
            ORDER BY
                COALESCE(avg_active_users, 0)
              + COALESCE(avg_session_duration_mins, 0) / 60.0
              + usage_event_count
        ) AS usage_quartile
    FROM fct_subscriptions
    WHERE subscription_id IS NOT NULL
        AND status IN ('active', 'trial')
        AND (data_quality_flag IS NULL
             OR data_quality_flag NOT IN ('mrr_outlier_extreme', 'mrr_outlier_high'))
)
SELECT
    customer_segment,
    plan_type,
    COUNT(*) AS power_users
FROM engaged
WHERE usage_quartile = 4
GROUP BY customer_segment, plan_type
ORDER BY power_users DESC;
