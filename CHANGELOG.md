# Changelog

이 프로젝트는 [Semantic Versioning](https://semver.org/)을 따릅니다.

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
