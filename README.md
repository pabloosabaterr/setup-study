# setup-study

A [Claude Code](https://claude.com/claude-code) skill that turns a subject's slides and past exams into study material:

- **One LaTeX summary per topic** (PDF): essentials, formulas to memorise, a worked example, and what usually comes up in exams.
- **A question bank** (`question_bank.md`): every past-exam question filed by topic, plus the patterns that repeat most.
- **A mega mock exam** and a **separate solutions file** (PDF), covering every topic in scope, longer than the real exam on purpose.

It asks which topics are in scope and which language to write in, and on re-runs it only regenerates what changed.

## Requirements

- Claude Code (it runs a shell script, spawns subagents and compiles LaTeX, so it does not work in the claude.ai web app).
- A LaTeX distribution with `latexmk` and `pdflatex`: [MacTeX](https://tug.org/mactex/) on macOS, TeX Live on Linux.
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
study.json                  scope, language, exam info (edit freely)
question_bank.md
latex/summaries/topicNN.pdf
latex/mega_exam.pdf
latex/mega_exam_solutions.pdf
md/ dedup/ exams/md/ exams/clean/   intermediate text
```

Add more slides or exams later and run it again: it converts only the new files, updates the bank, and regenerates only the affected summaries and the exam.

## How it works

1. `scripts/prepare.sh` converts every PDF/PPTX/DOCX with markitdown. For slides it removes the lines repeated by slide transitions (each line is kept only the first time it appears). Scanned PDFs and photos are listed in `_review.txt`, and Claude reads those directly.
2. Claude asks which topics are in scope and which language to use, and saves the answers in `study.json`.
3. It builds the question bank from the past exams, in parallel with subagents when there are many.
4. It writes one summary per topic, with one subagent per topic running in parallel.
5. It writes the mega exam and its solutions itself (numerical answers are checked with Python), and compiles everything.

## License

MIT
