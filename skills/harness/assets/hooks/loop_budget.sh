#!/bin/bash
# PostToolBatch (matcher 미지원 — 항상 발화) — 소요시간·배치 수·토큰 예산. 초과 시 exit 2 로 루프 중단.
# 토큰 정의: 유니크 requestId 기준 input_tokens + output_tokens 의 합, 작업 시작 기준선 대비 증가분.
#   = 새로 처리된 입력 + 생성된 출력. 캐시 필드는 둘 다 제외한다:
#   cache_read 는 턴마다 컨텍스트 전체가 재계상돼 실제 세션에서 14,000배 폭주했고(RED-8 실증),
#   cache_creation 은 캐시 만료 시 컨텍스트 전체가 한 요청에 잡혀 단일 요청이 예산을 터뜨린다.
#   이것은 "작업량" 근사치이지 청구액도 컨텍스트 크기도 아니다.
# 배치 ≠ 도구 호출: 한 배치에 여러 도구가 들어갈 수 있다. 배치 상한은 도구 호출 상한의 하한선이다.
_HOOK_NAME=loop_budget; . "$(dirname "$0")/_common.sh"
MAX_SEC="${HARNESS_MAX_SECONDS:-1800}"; MAX_BATCHES="${HARNESS_MAX_BATCHES:-50}"; MAX_TOK="${HARNESS_MAX_TOKENS:-100000}"
TP=$(jq -r '.transcript_path // ""' <<<"$INPUT")
NOW=$(date +%s)
S="$DIR/${KEY}.start"; [ -s "$S" ] || { echo "$NOW" > "$S"; gc_runs; }   # 작업 첫 배치: 시작 시각 기록 + 상태·원장 정리
START=$(cat "$S"); case "$START" in ''|*[!0-9]*) START=$NOW; echo "$NOW" > "$S";; esac
ELAPSED=$(( NOW - START ))
BATCHES=$(bump "$DIR/${KEY}.batches")

tokens_now() {  # 스트리밍: -s 슬럽 금지(61MB transcript 에서 RSS 폭증). requestId 로 중복 제거.
  jq -r 'select(.type=="assistant") | "\(.requestId // .message.id // "x")\t\((.message.usage.input_tokens//0)+(.message.usage.output_tokens//0))"' "$1" 2>/dev/null \
  | sort -u -k1,1 | awk -F'\t' '{s+=$2} END{printf "%d\n", s+0}'
}
TOK=0
if [ -n "$TP" ] && [ -f "$TP" ]; then
  CUR=$(tokens_now "$TP"); B="$DIR/${KEY}.tok0"
  [ -s "$B" ] || echo "$CUR" > "$B"          # 작업 시작 시점 기준선
  BASE=$(cat "$B"); case "$BASE" in ''|*[!0-9]*) BASE=$CUR;; esac
  TOK=$(( CUR - BASE )); [ "$TOK" -ge 0 ] || TOK=0
fi
if [ "$ELAPSED" -gt "$MAX_SEC" ] || [ "$BATCHES" -gt "$MAX_BATCHES" ] || [ "$TOK" -gt "$MAX_TOK" ]; then
  echo "STOP CONDITION: elapsed=${ELAPSED}s/${MAX_SEC} batches=${BATCHES}/${MAX_BATCHES} tokens=${TOK}/${MAX_TOK}. 예산 소진. 현재 최선의 산출물 + 완료된 작업 + 미해결 이슈 + 정지 사유를 반환하라. 부분 실패를 최종 답변 뒤에 숨기지 마라. 리셋: rm _workspace/runs/${KEY}.*" >&2
  exit 2
fi
exit 0
