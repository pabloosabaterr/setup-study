---
name: setup-study
description: Build study material for a university subject from PDFs. Converts topic slides with markitdown, dedups what slide transitions repeat, converts a folder of past exams, builds a question bank, and writes in LaTeX (compiled with pdflatex) one summary per topic plus a mega exam with a separate solutions file. Incremental on re-runs. Use when the user runs /setup-study, asks to prepare an exam or study material for a subject ("prepare the exam for X", "make summaries and a mock exam", "prepara el examen de X"), or drops topic PDFs and a past-exams folder into a subject directory.
---

# setup-study

Paths below like `<skill_dir>/scripts/…` and `templates/…` are relative to this skill's base directory (shown when the skill loads); pass absolute paths to subagents.

The user puts the topic PDFs (slides) loose in the subject directory and past exams in a subfolder (optionally with per-year subfolders, photos allowed). You convert everything to text, ask which topics are on the exam and which language to write in, build a question bank, and produce the LaTeX.

**Output language:** asked in step 3 and stored as `output_language` in `study.json`. All generated documents (summaries, explanations, solutions, section headings) use it. If it is not English, keep technical terms in English as the course uses them (throughput, timeout, sliding window…). Mega exam *questions* go in the language of the real exam. Talk to the user in the language they write to you in.

## Layout

```
<subject>/
  *.pdf                      topic slides (input)
  <exams>/                   past exams (input)
  study.json                 config: scope, exam info (you write it)
  md/ dedup/                 converted topics
  <exams>/md/ <exams>/clean/ converted exams
  _review.txt _changes.txt   written by prepare.sh
  question_bank.md           step 4
  latex/
    summaries/topicNN.tex    one per in-scope topic, each compiles alone
    mega_exam.tex            only the exam (+ formula sheet at the end)
    mega_exam_solutions.tex  solutions, same numbering
```

Every `.tex` starts from `templates/preamble.tex`. Adapt two lines: the `babel` option (see the comment above it) to the document's language, and `\qname` ("Question", "Pregunta", "Questão"…) to the language of the questions.

Never merge everything into one `.tex` with parts (exam / per topic / solutions). Summaries are separate files and the mega exam is only an exam.

## 1. Locate inputs and config

- Topics: loose PDF/PPTX/DOCX in the working directory, unless the user names another folder.
- Exams: the folder the user names; otherwise a subfolder like `tests`, `examenes`, `exams`, `parciales`. Ask only if there are several candidates or none.
- If `study.json` exists, this is a **re-run**: load it and follow the incremental rules in step 8.

## 2. Convert and dedup

```bash
<skill_dir>/scripts/prepare.sh <subject_dir> <exams_dir> [topics_dir]
```

It installs markitdown (>=0.1) in a reusable venv at `~/.local/share/markitdown-venv` (with Python 3.14/3.13/3.12, since 3.15 lacks onnxruntime). It only converts sources that are new or newer than their output, and lists them in `_changes.txt`.
- `dedup/<topic>.txt`: no blank lines, bullets, form feeds, table separators or repeated lines (`awk '!seen[$0]++'`), so the copies left by slide transitions disappear.
- `<exams>/clean/`: path flattened (`201415/teste01.pdf` → `201415_teste01.md`), without blank lines or name/student-number headers.
- `_review.txt`: photos and text-less (scanned) PDFs. Open them with Read (it reads images and PDF pages) and transcribe what matters. Do not skip them.

markitdown 0.1.x extracts by columns: sometimes it glues diagram labels to the start of neighbouring lines (e.g. "Session Layer a medium, which might…"). Mentally strip them; they are not real text. If dedup ate something meaningful (table rows or formulas that repeat on purpose), check the raw `md/` file for that part.

## 3. Ask scope and language

List the detected topics, numbered in `sort -V` order, with the title taken from the first lines of each `dedup/` file. Also look in the slides (usually the first and last topics) for the exam date, format, duration and scope, and note which language the slides and exams use.

Then ask the user, in a single AskUserQuestion call with two questions (skip any they already answered in the invocation, e.g. "topics 1 to 6, in English"). Phrase the questions and options in the user's language:
1. **Which topics are in scope.** Options like "All (1–N)" and the scope the slides announce if there is one (e.g. "1–6, as stated in lecture 11"). They can type a range in Other.
2. **Which language for the documents.** Options: the course language, the user's own language if different (with technical terms kept in English), and English if neither is. Put the course language first and mark it (Recommended).

Do not continue until you have both answers.

Write `study.json`:
```json
{
  "subject": "Computer Networks",
  "exams_dir": "tests",
  "output_language": "en",
  "topics": [
    {"n": 1, "file": "dedup/Computer Networks - Lecture 1 (EN).txt", "title": "Introduction to computer networks", "in_scope": true}
  ],
  "exam": {"date": "2026-10-29 18:30", "format": "2 h, closed book, open questions", "language": "en"}
}
```
`topicNN` in the output names is the `n` here (zero-padded).

## 4. Question bank (`question_bank.md`)

Extract every question from every clean exam (plus the transcribed images) and file it under the topic it belongs to:

```markdown
## T06 — Sliding window
- [201718_teste01_dez2017 Q2b] (calc) Minimum window for 100% utilization with RTT=… → pattern: BW×RTT/frame
- [201516_exame_jan2016 Q1] (T/F) …

## Out of scope
- [200506_exame_fev2006 Q4] (theory) … (topic no longer taught)

## Patterns
- Table: pattern → topics → years → number of appearances, sorted by frequency, weighting recent years more.
```

- Each entry starts with the `[source Qn]` tag, so a changed exam can have its entries replaced.
- One line per (sub)question: a short paraphrase in `output_language`, the type, and the key data/pattern. Do not copy whole statements.
- Questions on topics that are out of scope go under "Out of scope", not under a topic.
- **Parallelise when big:** if there are more than ~12 exams, split them into batches of ~8–10 and spawn one subagent per batch (all in one message). Each one reads its batch and writes `bank/part_K.md` in the format above, using the topic list from `study.json`. You then merge the parts into `question_bank.md` and write the "Patterns" section yourself. With fewer exams, do it directly.

## 5. Summaries: one subagent per topic

Spawn one subagent per in-scope topic, **all in the same message** so they run in parallel (general-purpose type). Give each this prompt, filled in:

> Write a LaTeX summary in {output_language} of topic {NN} "{title}" of {subject}. {If not English: Keep technical terms in English as the course uses them.} All headings and prose in {output_language}; set the babel language accordingly in the preamble.
> - Source (read it entirely): {abs path to dedup file}. If something looks garbled, check {abs path to raw md}.
> - Past exam questions for this topic: the "## T{NN}" section of {abs path to question_bank.md}.
> - Start from the preamble {abs path to this skill's templates/preamble.tex}; set the header to "{subject} --- {word for Topic in output_language} {NN}" / "{exam date}". The environments `key`, `sol`, `info` and the macros `\Q`, `\D` are already defined there.
> - Structure, 2–5 pages: (1) title; (2) essentials: every concept in the slides, in slide order, explained, not just listed; (3) formulas and definitions to memorise, with every variable and unit; (4) a short worked example if the topic has calculations (verify the numbers with Python); (5) what usually comes up: the bank's questions for this topic grouped by pattern, with years, plus typical mistakes.
> - Every fact must come from the slides; follow their conventions (units, notation). If something is unclear, say so instead of inventing.
> - Short, direct sentences, no filler. Section headings in {output_language}.
> - Write {abs path}/latex/summaries/topic{NN}.tex and compile it from that folder with `latexmk -pdf -interaction=nonstopmode -silent topic{NN}.tex`; fix all errors, then `latexmk -c`.
> - Reply with only: the path to the PDF, the page count, and anything in the slides you could not interpret.

When they finish, check that every `topicNN.pdf` exists. Rerun or fix the ones that failed.

## 6. Mega exam (main session)

Write it yourself, because it needs the whole picture. Read `question_bank.md` (especially "Patterns"), the summaries and, where needed, the `dedup/` files.

`latex/mega_exam.tex`, using the same preamble (babel set to `output_language`; title page, instructions and formula sheet in `output_language`, questions in the real exam's language):
- Title page with an `info` box: date and format of the real exam, scope (in-scope topics), where the questions come from (how many exams, which years, the patterns that repeat most), and how to use it.
- The exam: `\Q{...}` questions covering **every** in-scope topic, each tagged with its topics, e.g. `\Q{Sliding window (T06)}`. Put the most frequent patterns first, as variants of recurring past questions, and include questions on topics that are new this year. Make it longer than the real exam on purpose. Use the real exam's language.
- At the end, a one-page formula sheet (`multicols`) if the subject has formulas.

`latex/mega_exam_solutions.tex`, in `output_language`: one `sol` box per question with the same numbering. Show the reasoning, not just the result. Verify every numerical calculation with Python before writing it. Every fact must come from the slides; if the material is ambiguous, say so in the solution.

## 7. Compile

```bash
cd latex && latexmk -pdf -interaction=nonstopmode -silent mega_exam.tex mega_exam_solutions.tex
```
Fix all errors. Check the `.log` for undefined references and large overfull boxes, then run `latexmk -c` so only `.tex` and `.pdf` remain.

## 8. Re-runs (incremental)

When `study.json` already exists:
1. Run `prepare.sh` again and read `_changes.txt`.
2. A new topic PDF → add it to `study.json` and ask whether it is in scope (only about the new ones). If the user changes the scope, update `in_scope`. If they ask for another language, update `output_language` and regenerate all summaries and both exam files.
3. New or changed exams → extract only those into the bank. First remove the old entries with their `[source …]` tag, then update "Patterns".
4. Regenerate a summary (subagent, step 5) only if its topic file changed, its bank section changed, or it just entered the scope. Leave the others untouched.
5. Regenerate the mega exam and its solutions if anything above changed. Otherwise leave them.
6. If `_changes.txt` is empty and the scope did not change, say there is nothing new and stop.

## 9. Final report

Briefly, in the user's language: the generated or updated PDFs with their paths, the number of exams used, the 3–5 most frequent patterns, and anything you could not read (from `_review.txt`).
