#!/bin/bash
# PostToolBatch — 시간·배치수·토큰 예산 강제.
# exit 2 는 다음 모델 호출 전에 에이전틱 루프를 중단시킨다.
# 대화형 세션에서 루프 예산을 강제할 수 있는 유일한 메커니즘이다.
# 등록: settings.json hooks.PostToolBatch (matcher 미지원 — 항상 발화)
#
# 주의: 이 hook은 도구 호출 1건이 아니라 "도구 배치" 1건마다 발화한다.
#       따라서 BATCHES 는 논문 Table IV 의 "최대 도구 호출 50회"와 같은 단위가 아니다.
#       한 배치에 여러 도구가 들어갈 수 있으므로 BATCHES 상한은 도구 호출 상한의 하한선이다.
set -u
INPUT=$(cat)
MAX_SEC="${HARNESS_MAX_SECONDS:-1800}"
MAX_BATCHES="${HARNESS_MAX_BATCHES:-50}"
MAX_TOK="${HARNESS_MAX_TOKENS:-100000}"

HAVE_JQ=1; command -v jq >/dev/null 2>&1 || HAVE_JQ=0
if [ "$HAVE_JQ" -eq 1 ]; then
  SID=$(jq -r '.session_id // "unknown"' <<<"$INPUT")
  TP=$(jq -r '.transcript_path // ""' <<<"$INPUT")
else
  # jq 없이도 시간·배치 예산은 강제한다. 토큰만 계측 불가다.
  SID="nojq"; TP=""
  echo "harness/loop_budget: jq 미설치 — 토큰 예산은 계측하지 못한다(시간·배치 예산은 유효)." >&2
fi

DIR="${CLAUDE_PROJECT_DIR:-.}/_workspace/runs"
mkdir -p "$DIR" 2>/dev/null || exit 0
S="$DIR/${SID}.budget"
NOW=$(date +%s)
# -f 가 아니라 -s 로 검사한다. 빈 상태 파일이 있으면 START 가 비어
# elapsed 가 epoch 전체가 되어 즉시 오탐 정지한다.
[ -s "$S" ] || echo "$NOW 0" > "$S"
read -r START BATCHES < "$S" || { START=$NOW; BATCHES=0; }
case "$START" in ''|*[!0-9]*) START=$NOW ;; esac
case "$BATCHES" in ''|*[!0-9]*) BATCHES=0 ;; esac
BATCHES=$((BATCHES+1)); echo "$START $BATCHES" > "$S"
ELAPSED=$(( NOW - START ))

# transcript 에 cost 필드는 존재하지 않는다. 토큰만 합산할 수 있다.
TOK=0
if [ "$HAVE_JQ" -eq 1 ] && [ -n "$TP" ] && [ -f "$TP" ]; then
  TOK=$(jq -s '[.[] | select(.type=="assistant") | .message.usage
        | (.input_tokens // 0) + (.output_tokens // 0)
        + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)] | add // 0' \
        "$TP" 2>/dev/null || echo 0)
  case "$TOK" in ''|*[!0-9]*) TOK=0 ;; esac
fi

if [ "$ELAPSED" -gt "$MAX_SEC" ] || [ "$BATCHES" -gt "$MAX_BATCHES" ] || [ "$TOK" -gt "$MAX_TOK" ]; then
  echo "STOP CONDITION: elapsed=${ELAPSED}s batches=${BATCHES} tokens=${TOK}. 예산 소진. 현재 최선의 산출물 + 완료된 작업 + 미해결 이슈 + 정지 사유를 반환하라. 부분 실패를 최종 답변 뒤에 숨기지 마라." >&2
  exit 2
fi
exit 0
