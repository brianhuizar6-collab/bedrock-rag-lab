# Step-by-Step Guide — Bedrock RAG Lab & Assessment (Usage Metering & Billing)

**Everything in this guide is done by clicking through the AWS Management Console — no
AWS CLI and no SDK code (boto3, etc.) is used to build or run this lab.** The only piece
of code in this package is one small, optional local script that tallies your results
after you've filled them in by hand — it never talks to AWS. See "What you're building"
below and the file map at the end for exactly what that script does and doesn't do.

This guide is written assuming no prior AWS Bedrock console experience — every acronym is
defined the first time it's used, and every step says *why*, not just *what*.

If a term below is unfamiliar, `docs/concepts_glossary.md` has a plain-language
definition for it. `docs/architecture_overview.md` has the full picture and a diagram
once you've been through the steps once.

## What you're building

A system that answers engineering questions by searching four documents (a data
dictionary, a database schema, a pipeline README, and a set of data quality rules)
describing a usage metering & billing pipeline, and generating an answer grounded in what
it finds — refusing to answer when the documents don't cover the question, instead of
guessing. You build the whole thing — the S3 storage, the Bedrock Knowledge Base, and the
question-asking — using the AWS Management Console in your browser.

## Before you start: what you need from your TCS sandbox

Cloud AI sandboxes are normally pre-configured so trainees don't need account-owner
permissions. Before you start clicking, ask your sandbox admin (or check your onboarding
materials) for:

1. **A console login** for the sandbox AWS account (IAM user or federated/SSO login) and
   the **AWS Region** you should work in — the console shows the region in the top-right
   corner; every step below must happen in that same region.
2. **An S3 bucket name** you're allowed to upload to (or permission to create one).
3. **Confirmation that model access is enabled** for the approved embedding model
   (this lab uses Amazon Titan Text Embeddings V2) and the approved foundation model for
   generation. In the Bedrock console this is under **Bedrock configurations → Model
   access** — every model needs to show "Access granted" before you can use it.
4. **Vector store details**, since the sandbox pre-provisions this (creating it yourself
   normally needs account-owner permissions). Most sandboxes use **Amazon OpenSearch
   Serverless**; you'll need the collection name/ARN and vector index name your admin set
   up. If your sandbox instead lets you "quick create" a vector store directly from the
   Knowledge Base wizard, you can skip asking for this.
5. **An IAM service role** for the Knowledge Base to use, if your sandbox restricts
   self-service role creation. If you're allowed to create one, the console wizard in
   Step 2 offers to create it for you automatically — you won't need to touch IAM
   directly either way in the common case.

If any of this is unclear, ask before starting — nothing below works without the region,
bucket, and model access being correct first.

## Step 1 — Upload the knowledge source to S3

**What this does:** puts the four documents in `knowledge_source/` (plus their
`.metadata.json` sidecar files) somewhere Bedrock can read them from. Bedrock reads
documents from S3, not from your laptop — this step is what makes them visible to
Bedrock at all.

1. Open the **S3 console**: [console.aws.amazon.com/s3](https://console.aws.amazon.com/s3).
2. If you don't already have a bucket to use, click **Create bucket**, give it a unique
   name, leave **Block all public access** checked (these are internal engineering
   documents, never public), and leave default (SSE-S3) encryption on. Otherwise, open
   the bucket your sandbox admin gave you.
3. Inside the bucket, click **Create folder** and name it something like
   `usage-billing-kb/` — this keeps the knowledge source documents in their own prefix,
   separate from anything else in the bucket.
4. Open that folder and click **Upload**. Click **Add files**, and select all 8 files
   from your local `knowledge_source/` folder in one go:
   - `data_dictionary.md` and `data_dictionary.md.metadata.json`
   - `schema.sql` and `schema.sql.metadata.json`
   - `pipeline_README.md` and `pipeline_README.md.metadata.json`
   - `data_quality_rules.md` and `data_quality_rules.md.metadata.json`
5. Click **Upload** and wait for the green "Upload succeeded" confirmation.

**Why the `.metadata.json` files matter:** each one sits next to its source document with
the exact same base filename (Bedrock matches `data_dictionary.md.metadata.json` to
`data_dictionary.md` by filename convention). Bedrock reads these automatically during
Step 3 and attaches that metadata (document type, owner, classification, version) to
every chunk of the file — you don't configure anything extra for this to work, you just
need both files uploaded to the same folder.

**Sanity check:** the folder should show exactly 8 objects. If you see 4, you likely
forgot the metadata sidecar files — re-upload the missing ones.

## Step 2 — Create the Knowledge Base

**What this does:** tells Bedrock where to look for documents (the S3 folder from Step
1), which embedding model to use to make them searchable, and where to store the
resulting searchable vectors (the vector store). This step creates the Knowledge Base and
its data source — it does not yet read or index any documents; that's Step 3.

1. Open the **Amazon Bedrock console** and, in the left-hand navigation, find
   **Knowledge Bases** (under Builder tools / Orchestration, depending on console
   version).
2. Click **Create** → **Knowledge Base with vector store**.
3. **Knowledge Base details**: give it a name, e.g. `usage-billing-kb`, and a short
   description ("Knowledge base for the Usage Metering & Billing pipeline: data
   dictionary, schema, pipeline README, and data quality rules.").
4. **IAM permissions**: choose **Create and use a new service role** if your sandbox
   allows it (the console names and scopes the role for you automatically), or select the
   existing role your sandbox admin provided.
5. **Choose data source**: select **Amazon S3**, then continue.
6. **Configure data source**:
   - **Data source name**: e.g. `usage-billing-kb-s3-source`.
   - **S3 URI**: browse to (or paste) the S3 folder from Step 1, e.g.
     `s3://your-bucket-name/usage-billing-kb/`.
   - **Chunking strategy**: choose **Fixed-size chunking**, then set **Max tokens per
     chunk** to `300` and **Overlap percentage** to `20`. (Fixed-size chunking with a
     20% overlap means a sentence that straddles a chunk boundary still appears whole in
     at least one chunk — see `docs/concepts_glossary.md` for why chunking matters at
     all.)
   - Leave parsing and enrichment settings at their defaults for this lab.
7. **Select embedding model**: choose **Titan Text Embeddings V2** (the model ID looks
   like `amazon.titan-embed-text-v2:0`). If it's greyed out, go back and request model
   access per the prerequisites above, then return to this step.
8. **Vector database**: choose **Use an existing vector store**, select **Amazon
   OpenSearch Serverless**, and pick the collection and vector index your sandbox admin
   configured. (If your sandbox permits it, **Quick create a new vector store** does this
   for you automatically — use that instead if it's offered and you don't have existing
   vector store details.)
9. **Review and create**. This takes a minute or two; the console shows a status banner
   while the Knowledge Base is being created.

When it finishes, open the Knowledge Base's detail page — you'll land here again in every
later step, so it's worth bookmarking.

## Step 3 — Sync the data source (this is the actual indexing step)

**What this does:** this is where the real work happens. Bedrock reads the 4 documents
from S3, splits each into the chunks you configured, calls the embedding model on every
chunk, and writes the resulting vectors — plus each chunk's metadata — into the vector
store. After this step, the documents are actually searchable.

1. On the Knowledge Base's detail page, scroll to the **Data source** section.
2. Select the checkbox next to your S3 data source and click **Sync**.
3. Watch the **Status** column: it moves from `Syncing` to `Ready` (or `Failed`). For 4
   short documents, this usually takes well under a minute.
4. Click into the data source and open the **Sync history** tab to see the statistics:
   documents scanned, new/modified documents indexed, and any that failed.

**If a document fails:** the sync history shows a failure reason per document — usually
either a permissions issue (the Knowledge Base's IAM role can't read that S3 object; go
back to Step 2's IAM settings) or a chunking-configuration edge case. It is not a problem
with the documents themselves, since these are plain Markdown and SQL text files.

**Re-syncing:** if you ever edit and re-upload a file in `knowledge_source/`, come back to
this step and click **Sync** again — syncing is idempotent, so re-running it updates the
index rather than duplicating entries.

## Step 4 — Test one question using the console's built-in tester

**What this does:** the Knowledge Base detail page has a **Test Knowledge Base** panel
built directly into the console — no separate tool needed. This lets you ask a question
and see the generated answer, the exact source chunks it was grounded in, and (once you
set it up below) how the model behaves when it doesn't know something.

1. On the Knowledge Base detail page, open the **Test Knowledge Base** panel (usually a
   collapsible panel on the right-hand side, or a "Test" tab depending on console
   version).
2. Click **Select model**, and choose the approved foundation model for generation
   (the one your sandbox confirmed access to in the prerequisites).
3. Before asking anything, click the **Configurations** (gear) icon in the test panel and
   find **Generation prompt template** (sometimes labeled "Orchestration" or "Prompt
   template" depending on console version). Replace the default template with the
   following, then save:

   ```
   You are answering engineering questions about the Usage Metering & Billing pipeline
   using ONLY the retrieved source excerpts provided to you as $search_results$.

   Rules:
   1. Base your answer strictly on the retrieved excerpts. Do not use outside knowledge,
      even if you believe you know the answer.
   2. If the retrieved excerpts do not contain enough information to answer the question,
      respond with exactly: "I don't know based on the available sources." Do not guess,
      extrapolate, or fill gaps with plausible-sounding details.
   3. When you do answer, keep the answer short and cite which document the information
      came from.

   $search_results$
   ```

   This single instruction is what controls grounding and abstention — it's the same
   idea as telling a new hire "only answer from the manual in front of you, and say you
   don't know rather than guess." See `docs/concepts_glossary.md` ("Context engineering")
   for why this works.
4. Type a test question into the chat box, e.g.:
   ```
   What is the primary key of the usage_events table?
   ```
5. You should see:
   - An **answer** — a short factual statement (`event_id`).
   - A **"Show source details"** (or similar) link/expander under the answer — open it to
     see one or more citations, each pointing at `data_dictionary.md`, with the exact
     text snippet used.
6. Try a question the documents don't cover, to see abstention working:
   ```
   What is the retry backoff configuration, in seconds, for the API gateway's usage event exporter?
   ```
   You should see the answer be exactly *"I don't know based on the available sources."*
   with no source citation. If instead you get a confident, specific-sounding answer, see
   Troubleshooting below — usually this means the prompt template from step 3 above
   wasn't saved, or the model is over-generalizing from a loosely related retrieved
   chunk.

## Step 5 — Run the full assessment by hand

**What this does:** you'll ask all 13 questions from `assessment/questions.md` (10
answerable, 3 unanswerable — see that file for the full list and why each one was
chosen) through the same Test Knowledge Base panel from Step 4, one at a time, and record
what comes back.

1. Copy `assessment/results_template.csv` to `assessment/results.csv`, and open it in a
   spreadsheet program (Excel, Google Sheets) or any text editor.
2. For each question in `assessment/questions.md`, in order:
   - Type the question exactly as written into the Test Knowledge Base panel.
   - Copy the generated answer text into the `actual_answer` column.
   - Open "Show source details" and copy each citation's source document name into the
     `citations` column (or write `(none)` if there are no citations).
   - Determine the `grounding_result` using this table:

| Question type | What you see in the console | grounding_result |
|---|---|---|
| Answerable | Answer text + at least one citation | `GROUNDED` |
| Answerable | "I don't know based on the available sources." | `ABSTAINED` |
| Answerable | Confident answer text, but no citation shown | `UNGROUNDED_RISK` |
| Unanswerable | "I don't know based on the available sources." | `ABSTAINED` |
| Unanswerable | Answer text + a citation | `GROUNDED` |
| Unanswerable | Confident answer text, no citation | `UNGROUNDED_RISK` |

   - Fill in `question_id`, `question_type`, `question_text`, and `expected_source` by
     copying them from `assessment/questions.md` for that row.
   - Write a one- or two-sentence `failure_analysis`:
     - For an answerable question that came back `GROUNDED`, confirm the answer is
       actually correct against the source document, then note "OK — confirmed correct."
     - For an answerable question that came back `ABSTAINED` or `UNGROUNDED_RISK`, that's
       a failure — describe what likely went wrong (e.g., "retrieval didn't surface the
       right chunk — question phrasing didn't match the document's wording closely
       enough").
     - For an unanswerable question that came back `ABSTAINED`, note "OK — correctly
       abstained."
     - For an unanswerable question that came back `GROUNDED` or `UNGROUNDED_RISK`,
       that's a failure — describe it (e.g., "cited a loosely related chunk and
       over-generalized from it" or "answered with no supporting source at all — a clear
       hallucination").

## Step 6 (optional) — Get a quick scoreboard

Once `assessment/results.csv` is filled in, you can run the one local helper script in
this package to get a quick tally — this does not touch AWS at all, it just reads the CSV
you already filled in by hand:

```
cd assessment
python score_results.py
```

This prints how many of the 10 answerable questions were `GROUNDED` and how many of the 3
unanswerable questions were `ABSTAINED`, and flags any row that doesn't match the expected
pattern so you know exactly which rows still need a second look. It cannot check whether
`actual_answer` is factually correct — only you, reading it against the source documents,
can confirm that.

## (Optional) Step 7 — Put this in Git

The assignment description mentions Git as a tool, so if you want a version-controlled
record of this lab:

```
git init
git add .
git commit -m "Bedrock RAG lab: usage metering & billing knowledge base and assessment"
```

There's nothing sandbox-specific to exclude this time — since everything was built by
hand in the console, there's no config file holding a bucket name, role ARN, or
Knowledge Base ID to keep out of version control. `assessment/results.csv` is exactly the
completed assessment record the assignment asks for, safe to commit alongside everything
else.

## Troubleshooting

- **Model shows as greyed out / can't be selected** in Step 2 or Step 4 — go to
  **Bedrock configurations → Model access** in the left-hand console navigation, and
  request access to that model. This can take anywhere from immediate to a short review
  delay depending on the model and your account.
- **Sync fails with a permissions error** — open the Knowledge Base's IAM role (linked
  from the Knowledge Base detail page) and confirm it has read access to your S3 bucket
  and prefix, and `bedrock:InvokeModel` on the embedding model. If your sandbox created
  the role for you automatically in Step 2, this is usually already correct — a failure
  here more often means the S3 URI in the data source doesn't exactly match where you
  uploaded the files.
- **Sync completes but shows "0 documents indexed"** — double check the S3 URI configured
  on the data source matches the folder you uploaded to in Step 1, including the trailing
  slash.
- **Answers come back confident but wrong, with no citation shown** — this is the
  `UNGROUNDED_RISK` pattern from Step 5. First confirm the generation prompt template
  from Step 4 was actually saved (reopen Configurations and check). Second, try
  increasing the number of retrieved results in the test panel's configuration (if
  exposed in your console version) in case the right chunk isn't being retrieved at all.
- **An answerable question gets "I don't know"** — the right chunk likely wasn't
  retrieved. As a diagnostic, try rephrasing the question closer to the document's
  wording — if that fixes it, the issue is retrieval quality, not the model. Consider
  going back to Step 2's chunking settings and increasing overlap, then re-sync (Step 3).
- **Test Knowledge Base panel doesn't show source citations** — look for a "Show source
  details," "Source chunks," or similar expandable link directly beneath the generated
  answer; the exact label varies by console version, but every Knowledge Base test panel
  surfaces this.

## File map

```
bedrock-rag-lab/
├── README.md                          ← this file
├── knowledge_source/                  ← the 4 documents the KB indexes, + metadata sidecars
│   ├── data_dictionary.md
│   ├── schema.sql
│   ├── pipeline_README.md
│   ├── data_quality_rules.md
│   └── *.metadata.json
├── assessment/
│   ├── questions.md                   ← the 13 questions, human-readable, with rationale
│   ├── questions.json                 ← same questions, structured, for reference/traceability
│   ├── results_template.csv           ← copy to results.csv and fill in by hand (Step 5)
│   └── score_results.py               ← the ONLY code in this package; reads your filled-in
│                                          results.csv and prints a scoreboard. Never calls AWS.
└── docs/
    ├── concepts_glossary.md           ← plain-language definitions of every concept listed in the assignment
    └── architecture_overview.md       ← diagram + production-readiness considerations
```
