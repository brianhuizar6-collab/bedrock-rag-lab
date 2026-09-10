# Assessment Questions — Usage Metering & Billing Knowledge Base

13 questions total: 10 answerable from the four source documents, 3 deliberately
unanswerable. The unanswerable ones are not trick questions about grammar — each one
asks for a specific, plausible-sounding fact that simply is not in any of the four
documents (a live metric, an infrastructure config value, or a personnel/role fact).
That's what makes them a genuine test of abstention: a system without proper grounding
will often "helpfully" guess at these instead of saying it doesn't know.

`Q_ID` matches the `question_id` column `05_run_assessment.py` writes to the results CSV.

## Answerable (10)

| Q_ID | Question | Expected source document |
|---|---|---|
| A1 | What is the primary key of the `usage_events` table? | `data_dictionary.md` |
| A2 | What are the four approved values for `metric_type`? | `data_dictionary.md` |
| A3 | What time does the monthly invoice generation job run, and which billing period does it cover? | `pipeline_README.md` |
| A4 | How is `amount_due` calculated for an invoice? | `pipeline_README.md` |
| A5 | What happens to a usage event that arrives after its billing period's invoice has already been generated? | `pipeline_README.md` / `data_quality_rules.md` |
| A6 | How does the pipeline detect a duplicate usage event? | `data_quality_rules.md` |
| A7 | What is `ORPHANED_USAGE`, and how is it handled? | `data_quality_rules.md` |
| A8 | What is the quality target for the usage-to-subscription match rate, and what triggers an investigation? | `data_quality_rules.md` |
| A9 | What four KPIs does the pipeline compute after each billing run? | `pipeline_README.md` |
| A10 | What is the materiality threshold that makes an invoice adjustment high-priority? | `data_quality_rules.md` |

## Unanswerable (3)

| Q_ID | Question | Why it's unanswerable |
|---|---|---|
| U1 | What was the actual billing accuracy rate last month? | The docs define a *target* metric (usage-to-subscription match rate ≥ 99.5%) but explicitly state they do not publish live/historical KPI values — this is runtime data, not part of the document set. |
| U2 | What is the retry backoff configuration, in seconds, for the API gateway's usage event exporter? | The docs describe the pipeline's own ingestion retry policy (every 15 minutes for up to 2 hours) but say nothing about the internal retry configuration of the source systems that export data to it — that's a different system's implementation detail. |
| U3 | Who approves invoice adjustments that exceed the materiality threshold? | None of the four documents contain personnel, role, or approval-workflow information — only that an adjustment above the threshold triggers a notification to "the finance queue," with no named approver or process. |

## What "expected source" means for grading

For each answerable question, the correct system behavior is: answer correctly, and
cite the document listed above (or a superset that includes it). For each unanswerable
question, the correct system behavior is a clear abstention — "I don't know based on
the available sources" — not a confident guess and not zero citations paired with a
made-up answer.
