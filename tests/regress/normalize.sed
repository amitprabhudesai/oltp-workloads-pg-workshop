# normalize.sed — applied to BOTH actual output and expected files before diffing.
#
# Rules must be safe to apply symmetrically: they strip noise, never signal.
#
# How to extend
# ─────────────
# Add rules below as new tests need them.  Good candidates:
#   • OIDs in error messages:      s/'[0-9]+'::oid/'xxxx'::oid/g
#   • EXPLAIN ANALYZE timing:      s/(actual time=)[0-9.]+ /\1X.XXX /g
#   • EXPLAIN ANALYZE rows/loops:  s/(rows=)[0-9]+ (loops=)[0-9]+/\1N \2N/g
#   • Sequence values if exposed:  s/(nextval.*= )[0-9]+/\1<SEQ>/g
#   • Port numbers:                s/localhost:[0-9]+/localhost:xxxxx/g
#
# Not implemented here (see README):
#   expect_normalize.sed — rules applied to one side only before denormalized
#   diff output (the diff-filter pattern); useful for large test suites but
#   overkill for a workshop where diffs are always short.

# ── Separator lines ──────────────────────────────────────────────────────────
# psql aligned-output separator width depends on column name and value widths.
# Normalize ALL separator lines (any run of dashes / plus signs) to a fixed
# string so that column-width changes never break expected files.
s/^-[+-]{2,}$/---------------------------------------------------------------------/g

# ── Whitespace ───────────────────────────────────────────────────────────────
# Collapse leading whitespace to a single space.  Handles value-alignment
# shifts when column widths change (e.g. a longer value in the same column).
s/^\s+/ /g

# Strip trailing whitespace.  psql adds a trailing space to column header
# lines in aligned output; expected files in git should not carry that.
s/\s+$//g
