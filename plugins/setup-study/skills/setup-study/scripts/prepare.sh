#!/usr/bin/env bash
# Convert topic slides and past exams to text with markitdown, dedup the
# slides and clean the exams. Incremental: only (re)converts sources that are
# new or newer than their output.
#
# Usage: prepare.sh <subject_dir> <exams_dir> [topics_dir]
#   topics_dir: defaults to the loose PDF/PPTX/DOCX files in <subject_dir>.
#
# Output (inside <subject_dir>):
#   md/<topic>.md         raw markitdown of each topic
#   dedup/<topic>.txt     no blank lines, bullets or repeated lines
#   <exams_dir>/md/       raw markitdown of each exam (path flattened with _)
#   <exams_dir>/clean/    exams without blank lines or name/student-no. headers
#   pages/<topic>/        slides.pdf (link to the source PDF) + p-NN.png, one
#                         image per PDF page, to look at diagrams and to
#                         \includegraphics[page=N,trim=..,clip] them in LaTeX
#   <exams_dir>/pages/<exam>/p-NN.png   every exam page, for scans and for
#                         answers marked only by colour/circles
#   (<topic> in pages/ is the file name with anything but [A-Za-z0-9._-]
#   replaced by _, so LaTeX can use the path)
#   _review.txt           sources with no text (scans, photos) to read by hand
#   _changes.txt          what was new or changed in this run (empty = nothing)
set -euo pipefail

BASE=$(cd "$1" && pwd)
EXAMS=$(cd "$2" && pwd)
SLIDES=$(cd "${3:-$BASE}" && pwd)

VENV="$HOME/.local/share/markitdown-venv"
if [ ! -x "$VENV/bin/markitdown" ]; then
  # markitdown >=0.1 needs onnxruntime (via magika), which lags behind the
  # newest Python: use the first interpreter that has it.
  for PY in python3.14 python3.13 python3.12 python3; do command -v $PY >/dev/null && break; done
  $PY -m venv "$VENV"
  "$VENV/bin/pip" install -q 'markitdown[pdf,pptx,docx]>=0.1' || {
    echo "Could not install markitdown>=0.1 with $PY; install python@3.14 with brew" >&2; exit 1; }
fi
MD="$VENV/bin/markitdown"

REVIEW="$BASE/_review.txt"
CHANGES="$BASE/_changes.txt"
: > "$CHANGES"
touch "$REVIEW"

# Echo "new" or "changed" if $1 must be (re)built from $2, nothing otherwise.
status() { if [ ! -e "$1" ]; then echo new; elif [ "$2" -nt "$1" ]; then echo changed; fi; }

# Name usable in LaTeX paths: no spaces, parentheses, accents...
safe() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_'; }

# render <pdf> <outdir> <dpi>: one PNG per page (p-01.png, p-02.png...), so the
# Read tool can look at pages even without pdftoppm. Skips if up to date.
render() {
  local pdf="$1" out="$2" dpi="$3"
  [ -z "$(status "$out/p-01.png" "$pdf")" ] && return 0
  rm -rf "$out"; mkdir -p "$out"
  if command -v pdftoppm >/dev/null; then
    pdftoppm -r "$dpi" -png "$pdf" "$out/p"
    # pdftoppm pads to the page count's width; normalise to at least 2 digits
    for f in "$out"/p-?.png; do [ -e "$f" ] && mv "$f" "$out/p-0${f##*/p-}"; done
  elif command -v gs >/dev/null; then
    gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=png16m -r"$dpi" -sOutputFile="$out/p-%02d.png" "$pdf"
  elif command -v mutool >/dev/null; then
    mutool draw -q -r "$dpi" -o "$out/p-%02d.png" "$pdf"
  else
    echo "NO RENDERER (install poppler or ghostscript): $pdf" >> "$REVIEW"; return 0
  fi
}

# --- Topics ------------------------------------------------------------------
mkdir -p "$BASE/md" "$BASE/dedup"
find "$SLIDES" -maxdepth 1 -type f \( -iname '*.pdf' -o -iname '*.pptx' -o -iname '*.docx' \) \
  ! -iname 'mega_exam*' ! -iname 'topic*' | sort -V | while read -r f; do
  n=$(basename "$f"); n="${n%.*}"
  s=$(status "$BASE/dedup/$n.txt" "$f")
  [ -z "$s" ] && continue
  "$MD" "$f" -o "$BASE/md/$n.md" 2>/dev/null || { echo "FAILED topic: $f" >> "$REVIEW"; continue; }
  # Slide transitions repeat titles and bullets: drop zero-width spaces,
  # form feeds, bullets, trailing spaces, markdown table separators, blank
  # lines and any line already seen. (BSD sed has no \f, hence tr.)
  tr -d '\f' < "$BASE/md/$n.md" | sed 's/\xe2\x80\x8b//g; s/^[ •▪◦●-]*//; s/[[:space:]]*$//' \
    | grep -v '^\s*$' | grep -vE '^\|[ |:-]*\|$' \
    | awk '!seen[$0]++' > "$BASE/dedup/$n.txt" || true
  echo "TOPIC $s: $BASE/dedup/$n.txt" >> "$CHANGES"
  w=$(wc -w < "$BASE/dedup/$n.txt")
  if [ "$w" -lt 50 ]; then echo "NO TEXT topic ($w words): $f" >> "$REVIEW"; fi
done

# Page images of every topic PDF (also for topics converted in earlier runs).
find "$SLIDES" -maxdepth 1 -type f -iname '*.pdf' ! -iname 'mega_exam*' ! -iname 'topic*' | while read -r f; do
  n=$(basename "$f"); d="$BASE/pages/$(safe "${n%.*}")"
  render "$f" "$d" 80
  ln -sf "$f" "$d/slides.pdf"
done

# --- Exams -------------------------------------------------------------------
mkdir -p "$EXAMS/md" "$EXAMS/clean"
cd "$EXAMS"
find . -type f -not -path './md/*' -not -path './clean/*' -not -path './pages/*' | sort | while read -r f; do
  rel="${f#./}"
  n=$(echo "$rel" | sed 's#/#_#g; s#\.[^.]*$##')
  case "$(echo "$f" | tr "[:upper:]" "[:lower:]")" in
    *.pdf|*.docx|*.pptx)
      s=$(status "clean/$n.md" "$f")
      [ -z "$s" ] && continue
      "$MD" "$f" -o "md/$n.md" 2>/dev/null || { echo "FAILED exam: $EXAMS/$rel" >> "$REVIEW"; continue; }
      sed 's/\xe2\x80\x8b//g' "md/$n.md" | grep -v '^\s*$' \
        | grep -viE '^(NOME|NOMBRE|NAME)\b|^N(º|\.|o)? *(Aluno|Alumno|Student)|^_+$' > "clean/$n.md" || true
      echo "EXAM $s: $EXAMS/clean/$n.md" >> "$CHANGES"
      w=$(wc -w < "clean/$n.md")
      if [ "$w" -lt 50 ]; then echo "NO TEXT exam ($w words): $EXAMS/$rel -> read $EXAMS/pages/$n/" >> "$REVIEW"; fi
      ;;
    *.jpg|*.jpeg|*.png|*.heic)
      if ! grep -qF "$EXAMS/$rel" "$REVIEW"; then
        echo "IMAGE exam: $EXAMS/$rel" >> "$REVIEW"
        echo "EXAM new (image): $EXAMS/$rel" >> "$CHANGES"
      fi
      ;;
  esac
done

# Page images of every exam PDF: scans, and solutions marked by colour or
# circles that the text conversion loses.
find . -type f -iname '*.pdf' -not -path './md/*' -not -path './clean/*' -not -path './pages/*' | sort | while read -r f; do
  rel="${f#./}"; n=$(echo "$rel" | sed 's#/#_#g; s#\.[^.]*$##')
  render "$f" "$EXAMS/pages/$n" 100
done

echo "== Topics (words after dedup)"; wc -w "$BASE"/dedup/*.txt
echo "== Clean exams: $(ls "$EXAMS/clean" | wc -l | tr -d ' ') files, $(cat "$EXAMS"/clean/*.md 2>/dev/null | wc -w | tr -d ' ') words"
echo "== Changes in this run:"; cat "$CHANGES"
echo "== To read by hand (Read the PDF/image):"; cat "$REVIEW"
