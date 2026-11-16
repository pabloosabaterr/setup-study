"""Page-level helpers for setup-study. Run with the markitdown venv's python
(it has pdfminer.six and Pillow).

  pages.py dedup <raw.md> <out.txt>
      Slide text without what slide transitions repeat, with a marker
      "=== p N ===" before the first new line of each PDF page, so the text
      says which page each thing comes from.

  pages.py index <slides.pdf> <out.txt>
      One line per page: words, images, vector shapes, and FIG when the page
      has more images or drawing than the slide template, i.e. probably a
      diagram, table or figure worth looking at.

  pages.py figsheet <compiled.pdf> <out_prefix> [dpi]
      Renders only the pages that include figures and tiles them 2x2 into
      <out_prefix>-1.png, -2.png..., labelled with the page number, so all
      figures of a document can be checked with one or two Reads.

  pages.py exams <clean_dir>
      Collapses runs of spaces/tabs inside lines (pdfminer separates words
      with tab+spaces in some exams) and removes the header lines (first 15
      lines) that appear in at least 3 exams and half of them: instructions,
      course name... Idempotent: run it over all exams every time.
"""
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from collections import Counter

BULLET = re.compile(r"^(?:[ \t•▪◦●]+|- +)+")
TABLE_SEP = re.compile(r"^\|[ |:-]*\|$")
RULE = re.compile(r"^[-=_*~]{3,}$")
SPACES = re.compile(r"(?<=\S)[ \t]{2,}|(?<=\S)\t")
NUMBER = re.compile(r"^\d{1,3}$")
SLIDE_COMMENT = re.compile(r"^<!-- Slide number: (\d+) -->$")


def read(path):
    # newline="": keep "\r" inside lines (see exams()), do not split on it.
    return open(path, encoding="utf-8", errors="replace", newline="").read()


def clean_line(line):
    line = line.replace("​", "").rstrip()
    # Plain runs of spaces stay: they align code and tables on the slides.
    return BULLET.sub("", line)


def dedup(src, dst):
    text = read(src)
    # pdfminer separates PDF pages with form feeds; markitdown's pptx
    # converter writes "<!-- Slide number: N -->" instead.
    pages = text.split("\f")
    seen, out = set(), []
    for i, page in enumerate(pages, 1):
        marker = f"=== p {i} ===" if len(pages) > 1 else None
        for raw in page.split("\n"):
            m = SLIDE_COMMENT.match(raw.strip())
            if m:
                marker = f"=== p {m.group(1)} ==="
                continue
            line = clean_line(raw)
            if not line or TABLE_SEP.match(line) or RULE.match(line):
                continue
            # page numbers printed on the slide
            if NUMBER.match(line) and abs(int(line) - i) <= 2 and len(pages) > 1:
                continue
            if line in seen:
                continue
            seen.add(line)
            if marker:
                out.append(marker)
                marker = None
            out.append(line)
    with open(dst, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def page_stats(pdf):
    from pdfminer.high_level import extract_pages
    from pdfminer.layout import LTCurve, LTFigure, LTImage, LTTextContainer

    def walk(obj, acc):
        for o in obj:
            if isinstance(o, LTImage):
                acc["img"] += 1
            elif isinstance(o, LTCurve):  # also LTLine, LTRect
                acc["shp"] += 1
            elif isinstance(o, LTTextContainer):
                acc["words"] += len(o.get_text().split())
            if isinstance(o, LTFigure):
                acc["fig"] += 1
                walk(o, acc)
            elif hasattr(o, "__iter__") and not isinstance(o, LTTextContainer):
                walk(o, acc)
        return acc

    return [walk(p, Counter()) for p in extract_pages(pdf)]


def index(pdf, dst):
    stats = page_stats(pdf)
    # What every slide has (logo, header bar...) is the template, not content.
    base_img = statistics.median(s["img"] for s in stats)
    base_shp = statistics.median(s["shp"] for s in stats)
    lines = ["# page words images shapes  (FIG = more images/drawing than the template: look at it)"]
    figs = []
    for i, s in enumerate(stats, 1):
        fig = s["img"] > base_img or s["shp"] > base_shp + 6
        if fig:
            figs.append(str(i))
        lines.append(f"p{i:02d} {s['words']} {s['img']} {s['shp']}" + ("  FIG" if fig else ""))
    lines.insert(1, f"# FIG pages: {' '.join(figs) or 'none'}")
    with open(dst, "w") as f:
        f.write("\n".join(lines) + "\n")


def render(pdf, page, dpi, out):
    if shutil.which("pdftoppm"):
        cmd = ["pdftoppm", "-r", str(dpi), "-f", str(page), "-l", str(page), "-png", "-singlefile", pdf, out[:-4]]
    elif shutil.which("gs"):
        cmd = ["gs", "-q", "-dNOPAUSE", "-dBATCH", "-dSAFER", "-sDEVICE=png16m", f"-r{dpi}",
               f"-dFirstPage={page}", f"-dLastPage={page}", f"-sOutputFile={out}", pdf]
    elif shutil.which("mutool"):
        cmd = ["mutool", "draw", "-q", "-r", str(dpi), "-o", out, pdf, str(page)]
    else:
        sys.exit("no renderer: install poppler or ghostscript")
    subprocess.run(cmd, check=True)


def figsheet(pdf, prefix, dpi=60):
    from PIL import Image, ImageDraw

    pages = [i for i, s in enumerate(page_stats(pdf), 1) if s["fig"] or s["img"]]
    if not pages:
        print("no pages with figures")
        return
    with tempfile.TemporaryDirectory() as tmp:
        imgs = []
        for p in pages:
            out = os.path.join(tmp, f"{p}.png")
            render(pdf, p, dpi, out)
            imgs.append((p, Image.open(out).convert("RGB")))
        w = max(im.width for _, im in imgs)
        h = max(im.height for _, im in imgs)
        for k in range(0, len(imgs), 4):
            group = imgs[k:k + 4]
            sheet = Image.new("RGB", (2 * w + 10, 2 * h + 10), "white")
            draw = ImageDraw.Draw(sheet)
            for j, (p, im) in enumerate(group):
                x, y = (j % 2) * (w + 10), (j // 2) * (h + 10)
                sheet.paste(im, (x, y))
                draw.rectangle([x, y, x + 60, y + 18], fill="black")
                draw.text((x + 4, y + 3), f"p. {p}", fill="white")
            out = f"{prefix}-{k // 4 + 1}.png"
            sheet.save(out)
            print(out, "pages", " ".join(str(p) for p, _ in group))


def exams(clean_dir):
    files = [os.path.join(clean_dir, f) for f in sorted(os.listdir(clean_dir)) if f.endswith(".md")]
    # pdfminer separates words with "\t\r \xa0" in some exams: never use
    # splitlines() or universal newlines here, they would split on the \r.
    texts = {f: [SPACES.sub(" ", l.replace("\r", " ").replace("\xa0", " ").rstrip())
                 for l in read(f).rstrip("\n").split("\n")]
             for f in files}
    heads = Counter()
    for lines in texts.values():
        heads.update(set(lines[:15]))
    common = {l for l, n in heads.items() if n >= max(3, len(files) / 2)} if len(files) >= 3 else set()
    for f, lines in texts.items():
        kept = [l for i, l in enumerate(lines) if not (i < 15 and l in common)]
        new = "\n".join(kept) + "\n"
        if new != read(f):
            with open(f, "w", encoding="utf-8") as fh:
                fh.write(new)
    if common:
        print(f"exams: removed {len(common)} header lines common to the exams")


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "dedup":
        dedup(*args)
    elif cmd == "index":
        index(*args)
    elif cmd == "figsheet":
        figsheet(args[0], args[1], int(args[2]) if len(args) > 2 else 60)
    elif cmd == "exams":
        exams(*args)
    else:
        sys.exit(__doc__)
