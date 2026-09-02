#!/bin/bash
# PostToolUse + PostToolUseFailure — 완료율·복구시간의 데이터 소스.
# 이 두 지표는 네이티브 소스가 없다. 하네스가 쓰지 않으면 존재하지 않는다.
#
# 반드시 두 이벤트 모두에 등록한다:
#   PostToolUse        — 도구가 "성공적으로" 끝났을 때만 발화한다
#   PostToolUseFailure — 실패했을 때 발화한다. 최상위 error / is_interrupt / duration_ms 를 받는다
# PostToolUse 한쪽에만 걸면 원장의 ok 가 항상 true 가 되어 실패율을 잴 수 없다.
set -u
command -v jq >/dev/null 2>&1 || {
  echo "harness/audit_log: jq 미설치 — 감사 원장을 기록하지 못한다. 완료율·복구시간 지표는 계측 불가 상태다." >&2
  exit 0
}
INPUT=$(cat)
SID=$(jq -r '.session_id // "unknown"' <<<"$INPUT")
EV=$(jq -r '.hook_event_name // "unknown"' <<<"$INPUT")
DIR="${CLAUDE_PROJECT_DIR:-.}/_workspace/runs"
mkdir -p "$DIR" 2>/dev/null || exit 0

jq -c --arg ts "$(date -u +%FT%TZ)" --arg ev "$EV" '
  {ts:$ts, event:$ev, tool:(.tool_name // null),
   ok:($ev != "PostToolUseFailure"),
   error:(.error // null),
   interrupted:(.is_interrupt // false),
   duration_ms:(.duration_ms // null)}' \
  <<<"$INPUT" >> "$DIR/${SID}.jsonl" 2>/dev/null
exit 0
