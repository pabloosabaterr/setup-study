# setup-study

A [Claude Code](https://claude.com/claude-code) skill that turns a subject's slides and past exams into study material:

- **One LaTeX summary per topic** (PDF): the complete content of the slides, explained, with the slides' own diagrams cropped from the original PDF, formulas and APIs to memorise, and worked examples.
- **A question bank** (`question_bank.md`): every past-exam question filed by topic, plus the patterns that repeat most.
- **A mega mock exam** and a **separate solutions file** (PDF), covering every topic in scope, longer than the real exam on purpose.
- **`STUDY.md`**: a map of the subject folder (sources, scope, where each kind of information lives, known gaps), so later sessions and agents can work on it without you explaining the structure again.

It asks which topics are in scope and which language to write in, and on re-runs it only regenerates what changed.

## Requirements

- Claude Code (it runs a shell script, spawns subagents and compiles LaTeX, so it does not work in the claude.ai web app).
- A LaTeX distribution with `latexmk` and `pdflatex`: [MacTeX](https://tug.org/mactex/) on macOS, TeX Live on Linux (it needs the `adjustbox` and `listings` packages, included in both).
- One PDF renderer, to turn slide and exam pages into images: poppler (`pdftoppm`), ghostscript (`gs`) or mupdf (`mutool`). On macOS, `brew install poppler` also lets Claude's Read tool open PDFs directly.
- Python 3.12–3.14. The script installs [markitdown](https://github.com/microsoft/markitdown) in its own venv at `~/.local/share/markitdown-venv`. Python 3.15 does not work yet, because onnxruntime has no build for it.
- Tested on macOS. Linux should work. Windows is not supported (the script is bash).

## Install

As a plugin:

```
/plugin marketplace add <github-user>/setup-study
/plugin install setup-study@setup-study
```

Or manually: copy `plugins/setup-study/skills/setup-study/` to `~/.claude/skills/setup-study/`.

## Usage

```
my-subject/
  Lecture 1.pdf
  Lecture 2.pdf
  ...
  exams/              past exams; per-year subfolders and photos are fine
    2019/midterm1.pdf
    2018/exam_jan.pdf
```

Open Claude Code in `my-subject/` and run `/setup-study` (or just ask it to prepare the exam). You can give the scope and the language up front, e.g. `/setup-study topics 1 to 6, in Spanish`.

Output:

```
STUDY.md                    map of the folder (read this first)
study.json                  scope, language, exam info (edit freely)
question_bank.md
latex/summaries/topicNN.pdf labNN.pdf   lectures and labs, each numbered on its own
latex/summaries/*_key.md            compact key points, used to write the mega exam
latex/mega_exam.pdf
latex/mega_exam_solutions.pdf
md/ dedup/ exams/md/ exams/clean/   intermediate text
pages/ exams/pages/                 one PNG per slide/exam page
```

Add more slides or exams later and run it again: it converts only the new files, updates the bank, and regenerates only the affected summaries and the exam.

## How it works

1. `scripts/prepare.sh` converts every PDF/PPTX/DOCX with markitdown. For slides it removes the lines repeated by slide transitions (each line is kept only the first time it appears) and marks where each page starts. It also renders every slide and exam page to PNG and indexes which slides have diagrams or tables, so Claude looks only at the pages that need it (images cost far more tokens than text). Exam text is cleaned of repeated whitespace and common headers. Scanned PDFs and photos are listed in `_review.txt`, and Claude reads their page images.
2. Claude asks which topics are in scope and which language to use, and saves the answers in `study.json`.
3. It builds the question bank from the past exams, in parallel with subagents when there are many.
4. It writes one summary per topic, with one subagent per topic running in parallel. Summaries aim for completeness (every slide's content, no page limit) and include the slides' own diagrams, cropped from the original PDF in vector quality. Each subagent also writes a compact key-points file.
5. It writes the mega exam and its solutions itself from the question bank and the key-points files (numerical answers are checked with Python), and compiles everything.
6. It writes `STUDY.md`, the map of the folder, including what could not be read.

## License

MIT
