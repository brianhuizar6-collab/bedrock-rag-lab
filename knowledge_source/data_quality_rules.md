# Data Quality Rules — Usage Metering & Billing Pipeline

**Document owner:** Data Engineering, Billing Platform
**Classification:** Internal
**Version:** 1.0
**Last updated:** 2026-09-10

This document defines the validation rules applied at ingestion, the exception/adjustment
taxonomy produced downstream, and the quality thresholds the pipeline is expected to meet.

## 1. Field-level validation (applied at ingestion, before staging)

| Rule ID | Table | Rule | On failure |
|---|---|---|---|
| DQ-01 | `usage_events` | `quantity` must be greater than 0. | Row quarantined. |
| DQ-02 | `usage_events` | `metric_type` must be one of the four approved values (see data dictionary). | Row quarantined. |
| DQ-03 | `usage_events` | `source_system` must be one of the four approved values (see data dictionary). | Row quarantined. |
| DQ-04 | `usage_events` | `subscription_id` must correspond to a subscription that was `ACTIVE` at `event_ts`. | Row flagged as `ORPHANED_USAGE`, excluded from billing, not quarantined outright — see section 3. |
| DQ-05 | `invoices` | `amount_due` must be non-negative. | Invoice generation halts for that subscription and it is left in `DRAFT` status. |

Quarantined rows are written to a quarantine location and are excluded from billing for
that run. They are not automatically retried; a data steward reviews the quarantine queue
manually.

## 2. Duplicate detection

- A usage event is considered a duplicate if the same `subscription_id`, `metric_type`,
  `event_ts`, and `source_system` combination appears more than once within the same
  hourly ingestion batch.
- Duplicates are flagged as `DUPLICATE_USAGE_EVENT`. The pipeline keeps the
  first-received event as the billable one and excludes the rest from rating.
- Duplicate detection does not span multiple hourly batches — a legitimate re-reported
  correction from a source system in a later batch is not automatically treated as a
  duplicate of an earlier one.

## 3. Orphaned usage handling

- A usage event whose `subscription_id` does not match any subscription, or matches a
  subscription that was not `ACTIVE` at `event_ts` (for example, usage reported after
  cancellation), is flagged as `ORPHANED_USAGE`.
- Orphaned usage is excluded from billing entirely — it is not billed to any account —
  and is retained for investigation, since it usually indicates a source system reporting
  usage for a subscription it has stale information about.

## 4. Late usage events

- A usage event with an `event_ts` that falls within a billing period whose invoice has
  already been generated is not quarantined and is not an error. It is processed
  normally and becomes an adjustment line on the next period's invoice, per the pipeline
  README's "Late usage events" section.

## 5. Adjustment/exception taxonomy (full list)

| Type | Meaning |
|---|---|
| `ORPHANED_USAGE` | Usage event maps to no active subscription at the time it occurred. Excluded from billing. |
| `DUPLICATE_USAGE_EVENT` | Same subscription, metric, timestamp, and source system reported more than once in one batch. Only the first is billed. |
| `LATE_USAGE_ADJUSTMENT` | Usage event arrived after its billing period's invoice was already generated. Carried forward as an adjustment on the next invoice. |
| `INVOICE_GENERATION_FAILURE` | Monthly billing run could not compute `amount_due` for a subscription. Invoice left in `DRAFT`. |

## 6. Materiality threshold for adjustments

- A `LATE_USAGE_ADJUSTMENT` (or any other invoice adjustment) is treated as
  **high-priority**, triggering an immediate finance-queue notification, when the
  adjustment amount exceeds **$25.00** or **3% of the original invoice's amount_due**,
  whichever is greater.
- Adjustments below that threshold are still recorded and applied but are batched into
  the monthly summary rather than triggering an immediate notification.

## 7. Quality targets

- The pipeline's target **usage-to-subscription match rate** is **99.5% or higher** of
  ingested usage events. This is a target threshold used for monitoring and alerting —
  it describes what the pipeline is designed to achieve, not a historical or live
  measurement.
- Sustained match rate below 99% over three consecutive days triggers a data quality
  investigation with the reporting source system's owning team.

## 8. Retention and reprocessing

- Quarantined and orphaned-usage rows are retained for 60 days to support manual review
  and reprocessing.
- Issued invoices (`ISSUED`, `PAID`, `OVERDUE`, `VOID`) are retained indefinitely in
  `invoices` for audit purposes.

## Related documents

- `data_dictionary.md` — column-level definitions referenced by these rules.
- `schema.sql` — physical constraints (`CHECK` constraints mirror DQ-01, DQ-02, DQ-03).
- `pipeline_README.md` — where these rules are applied in the ingestion/rating flow.
