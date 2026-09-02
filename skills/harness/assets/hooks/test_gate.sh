#!/bin/bash
# PostToolUse (matcher: Bash|Edit|Write|NotebookEdit) + Stop/SubagentStop — "소스를 수정했는데 테스트를 안 돌리고 완료 보고" 차단.
#   실패 클래스 "센서 미실행 / 허위 완료 보고" 의 강한 수정. 원 설계: 2라운드 실사용 시뮬레이션(RED-6).
#   Stop hook 은 연속 8회 차단 후 무효화된다 — stop_hook_active 를 반드시 검사한다.
# 조정: HARNESS_TEST_PATTERN (테스트 명령 정규식), HARNESS_SRC_PATTERN (소스 경로 정규식)
_HOOK_NAME=test_gate; . "$(dirname "$0")/_common.sh"
TEST_RE="${HARNESS_TEST_PATTERN:-pytest|unittest|npm (run )?test|pnpm test|yarn test|cargo test|go test|make test|mvn test|gradle test|dotnet test}"
SRC_RE="${HARNESS_SRC_PATTERN:-(^|/)(src|lib|app|pkg|internal|tests?|spec)/}"
EV=$(jq -r '.hook_event_name // ""' <<<"$INPUT")
DIRTY="$DIR/${KEY}.dirty"; TESTED="$DIR/${KEY}.tested"
case "$EV" in
  PostToolUse)
    T=$(tool_name)
    case "$T" in
      Bash)  jq -r '.tool_input.command // ""' <<<"$INPUT" | grep -Eq "$TEST_RE" && : > "$TESTED" ;;
      Edit|Write|NotebookEdit)   # Read/Grep 등 읽기 도구는 dirty 가 아니다 — 매처를 "*"로 잘못 등록해도 여기서 막는다
             jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$INPUT" | grep -Eq "$SRC_RE" && : > "$DIRTY" ;;
    esac
    exit 0 ;;
  Stop|SubagentStop)
    if [ "$(jq -r '.stop_hook_active // false' <<<"$INPUT")" = "true" ]; then
      # 8회 캡 탈출: 차단을 더 못 한다. 작업을 기록은 한다 — 강제 종료로.
      [ "$EV" = Stop ] && jq -cn --arg ts "$(TS)" --arg k "$KEY" '{ts:$ts,task:$k,event:"task_end",dirty:true,tested:false,denied:0,tool_failures:0,verdict:"complete-forced"}' >> "$DIR/${SID}.tasks.jsonl"
      rm -f "$DIRTY" "$TESTED"; exit 0
    fi
    D=0; [ -f "$DIRTY" ] && D=1;  T=0; [ -f "$TESTED" ] && T=1
    if [ "$D" = 1 ] && [ "$T" = 0 ]; then
      [ "$EV" = Stop ] && jq -cn --arg ts "$(TS)" --arg k "$KEY" '{ts:$ts,task:$k,event:"task_blocked",reason:"untested"}' >> "$DIR/${SID}.tasks.jsonl"
      echo "차단: 소스를 수정했으나 이 작업에서 TEST 명령(패턴: $TEST_RE)이 실행된 기록이 없다. 완료 보고 전에 CLAUDE.md 의 TEST 명령을 실행하고 결과를 확인하라." >&2
      exit 2
    fi
    # 작업 완료 기록 — 논문의 "진짜 지표"(수동 개입 없이 완료되고 증거를 낸 작업 수)의 유일한 데이터 소스.
    # 작업 = 사용자 프롬프트 1턴(Stop 에서만 기록, SubagentStop 은 제외). denied = 이 작업에서 권한 경계가 막은 횟수.
    if [ "$EV" = Stop ]; then
      DEN=$(jq -c --arg k "$KEY" 'select(.task==$k and .denied==true)' "$LEDGER" 2>/dev/null | wc -l | tr -d ' ')
      FAILS=$(jq -c --arg k "$KEY" 'select(.task==$k and .event=="PostToolUseFailure")' "$LEDGER" 2>/dev/null | wc -l | tr -d ' ')   # PermissionDenied 는 ok:false 지만 도구 실패가 아니다
      V=complete; [ "$DEN" -gt 0 ] && V=complete-escalated; [ "$D" = 1 ] && [ "$T" = 1 ] && [ "$V" = complete ] && V=complete-tested
      jq -cn --arg ts "$(TS)" --arg k "$KEY" --argjson d "$D" --argjson t "$T" --argjson den "$DEN" --argjson f "$FAILS" --arg v "$V" \
        '{ts:$ts,task:$k,event:"task_end",dirty:($d==1),tested:($t==1),denied:$den,tool_failures:$f,verdict:$v}' >> "$DIR/${SID}.tasks.jsonl"
    fi
    rm -f "$DIRTY" "$TESTED"; exit 0 ;;
esac
exit 0
