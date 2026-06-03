# currys_analytics_task
Take Home Task

## Repository structure

```
currys-analytics-task/
├── README.md                  ← executive summary + findings narrative
├── data/
│   ├── subscriptions.csv
│   └── usage_events.csv
├── sql/
│   ├── part1_data_quality.sql
│   ├── part2_anomaly_detection.sql
│   ├── part3_data_modelling.sql
│   ├── part4_kpi_analysis.sql
│   └── part5_advanced_analysis.sql
├── setup/
│   └── create_tables.sql      ← DDL / staging definitions
└── screenshots/               ← query output evidence (part1…part5)
```

---

## Part 1 — Data Quality Assessment

A systematic audit was run across both source tables (`subscriptions`, 45 rows;
`usage_events`, 90 rows) covering three dimensions: **completeness** (missing
values), **validity** (impossible or malformed values) and **consistency**
(referential integrity and cross-table alignment). The queries behind every
finding below are in [sql/part1_data_quality.sql](sql/part1_data_quality.sql);
each finding links to the query output.

Throughout, professional and conditional language is used: where a value is
almost certainly a typo it is **flagged with an assumed correct value pending
confirmation from the data owner**, rather than silently "fixed".

> **Note on the loading approach.** In a production setting, data would ideally be
> brought into the warehouse through a dedicated loading/ingestion tool, with the
> expected values and constraints for each column agreed with stakeholders *up
> front* — so malformed or out-of-range records are caught (rejected, quarantined
> or typed) at the point of load. For the purpose of this task I deliberately
> loaded the raw data permissively (minimal typing and no validation at ingest),
> so that the data-quality and anomaly issues remain visible in the tables and can
> be surfaced as clear, queryable outputs rather than being filtered out before
> analysis. The treatments described below would, in production, be encoded as
> load-time contracts and downstream tests.

---

### 1.1 Completeness — missing values

NULLs in the subscriptions table are concentrated in three columns where they
are *expected* by design: `end_date` (88.9% — active subscriptions have no end
date), `trial_end_date` (22.2% — only trials carry one) and `payment_method`
(6.7%). The remaining columns each have a single NULL (2.2%).

![`sub_null_count.png`](./screenshots/part1/sub_null_count.png) · [`sub_pct_null_count.png`](screenshots/part1/sub_pct_null_count.png)

Three subscriptions are missing a revenue-critical field (`mrr_amount`,
`currency` or `billing_period`) and should be excluded from core revenue totals
until backfilled.

[`sub_critical_null_count.png`](screenshots/part1/sub_critical_null_count.png)

Usage data is near-complete: only `active_users` and `api_calls` carry a single
NULL each (1.1%). The two affected events cannot contribute to engagement
metrics and are filtered downstream.

[`usage_null_count.png`](screenshots/part1/usage_null_count.png) · [`usage_pct_null_count.png`](screenshots/part1/usage_pct_null_count.png) · [`usage_critical_null_count.png`](screenshots/part1/usage_critical_null_count.png)

> **Treatment:** NULLs in categorical columns are converted to true NULLs via
> `NULLIF` in staging; no imputation is applied. Downstream models filter or
> handle them explicitly.

---

### 1.2 Validity — impossible or malformed values

**Mixed date formats.** Most dates are `DD/MM/YYYY`, but a few rows are
`MM/DD/YYYY`, detected where the middle (day) segment exceeds 12 — impossible for
a real month. One subscription and two usage events are affected and must be
parsed format-aware to avoid being silently dropped or mis-ordered.

[`sub_invalid_dates.png`](screenshots/part1/sub_invalid_dates.png) · [`usage_invalid_dates.png`](screenshots/part1/usage_invalid_dates.png)

**Impossible date ordering.** One subscription ends before it starts. Assumed to
be a transposed/typo date pair, pending confirmation; excluded from
active-period segmentation in the interim.

[`sub_impossible_dates.png`](screenshots/part1/sub_impossible_dates.png)

**Suspect trial length.** One subscription has a trial period of 372 days
against a typical ≤30, consistent with a year typo (2025 → 2024). Assumed a typo,
pending confirmation from the data owner.

[`sub_suspect_trial_dates.png`](screenshots/part1/sub_suspect_trial_dates.png)

**Negative / zero MRR.** A negative MRR on a Starter plan is structurally invalid
— pricing tiers do not allow negative revenue — and is assumed to be an input
typo (sign error), pending confirmation. A second non-trial active subscription
records no MRR at all.

[`sub_negative_zero_mrr.png`](screenshots/part1/sub_negative_zero_mrr.png)

**MRR anomalies vs. plan rate.** Comparing each MRR against its plan's standard
rate surfaces three issues of distinct character: an extreme outlier at 100× the
Enterprise rate (likely a decimal-placement error), an annual total stored as
MRR (999 × 12 = 11,988, should be the monthly 999), and a Starter charged ~10×
its standard rate. These are **flagged but not corrected** — the true values
require business validation before amendment.

[`sub_mrr_anomalies.png`](screenshots/part1/sub_mrr_anomalies.png)

**Negative `active_users`.** One event records a negative user count — physically
impossible, likely a sign inversion during ETL — and is excluded from engagement
metrics.

[`usage_neg_active_users.png`](screenshots/part1/usage_neg_active_users.png)

**`active_users` outlier.** Against a mean + 2σ threshold (≈55.7, computed with
the extreme spike excluded so it doesn't distort the bound), one event shows a
spurious spike inconsistent with the account's other metrics, while a second
account's high values sit consistently above threshold and read as a genuinely
large account rather than an error.

[`usage_active_users_outliers.png`](screenshots/part1/usage_active_users_outliers.png)

**Inconsistent casing.** One subscription stores `billing_period` as `MONTHLY`
rather than `monthly`. Although semantically identical, it would split `GROUP BY`
and break joins, so it is standardised (lower-cased) before aggregation.

[`sub_billing_casing.png`](screenshots/part1/sub_billing_casing.png)

---

### 1.3 Consistency — referential integrity

**Duplicate `subscription_id` (genuine re-subscription).** SUB-003 (ACC-1003)
appears twice — one churned subscription (01/02/2024–30/04/2024) and one active
re-subscription (20/06/2024–present). Usage events for this account fall
correctly within their respective windows, indicating a genuine re-subscription
rather than a duplicate load. The reuse of the same `subscription_id` across two
distinct lifecycles is nonetheless a data quality issue — each lifecycle should
have a unique identifier.

> **Treatment:** Rather than deduplicating at the view layer (which would destroy
> churn history), date-bounded join logic attributes each usage event to its
> corresponding subscription period, and a surrogate key (`subscription_sk`)
> gives each lifecycle a unique identity. In a production dbt environment this
> would live in an intermediate model, keeping staging a faithful representation
> of source.

[`sub_duplicate_sub_id.png`](screenshots/part1/sub_duplicate_sub_id.png)

**Orphaned usage event.** One event belongs to an account (ACC-8888) with no
record in `subscriptions`. It cannot be attributed to any subscription and is
reported separately as an orphaned account.

[`event_with_no_sub.png`](screenshots/part1/event_with_no_sub.png)

**Usage events outside the subscription window.** After date-bounded matching,
three events fall outside their account's subscription period — two driven by the
inverted SUB-011 dates above, plus one late event on a churned account.
Importantly, ACC-1003's events are correctly attributed across its two windows
and are **not** flagged here, confirming the date-bounded logic works as
intended.

[`events_outside_sub_window.png`](screenshots/part1/events_outside_sub_window.png)

---

### Summary & recommendations

Across both tables the data is largely sound, with a small number of localised
issues: ~3 incomplete revenue rows, a handful of date/format anomalies, and four
MRR values warranting business validation. None are silently overwritten —
structurally invalid values (negative MRR, casing, mixed date formats) are
normalised in staging, while ambiguous values (extreme/annual MRR, inverted
dates) are flagged and quarantined pending confirmation from the data owner.

**Recommendations:** introduce front-end validation on the subscription setup
form (mandatory currency, non-negative MRR, `end_date ≥ start_date`, trial-length
bounds), standardise date and casing formats at ingestion, and enforce a unique
constraint per subscription lifecycle so re-subscriptions receive a fresh
identifier.

---

## Part 2 — Anomaly Detection

Building on the Part 1 audit, Part 2 moves from *is the value valid?* to *is the
value plausible?* — surfacing records that are individually well-formed but
behave abnormally against their statistical, business-logic or behavioural
context. Detection runs across three dimensions: **statistical outliers**,
**business-logic violations** and **pattern anomalies**. Every query is in
[sql/part2_anomaly_detection.sql](sql/part2_anomaly_detection.sql); each finding
links to its output below. As in Part 1, anomalies are **flagged and reported,
not silently corrected** — they are candidates for business review rather than
confirmed errors.

---

### 2.1 Statistical outliers

**MRR outliers by plan type.** Rather than a single global threshold (which
Enterprise plans would always breach legitimately), each MRR is compared against
the mean + 2σ *of its own plan type*. This contextual check is what exposes
ACC-1042 charging 490 on a Starter plan (standard ~49) — an outlier locally that
a global bound would hide beneath the Enterprise figures.

> A global mean + 2σ on MRR is itself skewed by the extreme outlier ACC-1029
> (99,900), which inflates the standard deviation and lifts the upper threshold
> so far that genuine anomalies are masked. Comparing within plan type removes
> this distortion — both the Starter overcharge and the Enterprise outliers read
> as clearly anomalous against their peers.

[`mrr_anomalies_by_plan_type.png`](screenshots/part2/mrr_anomalies_by_plan_type.png)

**Abnormal `api_calls` (global).** Against a mean + 2σ threshold, ACC-1029 stands
out with an api_calls volume roughly an order of magnitude above the next highest
account — consistent with the same account's extreme MRR and active-user spikes,
reinforcing it as a record requiring validation rather than a genuinely large
customer.

[`api_calls_anomalies.png`](screenshots/part2/api_calls_anomalies.png)

**Account-level spikes & drops in `api_calls`.** Global thresholds miss anomalies
that are only abnormal *relative to an account's own baseline*. Comparing each
event to its account average flags spikes (> 2× the account mean) and drops
(< 25% of it) — catching sudden disengagement or burst activity that sits within
the global normal range.

[`api_call_supsect_drops.png`](screenshots/part2/api_call_supsect_drops.png)

> The equivalent `active_users` checks — global mean + 2σ outliers (2.1c) and
> per-account spike/drop detection (2.1e) — apply the same logic but returned no
> rows: once the negative and 999-spike values handled in Part 1.2 are excluded,
> active-user counts fall within expected bounds. No screenshot is shown as there
> is no output to evidence.

---

### 2.2 Business-logic violations

**`end_date` before `start_date`.** A subscription cannot end before it begins.
SUB-011 is the known case; assumed a transposed/typo date pair pending
confirmation, and excluded from active-period segmentation in the interim.

[`Sub_end_before_start_date.png`](screenshots/part2/Sub_end_before_start_date.png)

**Usage events outside any subscription window.** A date-bounded LEFT JOIN
attributes each event to the subscription period it falls within; events that
match no window are returned as anomalies. The four flagged events split across
three causes: two (ACC-1011) fall in the impossible window created by the
inverted SUB-011 dates above; one (ACC-1017, EVT-00034) is a genuine late event
dated one day after its churned subscription's end_date; and one (ACC-8888,
EVT-00048) belongs to the orphaned account with no subscription record at all,
which also appears in the orphaned-events check below.

[`no_sub_window_events.png`](screenshots/part2/no_sub_window_events.png)

**Active status with a past `end_date`.** A subscription marked `active` should
not carry an `end_date` that has already passed. The only row here is ACC-1011 —
the same root cause as the two checks above, not an independent problem. The
subscription is genuinely active, so this reads as a date-entry error rather than
a churned account mislabelled as active: most likely the 10 Mar `end_date` is
wrong and should be `NULL` (the 10 Apr start matches `created_at` and precedes the
`trial_end_date`), though this needs confirmation before fixing.

[`active_status_past_end_date.png`](screenshots/part2/active_status_past_end_date.png)

**Trial expired but status unchanged.** Trials whose `trial_end_date` has passed
while status remains `trial` are stuck mid-onboarding — never converted to a
paying account nor explicitly cancelled. These warrant a sales/onboarding
follow-up and are excluded from both active and churned cohorts.

[`trial_status_unchanged.png`](screenshots/part2/trial_status_unchanged.png)

**Orphaned usage events.** ACC-8888 records usage but has no subscription record
to attribute it to — it cannot be tied to any plan, MRR or lifecycle, and is
reported separately (consistent with the orphaned-account finding in Part 1.3).

[`orphaned_account.png`](screenshots/part2/orphaned_account.png)

**Contradictory usage — zero users, positive activity.** Events recording
`active_users = 0` alongside positive `api_calls` (or session time) are
internally inconsistent: activity implies at least one user. ACC-1037
(EVT-00073, EVT-00074) is the known case, and the pattern suggests the
`active_users` figure failed to record rather than genuine zero usage.

[`zero_active_users_positive_api_calls.png`](screenshots/part2/zero_active_users_positive_api_calls.png)

> An impossible-transition check (2.2c — churned/cancelled subscriptions with no
> `end_date`) returned no rows: every terminal subscription carries a recorded
> end date and positive MRR, confirming they were paying customers rather than
> unconverted trials.

> **On `cancelled` vs `churned`.** The dataset has a single `cancelled`
> subscription (SUB-013) — a 100%-discounted Professional account that ran a trial
> then ended — so it cannot cleanly be read as a paid-plan refund. With only one
> example, the semantic difference between `cancelled` and `churned` cannot be
> reliably inferred and should be confirmed with the business; for analysis both
> are treated as non-active terminal states.

---

### 2.3 Pattern anomalies

**Active subscriptions with zero usage.** Every active paying customer should
generate some usage; its absence signals either a data-pipeline gap or a
genuinely disengaged customer at churn risk.

> ACC-1011 appears here only because its inverted start/end dates (Part 1.2)
> cause the date-bounded join to find no events within its (impossible) window.
> This illustrates how a single upstream data-quality issue can silently corrupt
> a downstream metric — here falsely flagging a paying customer as inactive.

[`active_sub_zero_usage.png`](screenshots/part2/active_sub_zero_usage.png)

**All-zero usage rows.** EVT-00052 (ACC-1026) and EVT-00082 (ACC-1041) record
zero across *every* metric. Distinct from the case above — the account does have
events, they simply contain no data — this pattern reads as a failed collection
event rather than genuine zero usage.

[`all_zero_metrics_events.png`](screenshots/part2/all_zero_metrics_events.png)

**Suspicious discount patterns.** Discounts above 30% materially reduce effective
MRR and may indicate unauthorised or unrecorded deals. Each flagged row reports
its effective MRR and revenue lost so the commercial impact is explicit and the
account can be reviewed.

[`high_discount.png`](screenshots/part2/high_discount.png)

**Long-pending subscriptions.** SUB-026 has sat in `pending` since July 2024 —
far beyond a normal onboarding window — pointing to a stalled signup or failed
payment that was never resolved. These represent unrealised revenue and should be
chased or closed.

[`sub_pending.png`](screenshots/part2/sub_pending.png)

> Two further behavioural checks ran clean (no rows, hence no screenshot):
> unusual clustering of subscription start dates / usage-event dates (2.3d and
> 2.3g — no single date carried a disproportionate volume suggesting a bulk load
> or backfill), and accounts whose usage drops to zero after prior
> activity (2.3e — a windowed `LAG` churn signal). Both remain in the SQL file as
> standing checks for future loads.

---

### Part 2 summary

The dataset's anomalies cluster around a small set of accounts — ACC-1029
(extreme MRR / api_calls / users), ACC-1011 (inverted dates cascading into
false-inactive and out-of-window flags), ACC-1037 (zero-user contradictions) and
ACC-8888 (orphaned) — rather than being broadly distributed. Several Part 2
findings trace directly back to Part 1 root causes, demonstrating how one
upstream defect propagates across multiple downstream metrics. Consistent with
the Part 1 stance, all anomalies are **flagged for business validation, not
overwritten**, and the contextual (per-plan, per-account) thresholds are
deliberately chosen so that legitimately large accounts are not misclassified as
errors.

---

## Part 3 — Data Modelling

Part 3 transforms the cleaned and validated data from Parts 1 & 2 into a dimensional schema:
three intermediate layers (`int_subscriptions`, `int_usage_per_subscription`) encapsulate
all business logic and quality handling, which then feed four dimension and fact tables
(`fct_subscriptions`, `dim_account`, `dim_plan`, `dim_date`). This structure isolates
domain knowledge in one place, keeps fact and dimension tables thin and queryable, and
makes downstream reporting (Part 4) self-contained and auditable.

All queries are in [sql/part3_data_modelling.sql](sql/part3_data_modelling.sql).

---

### 3.1 Intermediate layer — `int_subscriptions`

The first intermediate table applies all subscription-level business logic: currency
conversion to USD, effective MRR calculation after discount, and computed fields that
guard against data-quality issues identified in Parts 1 & 2.

**Key transformations:**

- **`mrr_usd`** — MRR in USD, calculated as `mrr_amount × rate_to_usd`. A NULL rate (unknown
  currency; SUB-044 from Part 1) yields NULL rather than breaking the join.
- **`effective_mrr_usd`** — MRR after discount: `mrr_amount × rate_to_usd × (1 − discount_percentage / 100)`.
- **`subscription_length_days`** — Days between start and end. If start > end (SUB-011), returns
  NULL and the issue is flagged in `data_quality_flag`. Length is computed as either end − start
  (churned subs) or today − start (active subs).
- **`trial_length_days`** — Days from trial start to end. Anomalies are guarded: if trial
  end is before start or exceeds 90 days (SUB-045), the field is NULL and flagged.
- **`billing_cycle_days`** — Mapped from billing_period (monthly = 30, quarterly = 90, annual = 365).
  No renewal-period data exists in the dataset, so `days_until_renewal` is omitted as requiring
  a billing-events source rather than fabricated from an arbitrary anchor.
- **`data_quality_flag`** — Consolidates all anomalies from Parts 1 & 2 (inverted dates, suspect
  trial length, zero/negative MRR, unknown currency, plan-level MRR anomalies, outliers) into
  a single flag surfaced downstream. Values are not corrected — they are flagged for business
  review and excluded from core metrics where appropriate.

[`int_subscription_output.png`](screenshots/part3/int_subscription_output.png)

> **On calculated fields and missing data.** The dataset contains no subscription upgrades or
> mid-life changes; ACC-1003 (the sole account with two subscription records) represents a
> churn and re-subscription, not an upgrade. The surrogate-key pattern (`subscription_sk`) and
> date-bounded join logic in `int_usage_per_subscription` are designed to handle upgrades
> correctly — each lifecycle gets a unique key, and usage is attributed to the right period.
> Were upgrade data present, the model would naturally extend without modification.

---

### 3.2 Intermediate layer — `int_usage_per_subscription`

The second intermediate table aggregates usage events to the subscription grain via a
date-bounded FULL OUTER JOIN, preserving both matched and orphaned records. This is the
first place where subscription-level aggregates (total API calls, average session duration, etc.)
are computed and orphaned accounts are formally flagged.

**Join logic:**

Each usage event is matched to a subscription based on date:
- Account ID matches *and*
- Event date ≥ subscription start_date *and*
- Event date ≤ subscription end_date (or NULL if still active)

A **FULL OUTER JOIN** ensures:
- Events matching a subscription are attributed to it (one row per subscription_sk)
- Events with no matching subscription are preserved and flagged as orphaned (one row per orphaned account_id)

**Orphan flag:**

```
CASE
  WHEN subscription_sk IS NULL AND no subscription record exists for this account
    THEN 'no_subscription_record'      — (e.g., ACC-8888)
  WHEN subscription_sk IS NULL
    THEN 'usage_outside_subscription_window' — (e.g., ACC-1011, ACC-1017)
  ELSE NULL
END
```

**Grain:** One row per subscription (matched or orphaned), with aggregated usage metrics.

[`int_usage_subscription_output.png`](screenshots/part3/int_usage_subscription_output.png)

> **On ACC-1011.** This account's start and end dates are inverted (start 10/04/2024,
> end 10/03/2024, per Part 1.2), creating an empty subscription window. No usage event
> can fall within an empty window, so its two usage events surface as separate rows flagged
> `usage_outside_subscription_window`. The subscription itself appears with zero attributed
> usage (because the window is empty) and is tagged `inverted_dates` in `int_subscriptions`.
> Both rows stem from the same root cause and would reconcile immediately if the dates
> were corrected at source — the data is deliberately left uncorrected to ensure the error
> is not silently buried.

---

### 3.3 Fact table — `fct_subscriptions`

The fact table is a LEFT JOIN of `int_usage_per_subscription` (left side, to preserve orphaned
accounts) onto `int_subscriptions`, pairing usage aggregates with subscription attributes.

**Key design decisions:**

- Keys come from `int_usage_per_subscription` (including orphaned accounts); subscription
  attributes are LOJ from `int_subscriptions`, yielding NULLs for ACC-8888.
- Usage metrics include `COALESCE(usage_event_count, 0)` so orphaned accounts show 0 events
  rather than NULL, and `has_usage` is a boolean flag for quick filtering.
- `data_quality_flag` is taken from the usage layer (`orphan_flag`) if present, otherwise
  from the subscription layer. This precedence ensures that an account's fundamental issue
  (orphaned vs. valid subscription) is surfaced first.

**Grain:** One row per subscription lifecycle (matched) or per orphaned account.

[`fct_subscription_output.png`](screenshots/part3/fct_subscription_output.png)

---

### 3.4 Dimension tables

**`dim_account` — Account dimension (current state only)**

One row per account, capturing the latest subscription (by start_date DESC) and whether the
account is currently active, churned, or orphaned. Orphaned accounts (ACC-8888) are unioned
in with all subscription columns set to NULL.

[`dim_account.png`](screenshots/part3/dim_account.png)

**`dim_plan` — Plan dimension**

One row per plan type in the dataset, with surrogate fields for tier (0–4 ordering) and
list price. COALESCE ensures NULLs (orphaned accounts with no plan) map to 'unknown', preserving
referential integrity with the fact table.

[`dim_plan.png`](screenshots/part3/dim_plan.png)

**`dim_date` — Date dimension**

One row per calendar day in the 2024 range, with fields for month, quarter, year, and
year-month (useful for monthly and quarterly time-series joins in Part 4).

[`dim_date.png`](screenshots/part3/dim_date.png)

---

### 3.5 Key design principles

**Explicit handling of data-quality issues.** Rather than silently filtering or correcting
anomalies, the model surfaces them in `data_quality_flag` and in the orphan_flag, allowing
downstream consumers to decide whether to include or exclude each row. This preserves
auditability: a metric can be stated both with and without flagged rows, making the impact
of each issue explicit.

**No imputation or fabrication.** The dataset contains no renewal or billing-cycle data,
so `days_until_renewal` is omitted rather than invented. Similarly, no plan upgrades or
bulk-fill events are detected, so the simpler subscription-per-account model is used rather
than over-engineered for cases that may never occur.

**Surrogate keys for lifecycle management.** Each subscription gets a unique `subscription_sk`
so that ACC-1003's churn-and-re-subscription is recorded as two distinct lifecycles, and
usage events are correctly attributed to the period they occurred in. This pattern naturally
extends to handle mid-subscription upgrades should they arise.

**Canonical join logic.** The date-bounded join (event_date within subscription window) is
implemented once in `int_usage_per_subscription` and reused downstream, ensuring consistency
and reducing redundant logic in ad-hoc queries.

---

### Part 3 summary

The dimensional schema successfully encapsulates all data-quality and business-logic handling
in two intermediate tables, leaving the fact and dimension tables clean and efficient for
downstream reporting. Orphaned and anomalous records are preserved and flagged rather than
dropped, enabling transparent, auditable metrics.

---

## Part 4 — KPI Analysis & Churn Risk Scoring

Part 4 transforms the modelled data from Part 3 into four business-critical analyses: **revenue
trends and composition**, **churn signals and retention curves**, **product engagement and
feature adoption**, and **forward-looking customer health scores for at-risk account
identification**. All queries are in [sql/part4_kpi_analysis.sql](sql/part4_kpi_analysis.sql);
screenshots from each analysis are linked below.

---

### 4.1 Revenue Metrics

**4.1a – Monthly MRR (clean vs all rows, side-by-side)**

Shows active MRR month-over-month in two columns: one excluding distorting outliers
(ACC-1029 at 99,900 USD, ACC-1009 at 11,988 USD), and one including all subscriptions. The
split makes it explicit how much the outliers skew the total — useful for board reporting
where "clean" and "actuals-including-anomalies" are both interesting.

[`mrr_active_clean_and_all_rows.png`](screenshots/part4/mrr_active_clean_and_all_rows.png)

**4.1b – MRR Growth Rate (month-over-month %)**

Calculates the month-over-month percentage change in clean MRR (outliers excluded), with a
LAG window function. Allows tracking momentum independent of data anomalies.

[`mrr_growth_pct_based_on_clean.png`](screenshots/part4/mrr_growth_pct_based_on_clean.png)

**4.1c – Average Revenue Per Account (ARPA)**

Total active MRR divided by the count of distinct active accounts. Shows per-account efficiency
(higher ARPA = better monetization or higher-tier mix). Computed on clean MRR to avoid
distortion from outliers.

[`arpa_clean.png`](screenshots/part4/arpa_clean.png)

**4.1d – Revenue by Plan Type and Customer Segment**

Breaks down effective MRR (post-discount, in USD) by plan tier (Starter/Basic/Professional/Enterprise)
and customer segment. Identifies which segments and tiers drive revenue and which are underutilised.

[`revenue_plan_segment.png`](screenshots/part4/revenue_plan_segment.png)

> **Note on outlier handling:** ACC-1029 (99,900) is excluded from MRR metrics to prevent skew.
> ACC-1009 (11,988, an annual total stored as MRR) is similarly flagged and excluded. Both are
> included in the "all rows" column for transparency. In production, these would be corrected at
> source before finalising reports.

---

### 4.2 Churn Metrics

**4.2a – Monthly Logo (Customer) Churn Rate**

Churn % = (customers churned in the month) / (customers active at the start of the month) × 100.

Counts are head-counts (number of accounts), not revenue. The denominator is subscriptions that
existed at month-start. Only `inverted_dates` is filtered (date quality issues corrupt the
calculation); MRR outliers are irrelevant to a head-count metric.

[`monthly_logo_churn_rate.png`](screenshots/part4/monthly_logo_churn_rate.png)

**4.2b – Monthly Revenue (MRR) Churn Rate**

Revenue churn % = (MRR lost to churn in the month) / (MRR active at month-start) × 100.

Shows the revenue impact of churn independently of customer count. A small number of high-value
accounts churning creates large revenue churn even if logo churn is low. Both metrics are needed
for a complete picture.

[`monthly_revenue_churn_rate.png`](screenshots/part4/monthly_revenue_churn_rate.png)

**4.2c – Cohort Retention Analysis**

Groups subscriptions by their start month (cohort), then shows how many survived vs. churned
over their lifetime. With only 3 churn events across the entire dataset, this is **directional
only** — a true multi-month retention curve (month 1, month 2, month 3 retention) cannot be
reliably computed with so little churn.

[`cohort_analysis.png`](screenshots/part4/cohort_analysis.png)

**4.2d – Average Customer Lifetime**

Restricted to genuinely churned customers (status = `churned`), calculates the average tenure
from first subscription start to final churn. Excludes still-active accounts (right-censored,
incomplete lifetimes). ACC-1003 (re-subscribed) is counted as still active.

With a sample of 2–3 churned customers, this metric is **highly directional**.

[`average_customer_lifetime.png`](screenshots/part4/average_customer_lifetime.png)

---

### 4.3 Usage & Engagement Metrics

**Important caveat:** The usage dataset has no `user_id`, only `active_users` headcount per event.
"Active Users" here = distinct **accounts** with activity in the period (DAU/WAU/MAU all refer to
active account counts, not individual users). The `active_users` field can be summed within a
single day but NOT across weeks/months (else individuals appear multiple times).

**4.3a – Daily/Weekly/Monthly Active Users (DAU/WAU/MAU)**

Captures all usage activity directly from `stg_usage_events` (including orphaned accounts outside
any subscription). Only the 999-user spike (Part 2.1) is excluded as a clear data error. The time
series is continuous (zero-activity days/weeks/months are shown as 0 rather than skipped) via a
LEFT JOIN to `dim_date`.

Usage data is sparse (~90 events across the year), so DAU and WAU are thin. MAU is the most
meaningful grain.

[`daily_active_users.png`](screenshots/part4/daily_active_users.png) · [`weekly_active_users.png`](screenshots/part4/weekly_active_users.png) · [`monthly_active_users.png`](screenshots/part4/monthly_active_users.png)

**4.3b – Feature Adoption Rates**

% of subscriptions (with usage) that adopted each of the three features (Feature A, B, C) at
least once. Shows which features resonate and which are underused. Orphaned accounts (usage
with no subscription record) are excluded.

[`feature_adoption_pct.png`](screenshots/part4/feature_adoption_pct.png)

**4.3c – Usage Intensity by Subscription Tier**

Average engagement metrics (active users, API calls, session duration, projects created,
integrations, support tickets) broken down by plan type. Reveals whether higher-tier plans have
higher engagement (a positive signal for upgrade-readiness) or similar usage patterns (suggesting
upsell opportunity or tier misalignment).

[`usage_intensity_sub_tier.png`](screenshots/part4/usage_intensity_sub_tier.png)

**4.3d – Correlation Between Usage and Retention**

Compares average engagement (active users, API calls, session time, feature adoption) between
retained (active) and churned subscriptions. If active customers use the product significantly
more, this is strong evidence that engagement drives retention and should inform retention
campaigns.

[`correlation_usage_retention.png`](screenshots/part4/correlation_usage_retention.png)

---

### 4.4 Customer Health Score & At-Risk Identification

A **two-tier early-warning system** combining explicit at-risk flags with a composite health score.

#### Design & Methodology

**At-Risk Flags** (immediate business action):
1. **Active but zero usage** — Most predictive churn signal; customer is paying but not engaging.
2. **Data quality outliers** — ACC-1029 / ACC-1009 (usage untrustworthy); unscored, marked "Unscoreable: data quality issue".

**Health Score (0–100)** — Composite signal for live, scoreable accounts (active + trial):

Four weighted components, each normalized 0–1 on the **non-outlier population max**:

- **Usage Engagement (45%)** — Average of three metrics (active users, session duration, integrations)
  normalized against non-outlier peers. Largest weight; engagement is the strongest churn predictor.
- **Payment Tenure (20%)** — Subscription length × (1 − discount %), capturing commitment
  (longer tenure + lower discount = more invested). Accounts with high discount risk churn faster.
- **Feature Adoption (20%)** — Count of 3 features used, normalized to 0–1. Breadth of engagement.
- **Support Health (15%)** — Inverted support tickets relative to usage engagement. High support
  + low usage = risky. Accounts with zero usage get a neutral 0.5 (flagged separately).

**Weights Rationale:** Based on SaaS churn literature: engagement (45%) is the strongest signal,
tenure (20%) captures commitment, features (20%) show breadth of adoption, and support (15%)
identifies technical friction.

**Banding:** 
- Score < 40 = "At risk"
- Score 40–70 = "Moderate"  
- Score ≥ 70 = "Healthy"

#### Design Notes

**Why API calls are excluded:** API calls is the most outlier-prone metric in the dataset
(ACC-1029 at 50,000+ vs. ~3,000 mean) and has a NULL value. Replaced with active users +
session duration + integrations — more stable and interpretable.

**Why trials are scored:** Trials are live accounts. Their engagement relative to peers predicts
conversion likelihood. A well-engaged trial converts; a disengaged trial churns. Both are scored
and banded normally.

**Why ACC-1042 (MRR anomaly) IS scored:** ACC-1042's anomaly is confined to MRR (Starter charged
490 vs. 49 standard). Its **usage data is trustworthy**, so it scores. The MRR outlier flag is
separate from usage flags.

**Outliers excluded from normalization:** ACC-1029 / ACC-1009 are excluded when computing
max(engagement) for the bounds CTE. This prevents their extreme usage from inflating the scale
and flattening scores for normal accounts.

**Limitations:** Weights are reasoned judgment, not calibrated against actual churn in this
dataset. Scores are relative to the scored population — they shift as the cohort changes (e.g.,
adding a very-high-engagement account raises the max and lowers others' relative scores).

[`health_score.png`](screenshots/part4/health_score.png)

---

### Part 4 summary

Revenue and churn metrics provide the business context (active MRR, churn %, customer lifetime);
usage and engagement metrics reveal product-market fit (DAU/WAU/MAU, feature adoption, intensity
by tier); and the health score enables proactive churn prevention by highlighting high-risk
accounts for intervention.

The health score intentionally **surfaces zero-usage accounts with explicit warnings** rather
than burying them in a low numeric score. Outlier accounts are kept visible but unscored, so
they remain in reports without misleading the business with fabricated quality metrics.

---

## Part 5 — Advanced Analysis: Product-Market Fit

Part 5 moves from *how is the business performing?* (Part 4) to *where does the product fit
best?* — using the engagement signals in `fct_subscriptions` to identify which segments
resonate most strongly and which accounts represent the clearest product-market fit (PMF).
All queries are in [sql/part5_advanced_analysis.sql](sql/part5_advanced_analysis.sql); each
finding links to its output below.

> **Outlier handling.** Consistent with Parts 1–4, the MRR outliers flagged earlier
> (`mrr_outlier_extreme`, `mrr_outlier_high` — principally ACC-1029 at 99,900) are excluded
> from every Part 5 query so engagement figures are not distorted by accounts whose data is
> known to be untrustworthy. Orphaned accounts (no `subscription_id`) are likewise excluded,
> since they cannot be attributed to a segment or plan.

---

### 5.1 Usage patterns by customer segment

Average engagement per segment, showing where the product is used most intensively. A clear
gradient emerges: **Enterprise > Mid-Market > SMB** on every intensity measure.

| Segment | Accounts | Avg active users | Avg session mins | Avg integrations | Avg feature usage | Avg features adopted |
|---|---|---|---|---|---|---|
| Enterprise | 17 | 13.3 | 468.3 | 4.5 | 237.2 | 3.00 |
| Mid-Market | 8 | 7.5 | 341.4 | 3.0 | 122.0 | 2.63 |
| SMB | 17 | 2.1 | 83.2 | 0.6 | 23.4 | 2.18 |

Enterprise accounts run roughly **6× the active users and 10× the total feature usage** of SMB
accounts, and adopt all three features on average (3.00) versus ~2.2 for SMB. This points to
PMF being strongest in the Enterprise segment, with Mid-Market sitting consistently between the
two. The relationship is monotonic across active users, session time, integrations and feature
breadth — not a single skewed metric — which strengthens the read.

> **Context / caveat.** `avg_usage_events` is essentially flat across segments (~1.8–1.9)
> because the usage dataset is sparse (~90 events across the year), so each account carries only
> a handful of events regardless of segment. Event *count* is therefore not a discriminating
> signal here; the intensity metrics (active users, session time, feature usage) are what
> separate the segments.

[`usage_customer_segment.png`](screenshots/part5/usage_customer_segment.png)

---

### 5.2 Power users — clearest product-market fit

Active and trial accounts are split into usage **quartiles** with `NTILE(4)` over a composite
engagement measure (active users + scaled session time + usage events); the **top quartile** is
read as the power-user cohort. These are the accounts demonstrating the strongest fit and the
best reference candidates for expansion and case studies.

The top quartile is dominated by **Enterprise-segment, Enterprise-plan accounts**, all of which
have adopted all three features. ACC-1001 is the one exception — an Enterprise-segment account
still on the Professional plan, making it a natural **upsell candidate** (high engagement, room
to move up a tier).

> **Outlier caveat — read with care.** ACC-1009 tops the list with ~514 average active users
> and ~955 session minutes, an order of magnitude above the other power users (~20–25 users,
> ~600–790 mins). This is the same account flagged in Parts 1–2 as an *annual total stored as
> monthly MRR* (11,988). Its usage figures look correspondingly inflated and should be treated
> as **suspect pending confirmation** rather than a genuine super-user — it is retained here
> only because it does not carry the `mrr_outlier_extreme`/`high` flags used for exclusion, and
> it is called out so it does not silently overstate the cohort. ACC-9999 also appears with high
> per-event activity (18 active users) but only a single usage event, so its ranking rests on a
> thin base and is best read as directional.

[`power_users.png`](screenshots/part5/power_users.png)

---

### 5.3 Power-user profile — who are the best-fit customers?

Aggregating the top quartile by segment and plan characterises the best-fit customer in one
line: **Enterprise segment on the Enterprise plan** (8 of 9 power users), with the single
remaining power user being the Enterprise-segment / Professional-plan account from 5.2.

| Segment | Plan | Power users |
|---|---|---|
| Enterprise | Enterprise | 8 |
| Enterprise | Professional | 1 |

The concentration is unambiguous: product-market fit is strongest among Enterprise-segment
accounts on the Enterprise tier. This supports focusing acquisition and customer-success
investment on the Enterprise segment, while treating high-engagement accounts on lower tiers
(e.g. ACC-1001) as priority upsell targets.

[`power_users_aggregated.png`](screenshots/part5/power_users_aggregated.png)

---

### Part 5 summary

The product resonates most strongly with the **Enterprise segment**, which leads every
engagement dimension and supplies almost the entire power-user cohort, with Mid-Market a
consistent middle and SMB the lightest users. The clearest fit is the Enterprise-segment /
Enterprise-plan account, and the most actionable individual signal is a highly engaged account
sitting on a lower tier than its usage warrants (ACC-1001) — a ready-made upsell. As elsewhere,
known data-quality outliers are excluded from the metrics, and the one flagged account that
survives the exclusion filter (ACC-1009) is explicitly called out so the cohort is not
overstated. With usage data this sparse, the segment-level gradient is robust while
individual power-user rankings are best read as **directional**.
