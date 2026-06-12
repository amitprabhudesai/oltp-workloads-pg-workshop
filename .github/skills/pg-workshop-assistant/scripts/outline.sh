#!/usr/bin/env bash
# outline.sh — print the full slide outline with slide numbers
#
# Usage: agent/scripts/outline.sh [--plain]
#
# Prints each section header and frame title alongside its slide number
# (the number that appears in the rendered PDF footer).
# Use this to locate a slide quickly before reading it in slides.tex.
#
# --plain  omit decorative formatting (useful for grep/pipe)
#
# Run from workshop-playground/ root.

set -euo pipefail

SLIDES="slides/slides.tex"
PLAIN=0

for arg in "$@"; do
  [[ "$arg" == "--plain" ]] && PLAIN=1
done

if [[ ! -f "$SLIDES" ]]; then
  echo "Error: $SLIDES not found. Run from workshop-playground/ root." >&2
  exit 1
fi

python3 - "$SLIDES" "$PLAIN" <<'PYEOF'
import sys, re

slides_file = sys.argv[1]
plain       = sys.argv[2] == "1"

lines = open(slides_file).readlines()

frame_re    = re.compile(r'\\begin\{frame\}')
title_re    = re.compile(r'\\begin\{frame\}(?:\[[^\]]*\])?\{([^}]*)\}')
section_re  = re.compile(r'^\\section\{([^}]*)\}')
standout_re = re.compile(r'\\begin\{frame\}\[standout\]')

slide_num   = 0
current_section = None

def clean(s):
    # Unwrap known commands (handle one level of nesting)
    for _ in range(3):
        s = re.sub(r'\\texttt\{([^{}]*)\}', r'`\1`', s)
        s = re.sub(r'\\textbf\{([^{}]*)\}', r'\1',   s)
        s = re.sub(r'\\emph\{([^{}]*)\}',   r'\1',   s)
        s = re.sub(r'\\[a-zA-Z]+\{([^{}]*)\}', r'\1', s)
    s = re.sub(r'\\[a-zA-Z]+', '', s)   # remaining bare commands
    s = re.sub(r'\\_', '_', s)          # escaped underscore
    s = re.sub(r'\\&', '&', s)          # escaped ampersand
    s = re.sub(r'---', '—', s)
    s = re.sub(r'[{}]', '', s)          # stray braces from partial matches
    return s.strip()

for i, line in enumerate(lines):
    sm = section_re.match(line.strip())
    if sm:
        current_section = clean(sm.group(1))
        if plain:
            print(f'\n[{current_section}]')
        else:
            print(f'\n  ── {current_section} ──')
        continue

    if frame_re.search(line):
        slide_num += 1
        m = title_re.search(line)
        if m:
            title = clean(m.group(1))
        elif standout_re.search(line):
            title = '[standout]'
        else:
            title = '[untitled]'

        if plain:
            print(f'Slide {slide_num:>3}  {title}  (line {i+1})')
        else:
            print(f'  Slide {slide_num:>3}  {title}')
PYEOF
