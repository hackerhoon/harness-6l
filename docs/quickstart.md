# 빠른 시작

## 설치

```bash
/plugin marketplace add hackerhoon/harness-6l
/plugin install harness-6l@harness-6l-marketplace
```

## 첫 하네스 만들기

프로젝트 디렉토리에서:

```
하네스 구축해줘
```

스킬은 먼저 다섯 문항을 묻는다.

1. 같은 워크플로를 **반복** 실행하는가?
2. 에이전트가 조용히 틀린 결과를 내면 **문제가 되는가**(알아차리지 못한 채 넘어갈 수 있는가)?
3. 다음 세션에 같은 컨텍스트를 **다시 설명**해야 하는가?
4. 실수가 **외부 결과**(배포·발송·삭제)를 만드는가?
5. **이 작업의 성공을 무엇으로 판정하는가? 그 판정은 관찰 가능한가?**

모든 문항은 "예 = 그 계층이 필요하다"다. 1~4가 전부 아니오면 하네스를 만들지 않는다. 5번에 답할 수 없으면 시작하지 않는다 — 잘못 정의된 목표를 둘러싼 완벽한 하네스는 신뢰성 있는 쓰레기를 만든다.

## 산출물

```
{project}/
├── CLAUDE.md                       L1 가이드 본체 (+ 하네스 섹션)
├── .claude/
│   ├── rules/*.md                  규칙이 커지면 paths: 스코프로 분할
│   ├── agents/*.md                 에이전트 정의
│   ├── skills/*/SKILL.md           스킬
│   ├── settings.json               권한 — 라인을 제시하고 사용자가 승인
│   └── hooks/*.sh                  강제가 필요한 예산만 (선택)
└── _workspace/                     단일 상태 저장소
    ├── {phase}_{agent}_{artifact}.{ext}
    ├── harness.md                  체크포인트 / 래칫 원장 / 성숙도
    └── runs/{session_id}.jsonl     hook 설치 시에만
```

## hook 설치 (선택)

예산을 문서가 아니라 **실제로** 강제하려면 hook을 설치한다. 요구사항: bash 3.2+, jq, Claude Code 2.1.196+.

스킬이 3단계(WIRE)에서 `${CLAUDE_SKILL_DIR}`를 치환해 설치한다 — 다섯 파일(`_common.sh` 포함)이 한 세트이고, `SHA256SUMS`로 무결성을 대조하며, `.gitignore`에 `_workspace/runs/`를 넣는다. 정확한 스니펫과 `settings.json` 등록 JSON은 `references/enforcement.md` 「hooks」.

| 스크립트 | 등록 이벤트 |
|---|---|
| `policy_gate.sh` | PreToolUse (`Edit\|Write\|NotebookEdit`) |
| `loop_budget.sh` | PostToolBatch |
| `audit_log.sh` | PostToolUse **+ PostToolUseFailure + PermissionDenied** |
| `test_gate.sh` | PostToolUse (`Bash\|Edit\|Write\|NotebookEdit`) + Stop + SubagentStop |

세 가지를 잊지 마라:
- `audit_log.sh`는 세 이벤트 모두에 건다. 하나라도 빠지면 실패율 또는 권한 차단이 원장에 남지 않는다.
- **hook은 설치만으로 발화하지 않는다.** `settings.json`에 hooks 블록을 등록해야 하며 그건 사용자 몫이다. 등록 전까지 그 예산의 `enforced_by`는 `none`이고 스킬은 그렇게 적는다.
- `_workspace/runs/`는 gitignore 대상이다. 원장은 증거이자 공격면이다.

## 실패가 나면

```
에이전트가 또 같은 실수를 했어
```

래칫이 돈다: 재현 → 실패 **클래스** 분류 → 가장 강한 계층 1곳 수정 → 원장 한 줄 → 재발 확인.

원장의 "재발" 열이 핵심이다. 재발이 기록되면 그 수정은 너무 약한 계층에서 이뤄진 것이므로 한 단계 올린다.
