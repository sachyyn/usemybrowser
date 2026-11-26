#!/usr/bin/env bash
# Usage: bench/run.sh <arm> <task> [run_id]
# Env: BENCH_BUDGET_USD (default 8), BENCH_TIMEOUT_SEC (default 1800), BENCH_MODEL (default sonnet)
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/run.py" "$@"
