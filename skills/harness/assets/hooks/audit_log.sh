#!/bin/bash
# PostToolUse + PostToolUseFailure + PermissionDenied — 감사 원장. 완료율·복구시간·"권한 경계 차단 1회" 의 유일한 데이터 소스.
#   PostToolUse 는 도구가 성공했을 때만 발화한다. 실패는 PostToolUseFailure(최상위 error/is_interrupt/duration_ms).
#   PermissionDenied 는 권한 규칙·hook 이 도구를 막았을 때 발화한다(논문 policy_gate 의 log_denial).
# 반드시 세 이벤트 모두에 등록한다. 한쪽만 걸면 ok 가 항상 true 가 되어 실패율을 잴 수 없다.
_HOOK_NAME=audit_log; . "$(dirname "$0")/_common.sh"
EV=$(san "$(jq -r '.hook_event_name // "unknown"' <<<"$INPUT")")
jq -cn --arg ts "$(TS)" --arg k "$KEY" --arg ev "$EV" --arg t "$(tool_name)" --arg r "$(tool_ref)" \
  --arg err "$(jq -r '.error // ""' <<<"$INPUT" | cut -c1-200 | tr -d '\000-\037')" \
  --argjson intr "$(jq -r '.is_interrupt // false' <<<"$INPUT" | grep -qx true && echo true || echo false)" \
  --argjson dur "$(jq -r '.duration_ms // 0' <<<"$INPUT" | grep -Eo '^[0-9]+' || echo 0)" \
  '{ts:$ts,task:$k,event:$ev,tool:$t,ref:$r,ok:($ev=="PostToolUse"),denied:($ev=="PermissionDenied"),error:(if $err=="" then null else $err end),interrupted:$intr,duration_ms:(if $dur==0 then null else $dur end)}' \
  >> "$LEDGER" 2>/dev/null
exit 0
