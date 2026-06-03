-- ============================================================
-- SEED: EXCHANGE RATES
-- ============================================================
-- Indicative fixed rates to USD. In production this would be
-- a dated rates table (one row per currency per day) joined on
-- the subscription's relevant date. Fixed rates used here as a
-- documented simplification for the task.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS seed_exchange_rates;

CREATE TABLE seed_exchange_rates (
    currency     VARCHAR(10) PRIMARY KEY,
    rate_to_usd  NUMERIC(10,4)
);

INSERT INTO seed_exchange_rates (currency, rate_to_usd) VALUES
    ('USD', 1.0000),
    ('EUR', 1.0800),
    ('GBP', 1.2700);
    