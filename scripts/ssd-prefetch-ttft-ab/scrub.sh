#!/bin/bash
# Scrub internal identifiers before committing evidence/logs to the fork.
# RULE: run this on every file before `git add`. Never commit paths,
# employee IDs, host IPs, or container names.
#
#   ./scrub.sh <file> [file...]
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: $0 <file> [file...]"; exit 2; }

for f in "$@"; do
  [ -f "$f" ] || { echo "missing: $f"; exit 1; }
  # BSD sed has no \b; protect loopback first, scrub other IPv4, restore.
  sed -i.bak \
    -e 's|127\.0\.0\.1|LOOPBACK_PLACEHOLDER|g' \
    -e 's|/home/[A-Za-z0-9._-]*|/home/<user>|g' \
    -e 's|[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*|<host-ip>|g' \
    -e 's|LOOPBACK_PLACEHOLDER|127.0.0.1|g' \
    -e 's|prefetch-916|<bench-container>|g' \
    "$f"
  rm -f "$f.bak"
  echo "scrubbed: $f"
done
echo "REMINDER: absolute latency numbers (ms) belong only in internal"
echo "evidence; anything referenced from a public PR must be percentages."
