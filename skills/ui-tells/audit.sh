#!/usr/bin/env bash
# AI Tells 기계 감사. 사용: bash audit.sh [--config <파일>] <소스경로...>
# 판정할 수 없는 항목(채도 균질·위계·목적)은 여기 없다. 그건 스크린샷을 보고 판단한다(ai-tells.md).
#
# ── 제1원칙: 검사하지 못했으면 통과라고 말하지 않는다 ──
#   · 읽을 파일이 0개면 exit 3으로 크게 실패한다
#   · 개별 체크가 자기 코퍼스/설정을 못 찾으면 ok가 아니라 SKIP이다
#   · SKIP이 하나라도 있으면 "통과"가 아니라 "부분 검사"다
#
# ── 규칙 선택은 확장자가 아니라 "표현 방식(dialect)"으로 한다 ──
#   Tailwind 유틸리티는 .vue·.html에도 있고, CSS 선언은 <style> 블록 안에도 있다.
#   그래서 .tsx만 읽던 예전 방식은 Vue 프로젝트의 위반을 통째로 놓쳤다.
#     tailwind — 유틸리티 클래스 문자열이 보이는가
#     css      — CSS 선언 구문이 보이는가 (.css/.scss + <style> 블록)
#     jsx      — JSX 컴포넌트 구문이 보이는가
#     locale.* — 제품 언어
#
# exit: 0 전부 실행·HIT 0 / 1 HIT 있음 / 2 사용법 오류 / 3 스캔 불가 / 4 부분 검사(SKIP 있음)
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# ── --handoff : 후단 skill 이음새 확인 ──────────────────────────────────────
# 우리는 후단의 **앵커 문자열**을 기준으로 위임한다(handoff.md). 상대가 문구를 바꾸면
# 위임이 조용히 어긋나므로 첫 위임 직전에 돌려 시끄럽게 만든다.
# 미설치는 실패가 아니라 "직접 수행 모드"다.
run_handoff() {
  local SK="${1:-}" FAIL=0 TASTE s
  [ -n "$SK" ] || SK="$(cd "$SELF_DIR/../.." 2>/dev/null && pwd)"
  _p() { printf "  \033[32mPASS\033[0m %s\n" "$1"; }
  _f() { FAIL=$((FAIL+1)); printf "  \033[31mFAIL\033[0m %s\n" "$1"; }
  _n() { printf "  \033[33m미설치\033[0m %s\n" "$1"; }
  _a() { grep -qF "$2" "$1" 2>/dev/null && _p "$3" || _f "$3 — 앵커 없음: \"$2\""; }

  echo "== 후단 이음새 =="
  echo "  스킬 디렉터리: $SK"
  echo
  TASTE="$SK/design-taste-frontend/SKILL.md"
  echo "design-taste-frontend:"
  if [ -f "$TASTE" ]; then
    _a "$TASTE" "Reference signals"               "DNA 투입구"
    _a "$TASTE" "Brand assets that already exist" "브랜드 자산 슬롯"
    _a "$TASTE" "Reading this as:"                "Design Read 포맷"
    _a "$TASTE" "DESIGN_VARIANCE"                 "다이얼 이름"
    _a "$TASTE" "not multi-step product UI"       "제품 UI 범위 선언"
  else
    _n "코드 생성을 직접 수행한다 — handoff.md 참조"
  fi
  echo
  echo "emil:"
  for s in animate animation-vocabulary find-animation-opportunities; do
    [ -d "$SK/$s" ] && _p "$s 설치됨" || _n "$s — handoff.md의 기본 모션 표 사용"
  done
  echo
  if [ "$FAIL" -eq 0 ]; then echo "결과: 이음새 정상."; return 0; fi
  echo "결과: 앵커 ${FAIL}건 깨짐. **우리 SKILL.md를 고친다**(후단 파일 수정 금지)."
  echo "  폴백은 handoff.md의 '앵커가 없을 때' 열을 따른다."
  return 1
}

# ── 인자 ───────────────────────────────────────────────────────────────────
CONFIG=""
HANDOFF=0
P=()
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="${2:-}"; shift 2 ;;
    --handoff) HANDOFF=1; shift ;;
    -h|--help) echo "usage: bash audit.sh [--config <파일>] <path...>"; exit 2 ;;
    *) P+=("$1"); shift ;;
  esac
done
[ "$HANDOFF" = 1 ] && { run_handoff "${P[0]:-}"; exit $?; }
[ ${#P[@]} -eq 0 ] && { echo "usage: bash audit.sh [--handoff] [--config <파일>] <path...>"; exit 2; }
for p in "${P[@]}"; do [ -e "$p" ] || { echo "경로 없음: $p"; exit 2; }; done

# ── 설정 ───────────────────────────────────────────────────────────────────
# 프로젝트가 선언하는 값들. 없으면 자동 감지로 부트스트랩하되 "추정"임을 항상 출력한다.
# 설정이 진실의 원천이고 감지는 부트스트랩일 뿐 — 감지는 썩는 표면이라 최소로 둔다.
DIALECTS=""           # 비우면 자동 감지. 예: "tailwind css jsx locale.ko"
TOKEN_BRAND=""        # 예: --accent   (미선언이면 관련 체크는 SKIP)
TOKEN_STATUS=""       # 예: status-
THEME_STRATEGY=""     # custom-variant | class | media
IGNORE_HEX=""         # 정당한 하드코딩 hex (OAuth 브랜드색 등)
IGNORE_HEX_REASON=""
MIN_CORPUS=8          # 부재 방향 체크가 유효하려면 필요한 최소 파일 수

find_config() {
  [ -n "$CONFIG" ] && { echo "$CONFIG"; return; }
  local d; d="$(cd "$(dirname "${P[0]}")" 2>/dev/null && pwd)" || return
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.design/audit.conf" ] && { echo "$d/.design/audit.conf"; return; }
    d="$(dirname "$d")"
  done
}
CONFIG="$(find_config)"
CONFIG_SRC="없음 (자동 감지)"
if [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG"
  CONFIG_SRC="$CONFIG"
fi

# ── 카운터 / 출력 ──────────────────────────────────────────────────────────
HITS=0; RAN=0; SKIPPED=0; WARNS=0; IGNORED=0
SKIPPED_IDS=()

hit()  { HITS=$((HITS+1)); RAN=$((RAN+1)); printf "  \033[31mHIT\033[0m  %-29s %s\n" "$1" "$2"; }
ok()   { RAN=$((RAN+1));   printf "  ok   %-29s %s\n" "$1" "$2"; }
warn() { WARNS=$((WARNS+1)); RAN=$((RAN+1)); printf "  \033[33m확인\033[0m %-29s %s\n" "$1" "$2"; }
skip() { SKIPPED=$((SKIPPED+1)); SKIPPED_IDS+=("$1"); printf "  \033[33mSKIP\033[0m %-28s (%s)\n" "$1" "$2"; }
sect() { printf "== %s ==\n" "$1"; }

# ── 코퍼스 ────────────────────────────────────────────────────────────────
# code  : 로직·마크업이 있는 파일 (클래스 문자열이 여기 산다)
# style : CSS 선언이 있을 수 있는 파일. .vue/.svelte/.astro/.html은 <style> 블록 때문에 양쪽에 속한다
CODE_EXT="tsx ts jsx js mjs cjs vue svelte astro html htm mdx"
STYLE_EXT="css scss sass less styl vue svelte astro html htm"

files_of() {
  local ext exprs=()
  for ext in $1; do exprs+=(-o -name "*.$ext"); done
  find "${P[@]}" -type f \( "${exprs[@]:1}" \) 2>/dev/null \
    | grep -vE '/(node_modules|\.next|dist|build|vendor|\.git)/'
}
CODE_FILES=$(files_of "$CODE_EXT")
STYLE_FILES=$(files_of "$STYLE_EXT")
CODE_N=$(printf '%s' "$CODE_FILES" | grep -c . || true)
STYLE_N=$(printf '%s' "$STYLE_FILES" | grep -c . || true)

# 매치된 "줄 내용"만 돌려준다.
# 주석은 파일 단위 awk로 먼저 제거한다 — 줄 단위 필터로는 여러 줄 블록 주석의
# **연속 줄**이 새서, 규칙을 설명한 주석이 그 규칙에 걸리는 오탐이 계속 났다.
# 주석 제거 awk.
read -r -d '' STRIP_AWK_SRC <<'AWK_EOF' || true
# 주석 제거. 파일 하나씩 통과시킨다(블록 주석 상태를 추적해야 하므로).
#
# 왜 필요한가: 규칙을 설명한 주석이 그 규칙 자신에게 걸리는 오탐이 반복해서 나왔다.
# 줄 단위로 "주석 문자로 시작하는 줄"만 버리면, 여러 줄 블록 주석의 **연속 줄**이 샌다
# 여러 줄 블록 주석의 둘째 줄이 그대로 새기 때문이다.
#
# 처리: /* */ 와 <!-- --> 블록(여러 줄 포함), 그리고 줄 주석 //.
# `#`은 건드리지 않는다 — CSS hex 색상(#6366f1)을 지워버린다.
# `//`는 앞 글자가 `:`이면 URL(https://)로 보고 건너뛴다.
# 여러 파일을 한 번에 넘기므로 파일이 바뀌면 블록 주석 상태를 리셋한다.
FNR == 1 { inblk = 0 }

{
  line = $0

  # 이전 줄에서 열린 블록 닫기
  while (inblk > 0) {
    if (inblk == 1 && match(line, /\*\//))      { line = substr(line, RSTART + 2); inblk = 0 }
    else if (inblk == 2 && match(line, /-->/))  { line = substr(line, RSTART + 3); inblk = 0 }
    else { line = ""; break }
  }

  # 이 줄에서 열리는 블록 처리
  changed = 1
  while (changed) {
    changed = 0
    if (match(line, /\/\*/)) {
      pre = substr(line, 1, RSTART - 1); rest = substr(line, RSTART + 2)
      if (match(rest, /\*\//)) { line = pre " " substr(rest, RSTART + 2); changed = 1 }
      else { line = pre; inblk = 1 }
    }
    if (match(line, /<!--/)) {
      pre = substr(line, 1, RSTART - 1); rest = substr(line, RSTART + 4)
      if (match(rest, /-->/)) { line = pre " " substr(rest, RSTART + 3); changed = 1 }
      else { line = pre; inblk = 2 }
    }
  }

  # 줄 주석 // — 단 URL의 `://`는 건너뛴다
  p = index(line, "//")
  while (p > 0) {
    if (p == 1 || substr(line, p - 1, 1) != ":") { line = substr(line, 1, p - 1); break }
    q = index(substr(line, p + 2), "//")
    if (q == 0) break
    p = p + 1 + q
  }

  print line
}
AWK_EOF
# 주석 제거는 **시작 시 1회**만. 체크마다 전 파일에 awk를 돌리면
# 파일 99개 × 체크 25개 = 2000회가 되고 파일 1000개에선 30초를 넘긴다.
CACHE="$(mktemp -d)"
trap 'rm -rf "$CACHE"' EXIT INT TERM
strip_to() { # $1=파일목록 $2=출력경로
  : > "$2"
  [ -z "$1" ] && return 0
  printf '%s\n' "$1" | tr '\n' '\0' | xargs -0 awk "$STRIP_AWK_SRC" > "$2" 2>/dev/null
}
strip_to "$CODE_FILES"  "$CACHE/code.txt"
strip_to "$STYLE_FILES" "$CACHE/style.txt"

_lines() { grep -E "$2" "$1" 2>/dev/null; }
lc() { _lines "$CACHE/code.txt"  "$1"; }   # code 코퍼스 — 줄 내용
ls_() { _lines "$CACHE/style.txt" "$1"; }  # style 코퍼스 (<style> 블록 포함)
nc() { lc "$1" | grep -c . || true; }      # 매치된 줄 수
ns() { ls_ "$1" | grep -c . || true; }
# 종류를 세야 할 때(`sort -u`)만 매치 문자열을 뽑는다. 앵커 없는 패턴에만 쓸 것.
gc() { lc "$1" | grep -oE "$1"; }
gs() { ls_ "$1" | grep -oE "$1"; }

# ── dialect 감지 ──────────────────────────────────────────────────────────
has_dialect() { case " $DIALECTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
DIALECT_SRC="설정"
if [ -z "$DIALECTS" ]; then
  DIALECT_SRC="추정"
  d=""
  # Tailwind: class/className 문자열 안에 유틸리티 토큰이 보이는가
  [ "$(nc 'class(Name)?="[^"]*\b(flex|grid|hidden|(bg|text|border|rounded|shadow|gap|p|m|px|py|mx|my|w|h)-[a-z0-9[])')" -gt 0 ] && d="$d tailwind"
  # CSS: 선언 구문이 보이는가
  CSS_PROP='(background|color|font-family|font-size|margin|padding|display|position|transition|transform|border|width|height|flex|grid|box-shadow|opacity)[[:space:]]*:[[:space:]]*[^;{]+;'
  [ "$(ns "$CSS_PROP")" -gt 0 ] && d="$d css"
  # JSX
  [ "$(printf '%s\n' "$CODE_FILES" | grep -cE '\.(tsx|jsx)$' || true)" -gt 0 ] && d="$d jsx"
  DIALECTS="$(echo "$d" | sed 's/^ //')"
fi

# ── preflight ─────────────────────────────────────────────────────────────
sect "0. 스캔 대상"
printf "  %-29s %s\n" "설정" "$CONFIG_SRC"
printf "  %-29s %s\n" "경로" "${P[*]}"
printf "  %-29s %s\n" "code 파일" "${CODE_N}개"
printf "  %-29s %s\n" "style 파일" "${STYLE_N}개"
printf "  %-29s %s\n" "표현 방식" "${DIALECTS:-(없음)} [$DIALECT_SRC]"
[ -n "$TOKEN_BRAND" ] && printf "  %-29s %s\n" "브랜드 토큰" "$TOKEN_BRAND"

if [ "$((CODE_N + STYLE_N))" -eq 0 ]; then
  echo
  echo "결과: 스캔 불가 — 읽을 파일 0개."
  echo "  찾는 확장자 : $CODE_EXT $STYLE_EXT"
  echo "  실제 확장자 :"
  find "${P[@]}" -type f 2>/dev/null | sed -n 's/.*\.\([a-zA-Z0-9]\{1,8\}\)$/\1/p' \
    | sort | uniq -c | sort -rn | head -8 | sed 's/^/    /'
  echo
  echo "  ai-tells.md의 기계 항목을 이 스택에 맞는 grep으로 직접 돌리고,"
  echo "  어떤 항목을 돌렸는지 보고할 것. **통과로 취급하지 말 것.**"
  exit 3
fi
if [ -z "$DIALECTS" ]; then
  echo
  echo "결과: 스캔 불가 — 파일은 찾았지만 인식 가능한 표현 방식이 없다."
  echo "  .design/audit.conf 에 DIALECTS를 직접 선언하거나(예: DIALECTS=\"css\"),"
  echo "  ai-tells.md의 기계 항목을 손으로 돌릴 것. **통과로 취급하지 말 것.**"
  exit 3
fi
echo

# ── 규칙 정의 ─────────────────────────────────────────────────────────────

# core — 표현 방식과 무관하게 어떤 파일에서든 유효한 체크.
# 값(hex·폰트 이름·커브 수치)과 문자열 리터럴만 본다. 구문에 기대지 않는다.

run_core() {
  sect "1. 컬러 (core)"

  # AI 보라 / Tailwind 기본 팔레트 값. 클래스명이든 hex든, 어느 파일에 있든 잡는다.
  local ai='#6366f1|#a855f7|#8b5cf6|#7c3aed|slate-50|indigo-600|violet-500|purple-600'
  local c=$(( $(nc "$ai") + $(ns "$ai") ))
  [ "$c" -gt 0 ] && hit "AI 보라·기본 팔레트" "${c}곳" || ok "AI 보라·기본 팔레트" "없음"

  # 하드코딩 hex: 테마 고정 표면(브랜드 버튼·반전 토스트)에서는 정당하다.
  # 기계로 의도를 알 수 없으므로 HIT가 아니라 "확인"으로 올린다.
  #
  # **토큰 정의부(`--foo: #hex`)는 세지 않는다.** 거기가 바로 hex가 있어야 할 자리다.
  # 문제는 "토큰을 놔두고 컴포넌트에 hex를 박는 것"이지 토큰 자체가 아니다.
  local hexes total ignored
  hexes=$( { lc '#[0-9a-fA-F]{6}\b' | grep -vE '^[^:]*--[a-z0-9-]+:'
             ls_ '#[0-9a-fA-F]{6}\b' | grep -vE '(^|[{;])[[:space:]]*--[a-z0-9-]+:'; } \
           | grep -oE '#[0-9a-fA-F]{6}\b' )
  total=$(printf '%s\n' "$hexes" | grep -c . || true)
  if [ -n "$IGNORE_HEX" ]; then
    ignored=$(printf '%s\n' "$hexes" | grep -icE "$IGNORE_HEX" || true)
    IGNORED=$((IGNORED + ignored)); total=$((total - ignored))
  fi
  [ "$total" -gt 0 ] && warn "하드코딩 hex" "${total}곳 (테마 고정 표면이면 정당. 아니면 토큰)" \
                     || ok "하드코딩 hex" "없음"

  sect "2. 타이포 (core)"
  # 폰트 이름은 값이라 어느 구문에서든 같은 문자열로 나타난다.
  local f='(Inter|Poppins|Noto Sans KR|Roboto|Open Sans|Montserrat)'
  c=$(( $(nc "font(-family)?[^;{]*$f|['\"]$f['\"]|font-(inter|poppins|roboto)") + $(ns "font-family[^;]*$f") ))
  [ "$c" -gt 0 ] && hit "기본 폰트" "${c}곳" || ok "기본 폰트" "없음"

  sect "5. 콘텐츠 (core)"
  local slop='🚀|✨|💡|🎉|Acme|John Doe|Jane Doe|99\.9%|10,000\+|api/placeholder|lorem ipsum|Lorem ipsum'
  c=$(( $(nc "$slop") + $(ns "$slop") ))
  [ "$c" -gt 0 ] && hit "더미·이모지 slop" "${c}곳" || ok "더미·이모지 slop" "없음"

  sect "6. 모션 (core)"
  # Tailwind/Material 기본 커브. 값이라 어느 구문에서든 동일.
  local cb='cubic-bezier\([[:space:]]*0?\.4[[:space:]]*,[[:space:]]*0[[:space:]]*,[[:space:]]*0?\.2[[:space:]]*,[[:space:]]*1[[:space:]]*\)'
  c=$(( $(nc "$cb") + $(ns "$cb") ))
  [ "$c" -gt 0 ] && hit "기본 커브" "${c}곳 (직접 설계한 커브를 쓸 것)" || ok "커스텀 커브" "기본커브 미사용"
}

# css — CSS 선언 구문으로 표현된 슬롭. .css/.scss뿐 아니라 .vue/.svelte/.astro/.html의
# <style> 블록도 같은 코퍼스로 읽는다. **이 팩이 이식성의 핵심이다** —
# Tailwind를 안 쓰는 프로젝트는 디자인 결정을 전부 여기에 담는다.

run_css() {
  sect "1. 컬러 (css)"
  # CSS 변수 정의부에 Tailwind 기본 팔레트가 그대로 앉아 있는 경우.
  # 유틸리티 클래스가 아니라 토큰 값이라 클래스 체크에 안 걸린다

  local TW='#6b7280|#9ca3af|#111827|#374151|#64748b|#0f172a|#94a3b8|#71717a|#f59e0b|#10b981|#22c55e|#3b82f6|#ef4444|#6366f1|#a855f7|#eab308'
  # 앵커를 줄 시작에 걸면 `:root { --accent: #6366f1; }` 같은 한 줄 선언을 놓친다.
  local c; c=$(ns "(^|[{;])[[:space:]]*--[a-z0-9-]+:[[:space:]]*($TW)")
  [ "$c" -gt 0 ] && hit "토큰에 기본 팔레트색" "${c}곳 (브랜드 값으로 대체할 것)" || ok "토큰 팔레트" "브랜드 값"

  # 브랜드색 그림자 → accent가 채도 높은 색이 되는 순간 네온 글로우가 된다.
  if [ -z "$TOKEN_BRAND" ]; then
    skip "브랜드 글로우" "TOKEN_BRAND 미선언"
  else
    c=$(( $(ns "(box-)?shadow[^;]*var\($TOKEN_BRAND\)") + $(nc "shadow-\[[^]]*var\($TOKEN_BRAND\)") ))
    [ "$c" -gt 0 ] && hit "브랜드 글로우" "${c}곳 (중립 그림자를 쓸 것)" || ok "브랜드 글로우" "없음"
    # 브랜드 토큰 옆 하드코딩 hex: 토큰을 바꾸면 이 짝만 안 바뀌어 그라데이션이 탁해진다.
    c=$(( $(ns "gradient\([^)]*var\($TOKEN_BRAND\)[^)]*#[0-9a-fA-F]{6}") \
        + $(nc "gradient\([^)]*var\($TOKEN_BRAND\)[^)]*#[0-9a-fA-F]{6}") ))
    [ "$c" -gt 0 ] && hit "그라데이션 짝값 하드코딩" "${c}곳 (종점도 토큰으로)" || ok "그라데이션 짝값" "토큰화됨"
  fi

  sect "4. 컴포넌트 (css)"
  c=$(ns 'transition:[[:space:]]*all\b')
  [ "$c" -gt 0 ] && hit "transition: all" "${c}곳 (속성을 명시할 것)" || ok "transition: all" "없음"

  # :hover 확대 남용. 몇 개까지는 정당하므로 임계값을 둔다.
  c=$(ns ':hover[^{]*\{[^}]*transform:[^;}]*scale\(')
  [ "$c" -eq 0 ] && c=$(ns 'transform:[[:space:]]*scale\(')
  [ "$c" -gt 3 ] && hit "hover scale 남용" "${c}곳" || ok "hover scale" "${c}곳"

  sect "2. 타이포 (css)"
  # 부재 방향 체크 — 코퍼스가 작으면 그 자체로 거짓 HIT가 된다.
  if [ "$STYLE_N" -lt "$MIN_CORPUS" ]; then
    skip "자간·행간 조정(css)" "style 파일 ${STYLE_N}개 — 규모 부족"
  else
    local decls tuned
    decls=$(ns 'font-size:')
    tuned=$(ns '(letter-spacing|line-height):')
    local need=$(( decls / 3 )); [ "$need" -lt 2 ] && need=2
    [ "$tuned" -lt "$need" ] && hit "자간·행간 미조정(css)" "${tuned}곳 (font-size ${decls}곳 대비 최소 ${need} 기대)" \
                             || ok "자간·행간 조정(css)" "${tuned}곳"
  fi
}

# tailwind — 유틸리티 클래스로 표현된 슬롭.
# 확장자가 아니라 dialect로 걸리므로 .vue·.html의 Tailwind도 그대로 잡는다.

run_tailwind() {
  sect "4. 컴포넌트 (tailwind)"
  local c
  c=$(nc 'transition-all')
  [ "$c" -gt 0 ] && hit "transition-all" "${c}곳 (속성을 명시할 것)" || ok "transition-all" "없음"
  c=$(nc 'hover:scale-')
  [ "$c" -gt 3 ] && hit "hover:scale 남용" "${c}곳" || ok "hover:scale" "${c}곳"

  sect "2. 타이포 (tailwind)"
  if [ "$CODE_N" -lt "$MIN_CORPUS" ]; then
    skip "자간·행간 조정(tw)" "code 파일 ${CODE_N}개 — 규모 부족"
  else
    # 절대 임계값은 12개짜리 프로젝트와 400개짜리에서 다른 뜻이 된다. 선언 수 대비 비율로 본다.
    local typo tuned need
    typo=$(nc 'text-\[[0-9.]+px\]|\btext-(xs|sm|base|lg|xl|[2-9]xl)\b')
    tuned=$(nc 'tracking-\[|leading-\[|\btracking-(tight|tighter|wide)\b')
    need=$(( typo / 12 )); [ "$need" -lt 3 ] && need=3
    [ "$tuned" -lt "$need" ] && hit "자간·행간 미조정(tw)" "${tuned}곳 (타이포 선언 ${typo}곳 대비 최소 ${need} 기대)" \
                             || ok "자간·행간 조정(tw)" "${tuned}곳"
  fi

  sect "3. 레이아웃 (tailwind)"
  if [ "$CODE_N" -lt "$MIN_CORPUS" ]; then
    skip "섹션 리듬" "code 파일 ${CODE_N}개 — 규모 부족"
    skip "비대칭 분할" "code 파일 ${CODE_N}개 — 규모 부족"
  else
    # 섹션 리듬만 본다(py-8 이상). 버튼·칩 내부 패딩(py-1~4)은 제외 — 오탐 방지
    local rh asym
    rh=$(gc '\bpy-([89]|[1-9][0-9])\b' | sort -u | grep -c . || true)
    [ "$rh" -le 1 ] && hit "섹션 리듬 없음" "섹션 패딩 종류 ${rh}개" || ok "섹션 리듬" "${rh}종"
    asym=$(nc 'grid-cols-\[|col-span-[4-9]|grid-cols-[5-9]|grid-cols-1[0-2]')
    [ "$asym" -eq 0 ] && hit "비대칭 분할 없음" "2·3열만 사용" || ok "비대칭 분할" "${asym}곳"
  fi

  sect "7. 테마 전략 (tailwind)"
  # `dark:` 변형과 `.dark` 클래스 토큰 오버라이드가 **둘 다** 있는데
  # @custom-variant dark 를 선언하지 않았으면, dark:는 OS 설정을 따르고 토큰은 클래스를 따라 어긋난다.
  # custom-variant를 정의한 프로젝트에서는 dark:가 정상이므로 HIT가 아니다.
  local dv co cv
  dv=$(nc 'dark:[a-z-]+')
  co=$(ns '^[[:space:]]*\.dark\b|:root:not\(\[data-theme')
  cv=$(( $(ns '@custom-variant[[:space:]]+dark') + $(nc '@custom-variant[[:space:]]+dark') ))
  if [ -n "$THEME_STRATEGY" ] && [ "$THEME_STRATEGY" = "custom-variant" ]; then
    ok "테마 전략" "custom-variant 선언됨 — dark: 정상"
  elif [ "$cv" -gt 0 ]; then
    ok "테마 전략" "@custom-variant dark 감지 — dark: 정상"
  elif [ "$dv" -gt 0 ] && [ "$co" -gt 0 ]; then
    hit "테마 전략 혼용" "dark: ${dv}곳 + .dark 토큰 ${co}곳 (@custom-variant 없이 섞이면 어긋난다)"
  elif [ "$dv" -eq 0 ] && [ "$co" -eq 0 ]; then
    skip "테마 전략" "다크 테마 구현 없음"
  else
    ok "테마 전략" "한 방식만 사용"
  fi
}

# react — JSX 구문에 기대는 체크.

run_react() {
  sect "4. 컴포넌트 (react)"
  local c
  # 아이콘 크기 획일. size={N} 규약을 쓰는 프로젝트에만 의미 있다.
  c=$(gc 'size=\{[0-9]+\}' | sort -u | grep -c . || true)
  if [ "$c" -eq 0 ]; then skip "아이콘 크기" "size={} 사용처 0곳 — 아이콘 규약이 다름"
  elif [ "$CODE_N" -lt "$MIN_CORPUS" ]; then skip "아이콘 크기" "code 파일 ${CODE_N}개 — 규모 부족"
  elif [ "$c" -le 1 ]; then hit "아이콘 크기 획일" "${c}종"
  else ok "아이콘 크기" "${c}종"; fi

  # 시맨틱 토큰 오용: 상태색(완료·에러·경고)을 데이터 표시에 빌려 쓰면 팔레트에 없는 색이 튄다.
  # 예: 별점이 status-done(초록)을 빌려 쓰면 팔레트에 없는 초록 배지가 뜬다.
  if [ -z "$TOKEN_STATUS" ]; then
    skip "별점에 상태색" "TOKEN_STATUS 미선언"
  else
    local c1 c2
    c1=$(nc "class(Name)?=\"[^\"]*(star|rating)[^\"]*($TOKEN_STATUS|success|danger)")
    c2=$(printf '%s\n' "$CODE_FILES" | tr '\n' '\0' \
         | xargs -0 grep -nE -A2 '<Star' 2>/dev/null | grep -cE "$TOKEN_STATUS|text-success|text-danger" || true)
    c=$((c1 + c2))
    [ "$c" -gt 0 ] && hit "별점에 상태색 사용" "${c}곳 (별점은 데이터, 중립색을 쓸 것)" || ok "시맨틱 토큰" "오용 없음"
  fi

  sect "6. 모션 (react)"
  # 진입 모션이 전부 같은 효과면 목적이 없다는 뜻.
  local kinds tot
  kinds=$(gc 'animation:[a-z-]+_[0-9]+m?s_[a-z-]*\([^)]*\)' | sed 's/_[0-9]*m*s_/_/' | sort -u | grep -c . || true)
  tot=$(nc 'animation:[a-z-]+_[0-9]+m?s')
  if [ "$tot" -eq 0 ]; then skip "진입 모션 종류" "진입 모션 선언 0곳"
  elif [ "$tot" -gt 2 ] && [ "$kinds" -le 1 ]; then hit "진입 모션 획일" "${tot}곳이 전부 같은 효과 (목적별로 달라야)"
  else ok "진입 모션 종류" "${kinds}종 / ${tot}곳"; fi
}

# locale.ko — 한국어 제품에서만 의미 있는 체크.
# 숫자 탐지에 한국어 단위가 들어가므로 core에 두면 영어권 제품에서 무력해진다.

run_locale_ko() {
  sect "2. 타이포 (locale.ko)"
  local num tab
  num=$(nc '[0-9]{1,3},[0-9]{3}|[0-9]+원|[0-9]+박|D-[0-9]|[0-9]+%')
  tab=$(nc 'tabular-nums|font-variant-numeric')
  if [ "$num" -le 3 ]; then skip "tabular-nums" "숫자 표기 ${num}곳 — 판정 근거 부족"
  elif [ "$tab" -eq 0 ]; then hit "tabular-nums 없음" "숫자 표기 ${num}곳인데 고정폭 0"
  else ok "tabular-nums" "${tab}곳"; fi

  # 한글은 자간을 좁히지 않으면 기본값이 성기게 보인다(typography.md §2).
  local ko ls
  ko=$(nc '[가-힣]{2,}')
  ls=$(( $(nc 'tracking-\[-') + $(ns 'letter-spacing:[[:space:]]*-') ))
  if [ "$ko" -lt 20 ]; then skip "한글 자간" "한글 문자열 ${ko}곳 — 한국어 제품 아님"
  elif [ "$ls" -eq 0 ]; then hit "한글 자간 미조정" "한글 ${ko}곳인데 음수 자간 0 (기본값은 성기다)"
  else ok "한글 자간" "${ls}곳"; fi
}


run_core
has_dialect css && run_css || skip "css 규칙" "css dialect 아님"
has_dialect tailwind && run_tailwind || skip "tailwind 규칙" "tailwind dialect 아님"
has_dialect jsx && run_react || skip "react 규칙" "jsx dialect 아님"
has_dialect locale.ko && run_locale_ko || skip "locale.ko 규칙" "한국어 제품 아님"
command -v run_local >/dev/null 2>&1 && run_local

# ── 요약 ──────────────────────────────────────────────────────────────────
echo
printf "검사 %d / 건너뜀 %d / HIT %d / 확인 %d" "$RAN" "$SKIPPED" "$HITS" "$WARNS"
[ "$IGNORED" -gt 0 ] && printf " / 무시 %d" "$IGNORED"
echo
[ "$IGNORED" -gt 0 ] && [ -n "$IGNORE_HEX_REASON" ] && echo "  무시 사유: $IGNORE_HEX_REASON"

if [ "$SKIPPED" -gt 0 ]; then
  echo "결과: 부분 검사. 건너뛴 ${SKIPPED}건은 검증되지 않았다 —"
  for id in "${SKIPPED_IDS[@]}"; do echo "  · $id"; done
  echo "이 항목들은 최종 보고에 '미검증'으로 명시할 것."
  [ "$HITS" -gt 0 ] && echo "그리고 HIT ${HITS}건을 먼저 처리할 것."
  exit 4
fi
if [ "$HITS" -eq 0 ]; then
  echo "결과: 기계 체크 통과. 이제 ai-tells.md의 시각 항목을 스크린샷으로 판정할 것."
  exit 0
fi
echo "결과: HIT ${HITS}건. 내가 만든 것이면 고치고 다시 렌더. 기존 것이면 보고만 한다."
exit 1
