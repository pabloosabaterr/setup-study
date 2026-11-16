---
name: setup-study
description: Build study material for a university subject from PDFs. Converts topic slides with markitdown, dedups what slide transitions repeat, renders every slide and exam page to images, converts a folder of past exams, builds a question bank, and writes in LaTeX (compiled with pdflatex) one complete summary per topic (reusing the slides' own diagrams) plus a mega exam with a separate solutions file, and a STUDY.md map of everything for later agents. Incremental on re-runs. Use when the user runs /setup-study, asks to prepare an exam or study material for a subject ("prepare the exam for X", "make summaries and a mock exam", "prepara el examen de X"), or drops topic PDFs and a past-exams folder into a subject directory.
---

# setup-study

Paths below like `<skill_dir>/scripts/…` and `templates/…` are relative to this skill's base directory (shown when the skill loads); pass absolute paths to subagents.

The user puts the topic PDFs (slides, lab handouts) loose in the subject directory or in a folder they name, and past exams in a subfolder (optionally with per-year subfolders, photos allowed). You convert everything to text and page images, ask which topics are on the exam and which language to write in, build a question bank, produce the LaTeX, and leave a `STUDY.md` that explains the whole folder.

**If `STUDY.md` already exists in the subject directory, read it first**: it is the map of this subject (sources, scope, where each kind of information lives, known gaps). Do not ask the user to explain the structure again.

**Output language:** asked in step 3 and stored as `output_language` in `study.json`. All generated documents (summaries, explanations, solutions, section headings, `STUDY.md`) use it. If it is not English, keep technical terms in English as the course uses them (throughput, timeout, sliding window…). Mega exam *questions* go in the language of the real exam. Talk to the user in the language they write to you in. If the user dismisses the question, use the language of the slides and say so.

## Layout

```
<subject>/
  STUDY.md                   map of the folder for humans and agents (step 8)
  study.json                 config: scope, exam info (you write it)
  *.pdf  or <topics_dir>/    topic slides / lab handouts (input)
  <exams>/                   past exams (input)
  md/ dedup/                 converted topics (raw / deduplicated text)
  pages/<topic>/             slides.pdf (link to the source) + p-NN.png per PDF page
  <exams>/md/ <exams>/clean/ converted exams
  <exams>/pages/<exam>/      p-NN.png per exam page (scans, colour-marked answers)
  _review.txt _changes.txt   written by prepare.sh
  question_bank.md           step 4
  latex/
    summaries/topicNN.tex    one per in-scope topic, each compiles alone
    mega_exam.tex            only the exam (+ formula sheet at the end)
    mega_exam_solutions.tex  solutions, same numbering
```

`<topic>` in `pages/` is the source file name with every character outside `[A-Za-z0-9._-]` replaced by `_`, so LaTeX can use the path.

Every `.tex` starts from `templates/preamble.tex`. Adapt two lines: the `babel` option (see the comment above it) to the document's language, and `\qname` ("Question", "Pregunta", "Questão"…) to the language of the questions. The preamble already loads `listings` (code), `graphicx`/`adjustbox` and defines `\slidefig` (a cropped figure from the original slides, see step 5).

Never merge everything into one `.tex` with parts (exam / per topic / solutions). Summaries are separate files and the mega exam is only an exam.

## 1. Locate inputs and config

- Topics: loose PDF/PPTX/DOCX in the working directory, unless the user names another folder (or there is one obvious folder of slides, e.g. `lectures`, `slides`, `teoria`).
- Exams: the folder the user names; otherwise a subfolder like `tests`, `examenes`, `exams`, `parciales`. Ask only if there are several candidates or none.
- If `study.json` exists, this is a **re-run**: load it (and `STUDY.md`) and follow the incremental rules in step 9.

## 2. Convert, dedup and render pages

```bash
<skill_dir>/scripts/prepare.sh <subject_dir> <exams_dir> [topics_dir]
```

It installs markitdown (>=0.1) in a reusable venv at `~/.local/share/markitdown-venv` (with Python 3.14/3.13/3.12, since 3.15 lacks onnxruntime). It only converts or renders sources that are new or newer than their output, and lists conversions in `_changes.txt`.
- `dedup/<topic>.txt`: no blank lines, bullets, form feeds, table separators or repeated lines, so the copies left by slide transitions disappear.
- `pages/<topic>/p-NN.png` (80 dpi) and `<exams>/pages/<exam>/p-NN.png` (100 dpi): one image per PDF page, rendered with pdftoppm, ghostscript or mutool, whichever exists. Use these with the Read tool to look at pages: the Read tool cannot open PDFs when poppler is missing, but it always reads PNGs. Read only the pages you need.
- `<exams>/clean/`: path flattened (`201415/teste01.pdf` → `201415_teste01.md`), without blank lines or name/student-number headers.
- `_review.txt`: photos and text-less (scanned) PDFs. Read their page images and transcribe what matters. Do not skip them.

markitdown 0.1.x extracts by columns: diagram labels get glued to neighbouring lines or scattered as loose words (e.g. "Session Layer a medium, which might…"). They are not real text: look at the page image instead. If dedup ate something meaningful (table rows or formulas that repeat on purpose), check the raw `md/` file.

## 3. Ask scope and language

List the detected topics with the title taken from the first lines of each `dedup/` file. Number them in a natural order: if there are several kinds of files (lectures, labs/practicals, problem sets), number each kind in `sort -V` order, lectures first, rather than mixing them alphabetically. Also look in the slides (usually the first and last topics) for the exam date, format, duration and scope, and note which language the slides and exams use.

Then ask the user, in a single AskUserQuestion call with two questions (skip any they already answered in the invocation, e.g. "topics 1 to 6, in English", or a pasted announcement with the syllabus). Phrase the questions and options in the user's language:
1. **Which topics are in scope.** Options like "All (1–N)" and the scope the slides announce if there is one (e.g. "1–6, as stated in lecture 11"). They can type a range in Other. Partial topics ("first 8 slides of lecture 13") are allowed: cut the dedup file to that part (e.g. `dedup/<topic>_partial.txt`) and point `file` to it.
2. **Which language for the documents.** Options: the course language, the user's own language if different (with technical terms kept in English), and English if neither is. Put the course language first and mark it (Recommended).

Write `study.json`:
```json
{
  "subject": "Computer Networks",
  "topics_dir": ".",
  "exams_dir": "tests",
  "output_language": "en",
  "topics": [
    {"n": 1, "file": "dedup/Computer Networks - Lecture 1 (EN).txt", "pages": "pages/Computer_Networks_-_Lecture_1__EN_",
     "title": "Introduction to computer networks", "in_scope": true}
  ],
  "books": "chapters/sections in scope, if the announcement lists them",
  "exam": {"date": "2026-10-29 18:30", "format": "2 h, closed book, open questions", "language": "en"}
}
```
`topicNN` in the output names is the `n` here (zero-padded).

## 4. Question bank (`question_bank.md`)

Extract every question from every clean exam (plus the transcribed scans and images) and file it under the topic it belongs to:

```markdown
## T06 — Sliding window
- [201718_teste01_dez2017 Q2b] (calc) Minimum window for 100% utilization with RTT=… → pattern: BW×RTT/frame → answer: 7 frames
- [201516_exame_jan2016 Q1] (T/F) …

## Out of scope
- [200506_exame_fev2006 Q4] (theory) … (topic no longer taught)

## Patterns
- Table: pattern → topics → years → number of appearances, sorted by frequency, weighting recent years more.
```

- Each entry starts with the `[source Qn]` tag, so a changed exam can have its entries replaced.
- One line per (sub)question: a short paraphrase in `output_language`, the type, the key data/pattern, and the official answer if a solved version exists (`→ answer:`). Mark answers that are not official (`→ key (not official):`). Do not copy whole statements.
- Solved versions (`…r`, `…sol`, `resolucao`…) are not separate exams: attach their answers to the unsolved question's tag.
- **Answers marked only visually** (circled or coloured options in multiple choice, highlighted text) are lost in the text conversion. Look at `<exams>/pages/<exam>/` for those pages before writing "likely": never leave a guessed key when the page image can confirm it.
- Questions on topics that are out of scope go under "Out of scope", not under a topic.
- **Parallelise when big:** if there are more than ~12 exams, split them into batches of ~8–10 (keep each school year and its solved versions in the same batch) and spawn one subagent per batch (all in one message). Each one reads its batch and writes `bank/part_K.md` in the format above, using the topic list from `study.json`, and reports what it could not read. You then merge the parts into `question_bank.md` and write the "Patterns" section yourself. With fewer exams, do it directly.

## 5. Summaries: one subagent per topic

Spawn one subagent per in-scope topic, **all in the same message** so they run in parallel (general-purpose type). Give each this prompt, filled in:

> Write a LaTeX summary in {output_language} of topic {NN} "{title}" of {subject}. {If not English: Keep technical terms in English as the course uses them.} All headings and prose in {output_language}; set the babel language accordingly in the preamble.
> - Sources: read {abs path to dedup file} entirely. The page images of the original are in {abs path to pages/<topic>/} (p-01.png, p-02.png…, one per PDF page; slides.pdf is the PDF itself). Look at every page that has a diagram, table, figure, code or a layout the text lost; the raw text is {abs path to raw md} if the dedup looks garbled. {If partial: only pages/slides X–Y are in scope.}
> - Past exam questions for this topic: the "## T{NN}" section of {abs path to question_bank.md} and the rows of its "## Patterns" table that mention T{NN}. Answers marked "not official"/"likely" are not official.
> - Start from the preamble {abs path to templates/preamble.tex}; set the header to "{subject} --- {word for Topic in output_language} {NN}" / "{exam date}". The environments `key`, `sol`, `info`, the macros `\Q`, `\D`, `\slidefig` and `listings` are already defined there.
> - **Completeness over brevity.** This summary replaces the slides for studying: every slide's content must be in it, in slide order, explained (not just listed). Do not drop examples, code, tables, definitions or caveats from the slides to save space. There is no page limit: length follows the material (as a rough guide, one page per 4–6 content slides). Concise wording is welcome; omitting content is not.
> - **Reuse the slides' own diagrams.** When a slide has a diagram, schema, timeline, table or figure that explains better than prose (state diagrams, memory layouts, protocol exchanges, architecture pictures), include it from the original PDF with `\slidefig{<rel path to slides.pdf from latex/summaries>}{<pdf page>}{<trim l b r t as fractions>}{<caption naming the slide>}`. Find the PDF page and the crop by looking at the page images; check the result by rendering your compiled page to PNG (`gs -q -dNOPAUSE -dBATCH -sDEVICE=png16m -r60 -dFirstPage=K -dLastPage=K -sOutputFile=… topic{NN}.pdf`) and Reading it. Redraw in TikZ only if the original is unreadable or a cleaner version is clearly better. Then explain the figure in the text.
> - Structure: (1) title with the slide range covered; (2) content, slide by slide or grouped by the slides' own sections, with their figures; (3) formulas, definitions and APIs to memorise, with every variable, unit, prototype and return value as the slides give them; (4) worked examples for every kind of calculation or code the topic has (verify numbers with Python, compile code if you can); (5) what usually comes up: the bank's questions for this topic grouped by pattern, with years, plus typical mistakes.
> - Every fact must come from the slides; follow their conventions (units, notation). When you add something the slides do not say (from the bank answers or general knowledge), mark it "(not in the slides)". If something is unclear, say so instead of inventing.
> - Write {abs path}/latex/summaries/topic{NN}.tex and compile it from that folder with `latexmk -pdf -interaction=nonstopmode -silent topic{NN}.tex`; fix all errors and large overfull boxes, then `latexmk -c topic{NN}.tex` (always with the file name: other agents compile in the same folder at the same time). If latexmk fails because its log vanished, run it again.
> - Reply with only: the path to the PDF, the page count, which slides you included as figures, and anything in the slides you could not interpret.

When they finish, check that every `topicNN.pdf` exists. Rerun or fix the ones that failed. Keep the "could not interpret" notes: they go into `STUDY.md`.

## 6. Mega exam (main session)

Write it yourself, because it needs the whole picture. Read `question_bank.md` (especially "Patterns"), the summaries and, where needed, the `dedup/` files and page images.

`latex/mega_exam.tex`, using the same preamble (babel set to `output_language`; title page, instructions and formula sheet in `output_language`, questions in the real exam's language):
- Title page with an `info` box: date and format of the real exam, scope (in-scope topics), where the questions come from (how many exams, which years, the patterns that repeat most), and how to use it.
- The exam: `\Q{...}` questions covering **every** in-scope topic, each tagged with its topics, e.g. `\Q{Sliding window (T06)}`. Follow the real exam's format (e.g. a multiple-choice part and an open part if recent exams have them). Put the most frequent patterns first, as variants of recurring past questions, and include questions on topics that are new this year. Make it longer than the real exam on purpose. Use the real exam's language.
- At the end, a one-page formula sheet (`multicols`) if the subject has formulas or APIs to remember.

`latex/mega_exam_solutions.tex`, in `output_language`: an answer key for any multiple-choice part, then one `sol` box per question with the same numbering. Show the reasoning, not just the result, and cite the source (slide, past exam). Verify every numerical calculation with Python and compile/run code answers when possible. Every fact must come from the slides; if the material is ambiguous, say so in the solution.

## 7. Compile

```bash
cd latex && latexmk -pdf -interaction=nonstopmode -silent mega_exam.tex mega_exam_solutions.tex
```
Fix all errors. Check the `.log` for undefined references and large overfull boxes, render a page or two with figures to PNG and look at them, then run `latexmk -c mega_exam.tex mega_exam_solutions.tex` so only `.tex` and `.pdf` remain.

## 8. `STUDY.md` (the map of the folder)

Write `<subject>/STUDY.md` in `output_language` from `templates/STUDY.md`, filling every section with the real data: subject and exam, scope, the topic table (number, title, in scope, source file, text, page images, summary), the exams table (year, kind, solved or not, text or scan), where to find each kind of information, what is generated and how to regenerate it, and the known gaps (unreadable pages, garbled diagrams, missing answer keys, official answers with mistakes, from the subagents' reports and your own work). It must let a new agent work on the subject without anyone explaining the structure. Keep it factual and complete; it is a map, not a summary of the content.

## 9. Re-runs (incremental)

When `study.json` already exists:
1. Read `STUDY.md`. Run `prepare.sh` again and read `_changes.txt`.
2. A new topic file → add it to `study.json` and ask whether it is in scope (only about the new ones). If the user changes the scope, update `in_scope`. If they ask for another language, update `output_language` and regenerate all summaries, both exam files and `STUDY.md`.
3. New or changed exams → extract only those into the bank. First remove the old entries with their `[source …]` tag, then update "Patterns".
4. Regenerate a summary (subagent, step 5) only if its topic file changed, its bank section changed, it just entered the scope, or the user asks (e.g. after a skill update). Leave the others untouched.
5. Regenerate the mega exam and its solutions if anything above changed. Otherwise leave them.
6. Update `STUDY.md` whenever anything above changed.
7. If `_changes.txt` is empty and the scope did not change, say there is nothing new and stop.

## 10. Final report

Briefly, in the user's language: the generated or updated PDFs with their paths, `STUDY.md`, the number of exams used, the 3–5 most frequent patterns, and anything you could not read (from `_review.txt` and the subagents' reports).
