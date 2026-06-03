-- Create subscriptions table
CREATE TABLE subscriptions (
    subscription_id      VARCHAR(225),
    account_id           VARCHAR(225),
    plan_type            VARCHAR(225),
    status               VARCHAR(225),
    mrr_amount           NUMERIC(12,2),
    currency             VARCHAR(225),
    start_date           VARCHAR(225),   -- kept as VARCHAR initially due to mixed date formats
    end_date             VARCHAR(225),
    trial_end_date       VARCHAR(225),
    created_at           VARCHAR(225),
    updated_at           VARCHAR(225),
    billing_period       VARCHAR(225),
    customer_segment     VARCHAR(225),
    payment_method       VARCHAR(225),
    discount_percentage  NUMERIC(10,2)
);


-- Create usage_events table
CREATE TABLE usage_events (
    event_id                VARCHAR(225),
    account_id              VARCHAR(225),
    event_date              VARCHAR(225),   -- VARCHAR for same reason
    active_users            NUMERIC(10,2),
    api_calls               NUMERIC(10,2),
    storage_gb              NUMERIC(8,2),
    projects_created        INT,
    integrations_used       INT,
    support_tickets         INT,
    feature_a_usage         INT,
    feature_b_usage         INT,
    feature_c_usage         INT,
    session_duration_mins   NUMERIC(10,2),
    mobile_usage_mins       NUMERIC(10,2)
);
