# harness-6l hook 공통 프렐류드 — 각 스크립트가 source 한다. 단독 실행 대상 아님.
# 설계 원칙: 강제할 수 없으면 조용히 통과시키지 않고 "경고 + exit 0(fail-open)"으로 알린다.
set -u
_H="${_HOOK_NAME:-hook}"
warn() { echo "harness/${_H}: $*" >&2; }
command -v jq >/dev/null 2>&1 || { warn "jq 미설치 — 이 hook은 비활성(fail-open)이다. 이 hook에 의존하는 예산의 enforced_by 는 none 이다."; exit 0; }
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || { warn "CLAUDE_PROJECT_DIR 미설정(Claude Code 2.1.196+ 필요) — 비활성(fail-open)."; exit 0; }
INPUT=$(cat)
# 입력 정제: session_id / prompt_id / tool_name 은 파일명·원장 키로 쓰이므로 [A-Za-z0-9_-] 만 허용한다.
# (경로 탈출 ../, NUL, 개행, 유니코드 위장 전부 제거)
san() { printf '%s' "$1" | tr -cd 'A-Za-z0-9_-' | cut -c1-64; }
SID=$(san "$(jq -r '.session_id // "unknown"' <<<"$INPUT")"); [ -n "$SID" ] || SID=unknown
PID_=$(san "$(jq -r '.prompt_id // "p0"' <<<"$INPUT")");   [ -n "$PID_" ] || PID_=p0
KEY="${SID}-${PID_}"                      # 작업(task) = 사용자 프롬프트 1턴. 다음 턴에서 자연 리셋된다.
DIR="$CLAUDE_PROJECT_DIR/_workspace/runs"
mkdir -p "$DIR" 2>/dev/null || { warn "$DIR 생성 실패 — 비활성(fail-open)."; exit 0; }
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
# append-only 카운터: read-modify-write 는 병렬 hook 에서 카운트를 잃는다. 한 줄 append 는 원자적이다.
bump() { echo 1 >> "$1"; wc -l < "$1" | tr -d ' '; }
