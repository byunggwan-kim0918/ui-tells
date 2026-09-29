#!/usr/bin/env bash
# 픽스처 회귀. 사용: bash tests/run-fixtures.sh
#
# 양성 픽스처는 기대한 HIT가 나와야 하고, 음성 픽스처는 **하나도** 나오면 안 된다.
# 음성 쪽이 이 파일의 존재 이유다 — 과거에 실제로 오탐을 냈던 케이스를 고정해 둔다.
# 규칙을 고치다 이게 깨지면, 그 수정이 예전에 잡은 오탐을 되살린 것이다.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="${AUDIT_BIN:-$D/../skills/ui-tells/audit.sh}"
PASS=0; FAIL=0

# 픽스처는 **격리**되어야 한다. 상위 디렉터리에 .design/audit.conf 가 생기면
# (또는 이 스킬이 그런 프로젝트 안에 설치되면) 자동 탐색이 그걸 주워와서
# dialect·토큰이 바뀌고 테스트가 조용히 다른 걸 검사하게 된다.
# 빈 설정을 명시적으로 물려 자동 탐색을 차단한다.
EMPTY_CONF="$(mktemp)"
trap 'rm -f "$EMPTY_CONF"' EXIT
run() { bash "$AUDIT" --config "$EMPTY_CONF" "$1" 2>&1; }

# $1=라벨 $2=경로 $3=기대 문자열(HIT 라인에 포함돼야 함)
expect_hit() {
  local out; out="$(run "$2")"
  if printf '%s' "$out" | grep -q $'\033\[31mHIT'".*$3"; then
    PASS=$((PASS+1)); printf "  \033[32mPASS\033[0m %-22s HIT: %s\n" "$1" "$3"
  else
    FAIL=$((FAIL+1)); printf "  \033[31mFAIL\033[0m %-22s HIT 기대했으나 없음: %s\n" "$1" "$3"
  fi
}

# $1=라벨 $2=경로 $3=항목명 — 그 항목이 SKIP 이 아니어야 한다.
# SKIP 은 "검사하지 못함"이므로, 구현이 있는데 못 알아보면 여기서 걸린다.
expect_ran() {
  local out; out="$(run "$2")"
  if printf '%s' "$out" | grep -q $'\033\[33mSKIP'".*$3"; then
    FAIL=$((FAIL+1)); printf "  \033[31mFAIL\033[0m %-22s SKIP 되면 안 됨: %s\n" "$1" "$3"
  else
    PASS=$((PASS+1)); printf "  \033[32mPASS\033[0m %-22s 실행됨: %s\n" "$1" "$3"
  fi
}

# $1=라벨 $2=경로 — HIT가 0건이어야 한다
expect_clean() {
  local out n; out="$(run "$2")"
  n=$(printf '%s' "$out" | grep -c $'\033\[31mHIT' || true)
  if [ "$n" -eq 0 ]; then
    PASS=$((PASS+1)); printf "  \033[32mPASS\033[0m %-22s HIT 0건\n" "$1"
  else
    FAIL=$((FAIL+1)); printf "  \033[31mFAIL\033[0m %-22s 오탐 %d건:\n" "$1" "$n"
    printf '%s' "$out" | grep $'\033\[31mHIT' | sed 's/^/        /'
  fi
}

# $1=라벨 $2=경로 $3=기대 exit code
expect_exit() {
  bash "$AUDIT" --config "$EMPTY_CONF" "$2" >/dev/null 2>&1; local rc=$?
  if [ "$rc" -eq "$3" ]; then
    PASS=$((PASS+1)); printf "  \033[32mPASS\033[0m %-22s exit=%d\n" "$1" "$rc"
  else
    FAIL=$((FAIL+1)); printf "  \033[31mFAIL\033[0m %-22s exit=%d (기대 %d)\n" "$1" "$rc" "$3"
  fi
}

echo "== 음성 (오탐 회귀 — 여기가 깨지면 예전 오탐이 되살아난 것) =="
expect_clean "tailwind/negative" "$D/fixtures/tailwind/negative.tsx"
expect_clean "css/negative"      "$D/fixtures/css/negative.css"
# CSS base·@theme 로 처리한 프로젝트를 "유틸리티 미사용"으로 오판하지 않는가 (근거 L23)
expect_clean "css-first"         "$D/fixtures/css-first"
expect_ran   "css-first"         "$D/fixtures/css-first" "테마 전략"

echo "== 양성 · Tailwind+React =="
expect_hit "tailwind/positive" "$D/fixtures/tailwind/positive.tsx" "AI 보라"
expect_hit "tailwind/positive" "$D/fixtures/tailwind/positive.tsx" "기본 폰트"
expect_hit "tailwind/positive" "$D/fixtures/tailwind/positive.tsx" "더미·이모지"
expect_hit "tailwind/positive" "$D/fixtures/tailwind/positive.tsx" "transition-all"
expect_hit "tailwind/positive" "$D/fixtures/tailwind/positive.tsx" "hover:scale"

echo "== 양성 · 순수 CSS (Tailwind 없음) =="
expect_hit "css/positive" "$D/fixtures/css/positive.css" "AI 보라"
expect_hit "css/positive" "$D/fixtures/css/positive.css" "토큰에 기본 팔레트색"
expect_hit "css/positive" "$D/fixtures/css/positive.css" "transition: all"
expect_hit "css/positive" "$D/fixtures/css/positive.css" "기본 폰트"
expect_hit "css/positive" "$D/fixtures/css/positive.css" "기본 커브"
expect_hit "css/positive" "$D/fixtures/css/positive.css" "hover scale"

echo "== 양성 · Vue (style 블록) =="
expect_hit "vue/positive" "$D/fixtures/vue/positive.vue" "AI 보라"
expect_hit "vue/positive" "$D/fixtures/vue/positive.vue" "transition: all"
expect_hit "vue/positive" "$D/fixtures/vue/positive.vue" "기본 폰트"

echo "== 양성 · Svelte (style 블록) =="
expect_hit "svelte/positive" "$D/fixtures/svelte/positive.svelte" "AI 보라"
expect_hit "svelte/positive" "$D/fixtures/svelte/positive.svelte" "transition: all"

echo "== 양성 · 순수 HTML =="
expect_hit "plain/positive" "$D/fixtures/plain/positive.html" "기본 폰트"
expect_hit "plain/positive" "$D/fixtures/plain/positive.html" "기본 커브"
expect_hit "plain/positive" "$D/fixtures/plain/positive.html" "더미·이모지"

echo "== 스캔 불가는 통과가 아니라 실패 =="
EMPTY="$(mktemp -d)"; printf 'hello\n' > "$EMPTY/readme.txt"
expect_exit "읽을 파일 0개" "$EMPTY" 3
rm -rf "$EMPTY"

echo
printf "PASS %d / FAIL %d\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
