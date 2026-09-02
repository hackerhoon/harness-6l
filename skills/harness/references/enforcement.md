# 강제 수단 — settings.json · hooks · 서브에이전트 · 샌드박스

이 파일은 "환경(최고 신뢰도) 계층"을 Claude Code에서 **실제로** 만드는 방법이다. 여기 적힌 것만이 모델의 의사와 무관하게 차단한다. 나머지는 전부 가이드다.

**검증 기준:** Claude Code 2.1.252~2.1.258 / macOS + Debian·Alpine 시험(RED-8), 2026-09-02, 공식 문서 확인. 버전이 크게 다르면 문법을 다시 확인한다.

## 목차
- [무엇이 실제로 강제되는가](#무엇이-실제로-강제되는가)
- [permissions 문법](#permissions-문법)
- [설정 우선순위와 병합](#설정-우선순위와-병합)
- [Capability Budget — 정본은 assets 템플릿](#capability-budget--정본은-assets-템플릿)
- [hooks](#hooks)
- [hook 보안·한계](#hook-보안한계)
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

**그 외의 모든 예산 항목은 hook을 직접 구현했을 때만 이 등급에 도달한다.** 구현하지 않으면 가이드다. 산출하는 모든 예산 라인에 `enforced_by`를 다는 이유가 이것이다. (`enforced_by` 값의 정본 표는 `layers.md` L3.)

### `enforced_by: hook`의 판정 기준 — "설치"가 아니라 "설치 + 등록"

hook 스크립트를 `.claude/hooks/`에 복사하는 것만으로는 **아무것도 발화하지 않는다.** hook은 `settings.json`(또는 스킬·서브에이전트 frontmatter)의 `hooks` 블록에 등록됐을 때만 실행되고, **`.claude/settings.json`은 protected path이므로 그 등록은 사용자가 직접 한다.** 하네스는 등록 JSON을 제시할 뿐 쓰지 않는다.

따라서:

| 시점 | hook 예산의 `enforced_by` |
|---|---|
| 스크립트 복사 + `chmod +x` 완료 | **`none`** — 파일이 있을 뿐 발화하지 않는다 |
| 사용자가 `hooks` 블록 등록을 확인해 줌 | `hook` |
| `jq` 부재 또는 `CLAUDE_PROJECT_DIR` 미설정 | **`none`** — 스크립트가 fail-open으로 통과시킨다 |

**하네스 구축이 끝난 시점의 hook 예산은 항상 `none`으로 기록한다.** 산출물(`_workspace/harness.md`)에 그렇게 적고, "사용자가 등록을 확인해 주면 그때 `hook`으로 올린다"를 함께 적는다. 등록되지 않은 스크립트를 `hook`으로 적는 것은 이 문서 전체가 막으려는 바로 그 실패 — 안전으로 위장한 상태 — 다.

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

## Capability Budget — 정본은 assets 템플릿

**권한 라인의 정본은 `${CLAUDE_SKILL_DIR}/assets/settings-permissions.template.json` 하나다.** 이 문서에 사본을 두지 않는다 — 두 판본이 갈라지면 어느 쪽이 옳은지 알 수 없게 되고, 그것이 논문 §XIV(한계).B가 경고한 "규칙 47과 규칙 183" 문제의 설정판이다. 템플릿을 읽고, 프로젝트에 맞게 값을 채우고, 사용자에게 제시한다.

### 산출 형식 — 표 + 적용용 JSON, 두 벌

JSON에는 주석을 쓸 수 없다. 그래서 "왜 이 줄인가"를 JSON 안에 넣을 수 없고, 넣으면 붙여넣은 순간 파싱 에러가 난다. 따라서 **두 벌로 낸다.**

1. **마크다운 표** — 사람이 읽고 판단하는 쪽. 열은 정확히 셋이다: **라인 / 무엇을 막는가 / `enforced_by`**.
2. **`_workspace/proposed-settings.json`** — 사용자가 그대로 복사해 넣을 수 있는 순수 JSON. 주석·설명을 넣지 않는다. 파일로 내는 이유는 대화 스크롤에서 잘린 JSON을 붙여넣는 사고를 없애기 위해서다.

표의 형태는 이렇다.

| 라인 | 무엇을 막는가 | `enforced_by` |
|---|---|---|
| `Bash(git push --force *)` (deny) | 리터럴 `git push --force`. `-f`·`--force-with-lease`는 못 막는다 | `settings` (부분) |
| `Bash(rm *)` (ask) | 모든 `rm` 호출을 사람에게 보여준다. 플래그 철자와 무관 | `settings` |
| 작업당 쓰기 20회 | PreToolUse hook 카운터 | `none` → 사용자 등록 후 `hook` |

**하네스가 `.claude/settings.json`을 직접 쓰지 않는다.** 이유는「자기 권한 확대 차단」.

논문 Table VI 중 **프로덕션 배포(인간 전용) · 외부 메시지 발송(질문) · 데이터·파일 삭제(인간 전용)** 세 행은 프로젝트마다 명령이 달라 템플릿이 미리 채울 수 없다. 표에 **자리표시자 라인으로 남기고** 무엇을 채워야 하는지 적는다 — 빈칸으로 비우면 "이 경계는 없다"가 아니라 "이 경계를 생각하지 않았다"가 된다.

### `rm` — deny로는 막히지 않는다

**실증:** `Bash(rm -rf *)` deny가 있는 상태에서 `rm -r -f <경로>`와 `rm -fr <경로>`는 **실제로 디렉토리를 삭제했다.** deny의 Bash 인자 매칭은 **의미가 아니라 철자**를 본다. `/bin/rm`, `rm -Rf`, `rm --recursive --force`, `xargs rm -rf`, `git clean -xfd`, `python3 -c "shutil.rmtree(...)"`도 같은 이유로 빠져나간다.

따라서 템플릿은 `rm`을 **deny가 아니라 `Bash(rm *)` ask**로 둔다. ask는 접두만 맞으면 플래그 철자와 무관하게 걸리고, 통과시키려면 사람이 봐야 한다.

**내장 critical-path 가드는 별개이고, 지키는 범위가 좁다.** `rm`/`rmdir`의 파일시스템 루트·최상위 디렉토리·홈·현재 작업 디렉토리와 **그 부모**만 막는다(allow로도, PreToolUse hook의 `allow`로도 못 뚫는다). **cwd 안쪽은 이 가드의 대상이 아니다.** 즉 "`rm`은 이중으로 막혀 있다"는 서술은 사실이 아니다 — 진짜로 막아야 하면 PreToolUse hook에서 명령을 정규화한 뒤 판정한다.

### `Bash({TEST 명령} *)`는 실행 파일까지만 쓴다

템플릿의 `Bash({TEST 명령} *)` / `Bash({LINT 명령} *)` 자리에는 **플래그를 제외한 실행 파일(과 하위 커맨드)까지만** 넣는다 — `Bash(pytest *)`, `Bash(npm test *)`는 되고 `Bash(pytest -q --maxfail=1 *)`는 안 된다. 인자가 하나라도 어긋나면 규칙이 조용히 빗나가 매번 프롬프트가 뜨고, 사용자는 그 프롬프트를 습관적으로 승인하게 된다.

### 샌드박스 키의 스코프 함정

**`sandbox.network.strictAllowlist`를 프로젝트 `.claude/settings.json`에 두면 무효다.** 이 키는 user/managed/`--settings` 스코프에서만 동작한다. 프로젝트 스코프에 두면 조용히 무시되어, 가지고 있지 않은 네트워크 경계를 가졌다고 믿게 된다. 샌드박스가 필요하면 `~/.claude/settings.json`에 **별도 블록으로** 제시한다.

### 논문 Template 2 ↔ Claude Code 대응

| 논문 Template 2 | Claude Code | `enforced_by` |
|---|---|---|
| `ALLOW read/write/execute` | `allow`의 `Read`/`Edit`/`Bash` | `settings` |
| `ASK before: git push, deploy` | `ask` | `settings` |
| `DENY: rm -rf, send_email` | `deny` (+ 내장 critical-path 가드, cwd 밖 한정) | `settings` (부분) |
| `RATE: max 20 writes` | 대응 키 없음 → PreToolUse hook | `none` → 등록 후 `hook` |
| `COST: max $5` | 대응 키 없음 → `claude -p --max-budget-usd` | 대화형 `none` / `-p-flag` |
| `TIMEOUT: 30분` | 대응 키 없음 → `PostToolBatch` hook | `none` → 등록 후 `hook` |

---

## hooks

### 규약

**입력(stdin JSON) 공통 필드:** `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`, `effort`. 서브에이전트 컨텍스트에서는 `agent_id`, `agent_type` 추가.
**툴 이벤트 필드:** `tool_name`, `tool_input`, `tool_use_id`. **PostToolUse는 `tool_response`를 받는다.**
**PostToolUseFailure는 `tool_response`가 없다** — 최상위 `error`, `is_interrupt`, `duration_ms`를 받는다. 두 이벤트의 입력 형태가 다르므로 같은 스크립트를 쓰려면 `hook_event_name`으로 분기해야 한다.

> **중요:** `PostToolUse`는 도구가 **성공적으로** 끝났을 때만 발화한다. 실패는 `PostToolUseFailure`로 간다. 감사 원장을 `PostToolUse` 한쪽에만 걸면 **모든 기록의 `ok`가 항상 true가 되어 실패율·완료율·복구시간을 잴 수 없다.**
>
> **권한으로 차단된 호출은 둘 중 어느 쪽도 발화하지 않는다.** 그 사건은 `PermissionDenied`로만 온다. 원장을 셋 모두에 등록해야 성공·실패·거부가 한 파일에서 이어진다.

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

### 등록 — 이 JSON은 사용자가 넣는다

**4종 전부를 등록해야 표에 적은 `enforced_by`가 성립한다.** 하나라도 빠지면 해당 예산은 `none`이다.

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
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/audit_log.sh" }] },
      { "matcher": "Bash|Edit|Write|NotebookEdit",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/test_gate.sh" }] }
    ],
    "PostToolUseFailure": [
      { "matcher": "*",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/audit_log.sh" }] }
    ],
    "PermissionDenied": [
      { "matcher": "*",
        "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/audit_log.sh" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/test_gate.sh" }] }
    ],
    "SubagentStop": [
      { "hooks": [{ "type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/test_gate.sh" }] }
    ]
  }
}
```

**`PermissionDenied`가 왜 필요한가.** 도구가 권한으로 차단되면 `PostToolUse`도 `PostToolUseFailure`도 발화하지 않는다. 이 이벤트를 등록하지 않으면 **"권한 경계가 최소 1회 행동을 차단했다"는 무인 승격 조건을 증명할 데이터가 아예 존재하지 않는다.** 논문 `policy_gate` 의사코드의 `log_denial(action, target, task)` 분기가 여기에 대응한다.

**`audit_log.sh`는 `"*"`, `test_gate.sh`는 `Bash|Edit|Write|NotebookEdit`로 따로 등록한다.** 한 항목에 묶으면 원장이 Read·Grep을 놓치거나, 반대로 `test_gate.sh`가 `Read(src/a.py)`에도 발화해 읽기만 한 세션의 완료를 차단한다(실측).

**`Stop`/`SubagentStop`은 matcher를 지원하지 않는다.** 그리고 `test_gate.sh`는 `stop_hook_active`를 검사해 조기 종료해야 한다 — Stop hook은 연속 8회 차단 후 무효화되기 때문이다.

### 스크립트 4종 — 번들 자산이 정본이다

네 스크립트의 **정본은 `${CLAUDE_SKILL_DIR}/assets/hooks/`에 있다.** 이 문서에 사본을 두지 않는다 — 두 판본이 갈라지면 어느 쪽이 옳은지 알 수 없게 되고, 그것이 논문 §XIV(한계).B가 경고한 "규칙 47과 규칙 183" 문제의 코드판이다.

대상 프로젝트에 설치한다:

```bash
set -e; [ -d "${CLAUDE_SKILL_DIR}/assets/hooks" ] || { echo "CLAUDE_SKILL_DIR 미치환 — 설치 중단"; exit 1; }
mkdir -p .claude/hooks
cp "${CLAUDE_SKILL_DIR}"/assets/hooks/{_common,policy_gate,loop_budget,audit_log,test_gate}.sh .claude/hooks/
cp "${CLAUDE_SKILL_DIR}"/assets/hooks/SHA256SUMS .claude/hooks/
(cd .claude/hooks && shasum -a 256 -c SHA256SUMS)     # SUMS 의 파일명은 상대경로 — 반드시 그 디렉토리 안에서 대조한다
chmod +x .claude/hooks/*.sh
[ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore; grep -qx '_workspace/runs/' .gitignore 2>/dev/null || echo '_workspace/runs/' >> .gitignore   # 개행 없이 끝난 .gitignore 에 이어 쓰면 마지막 규칙과 병합된다(실측)
```

**`_common.sh`를 빠뜨리면 네 스크립트 전부 첫 줄에서 죽는다.** 각 hook은 `. "$(dirname "$0")/_common.sh"`로 공통 프렐류드(jq·`CLAUDE_PROJECT_DIR` 검사, 입력 정제, per-task 키, append-only 카운터)를 읽는다. 다섯 파일이 한 세트다.

gitignore 대상은 **`_workspace/runs/`만**이다. `_workspace/` 전체를 무시하면 `harness.md`·산출물·`proposed-settings.json`이 버전 관리에서 빠져 "지표가 퇴행하면 롤백한다"의 근거가 사라진다.

| 스크립트 | 이벤트 | 강제하는 것 | 없으면 |
|---|---|---|---|
| `policy_gate.sh` | PreToolUse (`Edit\|Write\|NotebookEdit`) | 작업당 쓰기 한도 → 초과 시 `deny`(쓰기 동결) | RATE 예산이 `enforced_by: none` |
| `loop_budget.sh` | PostToolBatch (matcher 미지원) | 소요시간·배치 수·토큰 → 초과 시 `exit 2`로 루프 중단 | 시간·토큰 예산이 `enforced_by: none` |
| `audit_log.sh` | PostToolUse **·** PostToolUseFailure **·** PermissionDenied | 감사 원장 기록(성공·실패·권한 거부 3종) | 완료율·복구시간·"경계가 1회 차단"의 데이터 소스가 **아예 존재하지 않음** |
| `test_gate.sh` | PostToolUse **와** Stop/SubagentStop | 소스를 수정하고 테스트를 실행하지 않은 채 완료하려 하면 `exit 2`로 차단 | "완료했습니다"라고 보고하면서 센서가 한 번도 돌지 않는 실패가 **잡히지 않음** |

**`test_gate.sh`의 대상 판별은 환경변수로 조정한다.** 테스트 명령 패턴은 `HARNESS_TEST_PATTERN`(기본 `pytest|npm test|cargo test|go test|make test`), 소스 경로는 `HARNESS_SRC_PATTERN`.

### 카운터의 단위 — 두 가지를 혼동하지 않는다

- **배치 ≠ 도구 호출.** `loop_budget.sh`의 카운터는 도구 호출이 아니라 **도구 배치**를 센다. 한 배치에 여러 도구가 들어가므로 배치 상한은 논문 Table IV의 "최대 도구 호출 50회"와 같은 단위가 아니라 **그 하한선**이다. 정확한 도구 호출 수가 필요하면 `audit_log.sh`의 원장을 집계한다.
- **키는 per-task.** 모든 카운터 파일명은 `${session_id}-${prompt_id}`다. 여기서 **작업(task) = 사용자 프롬프트 1턴**이므로 논문 Template 2·Table IV의 "per task" 단위와 일치하고, **다음 프롬프트에서 자연 리셋된다.** 세션 단위 누적이 아니다.
- **카운트는 append-only.** `echo >> 파일` 후 `wc -l`로 센다. read-modify-write가 아니므로 락 없이 경합에 안전하다(이유는「hook 보안·한계」).

**환경변수로 조정한다:** `HARNESS_MAX_WRITES`(기본 20), `HARNESS_MAX_SECONDS`(1800), `HARNESS_MAX_BATCHES`(50), `HARNESS_MAX_TOKENS`(100000).

---

## hook 보안·한계

**이 절은 hook을 켜기 전에 읽는다.** 여기 적힌 것은 전부 실측이거나 설계상 확정된 한계다. 적지 않은 한계는 "없는 한계"가 아니라 "아직 시험하지 않은 한계"다.

### 요약표

| 항목 | 현재 설계 | 남는 위험 |
|---|---|---|
| 비밀 유출 | 원장에 내용을 기록하지 않음 + `_workspace/runs/` gitignore | 파일 경로 자체가 민감한 경우 |
| 카운터 경합 | append-only 카운트(락 불필요) | 없음 |
| `jq` 부재 | 경고 후 `exit 0` (fail-open), `enforced_by: none` | 무인 운영 중이면 경계가 조용히 열린다 |
| `CLAUDE_PROJECT_DIR` 미설정 | 경고 후 `exit 0` (cwd 폴백 금지) | v2.1.196 미만에서는 hook 전체가 무효 |
| `mkdir` 실패 | 경고 후 `exit 0` | 위와 동일 |
| 입력 위생 | `session_id`/`prompt_id`/`tool_name`을 `[A-Za-z0-9_-]`로 정제 | 없음 |
| 토큰 계측 | 유니크 `requestId`, `cache_read` 제외, 스트리밍 파싱 | 청구액과 정확히 같지는 않다 |
| 이식성 | bash 3.2+ 와 `jq` 필요 | Alpine/ash/dash·네이티브 Windows 미지원 |
| 무결성 | `SHA256SUMS` 대조 | 대조를 건너뛰면 위장 hook을 자기 것으로 믿는다 |

### 원장에 비밀을 남기지 않는다

**실증:** `tool_input` 전문을 기록하면 `Write`의 `content`와 `Edit`의 `new_string`에 담긴 API 키·`AWS_SECRET_ACCESS_KEY`·DB 비밀번호가 원장에 **평문으로** 남는다. 그리고 `_workspace/`는 기본적으로 커밋된다.

그래서 원장에는 **내용을 기록하지 않는다.** 남기는 것은 이것뿐이다.

| 기록 | 값 |
|---|---|
| 도구 이름 | `tool_name` (`[A-Za-z0-9_-]`로 정제) |
| 대상 | `Edit`/`Write`의 `file_path`만 |
| 명령 | `Bash`의 **첫 토큰**(실행 파일명)만 — "센서를 돌렸는가"에 답하기 위한 최소치 |
| 결과 | 성공/실패, `error` 유형, `duration_ms` |

각 필드는 **512자에서 절단**한다. 이 상한은 비밀 노출뿐 아니라 두 가지를 함께 해소한다 — ① 대용량 레코드 동시 append 시 줄이 뒤섞여 원장 전체가 JSON 파싱 불가가 되던 손상(200KB 레코드 6건 동시 → 6줄 전부 파손, 실측), ② 로테이션 없는 무제한 성장(10MB `content` 1건이 원장 1줄 10MB).

그리고 **`_workspace/runs/`를 대상 프로젝트의 `.gitignore`에 넣는다.** 설치 스니펫의 마지막 줄이 그것이다. 선택 단계가 아니다.

### 경합 — append-only라서 락이 필요 없다

락 없는 read-modify-write 카운터는 **동시 2건에서 90% 확률로 카운트를 잃는다**(macOS 실측, Debian은 더 나쁨). Claude Code는 한 배치에 `Edit`/`Write`를 여러 개 넣으므로 동시 2건은 예외가 아니라 표준 상황이다. 그래서 카운터는 `echo 1 >> "$C"` + `wc -l < "$C"`로 센다 — PIPE_BUF 이하의 소형 append는 `O_APPEND`로 원자적이라 락 없이 정확하다.

### fail-open — 조용히 열리지 않게 한다

4종 모두 **`jq`가 없거나 `CLAUDE_PROJECT_DIR`가 설정되지 않으면 stderr로 경고한 뒤 `exit 0`** 한다. 세션을 벽돌로 만드는 것보다 낫다는 판단이지만, **그 환경에서 해당 예산의 `enforced_by`는 예외 없이 `none`이다.** "시간·배치 예산은 그대로 강제된다" 같은 **부분 강제 주장을 하지 않는다** — 구버전은 `jq` 부재 시 세션 식별자를 상수로 폴백해 모든 신규 세션을 즉시 정지시켰다(실측). 상수 폴백도, cwd 폴백도 쓰지 않는다.

- `jq` 확인: `command -v jq`. **macOS는 15(Sequoia) 이상에서만 `/usr/bin/jq`가 동봉된다** — 14 이하에는 없다. Linux는 배포판에 따라 다르다.
- `CLAUDE_PROJECT_DIR`는 v2.1.196 이상에서 hook에 전달된다. cwd로 폴백하면 프로젝트 루트가 아닌 곳에 원장·카운터가 갈라져 생기고, 카운터가 갈라지면 트립와이어가 조용히 리셋된다.
- `mkdir -p` 실패(읽기 전용 디렉토리 등)도 같은 경로로 처리한다 — **침묵하지 않고 경고한 뒤 통과**시킨다.

### 입력 위생

`session_id`·`prompt_id`는 파일명이 되므로 `[A-Za-z0-9_-]` 외 문자를 **삭제**하고(전부 지워지면 `unknown`/`p0`), `tool_name`은 원장 필드이므로 비허용 문자를 **`_`로 치환**해 흔적을 남긴다(`Read\0BAD`→`Read_BAD` — 삭제하면 `ReadBAD`로 위장된다). 정제하지 않으면 `"session_id":"../../../../ESCAPED"`가 **프로젝트 밖에 파일을 만들고**(실측), 개행이 든 값은 개행이 든 파일명을 만들며, `tool_name`에 NUL을 넣으면 원장에 `Read\0BAD` → `"ReadBAD"`로 **다른 값이 기록**된다(증거 위조). 비UTF-8 바이트는 U+FFFD로 치환되므로 원장의 바이트는 실제 바이트와 다를 수 있다 — 원장은 **행위의 기록이지 바이트의 사본이 아니다.**

### 토큰 예산의 정의

**유니크 `requestId` 기준 `input_tokens + output_tokens`의 합 — 새로 처리된 입력 + 생성된 출력. 캐시 필드는 둘 다 제외**(`cache_read`는 컨텍스트 재계상으로 폭주, `cache_creation`은 캐시 만료 시 단일 요청이 예산을 터뜨린다). 작업 시작 시점을 기준선으로 잡고 그 증가분만 센다. transcript는 스트리밍으로 읽는다(`jq -r 'select(.type=="assistant") | "\(.requestId)\t\(토큰)"' | sort -u -k1,1 | awk` — 슬럽(`-s`) 없이 한 줄씩; (...)'`) — 61MB transcript에 배치당 약 0.3초, 메모리는 O(1)이다. 전량 슬럽(`jq -s`)하면 배치마다 100MB대 스파이크가 난다.

**이것은 청구 근사치이지 컨텍스트 크기가 아니다.** 구버전이 3번째 assistant 턴에 100K 예산을 소진한 원인은 두 가지였다 — ① `cache_read_input_tokens`를 턴마다 재합산(같은 컨텍스트를 N번 셈), ② transcript가 같은 메시지를 중복 저장(2,764줄 vs 유니크 1,446). 실측 합계가 기본 예산의 14,903배까지 나왔다. 토큰 예산을 켜기 전에 자기 프로젝트에서 한 번 실측한다.

### 예산 초과 후 리셋

카운터 키가 `${session_id}-${prompt_id}`이므로 **다음 사용자 프롬프트에서 자연히 리셋된다.** 그래도 지금 풀어야 하면:

```bash
rm _workspace/runs/<session_id>-<prompt_id>.*
```

deny/stop 메시지 본문에 이 경로와 명령이 함께 나오게 한다. 해제 절차가 없는 차단은 하네스가 아니라 벽돌이다.

### 이식성 — 요구사항을 먼저 확인한다

**요구사항: bash 3.2+ 와 `jq`.**

| 환경 | 판정 |
|---|---|
| macOS (bash 3.2 + jq 1.7) / Debian bookworm (bash 5.2 + jq 1.7) | 동작 확인 |
| **Alpine (bash 미설치)** | **미지원.** `#!/bin/bash` 셔뱅이 없어 exit 127 |
| **BusyBox ash / dash** | **미지원.** `<<<` 히어스트링은 POSIX가 아니다 |
| **네이티브 Windows** | **미지원.** Git Bash/WSL 필요 |
| 공백·비ASCII 경로 | 동작 확인 |

Alpine에서 특히 위험한 진단 패턴이 있다 — **`jq`가 없으면 `command -v` 분기에서 먼저 `exit 0`이 나 정상처럼 보이고, `jq`를 설치한 순간 깨진다.**

### 무결성 — 설치본이 내 것인지 확인한다

이 스킬은 `.claude/hooks/{_common,policy_gate,loop_budget,audit_log,test_gate}.sh`라는 **고정·공개 파일명을 표준화**한다. 그것은 위장 표적을 만든다는 뜻이기도 하다. 그래서 `assets/hooks/SHA256SUMS`를 함께 배포하고 설치 직후 `shasum -a 256 -c`로 대조한다. 하네스 점검 시에도 파일의 **존재**가 아니라 **해시**를 본다.

> **저장소가 공급하는 hook은 신뢰 게이트 없이 실행된다. 남의 저장소를 처음 열 때는 `.claude/hooks/`와 `.claude/settings.json`을 먼저 읽어라.** 프로젝트 `hooks`·`env`·`apiKeyHelper`는 워크스페이스 신뢰 다이얼로그와 무관하게 동작한다.

---

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
| **`PermissionDenied` hook** | `audit_log.sh`를 이 이벤트에 등록 | **"권한 경계가 최소 1회 행동을 차단했다"의 유일한 대화형 데이터 소스.** 차단된 도구·대상·시각. 이것 없이는 무인 승격 조건 6번이 검증 불가능한 체크박스가 된다 |
| OpenTelemetry | `CLAUDE_CODE_ENABLE_TELEMETRY=1` + `OTEL_METRICS_EXPORTER`/`OTEL_LOGS_EXPORTER` + `OTEL_EXPORTER_OTLP_ENDPOINT` | `claude_code.cost.usage`(추정치), `.token.usage`, `.code_edit_tool.decision`, 이벤트 `.tool_result`(`success`, `duration_ms`, `error_type`), `.api_request`(`cost_usd`) |
| print 모드 | `claude -p ... --output-format json` | `total_cost_usd`, `session_id`, `permission_denials`, 모델별 비용 분해 |
| 대화형 | `/usage`, `/insights` | `/insights`가 `~/.claude/usage-data/report.html` 생성 |

**작업당 비용을 진짜로 계측하려면** 하네스 실행을 `claude -p`로 감싸거나 OTel을 켜야 한다. 대화형 단독으로는 토큰 프록시까지만 가능하고, 그 토큰의 정의는「hook 보안·한계」의 「토큰 예산의 정의」를 따른다.

> 지표별로 어느 소스가 필요한지는 `layers.md` L6「지표별 계측 소스」.

---

### 상태 파일·원장 정리 — 작업 첫 배치에서 자동

per-task 키 때문에 `_workspace/runs/`에 작업마다 `<sid>-<pid>.{writes,batches,start,tok0,dirty,tested}`가 생긴다. `loop_budget.sh`가 **작업의 첫 배치**(`.start` 생성 시점)에 한 번 `gc_runs`를 돌린다 — 매 hook 마다 `find`를 돌리지 않기 위해서다.

| 대상 | 정책 | 환경변수(기본) |
|---|---|---|
| 상태 파일 6종 | mtime 기준 TTL 초과 삭제 | `HARNESS_STATE_TTL_DAYS` (7) |
| 원장 `<sid>.jsonl` | 크기 초과 시 `.jsonl.1`로 1회 로테이션(이전 `.1`은 덮어씀) | `HARNESS_LEDGER_MAX_KB` (10240) |
| 원장·`.1` | mtime 기준 TTL 초과 삭제 | `HARNESS_LEDGER_TTL_DAYS` (30) |
| 작업 원장 `<sid>.tasks.jsonl` | 위 원장과 같은 로테이션·TTL 적용 — 장기 추세는 `.1`을 따로 보관 | 동일 |

원장이 로테이션되면 `harness_report.sh`는 현재 파일만 읽는다 — 장기 추세가 필요하면 `.1`을 따로 보관한다.

### fail-closed — 무인·CI 용 opt-in

기본은 **fail-open**이다: `jq`가 없거나 `CLAUDE_PROJECT_DIR`가 없거나 `_workspace/runs/`를 만들 수 없으면 경고하고 통과시킨다. 세션을 벽돌로 만드는 것보다 낫고, 그 대가로 `enforced_by`를 `none`으로 정직하게 적는다.

**`HARNESS_FAIL_CLOSED=1`**을 주면 같은 상황을 "조용한 통과"가 아니라 **정지**로 다룬다. 사람이 보고 있지 않은 무인 실행이나 CI에서, 의존성 부재가 보호 없이 계속 도는 것보다 멈추는 게 안전할 때 쓴다.

| 이벤트 | fail-closed 동작 |
|---|---|
| PreToolUse (`policy_gate`) | `deny` JSON — 도구 호출 차단 |
| PostToolBatch (`loop_budget`) | `exit 2` — 루프 중단 |
| Stop / SubagentStop (`test_gate`) | `exit 2` — 완료 차단. `stop_hook_active`면 통과(8회 캡 존중) |
| PostToolUse / PostToolUseFailure / PermissionDenied (`audit_log`) | 차단 불가 이벤트 — 경고만 |

이벤트명은 **bash 내장 정규식**(`[[ =~ ]]`)으로 읽는다 — jq가 없는 환경에서는 grep·sed도 없을 수 있다(CI가 grep 없는 PATH로 검증한다). `HARNESS_FAIL_CLOSED`는 `1`·`true`·`yes`·`on`을 받는다. fail-closed 상태의 hook은 "강제되고 있다"가 아니라 "**아무 작업도 못 하게 막고 있다**"이다 — 의존성을 고치는 것이 목적이지 이 상태로 운영하는 것이 아니다.

### 작업 완료 원장과 스코어카드 — "진짜 지표"의 데이터 소스

`test_gate.sh`가 **`Stop`**(SubagentStop 제외)에서 작업 1건을 `<sid>.tasks.jsonl`에 기록한다. 작업 = 사용자 프롬프트 1턴.

```jsonl
{"ts":"…","task":"<sid>-<pid>","event":"task_blocked","reason":"untested"}
{"ts":"…","task":"<sid>-<pid>","event":"task_end","dirty":true,"tested":true,"denied":0,"tool_failures":1,"verdict":"complete-tested"}
```

| verdict | 뜻 |
|---|---|
| `complete-tested` | 소스를 수정했고 테스트를 돌렸고 권한 차단이 없었다 — **논문의 "진짜 지표"에 세는 것** |
| `complete` | 소스 수정 없이 끝났다(질문 응답 등). 권한 차단 없음 |
| `complete-escalated` | 이 작업에서 권한 경계가 1회 이상 막았다 — 에스컬레이션으로 집계 |
| `complete-forced` | Stop hook 8회 캡을 넘겨 더 이상 차단할 수 없었다 — 강제 종료. 진짜 지표에 세지 않는다 |

모든 원장 레코드에 `task` 키가 있어 작업 단위로 실패·차단을 묶을 수 있다.

```bash
"${CLAUDE_SKILL_DIR}"/assets/scripts/harness_report.sh [project-dir]
```

리포터가 계산하는 것: 진짜 지표(complete-tested 수) · 작업 수 · 완료율 · 테스트 증거 동반 완료율 · 에스컬레이션률 · 허위 완료 차단 횟수 · 도구 실패 수 · 권한 차단 수 · 평균 복구 시간(실패→**같은 세션 파일**의 다음 성공, 초 — 세션을 섞지 않는다) · 건너뛴 원장 줄 수(깨진 줄은 건너뛰고 경고한다 — `jq -s`였다면 전체를 잃었다). 원장은 파일로 넘겨 ARG_MAX를 넘지 않는다. **재작업률과 작업당 비용은 여기서 나오지 않는다** — OTel 또는 `claude -p --output-format json`이 필요하다. `null`은 "데이터 없음"이지 0이 아니다.

이 원장은 hook이 등록돼 발화할 때만 존재한다. 등록 전에는 스코어카드 전체가 `none`이고 리포터는 그렇게 말한다.

### 환경변수 한눈에

| 변수 | 기본 | 스크립트 |
|---|---|---|
| `HARNESS_MAX_WRITES` | 20 | policy_gate |
| `HARNESS_MAX_SECONDS` / `HARNESS_MAX_BATCHES` / `HARNESS_MAX_TOKENS` | 1800 / 50 / 100000 | loop_budget |
| `HARNESS_TEST_PATTERN` / `HARNESS_SRC_PATTERN` | 주요 테스트 러너 / `src\|lib\|app\|tests?…` | test_gate |
| `HARNESS_FAIL_CLOSED` | 0 | 전부 |
| `HARNESS_STATE_TTL_DAYS` / `HARNESS_LEDGER_TTL_DAYS` / `HARNESS_LEDGER_MAX_KB` | 7 / 30 / 10240 | loop_budget(gc) |

`settings.json`의 `env` 블록이나 셸에서 준다. 프로젝트 `.claude/settings.json`의 `env`는 워크스페이스 신뢰 없이도 적용된다.

### 트리거 회귀 스위트 실행 배선

`assets/scripts/run_trigger_eval.sh`가 `claude plugin eval`이 쓸 수 있으면 `evals/trigger_eval.json`을 돌리고(`--threshold 0.9 --no-publish`), early-access 게이트 뒤에 있으면 **건수를 표기하고 정직하게 스킵**한다. CI에서 `claude` CLI가 없으면 역시 스킵이다. 게이트가 열리는 날 스크립트를 바꾸지 않아도 된다.

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
- [ ] `Bash(rm -rf *)` deny로 삭제를 막았다고 믿는다 → **`rm -fr`·`rm -r -f`·`/bin/rm`은 그대로 지나간다(실증).** `Bash(rm *)`를 ask로 두고, 내장 critical-path 가드가 cwd **안쪽**은 지키지 않는다는 것을 함께 적는다
- [ ] hook을 설치만 하고 `enforced_by: hook`으로 적었다 → 사용자가 `hooks` 블록에 **등록**하기 전까지는 `none`이다
- [ ] `_workspace/`를 `.gitignore`에 넣지 않았다 → 감사 원장이 그대로 커밋된다. 설치 스니펫의 마지막 줄을 빠뜨리지 않는다
- [ ] `jq` 없는 환경에 hook을 설치했다 → 4종 전부 경고 후 `exit 0`이다. **아무것도 막히지 않는데 막힌다고 믿는 상태**가 가장 나쁘다. `command -v jq`를 설치 전에 확인하고, 없으면 예산 라인을 전부 `none`으로 적는다
- [ ] Alpine/BusyBox/네이티브 Windows에 설치했다 → **동작하지 않는다.** bash 3.2+ 와 `jq`가 요구사항이다
- [ ] 설치 후 `SHA256SUMS`를 대조하지 않았다 → 같은 파일명의 남의 hook을 자기 하네스로 믿게 된다


---

<sub>이 파일은 harness-6l의 원본 저작물이며 upstream `harness` 플러그인에서 파생되지 않았다. Copyright 2026 hackerhoon, Apache-2.0.</sub>
