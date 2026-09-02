#!/bin/bash
# PreToolUse (matcher: Edit|Write|NotebookEdit) — 작업당 쓰기 한도. 초과 시 deny(쓰기 동결).
# 카운터 키 = session-prompt → 작업 단위. 수동 리셋: rm _workspace/runs/<sid>-<pid>.writes
_HOOK_NAME=policy_gate; . "$(dirname "$0")/_common.sh"
MAX_WRITES="${HARNESS_MAX_WRITES:-20}"
TOOL=$(tool_name)
jq -cn --arg ts "$(TS)" --arg t "$TOOL" --arg r "$(tool_ref)" '{ts:$ts,event:"pre_tool",tool:$t,ref:$r}' >> "$LEDGER" 2>/dev/null
case "$TOOL" in
  Edit|Write|NotebookEdit)
    N=$(bump "$DIR/${KEY}.writes")
    if [ "$N" -gt "$MAX_WRITES" ]; then
      jq -cn --arg n "$N" --arg m "$MAX_WRITES" --arg k "$KEY" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",
        permissionDecisionReason:("TRIPWIRE write-rate: 작업당 쓰기 한도 \($m)회 초과 (현재 \($n)). 쓰기 동결. 에스컬레이션 패킷(필요한 결정/권장안/시도한 대안/대기 비용/무응답 시 기본 조치)을 작성하고 정지하라. 리셋: rm _workspace/runs/\($k).writes")}}'
      exit 0
    fi ;;
esac
exit 0
