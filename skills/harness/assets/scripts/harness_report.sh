#!/bin/bash
# 하네스 스코어카드 — 원장에서 계산한다. 논문 §VIII(관찰가능성)의 "진짜 지표"가 첫 줄이다.
# 사용: harness_report.sh [project-dir]   (기본: CLAUDE_PROJECT_DIR 또는 .)
# 데이터: _workspace/runs/<sid>.tasks.jsonl (test_gate.sh Stop 기록), <sid>.jsonl (audit_log.sh)
#   - 원장은 파일로 jq 에 넘긴다(--slurpfile). 인자로 실으면 ~900KB 에서 ARG_MAX 를 넘는다.
#   - 줄 단위로 파싱한다(fromjson?). jq -s 는 깨진 줄 하나에 원장 전체를 잃는다. 건너뛴 줄 수를 stderr 로 알린다.
#   - 복구 시간은 세션(파일)별로 계산한다. 세션을 섞으면 무관한 세션의 성공이 다른 세션의 실패를 "복구"한 것처럼 보인다.
set -u
R="${1:-${CLAUDE_PROJECT_DIR:-.}}/_workspace/runs"
command -v jq >/dev/null 2>&1 || { echo "jq 필요" >&2; exit 1; }
[ -d "$R" ] || { echo "원장 없음: $R — hook 이 등록·발화된 적이 없다. 모든 지표는 계측 불가(none)." >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
RAW=0; OKL=0
: > "$TMP/tasks.jsonl"; : > "$TMP/ledger.jsonl"; : > "$TMP/secs.jsonl"
for f in "$R"/*.jsonl; do
  [ -f "$f" ] || continue
  n=$(wc -l < "$f" | tr -d ' '); RAW=$((RAW+n))
  case "$f" in
    *.tasks.jsonl) jq -Rc 'fromjson? // empty' "$f" >> "$TMP/tasks.jsonl" ;;
    *) jq -Rc 'fromjson? // empty' "$f" > "$TMP/one.jsonl"
       cat "$TMP/one.jsonl" >> "$TMP/ledger.jsonl"
       # 이 세션의 복구 구간(초): 실패 → 같은 파일의 다음 성공
       jq -s '[sort_by(.ts) | reduce .[] as $r ({p:null,s:[]};
                if $r.event=="PostToolUseFailure" and .p==null then .p=$r.ts
                elif ($r.ok==true) and .p!=null then .s += [(($r.ts|fromdate)-(.p|fromdate))] | .p=null
                else . end) | .s[]]' "$TMP/one.jsonl" >> "$TMP/secs.jsonl" ;;
  esac
done
OKL=$(( $(wc -l < "$TMP/tasks.jsonl") + $(wc -l < "$TMP/ledger.jsonl") ))
SKIP=$((RAW-OKL)); [ "$SKIP" -gt 0 ] && echo "경고: 파싱 불가한 원장 줄 ${SKIP}개를 건너뜀 — 아래 수치는 그만큼 불완전하다." >&2
jq -n --slurpfile t "$TMP/tasks.jsonl" --slurpfile l "$TMP/ledger.jsonl" --slurpfile sec "$TMP/secs.jsonl" --argjson skip "$SKIP" '
  ($t | map(select(.event=="task_end"))) as $ends |
  ($t | map(select(.event=="task_blocked"))) as $blocked |
  ($sec | add // []) as $secs |
  def pct(n; d): if d>0 then (n*100/d|floor) else null end;
  {
    "진짜 지표 — 수동 개입 없이 완료되고 증거를 낸 작업 수": ($ends | map(select(.verdict=="complete-tested")) | length),
    "작업 수(Stop 기준)": ($ends | length),
    "완료율 %(에스컬레이션 없이 끝난 작업)": pct(($ends | map(select(.denied==0)) | length); ($ends|length)),
    "테스트 증거 동반 완료 %": pct(($ends | map(select(.verdict=="complete-tested")) | length); ($ends|length)),
    "에스컬레이션률 %(작업 중 권한 차단 ≥1)": pct(($ends | map(select(.denied>0)) | length); ($ends|length)),
    "Stop 8회 캡으로 강제 종료된 작업": ($ends | map(select(.verdict=="complete-forced")) | length),
    "허위 완료 차단 횟수(test_gate)": ($blocked | length),
    "도구 실패 수": ($l | map(select(.event=="PostToolUseFailure")) | length),
    "권한 차단 수(PermissionDenied)": ($l | map(select(.denied==true)) | length),
    "평균 복구 시간 초(실패→같은 세션의 다음 성공)": (if ($secs|length)>0 then (($secs|add)/($secs|length)|floor) else null end),
    "건너뛴 원장 줄": $skip,
    "_주의": "재작업률·작업당 비용은 여기서 계측되지 않는다 — OTel 또는 claude -p --output-format json 필요. null 은 데이터 없음이지 0 이 아니다."
  }'
