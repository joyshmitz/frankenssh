#!/usr/bin/env bash
set -euo pipefail

# FrankenSSH core CI gate runner — run always-required checks.
# Conformance/bench/advisory security gates are scope-triggered and run separately.
# Usage: ./scripts/gates.sh

echo "=== FrankenSSH CI Gates ==="
echo ""

echo "--- cargo fmt --check ---"
cargo fmt --check

echo "--- cargo check --all-targets ---"
cargo check --all-targets

echo "--- cargo clippy --all-targets -- -D warnings ---"
cargo clippy --all-targets -- -D warnings

echo "--- cargo test --workspace ---"
cargo test --workspace

echo ""
echo "=== All gates passed ==="
