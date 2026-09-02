#!/bin/bash
# evals/trigger_eval.json 실행 배선. claude plugin eval 은 early-access 게이트 뒤에 있다 — 열리면 그대로 돈다, 아니면 정직하게 스킵한다.
# 사용: run_trigger_eval.sh [plugin-root]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../../../.." && pwd)}"   # scripts → assets → harness → skills → 루트
EV="$ROOT/skills/harness/evals/trigger_eval.json"
[ -f "$EV" ] || { echo "스위트 없음: $EV" >&2; exit 1; }
N=$(python3 -c "import json;d=json.load(open('$EV'));print(len(d))" 2>/dev/null || echo '?')
if ! command -v claude >/dev/null 2>&1; then echo "SKIP: claude CLI 없음 (스위트 ${N}건은 파일로 존재)"; exit 0; fi
if claude plugin eval --help 2>&1 | grep -q 'early access' || { T=$(mktemp -d); (cd "$T" && claude plugin eval 2>&1 | grep -q 'early access'); r=$?; rm -rf "$T"; [ $r -eq 0 ]; }; then
  echo "SKIP: claude plugin eval 은 early access 게이트 뒤에 있다 (스위트 ${N}건은 파일로 존재). 게이트가 열리면 이 스크립트가 그대로 실행한다."; exit 0
fi
echo "claude plugin eval 사용 가능 — 실행"
exec claude plugin eval "$ROOT" --no-publish --threshold 0.9 --json "$ROOT/skills/harness/evals/results/last.json"
