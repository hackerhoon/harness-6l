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
    [ "$(jq -r '.stop_hook_active // false' <<<"$INPUT")" = "true" ] && exit 0
    if [ -f "$DIRTY" ] && [ ! -f "$TESTED" ]; then
      echo "차단: 소스를 수정했으나 이 작업에서 TEST 명령(패턴: $TEST_RE)이 실행된 기록이 없다. 완료 보고 전에 CLAUDE.md 의 TEST 명령을 실행하고 결과를 확인하라." >&2
      exit 2
    fi
    rm -f "$DIRTY" "$TESTED"; exit 0 ;;
esac
exit 0
