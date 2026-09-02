# harness-6l

**6계층 에이전트 하네스 엔지니어링 스킬 for Claude Code.**

에이전트를 "잘 굴러가게" 만드는 것은 프롬프트가 아니라 그 주위의 인프라다. 이 스킬은 그 인프라를 여섯 계층 — **가이드 · 센서 · 에이전틱 루프 · 메모리 · 권한 · 관찰가능성** — 으로 나누어 구성·점검·진화시킨다.

논문 **『Harness Engineering — Agent = Model + Harness: The 6-Layer Production Playbook』**(2026년 8월, 독립 편집본)의 6계층 아키텍처를 참고해, 그 계층들을 Claude Code가 **실제로 강제할 수 있는 수단**에 대응시킨 구현이다.

> **English:** A Claude Code skill for six-layer agent-harness engineering (guides, sensors, agentic loop, memory, permissions, observability). It maps each layer onto the mechanisms that Claude Code can *actually* enforce — `settings.json` permission rules, `PreToolUse`/`PostToolBatch` hooks, sub-agent frontmatter, the OS sandbox — and requires every budget line to declare `enforced_by`, so a control that is merely documented is never mistaken for one that is enforced. **The skill content is written in Korean.**

---

## 이 스킬이 다른 점

대부분의 "에이전트 팀" 도구는 *누가(에이전트) / 어떻게(스킬)* 를 조립한다. 그것만으로는 에이전트가 조용히 틀린 결과를 내는 것을 막지 못한다. 이 스킬이 추가하는 것은 나머지다.

가장 중요한 장치는 **`enforced_by`** 다. 문서에 `COST: max $5`라고 적는 것과 실제로 $5에서 멈추는 것은 다르다. 그 차이를 숨기면 하네스는 "안전으로 위장한 병목"이 된다. 그래서 이 스킬이 산출하는 모든 예산·제약 라인은 강제 수단을 함께 선언한다.

| 제약 | Claude Code 실제 | `enforced_by` |
|---|---|---|
| ALLOW / ASK / DENY | `permissions.*` (deny→ask→allow, 첫 매치 확정) | `settings` |
| 작업당 쓰기 한도 | 네이티브 없음 → PreToolUse hook 카운터 | `hook` |
| 소요시간 · 도구 배치 · 토큰 | 네이티브 없음 → `PostToolBatch` hook `exit 2` | `hook` |
| 단계당 재시도 3회 | 서브에이전트 frontmatter `maxTurns` | `subagent` |
| 새 도메인 접촉 차단 | `sandbox.network.allowedDomains` | `sandbox` |
| **비용 $5/task** | **대화형에 강제 수단 없음.** `claude -p --max-budget-usd`에서만 | `-p-flag` / **`none`** |
| 신뢰/비신뢰 입력 분리 | 네이티브 프리미티브 없음 | **`none`** + 행동반경 축소 |

`enforced_by: none`인 라인은 별도로 집계된다. 그것은 "환경 제약"이 아니라 "가이드"이며, 지켜지지 않아도 아무도 막지 않는다.

---

## 6계층

| 계층 | 역할 | Claude Code 실현 수단 | 강제되는가 |
|---|---|---|---|
| **L1 가이드** | 실행 전 알려진 실패 예방 | `CLAUDE.md`, `.claude/rules/*.md` (`paths:` 스코프) | 아니오 — 컨텍스트이지 강제 설정이 아니다 |
| **L2 센서** | 실행 후 실패 포착 | 프로젝트 test/lint/typecheck를 루프에 배선 | 종료코드로 관측, hook으로 차단 |
| **L3 루프** | 계획·실행·검증·수정 + 유한 재시도 | 서브에이전트 `maxTurns`, `PostToolBatch` hook | 부분 |
| **L4 메모리** | 세션 간 상태 지속 | `_workspace/` 파일 | 플랫폼 마찰 없음 |
| **L5 권한** | 안전 경계 | `settings.json`, PreToolUse hook, 샌드박스 | **예 — 유일하게 완전 강제되는 계층** |
| **L6 관찰가능성** | 추적·경보·회귀 포착 | transcript, hook 원장, OTel, `-p --output-format json` | 아니오 — 관측 계층 |

---

## 설치

```bash
/plugin marketplace add hackerhoon/harness-6l
/plugin install harness-6l@harness-6l-marketplace
```

비대화형:

```bash
claude plugin marketplace add hackerhoon/harness-6l
```

설치하면 `/harness-6l:harness` 로 호출된다.

**요구사항:** Claude Code 2.1.196+ (`CLAUDE_PROJECT_DIR`), 번들 hook을 쓰려면 **bash 3.2+ 와 jq**. Alpine/ash/dash, 네이티브 Windows에서는 hook이 동작하지 않는다(스킬 본체는 동작). 검증 환경은 macOS + Debian·Alpine(2.1.252~2.1.258).

> 원본 `harness` 플러그인을 함께 설치해 두었다면 트리거 문구가 겹친다. `~/.claude/settings.json`의 `enabledPlugins`에서 한쪽을 `false`로 두는 것을 권한다.

---

## 사용

```
하네스 구축해줘
하네스 점검해줘
에이전트가 같은 실수를 반복하는데 재발을 막아줘
이 에이전트를 무인으로 돌려도 될까?
```

스킬은 먼저 **하네스 결정 필터**를 통과시킨다. 반복 실행인가 / 조용히 틀리면 알아차리는가 / 세션 간 상태가 필요한가 / 실수가 외부 결과를 만드는가 — 전부 아니오면 **하네스를 만들지 않고 그 이유를 답한다.** 만들지 않는 것도 정당한 산출물이다.

그다음 다섯 단계를 밟는다: **SCOPE → GROUND → WIRE → BUILD → RATCHET.** 다만 항상 1단계부터 밟지는 않는다 — 진입점은 계층 번호가 아니라 관찰된 실패가 가리키는 계층이다.

| 프로젝트 상태 | 경로 |
|---|---|
| 신규 / 하네스 계층 0개 | 1 → 2 → 3 → 4 → 5 |
| 성숙 (테스트·린터·CI 보유) | 1 → **3** → 4 → 5 |
| 관찰된 실패가 명확 | 1 → **5 직행** |
| 기존 하네스 운영 | 1(drift 감사) → 5 |

---

## 구성

```
skills/harness/
├── SKILL.md                      진입 라우터 — 결정 필터, 5단계, 강제성 표, 체크리스트
├── references/
│   ├── layers.md                 6계층 규범과 Claude Code 실현 수단
│   ├── enforcement.md            settings.json 문법 · hook 규약 · 서브에이전트 · 샌드박스
│   ├── ratchet.md                실패를 영구 인프라로 전환하는 절차 · 운영/유지보수
│   ├── multi-agent.md            패턴 · 서브에이전트 오케스트레이터 · 핸드오프 · 독립 검증자
│   ├── multi-agent-team.md       에이전트 팀 모드(TeamCreate/SendMessage) — 팀 설계 시에만 로드
│   ├── skill-authoring.md        스킬 작성 · 센서로서의 스킬 평가 · 트리거 회귀
│   ├── verifier-agent.md         검증 에이전트 — 스택 중립 골격, 실제 버그 7건
│   └── verifier-web-checklist.md 웹(Next.js/React) 경계면 체크리스트 — 웹 프로젝트에서만 로드
├── assets/
│   ├── claude-md-harness-section.md
│   ├── settings-permissions.template.json
│   ├── workspace-harness.template.md
│   ├── hooks/{_common,policy_gate,loop_budget,audit_log,test_gate}.sh + SHA256SUMS
│   └── scripts/{harness_report,run_trigger_eval}.sh   스코어카드 리포터 · eval 배선
└── evals/trigger_eval.json       트리거 회귀 스위트 (should 12 / near-miss 12)
```

저장소 루트의 `scripts/check.sh`는 70여 항목의 회귀 스위트다. 적대적 검증에서 확정된 수정이 되돌아가지 않았는지 검사하며 CI(`.github/workflows/check.yml`)가 push마다 Linux에서 hook까지 실기한다.

hook 4종은 **선택**이다. 설치하지 않으면 해당 예산은 `enforced_by: none`이며, 스킬은 상태 파일에 그렇게 적는다.

| 스크립트 | 이벤트 | 강제하는 것 |
|---|---|---|
| `policy_gate.sh` | PreToolUse | 작업당 쓰기 한도 초과 시 `deny`(쓰기 동결) |
| `loop_budget.sh` | PostToolBatch | 시간·배치·토큰 초과 시 `exit 2`로 루프 중단 |
| `audit_log.sh` | PostToolUse + PostToolUseFailure + PermissionDenied | 감사 원장 — 완료율·복구시간·권한 차단의 유일한 데이터 소스 |
| `test_gate.sh` | PostToolUse + Stop | 소스를 수정하고 테스트를 안 돌린 채 완료 보고하면 **차단** |

- 카운터는 `session_id-prompt_id` 키로 **작업(사용자 프롬프트 1턴) 단위**다. 다음 프롬프트에서 자연 리셋된다.
- 토큰 예산은 "유니크 요청의 input + output" 증가분이다. 캐시 필드를 세면 실제 세션에서 예산의 14,000배가 나온다(1.0.0의 결함).
- `jq`가 없거나 `CLAUDE_PROJECT_DIR`가 없으면 **경고를 내고 통과시킨다(fail-open)**. 그 환경에서 hook 예산의 `enforced_by`는 `none`이다. 부분 강제는 없다. 무인·CI에서는 `HARNESS_FAIL_CLOSED=1`로 통과 대신 **정지**시킬 수 있다.
- 상태 파일은 7일, 원장은 30일 TTL로 작업 첫 배치에서 자동 정리되고 원장은 10MB에서 로테이션된다(`HARNESS_*_TTL_DAYS`, `HARNESS_LEDGER_MAX_KB`).
- `assets/scripts/harness_report.sh`가 원장에서 **진짜 지표**(테스트 증거를 동반하고 권한 차단 없이 끝난 작업 수)·완료율·에스컬레이션률·복구시간을 계산한다.
- **hook은 설치만으로 발화하지 않는다.** 사용자가 `settings.json`에 hooks 블록을 등록해야 한다. 등록은 에이전트가 못 하므로 **구축 완료 시점의 hook 예산은 항상 `none`**이고, 스킬은 그렇게 적는다.

---

## upstream `harness` 와 달라진 점

| 항목 | upstream 1.2.0 | harness-6l |
|---|---|---|
| 모델 | 모든 에이전트에 `model: "opus"` **강제** | 작업에 맞는 **최소 모델**. `model` 파라미터 *명시*는 유지 |
| 검증자 | 검증 스크립트 실행을 위해 쓰기 가능 타입 권장 | Edit/Write **제외**. 검증자는 다시 쓰지 않고 **보고**한다 |
| 가이드 파일 | CLAUDE.md는 "포인터 + 변경 이력만" | **CLAUDE.md가 L1 가이드 본체.** `AGENTS.md`는 만들지 않는다 |
| 권한 | 없음 | `settings.json` 라인 제시 + hook + 샌드박스, `enforced_by` 표기 |
| 관찰가능성 | 변경 이력 테이블 | 구조화 원장 · 트립와이어 6종 · 계측 가능성별 지표 구분 |
| 체크포인트 | 중간 산출물 **보존** | 활성 작업당 **최신 1개** — 덮어쓰기가 곧 만료 |
| 확장 게이트 | 없음 | **무인 운영 승격**에만 게이트. 팀 생성은 즉시 |
| 완료 보고 | 신뢰 | `test_gate.sh` — 수정 후 테스트 미실행이면 Stop hook이 **차단** |
| 트리거 | 긍정 예시만 | 부정 예시·빌트인 경계·영어 앵커. 회귀 스위트 24건 파일화 |

전체 변경 내역은 [`NOTICE`](NOTICE) 참조.

---

## 보안

이 스킬은 자기를 "1차 보안 경계(L5)"라고 부른다. 그래서 2라운드 검증에서 보안 검토를 받았고, 다음이 그 결과다.

- **원장에 비밀을 쓰지 않는다.** hook은 `tool_input` 전문을 기록하지 않는다 — 도구 이름, 파일 경로, 명령의 첫 실행 파일명(환경변수 대입 `KEY=…`는 건너뜀)만 남긴다. 그래도 `_workspace/runs/`는 **반드시 `.gitignore`에 넣는다.** 스킬이 3단계에서 자동으로 추가한다.
- **hook은 사용자 권한으로, 워크스페이스 신뢰 없이 실행된다.** 남의 저장소를 열 때 `.claude/hooks/`에 이 스킬의 파일명을 흉내 낸 스크립트가 있을 수 있다. `assets/hooks/SHA256SUMS`로 무결성을 확인하고, 모르는 저장소의 hook은 **열기 전에 읽어라.**
- **입력은 정제된다.** `session_id`의 `../` 경로 탈출, NUL 바이트 위장(`Read\0BAD`)은 파일명·원장에 도달하지 못한다.
- **`rm`은 패턴으로 못 막는다.** `Bash(rm -rf *)` deny는 `rm -fr`을 통과시킨다(실증). 템플릿은 `rm` 전체를 ask로 두고, 내장 critical-path 가드(루트·홈·cwd)에 나머지를 맡긴다.
- **fail-open은 설계다.** 강제할 수 없는 상황에서 세션을 벽돌로 만드는 대신 경고하고 통과시킨다. 그 대가로 `enforced_by`가 정직해야 한다 — 그것이 이 스킬의 중심 장치다. 사람이 없는 실행에서는 `HARNESS_FAIL_CLOSED=1`로 반대 선택을 할 수 있다.

상세는 `references/enforcement.md`의 「hook 보안·한계」.

---

## 한계 (정직하게)

- **스코어카드 6지표 중 네이티브 데이터 소스가 있는 것은 2개**다(에스컬레이션률, 가이드 증가율). 재작업률과 작업당 비용은 OTel을 켜거나 `claude -p`로 감싸야 하고, **완료율과 복구시간은 hook 원장을 설치해야만 존재한다.** 대화형 transcript에는 비용 필드가 없다.
- **비용 예산은 대화형에서 강제되지 않는다.** 토큰 프록시로 근사할 뿐이다.
- hook 4종은 `bash 3.2+`와 `jq`에 의존한다. 없으면 전부 **fail-open**(경고 출력)이며 그 환경에서 `enforced_by`는 `none`이다.
- `loop_budget.sh`의 배치 카운터는 도구 호출 수가 아니라 도구 **배치** 수다. 한 배치에 여러 도구가 들어갈 수 있다.
- 트립와이어 "센서 통과율 하락"은 도구 실패율의 프록시일 뿐 센서 판정을 구분하지 못한다.
- `claude plugin eval`은 early-access다. `assets/scripts/run_trigger_eval.sh`가 게이트를 감지해 열리면 실행하고 아니면 스킵한다.
- 검증 기준은 **Claude Code 2.1.252~2.1.258 / macOS + Debian·Alpine**이다. 권한·hook 문법은 버전에 따라 달라질 수 있다.
- 스킬 본문은 **한국어**다.

---

## 라이선스 및 귀속

Apache License 2.0.

이 프로젝트는 [revfactory/harness](https://github.com/revfactory/harness) 1.2.0 (Copyright 2025 robin, Apache-2.0)의 **파생 저작물**이다. 변경한 파일은 각 파일 끝에 변경 고지를 달았고, 전체 내역은 [`NOTICE`](NOTICE)에 있다.

**참고 문헌:** 이 스킬의 6계층 구조·래칫 원리·통제 신뢰도 사다리·빌드 경로·결정 프레임워크는 논문 **『Harness Engineering — Agent = Model + Harness: The 6-Layer Production Playbook』**(Production Agent Engineering Practice 2026, 2026년 8월 독립 편집본)을 참고해 만들었다. 논문 본문은 이 저장소에 포함하지 않았고, 논문의 표기대로 그 문서는 Google·OpenAI·Anthropic·HashiCorp 어디와도 제휴·보증 관계가 없다. 스킬의 절 인용(`논문 §III(가이드)` 등)은 그 논문의 절 번호다.

그 논문 자체가 종합한 1차 자료 — 6계층 구조·래칫 원리·guides-and-sensors 분류·통제 신뢰도 사다리는 공개된 엔지니어링 글에서 온 개념이다 — Mitchell Hashimoto(래칫), Birgitta Böckeler·Martin Fowler(guides and sensors), OpenAI Codex 필드 리포트, LangChain 엔지니어링, Lauren Tan·Cursor(반복 리뷰 코멘트의 구조화). 아이디어 출처로 밝히는 것이며 본문을 옮기지 않았다. 이 프로젝트는 위 어떤 조직과도 제휴·보증 관계가 없다.
