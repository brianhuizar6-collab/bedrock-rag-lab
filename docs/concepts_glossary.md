# Concepts Glossary — Plain-Language Definitions

Every term below is defined assuming no prior background, the way you'd explain it to a
stakeholder who isn't technical. Each definition also says exactly where that concept
shows up in this lab, so it isn't abstract.

## Embeddings

A number representation of meaning. An embedding model reads a piece of text and outputs
a list of numbers (a "vector," typically hundreds or thousands of numbers long) such that
pieces of text with similar meaning end up with similar-looking number lists. "The store
closes at 9pm" and "Closing time is 9:00 PM" would produce very similar vectors even
though the words are different — because embeddings capture meaning, not just keywords.
**In this lab:** the embedding model you select in the Knowledge Base creation wizard
(Titan Text Embeddings V2, `amazon.titan-embed-text-v2:0` — see README Step 2) converts
every chunk of our four source documents into a vector when you click Sync, and converts
every question into a vector at query time, so the system can compare them.

## Vector database (vector store)

A database built specifically to store these number-list vectors and answer the question
"which stored vectors are most similar to this new vector?" quickly, even across millions
of entries. It's the same idea as a normal database index, but for "closeness in meaning"
instead of exact matches. **In this lab:** the vector store is pre-configured by the TCS
sandbox and selected from a dropdown in the Knowledge Base wizard (README Step 2);
Bedrock writes chunk vectors into it when you click Sync, and searches it on every
question.

## Context engineering

The practice of deliberately controlling what information gets placed into a model's
prompt before it generates an answer — what to include, what to leave out, and how to
instruct the model to treat what's included. It's "engineering" because it's a design
decision with tradeoffs (too little context and the model can't answer; too much and
relevant details get buried), not something left to chance. **In this lab:** the
generation prompt template you paste into the Test Knowledge Base panel's Configurations
(README Step 4) is a piece of context engineering — it explicitly tells the model to
answer only from retrieved excerpts and to say "I don't know" rather than guess.

## RAG (Retrieval-Augmented Generation) architecture

A pattern for answering questions where, instead of relying only on what a language model
memorized during training, the system first *retrieves* relevant passages from your own
documents, then *generates* an answer using those passages as grounding material. "RAG"
names the two-step shape: retrieve, then generate. **In this lab:** the whole pipeline —
S3 documents describing the usage metering & billing pipeline → Bedrock Knowledge Base →
retrieval at query time → answer generation — is a RAG system.

## Chunking

Splitting a long document into smaller pieces before embedding it. Embedding an entire
50-page document as one vector would blur together too many different topics to be
useful for retrieval; chunking breaks it into pieces small enough that each one has a
focused, retrievable meaning. **In this lab:** the data source configuration step of the
Knowledge Base wizard (README Step 2) uses Fixed-size chunking (300 tokens per chunk,
20% overlap between consecutive chunks, so a sentence that straddles a chunk boundary
isn't lost from both sides).

## Ingestion and retrieval flow

**Ingestion** is the one-time (or periodic) process of reading source documents, chunking
them, embedding each chunk, and writing the vectors into the vector store — in this lab,
this happens the moment you click **Sync** on the data source (README Step 3), before any
question is asked. **Retrieval** is what happens at question time: embed the incoming
question, search the vector store for the most similar chunks, and hand those chunks to
the generation model — this happens automatically, behind the scenes, every time you type
a question into the Test Knowledge Base panel (README Steps 4–5). Ingestion happens once
per document update; retrieval happens once per question.

## Bedrock Knowledge Bases

Amazon Bedrock's managed service that wraps the whole ingestion-and-retrieval flow above
so you don't have to build the chunking, embedding-calling, and vector-search
infrastructure yourself. You point it at an S3 location and a vector store, and it
handles chunking, calling the embedding model, writing to the vector store, and — at
query time — the same `RetrieveAndGenerate` operation that does retrieval and generation
in one call, which the console's Test Knowledge Base panel runs for you behind a chat
interface. **In this lab:** created via the console wizard (README Step 2), populated by
clicking Sync (README Step 3), and queried through the Test Knowledge Base panel
(README Steps 4–5).

## Metadata

Structured facts *about* a document or chunk (who owns it, what type of document it is,
its classification level, its version) kept separately from the document's actual text.
Metadata can be used to filter retrieval (e.g., "only search internal documents") or to
help a human understand where an answer came from. **In this lab:** each source document
has a `.metadata.json` sidecar file (e.g., `data_dictionary.md.metadata.json`) carrying
`doc_type`, `domain` (`usage_metering_billing`), `owner`, `classification`, and
`version` — Bedrock picks these up automatically alongside the document the moment you
click Sync, with no extra configuration needed in the console.

## Grounding

Whether a generated answer is actually supported by the retrieved source material, as
opposed to being generated from the model's general training knowledge (which might be
outdated, generic, or simply wrong for your specific system). A "grounded" answer can be
traced back to specific retrieved text. **In this lab:** you judge grounding by eye —
whether the console's "Show source details" expander under an answer shows at least one
citation is your proxy for whether it was actually grounded in a retrieved chunk rather
than generated freely (see the `grounding_result` table in README Step 5).

## Source references (citations)

The specific retrieved passages — and where they came from — that a grounded answer is
based on. Bedrock generates these automatically, and the console surfaces them directly
under each answer in the Test Knowledge Base panel — expand "Show source details" to see
the source document and the exact text snippet used. **In this lab:** you copy these
citations by hand into the `citations` column of `assessment/results.csv` (README Step 5).

## Abstention

The system explicitly declining to answer rather than guessing, when the retrieved
material doesn't actually cover the question. A system that never abstains will
eventually answer a question it has no basis for — the technical term for that outcome
is a *hallucination*. **In this lab:** the generation prompt template you configure in
README Step 4 instructs the model to reply "I don't know based on the available sources"
when retrieval doesn't cover the question; the three unanswerable assessment questions
(U1–U3) exist specifically to test whether abstention actually works.

## Agentic RAG (overview)

A more advanced pattern where, instead of a single fixed retrieve-then-generate step, an
LLM-driven "agent" can decide *whether* to retrieve, *what* to search for, run multiple
retrieval rounds, call other tools, and revise its own approach based on intermediate
results — all before producing a final answer. Plain RAG follows one fixed path per
question; agentic RAG can take a different number of steps depending on the question.
**Not implemented in this lab** — this lab builds single-step RAG (one retrieval, one
generation, per question), which is the right starting point and is what the assessment
grades. Agentic RAG is noted here as the natural next step: for example, an agent that
first checks the data dictionary for a table name, then re-queries the quality rules
specifically for that table, rather than relying on one retrieval pass to surface
everything relevant.
