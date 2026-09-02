#!/bin/bash
# harness-6l 회귀 스위트 — 적대적 검증에서 확정된 수정이 되돌아가지 않았는지 검사한다.
# 계산적 센서다: 빠르고, 무료이고, 결정적이다. 판단이 필요한 검사는 여기 넣지 않는다.
# 사용: scripts/check.sh [skill-dir]   (기본: 이 저장소의 skills/harness)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SK="${1:-$ROOT/skills/harness}"
FAIL=0; PASS=0
ok()   { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }

echo "== 구조 =="
check "SKILL.md 존재"                       "[ -f '$SK/SKILL.md' ]"
check "references 7개"                      "[ \$(ls '$SK/references'/*.md | wc -l) -eq 7 ]"
check "hooks 4개 실행 가능 + _common.sh"     "[ \$(find '$SK/assets/hooks' -name '*.sh' -perm -u+x | wc -l) -eq 4 ] && [ -f '$SK/assets/hooks/_common.sh' ]"
for f in "$SK"/assets/hooks/*.sh; do check "bash 문법: $(basename "$f")" "bash -n '$f'"; done
check "settings 템플릿 JSON 유효"           "python3 -c \"import json;json.load(open('$SK/assets/settings-permissions.template.json'))\""
check "plugin.json 유효"                    "python3 -c \"import json;json.load(open('$ROOT/.claude-plugin/plugin.json'))\""
check "marketplace.json 유효"               "python3 -c \"import json;json.load(open('$ROOT/.claude-plugin/marketplace.json'))\""
check "plugin/marketplace 버전 일치"        "[ \"\$(python3 -c \"import json;print(json.load(open('$ROOT/.claude-plugin/plugin.json'))['version'])\")\" = \"\$(python3 -c \"import json;print(json.load(open('$ROOT/.claude-plugin/marketplace.json'))['plugins'][0]['version'])\")\" ]"

echo "== frontmatter =="
DESC_LEN=$(python3 - "$SK/SKILL.md" <<'PY'
import re,sys
s=open(sys.argv[1],encoding='utf-8').read(); fm=s.split('---')[1]
m=re.search(r'^description:\s*"(.*)"\s*$', fm, re.M); w=re.search(r'^when_to_use:\s*"(.*)"\s*$', fm, re.M)
print(len(m.group(1))+(len(w.group(1)) if w else 0))
PY
)
check "description(+when_to_use) ≤ 1536자 (현재 $DESC_LEN)" "[ $DESC_LEN -le 1536 ]"
check "frontmatter name: harness"           "grep -q '^name: harness$' '$SK/SKILL.md'"

echo "== 트리거 회귀 (구 스킬 5절 + 신규) =="
for t in "하네스 구성해줘" "하네스 구축해줘" "하네스 설계" "하네스 엔지니어링" "하네스 점검" "하네스 감사" "하네스 현황" "에이전트/스킬 동기화" "재구성하거나 확장" "메타 스킬" "무인"; do
  check "트리거: $t" "grep -q -- '$t' '$SK/SKILL.md'"
done

echo "== 2라운드 확정 사항 =="
check "SHA256SUMS 일치"                     "(cd '$SK/assets/hooks' && shasum -a 256 -c SHA256SUMS)"
check "loop_budget: cache_read 합산 안 함"   "! grep -q 'cache_read_input_tokens//0' '$SK/assets/hooks/loop_budget.sh'"
check "loop_budget: 슬럽(-s) 금지"           "! grep -q 'jq -s' '$SK/assets/hooks/loop_budget.sh'"
check "카운터 append-only(bump)"            "grep -q 'bump()' '$SK/assets/hooks/_common.sh' && ! grep -qE 'N=\\\$\\(\\( ' '$SK/assets/hooks/policy_gate.sh'"
check "원장에 tool_input 전문 기록 안 함"     "! grep -q 'input:.tool_input' '$SK/assets/hooks/policy_gate.sh'"
check "per-task 키(prompt_id)"              "grep -q 'prompt_id' '$SK/assets/hooks/_common.sh'"
check "audit_log: PermissionDenied"         "grep -q 'PermissionDenied' '$SK/assets/hooks/audit_log.sh'"
check "test_gate: stop_hook_active 검사"     "grep -q 'stop_hook_active' '$SK/assets/hooks/test_gate.sh'"
check "K1 극성: 결정 필터 Q2 (스킬+docs)"      "grep -q '문제가 되는가' '$SK/SKILL.md' && grep -q '문제가 되는가' '$ROOT/docs/quickstart.md' && ! grep -rq '알아차리겠는가' '$ROOT/docs' '$ROOT/README.md' '$SK/SKILL.md' '$SK/assets' '$SK/references/layers.md'"   # skill-authoring.md 는 실수 사례로 인용하므로 제외
check "K1 극성: 커버리지 Q5(SKILL 포인터/템플릿)" "grep -q '도달할 수 \*\*없다\*\*' '$SK/assets/workspace-harness.template.md'"
check "description 부정 예시"               "grep -q '트리거하지 마라' '$SK/SKILL.md'"
check "description 영어 앵커"               "grep -q 'harness engineering' '$SK/SKILL.md'"
check "evals/trigger_eval.json 24건"        "python3 -c \"import json;d=json.load(open('$SK/evals/trigger_eval.json'));t=sum(1 for x in d if x['should_trigger']);assert t>=12 and len(d)-t>=12\""
check "gitignore 지시(_workspace/runs)"      "grep -q '_workspace/runs/' '$SK/SKILL.md'"
check "템플릿: rm은 ask"                     "grep -q '\"Bash(rm \*)\"' '$SK/assets/settings-permissions.template.json' && ! grep -q 'rm -rf' '$SK/assets/settings-permissions.template.json' || grep -q 'Bash(rm \*)' '$SK/assets/settings-permissions.template.json'"
check "템플릿: 결정 필터·가지치기 섹션"        "grep -q '## 결정 필터' '$SK/assets/workspace-harness.template.md' && grep -q '## 가이드 가지치기' '$SK/assets/workspace-harness.template.md'"
check "논문 §N(아라비아) 인용 잔존 없음"       "! grep -rEq '논문 ?§[0-9]' '$SK/SKILL.md' '$SK/references' '$ROOT/docs' '$ROOT/README.md'"
check "docs: hook 3종 표현 잔존 없음"          "! grep -rq 'hook 3종' '$ROOT/README.md' '$ROOT/docs'"
check "docs: PermissionDenied 등록 안내"        "grep -q 'PermissionDenied' '$ROOT/docs/quickstart.md'"
echo "== 1라운드 확정 사항 =="
check "금지: \${CLAUDE_PLUGIN_ROOT} 0건"     "! grep -rq 'CLAUDE_PLUGIN_ROOT' '$SK'"
check "금지: _harness/ 0건"                 "! grep -rq '_harness/' '$SK'"
check "AGENTS.md 생성 지시 없음"            "! grep -rEq 'AGENTS\.md(을|를)? ?(만든다|생성한다|작성한다)' '$SK'"
check "opus 무조건 강제 없음"               "! grep -rEq 'model: *\"opus\"(을|를)? ?(사용한다|강제)' '$SK'"
check "enforced_by 개념 존재"               "grep -q 'enforced_by' '$SK/SKILL.md'"
check "템플릿 enforced_by 기본값 none"      "[ \$(grep -c '| \*\*none\*\* |' '$SK/assets/workspace-harness.template.md') -ge 6 ]"
check "audit_log: PostToolUseFailure 등록"  "grep -q 'PostToolUseFailure' '$SK/references/enforcement.md' && grep -q 'PostToolUseFailure' '$SK/assets/hooks/audit_log.sh'"
check "loop_budget: -s 로 빈 상태파일 방어"  "grep -q '\[ -s \"\$S\" \]' '$SK/assets/hooks/loop_budget.sh'"
check "strictAllowlist 스코프 경고(템플릿)" "grep -q 'strictAllowlist' '$SK/assets/settings-permissions.template.json' && grep -q '무효\|무시' '$SK/assets/settings-permissions.template.json'"
check "권위 역전 문장(템플릿)"              "grep -q '이 파일이 이긴다' '$SK/assets/claude-md-harness-section.md'"
check "결정 필터 5번(수용 기준)"            "grep -q '성공을 무엇으로 판정' '$SK/SKILL.md'"
check "hook 설치 단계 존재"                 "grep -q 'assets/hooks' '$SK/SKILL.md'"
check "검증자 Edit/Write 제외"              "grep -q 'disallowedTools: Edit, Write' '$SK/references/verifier-agent.md'"
check "무효 규칙 Write(경로) 템플릿에 없음" "! grep -Eq '\"Write\(' '$SK/assets/settings-permissions.template.json'"

echo "== 상호참조 =="
# 변경 고지(<sub>...출처 및 변경 고지...) 줄은 upstream 파일명을 인용하므로 스캔에서 제외한다
DEAD=$(grep -rh --include='*.md' -v '출처 및 변경 고지' "$SK" | grep -oE '(references|assets)/[A-Za-z0-9_./-]+\.(md|json|sh)' | sort -u | while read -r r; do [ -e "$SK/$r" ] || echo "$r"; done | tr '\n' ' ')
check "dead link 0${DEAD:+ (발견: $DEAD)}" "[ -z \"$DEAD\" ]"
ODD=$(for f in "$SK"/SKILL.md "$SK"/references/*.md; do n=$(grep -c '^```' "$f"); [ $((n%2)) -eq 0 ] || basename "$f"; done)
check "코드펜스 균형${ODD:+ (홀수: $ODD)}"  "[ -z \"$ODD\" ]"
for f in "$SK"/references/*.md; do
  L=$(wc -l < "$f" | tr -d ' ')
  if [ "$L" -ge 300 ]; then check "ToC 존재 (${L}줄): $(basename "$f")" "grep -q '## 목차' '$f'"; fi
done

echo "== 라이선스 고지 (Apache-2.0 §4(b)) =="
for f in SKILL.md references/multi-agent.md references/skill-authoring.md references/verifier-agent.md references/verifier-web-checklist.md references/ratchet.md; do
  check "변경 고지: $f" "grep -q '출처 및 변경 고지' '$SK/$f'"
done
check "NOTICE 존재"                          "[ -f '$ROOT/NOTICE' ]"
check "LICENSE에 원저작권 보존"              "grep -q 'Copyright 2025 robin' '$ROOT/LICENSE'"

echo
echo "결과: PASS $PASS / FAIL $FAIL"
[ "$FAIL" -eq 0 ]
