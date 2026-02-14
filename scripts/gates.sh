#!/usr/bin/env bash
set -euo pipefail

# FrankenSSH CI gate runner — run all mandatory checks
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
