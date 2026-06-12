#!/usr/bin/env bash
# search-slides.sh — find slides containing a keyword
#
# Usage: agent/scripts/search-slides.sh <keyword>
#
# For each matching line in slides/slides.tex, walks backward to find the
# enclosing \begin{frame} title and reports:
#   Slide N  |  "Frame Title"  |  file:line  |  matching text
#
# Run from workshop-playground/ root.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <keyword>" >&2
  exit 1
fi

KEYWORD="$1"
SLIDES="slides/slides.tex"

if [[ ! -f "$SLIDES" ]]; then
  echo "Error: $SLIDES not found. Run from workshop-playground/ root." >&2
  exit 1
fi

python3 - "$SLIDES" "$KEYWORD" <<'PYEOF'
import sys, re

slides_file = sys.argv[1]
keyword     = sys.argv[2].lower()

lines = open(slides_file).readlines()

# Build a map: line_number (0-based) -> frame title and slide number
frame_title_at = {}   # line index -> title string
frame_slide_at = {}   # line index -> slide number
slide_num = 0

frame_re     = re.compile(r'\\begin\{frame\}')
title_re     = re.compile(r'\\begin\{frame\}(?:\[[^\]]*\])?\{([^}]*)\}')
standout_re  = re.compile(r'\\begin\{frame\}\[standout\]')

for i, line in enumerate(lines):
    if frame_re.search(line):
        slide_num += 1
        m = title_re.search(line)
        if m:
            # Strip LaTeX commands for readability
            title = re.sub(r'\\[a-zA-Z]+\{([^}]*)\}', r'\1', m.group(1))
            title = re.sub(r'\\[a-zA-Z]+', '', title).strip()
        elif standout_re.search(line):
            title = '[standout]'
        else:
            title = '[untitled]'
        frame_title_at[i] = title
        frame_slide_at[i] = slide_num

# Index: for each line, which frame does it belong to?
def frame_for_line(n):
    best = None
    for fi in frame_title_at:
        if fi <= n:
            if best is None or fi > best:
                best = fi
    return best

hits = []
for i, line in enumerate(lines):
    if keyword in line.lower():
        fi = frame_for_line(i)
        if fi is None:
            continue
        hits.append((frame_slide_at[fi], frame_title_at[fi], i + 1, line.rstrip()))

if not hits:
    print(f'No matches for "{keyword}"')
    sys.exit(0)

print(f'{"Slide":<7}  {"Frame Title":<45}  {"Line":<6}  Match')
print('-' * 110)
for snum, title, lineno, text in hits:
    text_short = text.strip()[:60]
    print(f'Slide {snum:<3}  {title:<45}  :{lineno:<5}  {text_short}')
PYEOF
