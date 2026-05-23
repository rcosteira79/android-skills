#!/usr/bin/env bash
#
# upstream-drift.sh — surface changes in credited upstream skill repos since our last audit.
#
# We *absorb* upstream skills (rewrite/expand into our own roster); we do not fork or mirror
# them. So this tool deliberately does NOT pull or sync anything. It only reports what changed
# upstream, so a human can decide whether to absorb anything new through the normal
# audit -> absorb -> smoke-test workflow.
#
# Usage:
#   scripts/upstream-drift.sh             Report what changed since the last audit.
#   scripts/upstream-drift.sh --update    Re-baseline: mark every reachable repo as audited at
#                                         its current HEAD. Run this AFTER triaging the drift.
#
# Requires: gh (authenticated) and jq.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ledger="$here/upstream-audit-ledger.json"

command -v gh >/dev/null 2>&1 || { echo "error: gh CLI is required and must be authenticated." >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "error: jq is required." >&2; exit 2; }
[[ -f "$ledger" ]] || { echo "error: ledger not found: $ledger" >&2; exit 2; }

update=0
[[ "${1:-}" == "--update" ]] && update=1

today="$(date +%Y-%m-%d)"
current="{}"   # repo -> current HEAD sha (collected as we go)
drift=0

echo "Checking credited upstream repos for drift since last audit..."
echo ""

while IFS=$'\t' read -r repo branch old; do
  cur="$(gh api "repos/$repo/commits/$branch" --jq '.sha' 2>/dev/null || true)"
  if [[ -z "$cur" ]]; then
    printf '  ??  %-46s could not reach %s (renamed / private / offline?)\n' "$repo" "$branch"
    continue
  fi
  current="$(jq -c --arg k "$repo" --arg v "$cur" '.[$k]=$v' <<<"$current")"
  if [[ "$cur" == "$old" ]]; then
    printf '  ok  %-46s up to date (%s @ %s)\n' "$repo" "$branch" "${old:0:7}"
  else
    drift=1
    printf '\n  >>  %-46s CHANGED  %s -> %s\n' "$repo" "${old:0:7}" "${cur:0:7}"
    gh api "repos/$repo/compare/$old...$cur" --jq '
      "        \(.ahead_by) new commit(s):",
      (.commits[] | "          - " + (.commit.message | split("\n")[0])),
      (if ([.files[]? | select(.filename | test("(SKILL\\.md|\\.md|\\.toml|\\.json)$"))] | length) > 0
         then "        changed skill / docs files:" else empty end),
      (.files[]? | select(.filename | test("(SKILL\\.md|\\.md|\\.toml|\\.json)$"))
                 | "          ~ \(.status): \(.filename)")
    ' 2>/dev/null || printf '        (cannot diff — recorded SHA unreachable; re-baseline with --update)\n'
    printf '\n'
  fi
done < <(jq -r '.repos[] | [.repo, .branch, .lastAuditedSha] | @tsv' "$ledger")

if [[ "$update" == 1 ]]; then
  tmp="$(mktemp)"
  jq --argjson cur "$current" --arg t "$today" '
    .lastRun = $t
    | .repos |= map(
        if ($cur[.repo]) then .lastAuditedSha = $cur[.repo] | .auditedOn = $t else . end
      )
  ' "$ledger" > "$tmp" && mv "$tmp" "$ledger"
  echo ""
  echo "  Re-baselined ledger to current HEADs (auditedOn=$today)."
  exit 0
fi

echo ""
if [[ "$drift" == 1 ]]; then
  echo "  Drift detected. Triage the changes above, absorb anything worthwhile, then run:"
  echo "    scripts/upstream-drift.sh --update"
else
  echo "  No drift — all credited upstreams unchanged since last audit."
fi
