#!/usr/bin/env bash
# Verify the local SHA of upstream-verbatim files in the tigerbeetle-io port
# matches the upstream SHAs recorded here.
#
# Patched files (io.zig, queue.zig, time.zig, stdx/stdx.zig, io/darwin.zig)
# are NOT checked — their patches are documented in UPSTREAM.md and tracked
# by inline `// braingang patch:` comments at the patch sites.
#
# This script is a sync-time helper: after pulling a new upstream snapshot,
# confirm the files declared "byte-for-byte identical" really are identical.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Parallel arrays — avoids bash 3.2's lack of `declare -A`.
# Pinned upstream SHAs for TigerBeetle 0.17.4
# (commit c93615ab7979034484711a6a201acd01a4e40f1b, vendored 2026-05-31).
FILES=(
  "src/io/common.zig"
  "src/io/linux.zig"
  "src/list.zig"
  "src/stdx/time_units.zig"
  "src/stdx/windows.zig"
)
UPSTREAM_SHAS=(
  "1701edf2af72e13ac31126162bc2250c804a8cdb4cff7d87816bc37c425c69ae"
  "ef06848a8e4a122c59387897d15f865bfb8e71f4e7def79b6343ccc495da7fac"
  "92d0a7c43c67d779f813f45aed988015b4342f0a10a82c84b7012af2ce700484"
  "971be953d27e71cbfe1b0b08075ab5680090165176c1f5326e28cb81c9dc7a36"
  "3e62e5c1df9db5d173694dfc67147e64d3f2cfe79501ac7dc091fe472dc14c62"
)

# Note: src/io/darwin.zig is "verbatim from upstream" in concept but
# currently carries two `// braingang patch:` lines for Zig 0.16 std API
# drift (kqueue, close). It is intentionally NOT in the FILES list above —
# move it back here once upstream itself moves to Zig 0.16 and the patches
# can be reverted.

fail=0
for i in "${!FILES[@]}"; do
  f="${FILES[$i]}"
  expected="${UPSTREAM_SHAS[$i]}"
  if [ ! -f "$f" ]; then
    echo "MISSING  $f"
    fail=1
    continue
  fi
  local_sha=$(shasum -a 256 "$f" | awk '{print $1}')
  if [ "$local_sha" != "$expected" ]; then
    echo "DRIFT    $f"
    echo "    local    = $local_sha"
    echo "    upstream = $expected"
    fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "All ${#FILES[@]} verbatim files match upstream."
fi

exit $fail
