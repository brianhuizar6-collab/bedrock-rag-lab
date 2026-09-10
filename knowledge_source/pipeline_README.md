# Pipeline README — Usage Metering & Billing

**Document owner:** Data Engineering, Billing Platform
**Classification:** Internal
**Version:** 1.0
**Last updated:** 2026-09-10

## Purpose

This pipeline collects metered usage from four source systems throughout the day,
converts that usage into monetary amounts, and generates one invoice per subscription
per billing period. It also computes billing KPIs for the finance and platform teams.

## Schedule

- **Usage ingestion** runs every hour, at 5 minutes past the hour, picking up the usage
  events each source system reported in the prior hour.
- **Invoice generation** runs once per calendar month, on the 1st day at **03:00 UTC**,
  and covers the entire prior calendar month as the billing period.

## Ingestion

1. Each of the four source systems (`API_GATEWAY`, `STORAGE_SERVICE`, `SEAT_MANAGER`,
   `COMPUTE_SCHEDULER`) delivers an hourly CSV batch of `usage_events` to the ingestion
   landing zone.
2. Every batch is validated against the schema in `schema.sql` before being accepted.
   Rows that fail validation are routed to quarantine and are not included in billing.
3. Accepted events are loaded into a staging table, keyed by `event_id`, ahead of the
   monthly rating step.

## Rating and invoice generation

- Once a billing period closes, the monthly run aggregates all accepted `usage_events`
  for each `subscription_id`, grouped by `metric_type`, over the billing period.
- For each metric, the aggregated `quantity` is multiplied by that event's `unit_cost`,
  and the results are summed across all metrics to produce `amount_due` on a new
  `invoices` row.
- Exactly one invoice is generated per subscription per billing period — a subscription
  with zero usage in a period still receives an invoice with `amount_due = 0.00`, unless
  the subscription's `status` was `CANCELED` before the period started.

## Proration

- A subscription that starts or is canceled partway through a billing period is prorated
  by day count: usage is billed normally, but any period-based charges (none currently
  defined beyond usage-based billing) would be scaled by the fraction of the period the
  subscription was active. Usage-based metrics themselves are never prorated — they are
  billed for exactly the usage that occurred, which naturally reflects partial-period
  activity.

## Late usage events

- A usage event that arrives **after** its billing period's invoice has already been
  generated is not used to reissue or void that invoice. Instead, it is carried forward
  and appended as an adjustment line to the **next** billing period's invoice, along with
  a reference back to the original period it belongs to.
- This behavior is a deliberate business rule to keep already-issued invoices immutable
  once generated, rather than a limitation of the ingestion process.

## KPIs computed after each billing run

- **Billing accuracy rate**: percentage of generated invoice lines that required no
  correction after issuance.
- **On-time invoice generation rate**: percentage of billing periods for which the
  invoice was generated within the scheduled monthly run, without manual intervention.
- **Average time to correct a disputed invoice line**: mean time between a dispute being
  opened and the corresponding adjustment being applied.
- **Usage-to-subscription match rate**: percentage of ingested usage events that mapped
  to a subscription that was active at the time of the event.

This README does not publish live values for these KPIs — those are runtime metrics, not
part of this document set.

## Failure handling and retries

- If an hourly usage batch from a source system does not arrive on schedule, ingestion
  retries pulling it every 15 minutes for up to 2 hours before alerting the on-call
  distribution list.
- If the monthly billing run cannot complete for a subscription (for example, missing
  rate information), that subscription's invoice is left in `DRAFT` status and excluded
  from the batch of invoices marked `ISSUED`, rather than blocking the rest of the run.
- The monthly billing run is idempotent for a given billing period: re-running it
  recomputes and overwrites `DRAFT` invoices for that period rather than creating
  duplicates. It does not modify invoices already in `ISSUED` or later statuses.

## Outputs

- New or updated `invoices` rows for the billing period processed.
- A monthly KPI summary record.
- A notification to the finance queue for any invoice whose adjustment (from a late
  usage event, see above) exceeds the materiality threshold defined in
  `data_quality_rules.md`.

## Related documents

- `data_dictionary.md` — column-level definitions for every table referenced here.
- `schema.sql` — physical schema (DDL) for the four core tables.
- `data_quality_rules.md` — validation rules, thresholds, and the exception/adjustment
  taxonomy.
