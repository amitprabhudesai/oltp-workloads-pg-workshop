# ---------------------------------------------------------------------------
# tests/regress/Makefile
#
# Targets:
#   make test                       — run all tests
#   make test EXTRA_TESTS="02_synchronous_commit 03_checkpoint_fpi"
#                                   — run specific tests (space-separated names)
#   make generate-expected          — (re)generate expected/*.out from actual
#                                     output, normalized via normalize.sed.
#                                     Run once on a known-good cluster, verify
#                                     the output manually, then commit.
#   make clean                      — remove out/ directory
#
# Connection defaults (override on the command line):
#   make test PGHOST=localhost PGUSER=workshop PGPASSWORD=workshop
# ---------------------------------------------------------------------------

PGHOST       ?= postgres
PGPORT       ?= 5432
PGDATABASE   ?= workshop
REGRESS_USER ?= workshop
REGRESS_PASS ?= workshop

SHELL  := /bin/bash
SCRIPT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))run_tests.sh

export PGHOST PGPORT PGDATABASE REGRESS_USER REGRESS_PASS

.PHONY: test generate-expected clean

test:
ifdef EXTRA_TESTS
	bash $(SCRIPT) $(EXTRA_TESTS)
else
	bash $(SCRIPT)
endif

# ---------------------------------------------------------------------------
# generate-expected
#
# Run every SQL file through psql, pipe through normalize.sed, and write
# directly into expected/.  Expected files are stored normalized (no trailing
# whitespace, fixed-width separator lines) so they are clean for git.
#
# Only run this on a known-good cluster.  Verify expected/*.out before commit.
# ---------------------------------------------------------------------------
generate-expected:
	@mkdir -p out
	@for f in sql/*.sql; do \
	    name=$$(basename $$f .sql); \
	    echo "Generating expected/$$name.out ..."; \
	    PGOPTIONS='-c client_min_messages=warning' PGPASSWORD=$(REGRESS_PASS) \
	    psql -h $(PGHOST) -p $(PGPORT) -U $(REGRESS_USER) -d $(PGDATABASE) \
	         -X -q -f $$f \
	    | sed -Ef normalize.sed \
	    > expected/$$name.out 2>&1; \
	done
	@echo "Done.  Review expected/*.out before committing."

clean:
	rm -rf out
