# 후단 연결 (handoff)

이 skill은 판정·리서치·결정·검증·제시를 한다. 코드 생성과 모션 구현은 후단 skill에 위임할 수 있다.
**단 위임은 최적화지 전제가 아니다.** 후단이 없어도 멈추지 않는다.

---

## 1. 절 번호를 부르지 않는다 — 앵커 문자열로 찾는다

후단 skill의 `§0.A`, `§13` 같은 절 번호를 우리 본문에 박으면, 상대가 절을 재배치하는 순간
**조용히** 깨진다. 우리가 필요한 건 위치가 아니라 그 자리에 있는 **문자열**이다.

| 우리가 필요한 것 | 후단 앵커 문자열 | 앵커가 없을 때 |
|---|---|---|
| DNA 투입구 | `Reference signals` | 헤더 없이 본문 앞부분에 같은 내용을 전달 |
| 브랜드 자산 슬롯 | `Brand assets that already exist` | DNA의 브랜드 절을 그대로 전달 |
| Design Read 포맷 | `Reading this as:` | 우리 형식으로 직접 출력 |
| 다이얼 이름 | `DESIGN_VARIANCE` / `MOTION_INTENSITY` / `VISUAL_DENSITY` | 수치 + 각 축의 정의를 함께 전달 |
| 제품 UI 범위 선언 | `not multi-step product UI` | 범위 판정을 우리가 단독 수행 |
| 레이아웃 보존 규칙 | `preserve` + `IA` | 요청 없이 IA·라우트·라벨을 바꾸지 않는다는 원칙만 적용 |

**절 번호는 이 표 밖에 존재하지 않는다.** 본문에서는 "taste-skill의 `Reference signals` 슬롯"처럼 부른다.

확인: `bash audit.sh --handoff` — 첫 위임 직전에 돌린다. 밀리초면 끝난다.
FAIL이 뜨면 **우리 쪽을 고친다**(후단 파일을 고치지 않는다).

---

## 2. 후단이 없으면 — 멈추지 말고 직접 한다

예전 규칙은 "미설치면 설치 명령을 안내하고 멈춘다"였다. 그러면 **처음 쓰는 사람은 첫 실행이 곧 중단**이다.
§9의 중단 조건 철학과도 어긋난다 — 진짜 중단 사유는 내가 물리적으로 접근할 수 없는 것뿐이고,
설치 안 된 선택적 skill은 거기 해당하지 않는다.

| 능력 | 1순위 (skill 있음) | 2순위 (없음 → 직접) |
|---|---|---|
| **코드 생성** | `design-taste-frontend`에 위임 | **직접 쓴다.** DNA·다이얼·[ai-tells.md](ai-tells.md)가 이미 우리 손에 있다. 부족한 건 후단의 프리셋 표뿐이고, 그건 다이얼 수치로 대체된다 |
| **모션 구현** | `animate`에 위임 | **아래 기본 표로 직접 구현** |
| **모션 어휘** | `animation-vocabulary` 참조 | **아래 12개 축약본** 사용. "불명(용어집 외)"의 바닥을 만든다 |
| **모션 탐색** | `find-animation-opportunities` | 스펙이 불명이면 모션을 넣지 않는다. 추측해서 넣지 않는다 |
| **모션 리뷰** | `review-animations` (자동 트리거 꺼짐 → 명시 실행 안내) | 아래 "절대 금지" 목록으로 자가 점검 |

**어느 경우든** 최종 제시에 한 줄 남긴다:
> 후단 미설치 — `<skill>` 설치 시 이 단계가 강화된다: `<설치 명령>`

### 2.A 모션 기본 표 (`animate` 없을 때)

| 상황 | 지속시간 | 이징 | 속성 |
|---|---|---|---|
| 진입 (모달·드로어) | 200~300ms | `cubic-bezier(0.23, 1, 0.32, 1)` | `opacity` + `transform` |
| 진입 (툴팁·작은 팝오버) | 125~200ms | 같음 | 같음 |
| 퇴장 | 진입의 0.8배 | 같음 | 들어온 경로로 나간다 |
| 호버·색 변화 | 100~160ms | `ease` | 해당 속성만 명시 |
| 누름 | 100ms | `ease-out` | `transform: scale(0.98)` 또는 `translateY(1px)` |
| 화면 내 이동·변형 | 200~300ms | `cubic-bezier(0.77, 0, 0.175, 1)` | `transform` |
| 로딩(불확정) | 1.2~1.6s 루프 | `linear` | `opacity` 또는 `transform` |

**절대 금지** — 후단 리뷰가 없어도 이건 지킨다:
`transition: all` · `scale(0)`에서 시작 · UI에 `ease-in` · 300ms 넘는 UI 전환(이유 없이) ·
하루 100번 보는 동작에 모션 · 빠르게 연타되는 요소에 keyframes(전환을 쓸 것) ·
`prefers-reduced-motion` 미처리 · 게이트 없는 `:hover` 모션 · 접힘선 아래 요소에 로드 시점 모션.

### 2.B 모션 어휘 축약본 (`animation-vocabulary` 없을 때)

`Fade in` / `Fade out` / `Crossfade` / `Slide in` / `Pop in`(살짝 확대하며 등장) /
`Stagger`(순차 지연) / `Scroll reveal` / `Skeleton shimmer` / `Spinner` /
`Rubber-banding`(경계 탄성) / `Spring`(물리 기반) / `Morph`(형태 전환).

이 12개 밖이면 `불명(용어집 외)`로 적는다. 형용사("부드럽게", "산뜻하게")로 대체하지 않는다.

---

## 3. 설치 명령과 함정

```bash
npx skills add Leonxlnx/taste-skill        -s design-taste-frontend -a claude-code -y --copy
npx skills add emilkowalski/skills         -s animate               -a claude-code -y --copy
npx skills add emilkowalski/skills         -s animation-vocabulary  -a claude-code -y --copy
```

함정 셋 — 전부 실제로 걸렸다:
1. **에이전트 ID는 `claude-code`다.** `claude`가 아니다.
2. **`-s`에 콤마로 여러 개를 주면 대화형 다중선택으로 빠진다.** 하나씩 실행할 것.
3. **비대화형 환경에서는 `< /dev/null`을 붙인다.** 안 그러면 프롬프트에서 멈춘다.

폴더명과 install name이 다를 수 있다(`taste-skill` 폴더 ↔ `design-taste-frontend` install name).
`-s` 값에는 **install name**을 쓴다.

---

## 4. 브라우저·래스터 도구가 없을 때

시각 확인은 원칙 3이라 포기 대상이 아니다. 아래 순서로 내려간다.

1. Playwright MCP / Claude in Chrome
2. **MCP가 없어도 `node_modules/playwright` + 브라우저 캐시가 살아있을 수 있다.**
   `ls node_modules/playwright` 와 `ls ~/Library/Caches/ms-playwright`(macOS) /
   `~/.cache/ms-playwright`(Linux)를 먼저 확인한다. 있으면 스크립트로 직접 띄운다.
   (주의: 스크립트는 `require('playwright')`가 해석되는 프로젝트 루트에서 실행할 것)
3. **산출물이 이미지인 것은 받아서 그대로 연다** — 생성 이미지·앱 아이콘은 `curl`로 받아 확인.
4. **SVG는 래스터해서 최종 표시 치수로 본다.**
   - `rsvg-convert -w 16 -h 16 icon.svg -o a.png` (librsvg)
   - 확대: `sips -z 320 320 a.png --out zoom.png` (**macOS 전용**) /
     `magick a.png -scale 320x320 zoom.png` (ImageMagick) /
     `python3 -c "from PIL import Image; ..."` (Pillow)
   - 셋 다 없으면 16px 원본을 그대로 열어본다. 작지만 형태 판정은 된다.
5. 전부 실패하면 **"시각 미확인"**으로 명시하고 사용자에게 확인을 요청한다. 수치로 대체하지 않는다.
