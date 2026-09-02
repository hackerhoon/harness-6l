# Changelog

이 프로젝트는 [Semantic Versioning](https://semver.org/)을 따릅니다.

## [1.2.0] - 2026-09-02

1.1.0이 「다음 라운드 후보」로 남긴 5건을 전부 처리했다. 새 hook 동작은 실기 시험(fail-closed 3경로·GC TTL/로테이션·작업 판정 4종·리포터·경합·비밀 회귀)을 거쳤다.

### Added
- **`HARNESS_FAIL_CLOSED=1`** — 무인·CI용 opt-in. jq/`CLAUDE_PROJECT_DIR`/디렉토리 부재 시 통과 대신 정지(PreToolUse→deny, PostToolBatch/Stop→exit 2, 차단 불가 이벤트는 경고). 이벤트명은 jq·grep·sed 없이 bash 내장 정규식으로 읽는다. `1`/`true`/`yes`/`on` 허용
- **상태 파일·원장 자동 정리** — 작업 첫 배치에서 `gc_runs`: 상태 파일 7일 TTL, 원장 10MB 로테이션(`.1`)·30일 TTL. 환경변수로 조정
- **작업 완료 원장 `<sid>.tasks.jsonl`** — `test_gate.sh`가 Stop에서 작업 1건을 기록(verdict: `complete-tested` / `complete` / `complete-escalated` / `complete-forced`, `task_blocked`). 모든 원장 레코드에 `task` 키. `tool_failures`는 PermissionDenied를 세지 않는다
- **`assets/scripts/harness_report.sh`** — 논문의 "진짜 지표"(테스트 증거 동반·권한 차단 없이 완료된 작업 수)와 완료율·에스컬레이션률·허위 완료 차단·복구 시간을 원장에서 계산. 재작업률·비용은 계측 불가로 명시
- **`assets/scripts/run_trigger_eval.sh`** — `claude plugin eval` 게이트를 감지해 열리면 `evals/trigger_eval.json`을 실행, 아니면 건수 표기 후 스킵
- **`references/multi-agent-team.md`** — 에이전트 팀 모드(TeamCreate/SendMessage) 전용 내용을 분리. 서브에이전트 모드 호출에서 로드되지 않음
- `enforcement.md` 「환경변수 한눈에」「fail-closed」「작업 완료 원장과 스코어카드」「상태 파일·원장 정리」절

### Changed
- `layers.md` L6 계측 소스 표: 완료율·복구시간·에스컬레이션률의 소스가 `harness_report.sh`로 실재
- `scripts/check.sh` 80+ 항목, CI에 fail-closed·리포터 실기 추가

## [1.1.0] - 2026-09-02

2라운드 적대적 검증(논문 원문 대조 · 실사용 시뮬레이션 · 트리거/경제성 · 보안/이식성 4개 검사관 + 독립 재검증)의 결과. 1.0.0의 hook은 **문서대로 설치하면 1분 안에 에이전트를 정지시켰다.** 1.0.0 사용자는 반드시 갱신하라.

### Fixed
- **[치명] 결정 필터 Q2와 센서 커버리지 Q5의 극성 역전.** "예 = 필요/충족"으로 통일. 두 곳이 서로 다른 검사관에게 독립 적발돼 실패 클래스("질문 극성 ↔ 집계 규칙 불일치")로 규범화(`skill-authoring.md`)
- **[치명] `loop_budget.sh` 토큰 합산 폭주** — `cache_read`를 턴마다 재합산해 실제 세션에서 예산의 14,903배. 정의를 "유니크 requestId 기준 input+output, 작업 시작 기준선 대비 증가분"으로 교체. 스트리밍 파싱
- **[치명] 카운터 경합** — 동시 hook에서 10회 중 9회 카운트 손실. append-only로 교체(동시 20건 = 20 검증)
- **[치명] 원장에 `tool_input` 전문(API 키 포함) 평문 기록.** tool 이름·파일 경로·명령 첫 토큰(환경변수 대입 건너뜀)만 기록. `_workspace/runs/` gitignore 지시
- **[치명] jq 부재 시 `nojq` SID 공유로 전 세션 자기 DoS.** 3종 모두 경고 + fail-open. 부분 강제 주장 삭제
- **[치명] 논문 인용 104곳이 원문에서 해석 불가** — 요약본의 §0~§14를 원문 로마자 §I~§XVIII로 재매핑, 자기 절 참조와 구분
- `Bash(rm -rf *)` deny가 `rm -fr`·`rm -r -f`를 통과시킴(실증) → `rm` 전체를 ask로. "이중 강제" 표기 철회
- `audit_log.sh`가 `PermissionDenied`를 기록하지 않아 "권한 경계 차단 1회" 조건에 데이터 소스가 없었음
- hook의 per-task 예산이 per-session으로 구현되어 리셋 경로 없음 → `session_id-prompt_id` 키로 작업 단위, 다음 프롬프트에서 자연 리셋
- 입력 정제 — `session_id`의 `../` 경로 탈출, NUL 바이트 증거 위장(`Read\0BAD`→`Read_BAD`로 흔적 보존)
- `CLAUDE_PROJECT_DIR` 미설정 시 cwd에 상태 분열 → 경고 + fail-open
- 원문 `agentic_loop`의 `retryable` 분기 소실 — 재시도 불가 실패는 예산 소모 없이 즉시 에스컬레이션
- GROUND에서 테스트 exit 1(빨간 상태)의 진행/중단 규정 없음 → "명령이 올바르면 진행·기록, 명령 자체가 틀리면 중단"
- hook 강제성 판정 기준이 "설치"로만 쓰여 구축 완료 시점에 `enforced_by: hook` 허위 표기 가능 → "설치 + 사용자 등록" 이후로
- 핸드오프 5번째 필드 "기한(deadline)" 복구, 검증자 실패 보고(6필드)와 명칭 분리

### Added
- **`test_gate.sh`** — 소스 수정 후 테스트 미실행 시 Stop hook이 완료 차단. 실패 클래스 "센서 미실행 / 허위 완료 보고" 신설(스킬 트리거 (6)의 대표 시나리오였는데 분류표에 없었다)
- **`assets/hooks/SHA256SUMS`** 무결성 확인 + "저장소가 공급하는 hook은 신뢰 게이트 없이 실행된다" 경고
- **`evals/trigger_eval.json`** — should 12 / near-miss 12 트리거 회귀 스위트(공식 마켓플레이스 관례 형식)
- **description 부정 예시** — update-config / init / claude-code-guide / security-review / loop 경계 명시, 영어 앵커. 예측 오분류 8/24 → 2/24
- `scripts/check.sh` 회귀 스위트(70+ 항목) + GitHub Actions(`check.yml`, Linux에서 hook 실기)
- `references/verifier-web-checklist.md` — Next.js/React 전용 체크리스트 분리(파이썬 프로젝트에서 ~200줄 과잉 로딩 해소)
- `harness.md` 템플릿에 `## 결정 필터`, `## 가이드 가지치기`, 비상 정지·무인 3회 성공·규칙 5개+ 조건, 최근 센서 관측
- `enforcement.md` 「hook 보안·한계」절 — 이전 판이 침묵한 11항목 전부 고지
- 서두에 실증 근거 1줄과 §XV.A 반증("하네스에 코드 직접 쓰기보다 더 많은 시간")

### Changed
- SKILL.md 255→182줄. 강제성 표·마이그레이션·무인 게이트·계측 소스 표·테스트 시나리오를 reference/템플릿으로 이관(정본 1곳 원칙)
- 토큰 예산 정의: "청구액"도 "컨텍스트 크기"도 아닌 "새로 처리된 입력 + 생성 출력"
- 요구사항 명시: bash 4+, jq, Claude Code 2.1.196+. Alpine/ash/dash·네이티브 Windows 미지원
- 검증 환경 표기 2.1.252~2.1.258 / macOS + Debian·Alpine
- frontmatter `allowed-tools` 선언은 보류 — 사용자 스코프/플러그인 양쪽에서 `${CLAUDE_SKILL_DIR}` 치환이 확인될 때까지

### 다음 라운드 후보 (이번 릴리스 범위 밖 — 논문 §XIV(한계).A "최소 인프라")
- `HARNESS_FAIL_CLOSED=1` opt-in — jq 부재 시 fail-open 대신 차단
- `_workspace/runs/` 원장 로테이션·상태 파일 자동 정리
- "진짜 지표"(작업 단위 완료 수) 계측 자산 — `TaskCompleted` hook 예시
- `multi-agent.md` 팀 모드 ~200줄의 조건부 분리
- `claude plugin eval` 게이트가 열리면 `evals/trigger_eval.json` 실행 배선

## [1.0.0] - 2026-09-02

`harness-6l`의 첫 릴리스. [revfactory/harness](https://github.com/revfactory/harness) 1.2.0의 파생 저작물이며, 6계층 하네스 아키텍처로 재구성했습니다. 전체 파생 관계와 변경 고지는 [`NOTICE`](NOTICE)에 있습니다.

### Added
- **L5 권한 계층** — capability budget을 `settings.json` deny/ask/allow로 매핑, PreToolUse hook, 샌드박스 네트워크 allowlist, 서브에이전트 frontmatter 제약
- **`enforced_by` 필드** — 모든 예산·제약 라인이 강제 수단(`settings`/`hook`/`subagent`/`sandbox`/`-p-flag`/`none`)을 선언한다. `none`은 별도 집계
- **L6 관찰가능성** — 구조화 원장, 트립와이어 6종, 계측 가능성별로 구분한 스코어카드
- **L2 센서** — 계산적/추론적 구분, 자기검증 패턴, 센서 커버리지 테스트 5문항, 적대적 센서 원칙
- **L3 루프 경계** — Table IV 6종과 각각의 강제 수단, 에스컬레이션 패킷 5요소
- **L4 체크포인트 만료** — 활성 작업당 최신 1개, 덮어쓰기가 곧 만료
- **하네스 결정 필터** — 하네스를 만들지 않는 것도 산출물. 수용 기준 문항 포함
- **래칫 프로토콜** — 실패 분류표, 통제 신뢰도 사다리, 6단계 엔지니어링 루프, 3회 규칙, 가지치기, 롤백 조건
- **번들 hook 3종** — `policy_gate.sh`, `loop_budget.sh`, `audit_log.sh`
- **마이그레이션 경로** — 기존 하네스 보유 프로젝트 진입 절차, drift·dangling·무효 권한 규칙 감사
- `references/layers.md`, `references/enforcement.md`, `assets/**` (원본 저작물)

### Changed
- **`model: "opus"` 무조건 강제 철회.** 작업에 맞는 최소 모델이 기본. `model` 파라미터 명시 요구는 유지
- **검증자에게서 Edit/Write 제거.** 검증자는 산출물을 다시 쓰지 않고 실패를 보고한다
- **CLAUDE.md가 L1 가이드 본체.** "포인터 + 변경 이력만" 조항 철회
- 확장 게이트를 팀 생성이 아니라 **무인 운영 승격**에 적용. 팀·오케스트레이터는 즉시 생성
- 진입 경로를 4종으로 분리 — 항상 1단계부터 밟지 않는다
- 스킬 테스트를 계산적/추론적 **센서** 언어로 재프레이밍
- `references/` 6개로 통합 (agent-design-patterns + orchestrator-template + team-examples → multi-agent, skill-writing-guide + skill-testing-guide → skill-authoring, qa-agent-guide → verifier-agent)

### Removed
- **`AGENTS.md` 산출 조항.** Claude Code는 `CLAUDE.md`를 읽고 `AGENTS.md`는 읽지 않는다
- **"`.claude/commands/`에 아무것도 생성하지 않음" 검증 항목.** 커스텀 커맨드는 스킬로 통합되었다

### Fixed
- 경계면 교차 비교를 추론적 센서가 아닌 **계산적 센서**로 재분류 (grep 기반 결정적 검사)
- `_workspace/` 중간 산출물 무조건 보존 → 체크포인트는 만료, 아티팩트는 보존으로 분리
