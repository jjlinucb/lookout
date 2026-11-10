#!/bin/bash
# The one check: Lean proofs, then every test. Red if any promise breaks.
#
#   ./check.sh
#
# 1. Lean checks the proofs in proofs/Lookout.lean and prints test vectors
#    from its model into mac/Tests/LookoutCoreTests/lean-vectors.txt.
# 2. The Swift tests (LeanTieTests among them) ask the real code the same
#    questions, then the shell tests run.
# Needs Lean via elan (https://lean-lang.org/install) and the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

LEAN=$(command -v lean || echo "$HOME/.elan/bin/lean")
[ -x "$LEAN" ] || { echo "Lean not found; install elan: https://lean-lang.org/install" >&2; exit 1; }
VECTORS=mac/Tests/LookoutCoreTests/lean-vectors.txt
echo "== Lean proofs"
(cd proofs && "$LEAN" --run Lookout.lean) > "$VECTORS.new" || { cat "$VECTORS.new" >&2; rm -f "$VECTORS.new"; exit 1; }
mv "$VECTORS.new" "$VECTORS"
echo "proved; $(wc -l < "$VECTORS" | tr -d ' ') vectors"

echo "== Tests"
mac/build_app.sh --test-only
