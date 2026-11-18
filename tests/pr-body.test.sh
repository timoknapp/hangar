#!/usr/bin/env bash
# Synthetic final-render regression. Also runs against an installed worker:
# HANGAR_WORKER_SCRIPT=/home/copilot/worker-loop.sh bash pr-body.test.sh
# shellcheck disable=SC2034,SC2317
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export GITHUB_OWNER=example GITHUB_REPO=repo WORKSPACE_DIR="$TMP/repo"
# shellcheck source=/dev/null
source "${HANGAR_WORKER_SCRIPT:-$ROOT/worker/worker-loop.sh}"
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$WORKSPACE_DIR"; cd "$WORKSPACE_DIR"
command git init -q
command git config user.name Fixture
command git config user.email fixture@example.invalid
printf 'base\n' > example.txt
command git add .; command git commit -qm base
TASK_BASE_SHA=$(command git rev-parse HEAD)
printf 'change\n' >> example.txt
command git commit -qam change
CURRENT_ISSUE=42 TASK_SPEC=false LOOP_PROFILE_DIR='' GATE_NOTE='' REVIEW_SUGGESTIONS_MD=''
issue_title='Synthetic implementation phase'
PR_EXECUTIVE_SUMMARY=$'## Problem\nA bounded phase is incomplete.\n\n## Root Cause\nThe old guard was missing.\n\n## Solution\nCloses #42. Fixes #17.\n\n## Testing\nSynthetic checks passed.\n\n## Future Work\nRefs #17.'
closing_ids() {
  node -e 'let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>console.log([...s.matchAll(/\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+#(\d+)\b/gi)].map(m=>m[1]).join(",")))'
}
render_expect() {
  local expected="$1"; issue_body="$2"
  build_final_pr_body || fail "render rejected: $issue_body"
  [[ "$(closing_ids <<<"$FINAL_PR_BODY")" == "$expected" ]] || fail "final closing IDs for: $issue_body"
  [[ "$FINAL_PR_BODY" == *'Closes issue #42'* && "$FINAL_PR_BODY" == *'Fixes issue #17'* ]] || fail 'untrusted summary not neutralized'
  [[ "$FINAL_PR_BODY" == *'<!-- hangar-evidence base='* ]] || fail 'not the final evidence-bound body'
}
# This first case fails on the original installed publisher, despite a raw link.
render_expect 42 'Close this implementation phase on merge; never auto-close an unresolved parent finding #17.'
for contract in \
  'Close this phase; never close parent finding #17 and keep its discussion open.' \
  'Do not close #17; close current issue #42 on merge.' \
  'Never close example/other#42; close the current phase.' \
  'Never close https://github.com/example/other/issues/42; close the current phase.' \
  'Do not close parent findings; do not close this issue until checks pass.' \
  'This implements the result of the parent discussion #17.' \
  'The parent is a discussion issue; close this implementation phase.' \
  'Never close until the required checks pass.' \
  'Must not close this issue unless the dependency is updated.' \
  'No auto-closing before review.' \
  'Do not close this issue without this guard.' \
  'Do not close this issue until checks pass and never close the parent.' \
  '' ; do
  render_expect 42 "$contract"
done
for contract in \
  'Never close this issue.' \
  'Do not close the issue.' \
  'Never close #042.' \
  'Never close example/repo#42.' \
  'Never close https://github.com/example/repo/issues/42.' \
  'Reference-only.' \
  'Do not auto-close current phase #42.' \
  'Do not close #42; close #17.' \
  'No auto-closing.' \
  'Before review, never close this issue.' \
  'Never close this issue; before publishing, run the tests.' \
  'Do not close without the guard; never close this issue.' \
  'Do not close this issue until checks pass and never close this issue.' \
  'Do not close this issue, but do not close the parent until checks pass.' \
  'This is a discussion issue.' \
  'For discussion only.' \
  'Discussion: compare the approaches.' \
  'This issue is reference-only.'; do
  render_expect '' "$contract"
done
TASK_SPEC=true
render_expect '' 'Close this phase after its spec is approved; never close the parent.'
TASK_SPEC=false
for contract in \
  'Never close the tracking item.' \
  'An earlier discussion informs this implementation.' \
  'Never close this issue and run the checks before review.' \
  'Never close parent finding #42.' \
  'Never close #17 and #42.' \
  'Never close parent #17 or this issue.'; do
  issue_body="$contract"; rc=0
  build_final_pr_body 2>/dev/null || rc=$?
  [[ "$rc" == 2 && "$GATE_NOTE" == *'decision'* ]] || fail "ambiguous contract did not stop for a decision: $contract"
done
# Raw-summary evidence is not final-body evidence. Removing the publisher link
# leaves the neutralized agent link, which cannot satisfy the final contract.
render_expect 42 'Close this implementation phase; never close the parent #17.'
original_summary="$PR_EXECUTIVE_SUMMARY"
PR_EXECUTIVE_SUMMARY="${PR_EXECUTIVE_SUMMARY/ Fixes #17./}"
build_final_pr_body || fail 'current-only summary rejected'
[[ "$(closing_ids <<<"$PR_EXECUTIVE_SUMMARY")" == 42 ]] || fail 'raw summary does not have exactly the current ID'
validate_final_pr_body_closure || fail 'valid final body rejected'
FINAL_PR_BODY="${FINAL_PR_BODY/Closes #42./Refs #42.}"
if validate_final_pr_body_closure; then fail 'raw link accepted as evidence for the transformed body'; fi
PR_EXECUTIVE_SUMMARY="$original_summary"
render_expect 42 'Complete current phase; never auto-close the parent.'
FINAL_PR_BODY+=$'\nCLOSES #17.'
if validate_final_pr_body_closure; then fail 'additional final-body closing ID accepted'; fi
# The actual quality loop reaches the critic once, using the rendered body;
# no correction is spent asking the implementer to rewrite a neutralized link.
verify_count=0 critic_count=0 correction_count=0
LOOP_CRITIC=true
TASK_SPEC=false
issue_body='Close this implementation phase on merge; never auto-close an unresolved parent finding #17.'
task_integrity() { return 0; }
run_verify_with_corrections() { verify_count=$((verify_count+1)); }
run_critic_review() {
  critic_count=$((critic_count+1))
  [[ "$(closing_ids <<<"$FINAL_PR_BODY")" == 42 ]] || return 1
}
take_correction() { correction_count=$((correction_count+1)); return 1; }
run_quality_gates || fail 'publisher caused a correction loop'
[[ "$verify_count,$critic_count,$correction_count" == '1,1,0' ]] || fail 'unnecessary correction/review round'
# Ambiguity parks once via the existing human-decision path, not corrections.
issue_body='Never close the tracking item.'
critic_count=0 correction_count=0 parked=false
fresh_base_compatible() { return 0; }
park_for_decision() { parked=true; [[ "$2" == *decision* ]]; }
cleanup_issue() { fail 'ambiguous closure policy treated as a code failure'; }
rc=0; finish_issue 42 "$issue_title" feature 2>/dev/null || rc=$?
[[ "$rc,$parked,$critic_count,$correction_count" == '1,true,0,0' ]] || fail 'ambiguity did not park without review/correction'
# Case, whitespace and qualified cross-references remain untrusted too.
PR_EXECUTIVE_SUMMARY+=$'\nCLOSES #17. Resolves\n#17. Fixes example/other#17. Closes https://github.com/example/other/issues/17.'
render_expect 42 'Close current issue #42; never close parent finding #17.'
for invalid in '' 0 -1 malformed 42x; do
  rc=0; issue_requests_reference_only "$invalid" </dev/null || rc=$?
  [[ "$rc" == 2 ]] || fail 'invalid current ID accepted'
done
# The fallback actually embeds issue context, including hostile cross-links.
PR_EXECUTIVE_SUMMARY=$'## Problem\n\n## Root Cause\nFixture\n\n## Solution\nCloses #42. Fixes #17.\n\n## Testing\nFixture\n\n## Future Work\nNone.'
render_expect 42 $'Close this phase; never close parent #17.\nCLOSES #17. Fixes example/other#17.'
[[ "$FINAL_PR_BODY" == *'> CLOSES issue #17.'* ]] || fail 'issue-context neutralization was not exercised'
PR_EXECUTIVE_SUMMARY="$original_summary"
# Repository words are identity data, not semantic target nouns.
rc=0; REPO_SLUG=example/parent issue_requests_reference_only 42 <<<'Never close example/parent#42.' || rc=$?
[[ "$rc" == 0 ]] || fail 'repository name confused with parent target'
# An unsafe later rendering addition is stopped before review/correction too.
generate_change_summary() { printf 'CLOSES #17.\n'; }
issue_body='Close this implementation phase; never close parent #17.'
critic_count=0 correction_count=0
rc=0; run_quality_gates || rc=$?
[[ "$rc,$critic_count,$correction_count" == '1,0,0' && "$GATE_NOTE" == *'Publisher-rendered'* ]] || fail 'unsafe final render reached review/correction'
echo 'PASS: actual final rendering, target-aware policy, decision stops, raw/final evidence, one critic and zero corrections'
