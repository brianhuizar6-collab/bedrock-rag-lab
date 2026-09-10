"""
score_results.py

This is the ONLY piece of code in this lab, and it never touches AWS — it
does not call the Bedrock API, the AWS CLI, or boto3. All the actual AWS
work (creating the S3 bucket, uploading files, creating the Knowledge Base,
syncing it, and asking questions) is done by hand in the AWS Management
Console, following README.md.

What this script does: once you've manually run all 13 assessment
questions through the console's "Test Knowledge Base" panel and filled in
assessment/results.csv by hand (see README.md, Step 5), run this script to
get a quick scoreboard — how many answerable questions were grounded, how
many unanswerable questions correctly abstained — so you can sanity-check
your results before treating the CSV as final.

Usage:
    python score_results.py
    python score_results.py path/to/results.csv
"""
import csv
import sys
from pathlib import Path

DEFAULT_PATH = Path(__file__).parent / "results.csv"

VALID_TYPES = {"answerable", "unanswerable"}
VALID_VERDICTS = {"GROUNDED", "ABSTAINED", "UNGROUNDED_RISK"}


def load_results(path: Path) -> list:
    if not path.exists():
        sys.exit(
            f"{path} not found. Copy results_template.csv to results.csv, "
            "fill it in by hand from the console's Test Knowledge Base "
            "panel (see README.md Step 5), then run this again."
        )
    with open(path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        sys.exit(f"{path} has no rows yet — nothing to score.")
    return rows


def validate(rows: list) -> list:
    problems = []
    for r in rows:
        qid = r.get("question_id", "?")
        qtype = (r.get("question_type") or "").strip()
        verdict = (r.get("grounding_result") or "").strip()
        if qtype not in VALID_TYPES:
            problems.append(f"[{qid}] question_type '{qtype}' is not 'answerable' or 'unanswerable'")
        if verdict not in VALID_VERDICTS:
            problems.append(f"[{qid}] grounding_result '{verdict}' is not one of {sorted(VALID_VERDICTS)}")
        if not (r.get("actual_answer") or "").strip():
            problems.append(f"[{qid}] actual_answer is empty — did you fill this row in yet?")
    return problems


def score(rows: list) -> None:
    answerable = [r for r in rows if r["question_type"] == "answerable"]
    unanswerable = [r for r in rows if r["question_type"] == "unanswerable"]

    grounded_correctly = [r for r in answerable if r["grounding_result"] == "GROUNDED"]
    abstained_correctly = [r for r in unanswerable if r["grounding_result"] == "ABSTAINED"]

    print(f"Answerable questions:   {len(grounded_correctly)}/{len(answerable)} correctly GROUNDED")
    for r in answerable:
        if r["grounding_result"] != "GROUNDED":
            print(f"  needs review: [{r['question_id']}] came back {r['grounding_result']} instead of GROUNDED")

    print(f"Unanswerable questions: {len(abstained_correctly)}/{len(unanswerable)} correctly ABSTAINED")
    for r in unanswerable:
        if r["grounding_result"] != "ABSTAINED":
            print(f"  needs review: [{r['question_id']}] came back {r['grounding_result']} instead of ABSTAINED")

    print(
        "\nReminder: this is a mechanical tally of the grounding_result column "
        "you filled in by hand — it does not verify that actual_answer is "
        "factually correct. Read each row against the source documents in "
        "knowledge_source/ before calling the assessment final."
    )


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    rows = load_results(path)

    problems = validate(rows)
    if problems:
        print("Found some rows that don't look filled in correctly yet:\n")
        for p in problems:
            print(f"  - {p}")
        print("\nFix these in the CSV and re-run.")
        return

    score(rows)


if __name__ == "__main__":
    main()
