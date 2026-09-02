# harness-6l hook 공통 프렐류드 — 각 스크립트가 source 한다. 단독 실행 대상 아님.
# 설계 원칙: 강제할 수 없으면 조용히 통과시키지 않고 "경고 + exit 0(fail-open)"으로 알린다.
set -u
_H="${_HOOK_NAME:-hook}"
warn() { echo "harness/${_H}: $*" >&2; }
INPUT=$(cat)   # jq 검사보다 먼저 읽는다 — fail-closed 분기가 이벤트명을 jq 없이 grep 으로 읽어야 한다
# ── fail-open / fail-closed ──────────────────────────────────────────────────
# 기본(fail-open): 강제할 수 없으면 경고하고 통과시킨다. 세션을 벽돌로 만들지 않는다. 그 대가로 enforced_by 는 none 이다.
# HARNESS_FAIL_CLOSED=1|true|yes|on (opt-in, 무인·CI 용): 의존성 부재를 "조용한 통과"가 아니라 "정지"로 다룬다.
#   PreToolUse → deny JSON / PostToolBatch·Stop → exit 2 / 차단 불가 이벤트(PostToolUse 등) → 경고만.
_event() {   # bash 내장 정규식만 쓴다 — jq 가 없는 환경에서는 grep/sed 도 없을 수 있다 (bash 3.2 의 =~ 로 충분)
  if [[ "$INPUT" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]+)\" ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
}
fail() {
  case "${HARNESS_FAIL_CLOSED:-0}" in 1|true|TRUE|yes|YES|on|ON) _FC=1 ;; *) _FC=0 ;; esac   # 1/true/yes/on 전부 허용
  if [ "$_FC" = 1 ]; then
    case "$(_event)" in
      PreToolUse) printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"harness/%s FAIL-CLOSED: %s"}}\n' "$_H" "$1"; exit 0 ;;
      PostToolBatch) echo "harness/${_H} FAIL-CLOSED: $1" >&2; exit 2 ;;
      Stop|SubagentStop)
        [[ "$INPUT" =~ \"stop_hook_active\"[[:space:]]*:[[:space:]]*true ]] && exit 0   # 8회 캡 존중 (내장 정규식)
        echo "harness/${_H} FAIL-CLOSED: $1" >&2; exit 2 ;;
      *) warn "FAIL-CLOSED 이지만 이 이벤트는 차단 불가 — $1"; exit 0 ;;
    esac
  fi
  warn "$1 — 비활성(fail-open). 이 hook에 의존하는 예산의 enforced_by 는 none 이다."; exit 0
}
command -v jq >/dev/null 2>&1 || fail "jq 미설치"
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || fail "CLAUDE_PROJECT_DIR 미설정(Claude Code 2.1.196+ 필요)"
# 입력 정제: session_id / prompt_id / tool_name 은 파일명·원장 키로 쓰이므로 [A-Za-z0-9_-] 만 허용한다.
# (경로 탈출 ../, NUL, 개행, 유니코드 위장 전부 제거)
san() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-64; }
SID=$(san "$(jq -r '.session_id // "unknown"' <<<"$INPUT")"); [ -n "$SID" ] || SID=unknown
PID_=$(san "$(jq -r '.prompt_id // "p0"' <<<"$INPUT")");   [ -n "$PID_" ] || PID_=p0
KEY="${SID}-${PID_}"                      # 작업(task) = 사용자 프롬프트 1턴. 다음 턴에서 자연 리셋된다.
DIR="$CLAUDE_PROJECT_DIR/_workspace/runs"
mkdir -p "$DIR" 2>/dev/null || fail "$DIR 생성 실패"
LEDGER="$DIR/${SID}.jsonl"
TS() { date -u +%FT%TZ; }
# 원장에 tool_input 전문을 쓰지 않는다 — 비밀(API 키·토큰)이 평문으로 남는다. 식별에 필요한 최소만, 512자 절단.
tool_name() { jq -r '.tool_name // ""' <<<"$INPUT" | tr -d '\n' | tr -c 'A-Za-z0-9_-' '_' | cut -c1-64; }   # 비허용 문자는 삭제가 아니라 _ 치환 — "Read\0BAD"가 "ReadBAD"로 위장되지 않게
tool_ref()  {   # Edit/Write: file_path. Bash: 환경변수 대입(VAR=… — 비밀이 여기 온다)을 건너뛴 첫 실행 파일명만.
  local fp; fp=$(jq -r '.tool_input.file_path // .tool_input.path // ""' <<<"$INPUT" 2>/dev/null)
  if [ -n "$fp" ]; then printf '%s' "$fp" | cut -c1-512 | tr -d '\000-\037'; return; fi
  jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null | head -1 \
    | awk '{for(i=1;i<=NF;i++){ if($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/){print $i; exit} }}' | cut -c1-128 | tr -d '\000-\037'
}
# ── 상태 파일·원장 정리 (작업 첫 배치에서 1회 호출) ─────────────────────────
# 상태 파일: HARNESS_STATE_TTL_DAYS(기본 7) 지난 것 삭제. 원장: HARNESS_LEDGER_MAX_KB(기본 10240) 초과 시 .1 로 1회 로테이션,
# HARNESS_LEDGER_TTL_DAYS(기본 30) 지난 것 삭제. 전부 mtime 기준(find -mtime, POSIX).
gc_runs() {
  local sd="${HARNESS_STATE_TTL_DAYS:-7}" ld="${HARNESS_LEDGER_TTL_DAYS:-30}" mk="${HARNESS_LEDGER_MAX_KB:-10240}" f
  find "$DIR" -type f \( -name '*.writes' -o -name '*.batches' -o -name '*.start' -o -name '*.tok0' -o -name '*.dirty' -o -name '*.tested' \) -mtime +"$sd" -delete 2>/dev/null
  find "$DIR" -type f \( -name '*.jsonl' -o -name '*.jsonl.1' \) -mtime +"$ld" -delete 2>/dev/null
  for f in "$DIR"/*.jsonl; do [ -f "$f" ] || continue
    [ "$(( $(wc -c < "$f") / 1024 ))" -gt "$mk" ] && mv -f "$f" "$f.1"
  done; return 0
}
# append-only 카운터: read-modify-write 는 병렬 hook 에서 카운트를 잃는다. 한 줄 append 는 원자적이다.
bump() { echo 1 >> "$1"; wc -l < "$1" | tr -d ' '; }
