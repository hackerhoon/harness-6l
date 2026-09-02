#!/bin/bash
# PreToolUse — RATE 예산 강제 + 감사 기록.
# 등록: settings.json hooks.PreToolUse, matcher "Edit|Write|NotebookEdit"
#
# jq 가 없으면 이 게이트는 아무것도 막지 못한다(fail-open). 그 사실을 숨기지 않고 알린다.
# 이 hook 에 의존하는 예산 라인은 jq 가 없는 환경에서 enforced_by: none 이다.
set -u
command -v jq >/dev/null 2>&1 || {
  echo "harness/policy_gate: jq 미설치 — 쓰기 한도 트립와이어가 비활성(fail-open) 상태다. 이 예산의 enforced_by 는 none 으로 낮춰 기록하라." >&2
  exit 0
}
INPUT=$(cat)
TOOL=$(jq -r '.tool_name // ""' <<<"$INPUT")
SID=$(jq -r '.session_id // "unknown"' <<<"$INPUT")
MAX_WRITES="${HARNESS_MAX_WRITES:-20}"
DIR="${CLAUDE_PROJECT_DIR:-.}/_workspace/runs"
mkdir -p "$DIR" 2>/dev/null || exit 0

jq -c --arg ts "$(date -u +%FT%TZ)" \
  '{ts:$ts, event:"pre_tool", tool:.tool_name, input:.tool_input}' \
  <<<"$INPUT" >> "$DIR/${SID}.jsonl" 2>/dev/null

case "$TOOL" in
  Edit|Write|NotebookEdit)
    C="$DIR/${SID}.writes"
    N=$(cat "$C" 2>/dev/null || echo 0)
    case "$N" in ''|*[!0-9]*) N=0 ;; esac
    N=$((N+1)); echo "$N" > "$C"
    if [ "$N" -gt "$MAX_WRITES" ]; then
      jq -n --arg n "$N" --arg m "$MAX_WRITES" '{hookSpecificOutput:{
        hookEventName:"PreToolUse",
        permissionDecision:"deny",
        permissionDecisionReason:("TRIPWIRE write-rate: 작업당 쓰기 한도 \($m)회 초과 (현재 \($n)). 쓰기 동결. 에스컬레이션 패킷(필요한 결정/권장안/시도한 대안/대기 비용/무응답 시 기본 조치)을 작성하고 정지하라.")}}'
      exit 0
    fi
    ;;
esac
exit 0
