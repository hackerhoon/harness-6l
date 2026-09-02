# 강제 수단 — settings.json · hooks · 서브에이전트 · 샌드박스

이 파일은 "환경(최고 신뢰도) 계층"을 Claude Code에서 **실제로** 만드는 방법이다. 여기 적힌 것만이 모델의 의사와 무관하게 차단한다. 나머지는 전부 가이드다.

**검증 기준:** Claude Code 2.1.252 / macOS, 2026-09-02, 공식 문서 확인. 버전이 크게 다르면 문법을 다시 확인한다.

## 목차
- [무엇이 실제로 강제되는가](#무엇이-실제로-강제되는가)
- [permissions 문법](#permissions-문법)
- [설정 우선순위와 병합](#설정-우선순위와-병합)
- [Capability Budget 템플릿](#capability-budget-템플릿)
- [hooks](#hooks)
- [자기 권한 확대 차단](#자기-권한-확대-차단)
- [서브에이전트 예산](#서브에이전트-예산)
- [샌드박스 — OS 레벨 차단](#샌드박스--os-레벨-차단)
- [관찰가능성 데이터 소스](#관찰가능성-데이터-소스)
- [흔한 함정](#흔한-함정)

---

## 무엇이 실제로 강제되는가

"환경(최고)" 자격을 갖는 것은 다섯 가지뿐이다.

| # | 수단 | 무엇을 강제하나 |
|---|---|---|
| a | `settings.json`의 `permissions` deny/ask/allow | 도구·경로·명령 접근 |
| b | **PreToolUse hook의 `deny`** | 모든 권한 모드보다 먼저 발화하며 `bypassPermissions`도 뚫는다 |
| c | 서브에이전트 frontmatter (`tools`, `maxTurns`, `permissionMode` 등) | 서브에이전트의 능력과 턴 수 |
| d | `sandbox.network.allowedDomains` | OS 레벨 네트워크(서브프로세스 포함) |
| e | `claude -p --max-budget-usd` / `--max-turns` | 비용·턴 (print mode 전용) |

**그 외의 모든 예산 항목은 hook을 직접 구현했을 때만 이 등급에 도달한다.** 구현하지 않으면 가이드다. 산출하는 모든 예산 라인에 `enforced_by`를 다는 이유가 이것이다.

---

## permissions 문법

### 평가 순서 — 여기서 대부분의 실수가 난다

**deny → ask → allow, 첫 매치가 확정.** 구체성은 순서를 바꾸지 않는다.

`Bash(aws *)`가 deny에 있으면 allow의 `Bash(aws s3 ls)`는 **무효**다. 즉 **deny 규칙에 예외를 담을 수 없다.** 예외가 필요하면 deny를 더 좁게 쓴다.

`ask`는 더 구체적인 `allow`가 있어도 이긴다.

### 경로 앵커 4종 — 혼동하면 규칙이 조용히 빗나간다

| 표기 | 기준 |
|---|---|
| `//abs/path` | 파일시스템 루트 절대경로 |
| `~/path` | 홈 디렉토리 |
| `/path` | **설정 파일이 있는 위치 기준** — 절대경로가 아니다 |
| `path`, `./path` | 현재 작업 디렉토리 |

`/Users/alice/file`은 절대경로가 **아니다**. 절대경로는 `//Users/alice/file`이다.

### 파일 규칙은 `Read(...)`와 `Edit(...)`만 조회된다

`Write(경로)`, `NotebookEdit(경로)`, `Glob(경로)`, `MultiEdit(경로)`에 경로를 쓰면 규칙은 **수락되지만 절대 참조되지 않고** 시작 시 경고만 뜬다. 자기가 부여했다고 믿는 권한을 실제로는 갖고 있지 않게 된다.

**산출 템플릿에서 `Write(경로)` 형태를 쓰지 않는다.** 전부 `Edit(...)`/`Read(...)`로 쓴다.

`Read` deny는 같은 경로의 Edit/Write도 막는다. NotebookEdit은 별도로 `Edit` deny가 필요하다.

### Bash 규칙은 인자 제약에 취약하다

문서가 명시적으로 "fragile"이라고 경고한다. `Bash(curl http://github.com/ *)`는 `-X GET` 선행, https, 리다이렉트, 변수 치환, 여분 공백에 전부 뚫린다.

**URL·도메인 제어는 Bash 네트워크 도구를 deny하고 `WebFetch(domain:)` + 샌드박스 allowlist로 한다.**

**복합 명령은 각 서브커맨드가 독립적으로 매치돼야 한다.** 구분자: `&&`, `||`, `;`, `|`, `|&`, `&`, 개행. 출력 리다이렉션(`>`, `>>`, `2>`)의 타깃은 파일 쓰기로 검사된다.

**래퍼 스트리핑 목록은 빌트인이고 변경할 수 없다:** `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`, 플래그 없는 `xargs`.
**`npx`, `docker exec`, `devbox run`, `mise exec`는 스트리핑 대상이 아니다** — 즉 `Bash(devbox run *)`을 허용하면 `devbox run rm -rf .`도 허용한 것이다.

### 회로차단기 — allow로도 못 뚫는 것

`rm`/`rmdir`의 critical path(파일시스템 루트, 최상위 디렉토리, 홈, 작업 디렉토리와 그 부모)는 **allow 규칙으로도, PreToolUse hook의 `allow`로도 승인되지 않는다.** `$(...)`·백틱·프로세스 치환 안에 숨겨도 검출된다.

### 파라미터 매칭 (deny/ask 전용)

```json
"ask": ["Agent(model:opus)", "Bash(run_in_background:true)"]
```

`command`/`file_path`/`url` 같은 주 콘텐츠 필드에는 쓸 수 없다(무시 + 경고). 설정 파일에서 괄호가 있는 `mcp__` 규칙은 스킵된다 — MCP 파라미터 매칭은 `--disallowedTools`로만 된다.

### MCP 도구

`mcp__<server>__<tool>` 형태로 개별 deny, `mcp__*` 글롭으로 전체 deny. bare 이름 deny는 **도구를 컨텍스트에서 제거**한다.

---

## 설정 우선순위와 병합

높은 순서대로:

1. **Managed settings** — MDM/콘솔. 무엇으로도 덮을 수 없다(`--settings`, `--model` 포함)
2. **명령줄** — `claude --settings <file|json>`
3. `.claude/settings.local.json`
4. `.claude/settings.json`
5. `~/.claude/settings.json`

**어느 레벨에서든 deny면 다른 어떤 레벨도 allow로 뒤집지 못한다.** user deny가 project allow를 이기고 그 역도 성립한다.

**리스트 키(`permissions.allow` 등)는 덮어쓰기가 아니라 병합된다.**

### CI 함정 — 프로젝트 allow가 죽는다

프로젝트 `.claude/settings.json`의 `permissions.allow`와 `additionalDirectories`는 **워크스페이스 신뢰 다이얼로그를 수락한 뒤에만** 적용된다. `deny`/`ask`는 제한만 하므로 무관하다.

**`claude -p`와 SDK 세션은 신뢰 다이얼로그를 절대 띄우지 않는다.** 따라서 프로젝트 allow 규칙이 적용되지 않고 stderr에 `this workspace has not been trusted` 경고가 나온다. **CI 하네스는 권한을 `--settings`나 user 스코프로 전달해야 한다.**

반대로 **프로젝트의 hooks, `env`, `apiKeyHelper`, 프로젝트 스킬의 `allowed-tools`는 신뢰 없이도 실행된다.** 저장소가 공급하는 hook에는 신뢰 게이트가 없다 — 남의 저장소를 열 때의 공격면이다.

---

## Capability Budget 템플릿

논문 Template 2의 완전한 등가물이다. 이 JSON을 **사용자에게 제시**하고 사용자가 적용한다.

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force *)",
      "Bash(curl *)",
      "Bash(wget *)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "mcp__*"
    ],
    "ask": [
      "Bash(git push *)",
      "Bash(npm publish *)",
      "Bash(gh pr create *)"
    ],
    "allow": [
      "Read(/src/**)",
      "Read(/tests/**)",
      "Edit(/src/**)",
      "Edit(/tests/**)",
      "Bash(npm test *)",
      "Bash(npm run lint *)",
      "WebFetch(domain:docs.example.com)"
    ],
    "defaultMode": "default",
    "disableBypassPermissionsMode": "disable"
  }
}
```

제시할 때 각 줄에 무엇을 막는지와 `enforced_by`를 함께 쓴다.

**`sandbox.network.strictAllowlist`를 이 템플릿에 넣어 프로젝트 `.claude/settings.json`에 두면 무효다.** 이 키는 user/managed/`--settings` 스코프에서만 동작한다. 프로젝트 스코프에 두면 조용히 무시되어, 가지고 있지 않은 네트워크 경계를 가졌다고 믿게 된다. 샌드박스가 필요하면 `~/.claude/settings.json`에 별도로 제시한다.

| 논문 Template 2 | 위 JSON | `enforced_by` |
|---|---|---|
| `ALLOW read/write/execute` | `allow`의 `Read`/`Edit`/`Bash` | `settings` |
| `ASK before: git push, deploy` | `ask` | `settings` |
| `DENY: rm -rf, send_email` | `deny` + 회로차단기 | `settings` |
| `RATE: max 20 writes` | 대응 키 없음 → hook | `hook` |
| `COST: max $5` | 대응 키 없음 → `-p` 플래그 | `-p-flag` |
| `TIMEOUT: 30분` | 대응 키 없음 → hook | `hook` |

---

## hooks

### 규약

**입력(stdin JSON) 공통 필드:** `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `effort`. 서브에이전트 컨텍스트에서는 `agent_id`, `agent_type` 추가.
**툴 이벤트 필드:** `tool_name`, `tool_input`, `tool_use_id`. **PostToolUse는 `tool_response`를 받는다.**
**PostToolUseFailure는 `tool_response`가 없다** — 최상위 `error`, `is_interrupt`, `duration_ms`를 받는다. 두 이벤트의 입력 형태가 다르므로 같은 스크립트를 쓰려면 `hook_event_name`으로 분기해야 한다.

> **중요:** `PostToolUse`는 도구가 **성공적으로** 끝났을 때만 발화한다. 실패는 `PostToolUseFailure`로 간다. 감사 원장을 `PostToolUse` 한쪽에만 걸면 **모든 기록의 `ok`가 항상 true가 되어 실패율·완료율·복구시간을 잴 수 없다.** 반드시 두 이벤트 모두에 등록한다.

**종료코드:**
- `0` — 이의 없음. **PreToolUse에서 0은 승인이 아니다**(통상 권한 흐름이 그대로 적용된다)
- `2` — **차단.** stderr가 사유가 된다
- 기타 — stdout이 스키마를 통과하는 JSON이면 그것이 결정, 아니면 비차단 에러

**exit 2로 차단 가능한 이벤트:** PreToolUse, UserPromptSubmit, UserPromptExpansion, Stop, SubagentStop, **PostToolBatch**, TaskCreated, TaskCompleted, ConfigChange, PreModelSwitch, TeammateIdle.
**차단 불가:** PostToolUse, PostToolUseFailure, PermissionRequest, StopFailure.

**JSON 출력 형태:**
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow|deny|ask","permissionDecisionReason":"...","updatedInput":{},"additionalContext":"..."}}
```
`additionalContext`를 최상위에 두면 **조용히 무시된다.** 최상위에 올 수 있는 것은 `systemMessage`, `continue`, `stopReason`, `suppressOutput`.
**exit 2와 JSON 출력을 한 hook에서 섞지 않는다.**

**matcher:** 정확 매치(`"Bash"`), 대안(`"Edit|Write"`), 정규식(`"^Notebook.*"`), 전체(`"*"`), MCP(`"mcp__memory__.*"`).
**`PostToolBatch`, `UserPromptSubmit`, `Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `CwdChanged`, `MessageDisplay`는 matcher를 지원하지 않고 항상 발화한다.**

**`if` 필드**는 툴 이벤트 5종(PreToolUse/PostToolUse/PostToolUseFailure/PermissionRequest/PermissionDenied)에서만 동작한다. **다른 이벤트에 붙이면 hook이 아예 실행되지 않는다.** 또한 best-effort이므로 하드 차단을 여기에 의존하지 않는다.

**핵심 성질 두 가지:**
- **PreToolUse hook은 모든 권한 모드보다 먼저 발화한다.** `deny` 반환은 `bypassPermissions`와 `--dangerously-skip-permissions`에서도 도구를 막는다. 사용자가 모드를 바꿔도 우회할 수 없는 정책을 여기에 둔다.
- **역은 성립하지 않는다.** hook의 `allow`는 deny 규칙을 뚫지 못한다. **hook은 조일 수만 있고 풀 수는 없다.**

**타임아웃 기본값:** `command`/`http`/`mcp_tool` 600초, `prompt` 30초, `agent` 60초. UserPromptSubmit·PreModelSwitch·PostModelSwitch 30초, MessageDisplay 10초, SessionEnd는 전체 1.5초 공유. **PreToolUse가 타임아웃되면 도구 호출은 그대로 진행된다(차단이 아니다).**

**Stop hook은 연속 8회 차단 후 무효화된다.** 스크립트는 `stop_hook_active`를 검사해 조기 종료해야 한다.

**정의 위치:** `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`, managed, 플러그인 `hooks/hooks.json`, **스킬 frontmatter `hooks:`**(호출 후 세션 잔여 기간), **서브에이전트 frontmatter `hooks:`**(그 서브에이전트 실행 중).

### 등록

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write|NotebookEdit",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/policy_gate.sh", "timeout": 10 }] }
    ],
    "PostToolBatch": [
      { "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/loop_budget.sh" }] }
    ],
    "PostToolUse": [
      { "matcher": "*",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/audit_log.sh" }] }
    ],
    "PostToolUseFailure": [
      { "matcher": "*",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/audit_log.sh" }] }
    ]
  }
}
```

### 스크립트 3종 — 번들 자산이 정본이다

세 스크립트의 **정본은 `${CLAUDE_SKILL_DIR}/assets/hooks/`에 있다.** 이 문서에 사본을 두지 않는다 — 두 판본이 갈라지면 어느 쪽이 옳은지 알 수 없게 되고, 그것이 논문 §13이 경고한 "규칙 47과 규칙 183" 문제의 코드판이다.

대상 프로젝트에 설치한다:

```bash
mkdir -p .claude/hooks
cp "${CLAUDE_SKILL_DIR}"/assets/hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh
```

| 스크립트 | 이벤트 | 강제하는 것 | 없으면 |
|---|---|---|---|
| `policy_gate.sh` | PreToolUse (`Edit\|Write\|NotebookEdit`) | 작업당 쓰기 한도 → 초과 시 `deny`(쓰기 동결) | RATE 예산이 `enforced_by: none` |
| `loop_budget.sh` | PostToolBatch (matcher 미지원) | 소요시간·배치 수·토큰 → 초과 시 `exit 2`로 루프 중단 | 시간·토큰 예산이 `enforced_by: none` |
| `audit_log.sh` | PostToolUse **와** PostToolUseFailure | 감사 원장 기록 | 완료율·복구시간의 데이터 소스가 **아예 존재하지 않음** |

**`loop_budget.sh`의 카운터는 도구 호출이 아니라 도구 배치를 센다.** 한 배치에 여러 도구가 들어갈 수 있으므로, 배치 상한은 논문 Table IV의 "최대 도구 호출 50회"와 같은 단위가 아니라 그 하한선이다. 정확한 도구 호출 수가 필요하면 `policy_gate.sh`의 원장을 집계한다.

**환경변수로 조정한다:** `HARNESS_MAX_WRITES`(기본 20), `HARNESS_MAX_SECONDS`(1800), `HARNESS_MAX_BATCHES`(50), `HARNESS_MAX_TOKENS`(100000).

### jq 의존성 — 없으면 게이트가 열린다

세 스크립트 모두 `jq`를 쓴다. `jq`가 없으면:

- `policy_gate.sh` — 아무것도 막지 못한다(**fail-open**). stderr로 경고하고 통과시킨다. 세션을 벽돌로 만드는 것보다 낫지만, **그 환경에서 RATE 예산의 `enforced_by`는 `none`이다.** 상태 파일에 그렇게 기록한다
- `loop_budget.sh` — 시간·배치 예산은 그대로 강제하고 **토큰만 계측 불가**가 된다
- `audit_log.sh` — 원장을 남기지 못한다. 완료율·복구시간이 계측 불가가 된다

설치 전에 `command -v jq`로 확인한다. macOS는 시스템 기본 제공, Linux는 배포판에 따라 다르다.

## 자기 권한 확대 차단

**이것은 방침이 아니라 플랫폼 사실이다.** `.claude`는 protected directory이고, `permissions.allow`의 `Edit(.claude/**)`는 protected-path 쓰기를 **사전승인하지 못한다** — 안전검사가 allow 평가보다 먼저 실행되기 때문이다.

모드별 결과: default/acceptEdits는 프롬프트, auto는 classifier 심사, dontAsk는 거부, **bypassPermissions는 허용(유일한 구멍)**.

완전히 잠그려면 3중으로 건다.

```json
{
  "permissions": {
    "deny": [
      "Edit(//Users/<you>/.claude/settings.json)",
      "Edit(//Users/<you>/.claude/settings.local.json)",
      "Edit(/.claude/settings.json)",
      "Edit(/.claude/settings.local.json)",
      "Bash(claude config *)"
    ],
    "disableBypassPermissionsMode": "disable"
  }
}
```
여기에 PreToolUse hook의 deny를 더한다 — (a) deny는 어느 레벨의 allow도 이기고, (b) `disableBypassPermissionsMode`는 어느 스코프에서든 작동하며, (c) **PreToolUse hook deny만이 `bypassPermissions`까지 막는다.**

**따라서 하네스는 settings.json을 직접 쓰지 않고 라인을 제시한다.** 예외: 사용자가 권한 프롬프트에서 "이 세션 동안 Claude가 자기 설정을 편집하도록 허용"을 선택하면 그 세션 내 `.claude/` 쓰기는 더 이상 묻지 않는다.

---

## 서브에이전트 예산

`maxTurns`가 논문 Table IV "단계당 최대 재시도 3회"의 **유일한 네이티브 강제 수단**이다.

```markdown
---
name: verifier
description: 산출물을 독립 검증하고 실패를 보고한다. 수정하지 않는다.
tools: Read, Grep, Glob, Bash
disallowedTools: Edit, Write, NotebookEdit, WebFetch, mcp__*
model: sonnet
permissionMode: dontAsk
maxTurns: 3
memory: project
hooks:
  PostToolBatch:
    - type: command
      command: "${CLAUDE_PROJECT_DIR}/.claude/hooks/loop_budget.sh"
---
```

- `permissionMode: dontAsk` — allow에 없으면 전부 자동 거부. 최소 권한의 기본값으로 쓴다.
- 검증자에게 `Edit`/`Write`를 주지 않는다. 검증자는 **다시 쓰지 않고 보고한다.**
- 설정 측 레버: `deny: ["Agent(<name>)"]`, `ask: ["Agent(model:opus)"]`, 환경변수 `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`(기본 3), `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`(기본 20).

---

## 샌드박스 — OS 레벨 차단

```json
{
  "sandbox": {
    "enabled": true,
    "network": { "allowedDomains": ["registry.npmjs.org", "*.github.com"], "strictAllowlist": true }
  }
}
```

macOS Seatbelt / Linux·WSL2 bubblewrap로 **Bash 서브프로세스 전체**(스크립트와 자식 프로세스 포함)에 적용된다. 네이티브 Windows는 미지원.

`strictAllowlist: true`는 **user/managed/`--settings`에서만 유효**하다. 프로젝트 settings에 쓰면 무효다.

**한계:** Read/Edit/Write 내장 도구는 샌드박스가 아니라 권한 시스템을 탄다. TLS를 검사하지 않으므로 domain fronting이 가능하다. 완전한 격리 경계가 아니다.

---

## 관찰가능성 데이터 소스

| 소스 | 경로/방법 | 얻는 것 |
|---|---|---|
| 세션 transcript | `~/.claude/projects/<슬러그화된 cwd>/<session_uuid>.jsonl` | assistant 라인의 `message.usage`(input/output/cache_read/cache_creation 토큰, `thinking_tokens`), `timestamp`, `requestId`, `gitBranch`, `isSidechain`. **cost/usd 필드는 없다** |
| hook 입력 | 모든 hook이 `transcript_path`를 받는다 | 위 파일을 hook이 직접 파싱 |
| OpenTelemetry | `CLAUDE_CODE_ENABLE_TELEMETRY=1` + `OTEL_METRICS_EXPORTER`/`OTEL_LOGS_EXPORTER` + `OTEL_EXPORTER_OTLP_ENDPOINT` | `claude_code.cost.usage`(추정치), `.token.usage`, `.code_edit_tool.decision`, 이벤트 `.tool_result`(`success`, `duration_ms`, `error_type`), `.api_request`(`cost_usd`) |
| print 모드 | `claude -p ... --output-format json` | `total_cost_usd`, `session_id`, `permission_denials`, 모델별 비용 분해 |
| 대화형 | `/usage`, `/insights` | `/insights`가 `~/.claude/usage-data/report.html` 생성 |

**작업당 비용을 진짜로 계측하려면** 하네스 실행을 `claude -p`로 감싸거나 OTel을 켜야 한다. 대화형 단독으로는 토큰 프록시까지만 가능하다.

---

## 흔한 함정

- [ ] `Write(경로)` 규칙을 썼다 → **조회되지 않는다.** `Edit(...)`로 바꾼다
- [ ] `/Users/...`를 절대경로로 알고 썼다 → 설정 파일 위치 기준이다. `//Users/...`로 쓴다
- [ ] deny에 넓은 패턴을 넣고 allow로 예외를 만들려 했다 → **불가능하다.** deny를 좁게 쓴다
- [ ] `Bash(devbox run *)`을 허용했다 → 그 뒤의 임의 명령을 전부 허용한 것이다
- [ ] Bash 규칙으로 URL을 제한하려 했다 → 뚫린다. `WebFetch(domain:)` + 샌드박스를 쓴다
- [ ] `if` 필드를 PostToolBatch/Stop에 붙였다 → **hook이 아예 실행되지 않는다**
- [ ] 한 hook에서 exit 2와 JSON 출력을 섞었다 → 하나만 쓴다
- [ ] `additionalContext`를 JSON 최상위에 뒀다 → 조용히 무시된다. `hookSpecificOutput` 안에 넣는다
- [ ] PreToolUse에서 exit 0으로 "승인"하려 했다 → 0은 승인이 아니다. `permissionDecision:"allow"` JSON을 쓴다
- [ ] Stop hook에서 `stop_hook_active`를 검사하지 않았다 → 8회 후 무효화된다
- [ ] 프로젝트 settings의 allow에 의존하는 CI를 짰다 → 신뢰 다이얼로그가 없어 죽는다. `--settings`나 user 스코프로 옮긴다
- [ ] `$CLAUDE_PROJECT_DIR` 등을 따옴표 없이 셸 폼에 넣었다 → 공백 경로에서 깨진다
- [ ] 스킬 번들 스크립트를 상대경로로 참조했다 → 세션 cwd를 따라가 깨진다. `${CLAUDE_SKILL_DIR}`를 쓴다


---

<sub>이 파일은 harness-6l의 원본 저작물이며 upstream `harness` 플러그인에서 파생되지 않았다. Copyright 2026 hackerhoon, Apache-2.0.</sub>
