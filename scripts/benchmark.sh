#!/usr/bin/env bash
set -euo pipefail

# FrankenSSH benchmark runner
# Usage: ./scripts/benchmark.sh

echo "=== FrankenSSH Benchmark Suite ==="
echo ""

# Conformance harness benchmarks
echo "--- Criterion benchmarks ---"
cargo bench -p fsh-harness 2>&1 || echo "(no benchmarks defined yet)"

echo ""
echo "=== Done ==="
