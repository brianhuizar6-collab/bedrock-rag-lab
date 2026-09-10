-- ============================================================================
-- Schema — Usage Metering & Billing Pipeline
-- Document owner: Data Engineering, Billing Platform
-- Classification: Internal
-- Version: 1.0
-- Last updated: 2026-09-10
--
-- This is the authoritative physical schema for the pipeline's four core
-- tables. It must stay consistent with data_dictionary.md — if you change
-- one, change the other in the same commit.
-- ============================================================================

CREATE TABLE customers (
    customer_id      VARCHAR(32)     NOT NULL,
    account_name     VARCHAR(120)    NOT NULL,
    plan_code        VARCHAR(20)     NOT NULL,
    signup_date      DATE            NOT NULL,
    billing_country  CHAR(2)         NOT NULL,
    status           VARCHAR(20)     NOT NULL DEFAULT 'TRIAL',
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT chk_customer_plan_code CHECK (
        plan_code IN ('STARTER', 'GROWTH', 'SCALE', 'ENTERPRISE')
    ),
    CONSTRAINT chk_customer_status CHECK (
        status IN ('TRIAL', 'ACTIVE', 'PAST_DUE', 'CANCELED')
    )
);

CREATE TABLE subscriptions (
    subscription_id  VARCHAR(32)     NOT NULL,
    customer_id      VARCHAR(32)     NOT NULL,
    plan_code        VARCHAR(20)     NOT NULL,
    billing_cycle    VARCHAR(10)     NOT NULL,
    start_date       DATE            NOT NULL,
    end_date         DATE,
    status           VARCHAR(20)     NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT pk_subscriptions PRIMARY KEY (subscription_id),
    CONSTRAINT fk_subscriptions_customer FOREIGN KEY (customer_id)
        REFERENCES customers (customer_id),
    CONSTRAINT chk_subscription_billing_cycle CHECK (
        billing_cycle IN ('MONTHLY', 'ANNUAL')
    ),
    CONSTRAINT chk_subscription_status CHECK (
        status IN ('ACTIVE', 'PAUSED', 'CANCELED')
    )
);

CREATE TABLE usage_events (
    event_id         VARCHAR(32)     NOT NULL,
    subscription_id  VARCHAR(32)     NOT NULL,
    event_ts         TIMESTAMP       NOT NULL,
    metric_type      VARCHAR(20)     NOT NULL,
    quantity         DECIMAL(14,4)   NOT NULL,
    unit_cost        DECIMAL(10,6)   NOT NULL,
    source_system    VARCHAR(30)     NOT NULL,
    CONSTRAINT pk_usage_events PRIMARY KEY (event_id),
    CONSTRAINT fk_usage_events_subscription FOREIGN KEY (subscription_id)
        REFERENCES subscriptions (subscription_id),
    CONSTRAINT chk_usage_quantity_positive CHECK (quantity > 0),
    CONSTRAINT chk_usage_metric_type CHECK (
        metric_type IN ('API_CALLS', 'STORAGE_GB', 'SEATS', 'COMPUTE_MINUTES')
    ),
    CONSTRAINT chk_usage_source_system CHECK (
        source_system IN ('API_GATEWAY', 'STORAGE_SERVICE', 'SEAT_MANAGER', 'COMPUTE_SCHEDULER')
    )
);

CREATE TABLE invoices (
    invoice_id            VARCHAR(32)   NOT NULL,
    subscription_id       VARCHAR(32)   NOT NULL,
    billing_period_start  DATE          NOT NULL,
    billing_period_end    DATE          NOT NULL,
    amount_due             DECIMAL(12,2) NOT NULL,
    status                VARCHAR(20)   NOT NULL DEFAULT 'DRAFT',
    generated_ts          TIMESTAMP     NOT NULL,
    paid_ts               TIMESTAMP,
    CONSTRAINT pk_invoices PRIMARY KEY (invoice_id),
    CONSTRAINT fk_invoices_subscription FOREIGN KEY (subscription_id)
        REFERENCES subscriptions (subscription_id),
    CONSTRAINT chk_invoice_status CHECK (
        status IN ('DRAFT', 'ISSUED', 'PAID', 'OVERDUE', 'VOID')
    )
);

-- Indexes supporting the hourly ingestion and monthly billing run
-- (see pipeline_README.md, "Ingestion" and "Rating and invoice generation")
CREATE INDEX idx_usage_events_subscription_ts ON usage_events (subscription_id, event_ts);
CREATE INDEX idx_subscriptions_customer_id ON subscriptions (customer_id);
CREATE INDEX idx_invoices_subscription_period ON invoices (subscription_id, billing_period_start);
