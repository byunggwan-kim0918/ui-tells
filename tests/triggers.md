# design-reference · 테스트 픽스처

SKILL.md를 고칠 때마다 **빠른 루프**(A·B)를, 파이프라인/외부 skill을 바꿨을 때 **마일스톤 루프**(C·D)를 돌린다.
판정은 사람이 표를 보고 재현하거나, Claude에게 "이 프롬프트에 design-reference가 로드되나?"로 물어 확인한다.

_마지막 검증: 2026-09-21 · SKILL.md v4(영문 트리거 추가) · audit.sh v2(preflight·SKIP·exit code) · taste-skill(design-taste-frontend) / emil skills 11개 기준_

---

## A. 트리거 매트릭스 (빠른 루프)

| # | 프롬프트 | 기대 | 근거 |
|---|---|---|---|
| 1 | "레퍼런스 찾아서 랜딩 만들어줘" | ✅ 로드 | 레퍼런스 + 제작 요청 |
| 2 | "Awwwards 스타일로" | ✅ 로드 | description 트리거 예시. ⚠ taste-skill의 vibe word이기도 함(아래 B-2) |
| 3 | "이 사이트 느낌으로 만들어줘" | ✅ 로드 | description 트리거 예시 |
| 4 | "디자인 레퍼런스 찾아줘" | ✅ 로드 | description 트리거 예시 |
| 5 | "화면 만들어줘" | ❌ 안 로드 | 레퍼런스 신호 없음 → taste-skill 단독 |
| 6 | "이 애니메이션 개선해줘" | ❌ 안 로드 | → improve-animations / review-animations |
| 7 | "redesign this app" | ✅ 로드 | description 영문 트리거 (2026-09-21 추가) |
| 8 | "make the design less AI-looking" | ✅ 로드 | description 영문 트리거 |
| 9 | "make it look like linear.app" | ✅ 로드 | description 영문 트리거(`make it look like <site>`) |
| 10 | "modernize the UI" | ✅ 로드 | description 영문 트리거 |
| 11 | "build a login screen" | ❌ 안 로드 | 레퍼런스·리디자인 신호 없음 → taste-skill 단독. #5의 영문 대응 |
| 12 | "improve the animations here" | ❌ 안 로드 | → improve-animations. #6의 영문 대응. 영문 추가가 이 절연을 깨지 않는지가 핵심 |

**경계 케이스 (감시 대상, 현재는 규칙 추가 안 함):**
- "이 사이트처럼 애니메이션 넣어줘" — 레퍼런스(✅축) + 애니메이션(emil `animate`축)이 **둘 다** 걸릴 수 있음.
  현 description은 "기존 애니메이션 개선·리뷰"만 배제하고 "레퍼런스 기반 신규 모션"은 배제 안 함 → 의도된 회색지대.
  design-reference가 레퍼런스를 먼저 수집하고 `animate`로 넘기는 게 맞는 흐름이므로 방치한다.
  오발이 실제로 관찰되면 그때 description에 경계 문구를 넣는다. (description 부풀리기 방지)

## B. 충돌 검사 (빠른 루프) — emil 11개 대비

- **animate / animate-expo** — "animate/모션 넣어줘"에 트리거. 우리는 "레퍼런스 기반 제작"이라 신호가 다름. 겹치는 지점은 위 경계 케이스뿐.
- **find-animation-opportunities / improve-animations / review-animations** — "기존 코드의 모션"이 대상. 우리 description이 "기존 애니메이션 개선·리뷰 요청에는 쓰지 않는다"로 이미 절연. ✅
- **apple-design** — "Apple-style / 제스처 UI"에 트리거. 미학 이름이지 레퍼런스 수집이 아님. 겹침 없음.
- **animation-vocabulary** — "이거 뭐라고 불러?" 명명 질문. 우리는 명명이 아니라 수집. 겹침 없음. (우리는 이 용어집을 *출력 형식*으로만 참조)
- **ask-sonner(토스트) / write-swift(Swift) / pick-ui-library / prototype** — 도메인 orthogonal. 겹침 없음.
- **B-2 주의**: "Awwwards"는 taste-skill의 vibe word 목록에도 있어 taste-skill도 반응할 수 있다. 이건 **의도된 중복** —
  design-reference가 앞단에서 레퍼런스를 수집·검증한 뒤 taste-skill로 넘기는 구조이므로, 둘 다 뜨면 design-reference가 주도한다.

## C. 출력 드라이런 체크리스트 (마일스톤 루프)

canonical 요청 예: **"<도메인> 서비스 랜딩, Awwwards 감성으로 레퍼런스 찾아서 만들어줘"**
신규 경로 확인용: **"@design-reference 신규 디자인"** (§0 모드 판정 → greenfield.md 진입)

_2026-09-10 개정: 확인 게이트를 제거하고 자율 실행 → 화면 제시로 바꿨다. 아래는 그 기준._

- [ ] (i)~(v) 프로젝트 판정을 **파일 경로 근거와 함께** 출력한다
- [ ] (iii)이 대시보드/제품 UI면 **레이아웃 발명 대신 위계·밀도·상태 커버리지로** 방향이 갈린다
      (중단하지 않는다 — 예전 체크리스트엔 "중단 게이트"로 적혀 있었으나 SKILL.md와 모순이었다)
- [ ] 레퍼런스 2개(주축+보완축), 스테이징/템플릿 도메인은 제외
- [ ] DNA 7항목 전부, 각 항목에 **근거 등급** 태그. DNA는 내부 작업물로만 쓴다
- [ ] 모션은 animation-vocabulary 어휘로만 (형용사 금지), 확인 못 하면 "불명"
- [ ] WebFetch 구체값은 교차 일치 시만 `[교차확인]`, 모순 시 "미확인" 강등
- [ ] 다이얼 근거에 (ii)+(v) 반영, taste-skill 프리셋 표 대비 보정치
- [ ] **중간에 멈춰 묻지 않는다.** §9 중단 2조건(브랜드 아이덴티티 *교체* · 새 의존성/되돌리기 어려운 변경) 외에는 기본값으로 진행
- [ ] 후단 미설치여도 **멈추지 않고** 직접 수행하며, 제시에 "후단 미설치" 한 줄을 남긴다
- [ ] taste-skill → (모션 있으면) emil 까지 **위임이 실제로 일어난다**
- [ ] **렌더 후 AI Tell 자가검사**를 하고, 걸리면 묻지 않고 고쳐 다시 렌더한다
- [ ] 라이트·다크·모바일(390px) 확인, 가로 스크롤 없음
- [ ] **화면(스크린샷)과 before/after 실측값을 제시하며 끝난다**

**디자이너 4원칙 검증 (v3):**
- [ ] 확신 — 취향 판단에 `AskUserQuestion`을 쓰지 않았다. 방향을 하나만 제시했다
- [ ] 시스템 — 공유 토큰/컴포넌트를 건드렸으면 소비처를 `grep`으로 세고 영향 화면 목록을 먼저 만들었다. 변경 후 전부 렌더했다
- [ ] 눈 — 스크린샷을 **말로 묘사한 뒤** 수치를 냈다. 스크린샷 실패 시 "시각 미확인"으로 명시했다(수치로 대체 안 함)
- [ ] 번역 — DNA 시그니처마다 "왜 작동하는가" 한 줄이 있고, 결정에서 요소가 아니라 효과를 가져왔다
- [ ] `design-dna.md` 저장

## D. 이음새 계약 assertion (마일스톤 루프) — 외부 레포가 바뀌면 시끄럽게 깨지도록

**이 절은 `audit.sh --handoff`로 자동화됐다.** 손으로 grep하지 말고 그걸 돌린다:

```
bash audit.sh --handoff          # 설치 위치 자동 탐색
bash audit.sh --handoff <스킬디렉터리>
```

앵커 문자열 목록과 "앵커가 없을 때"의 폴백은 [handoff.md](../skills/ui-tells/handoff.md) §1 표에 있다.
절 번호는 그 표 밖에 존재하지 않는다 — 후단이 절을 재배치해도 깨지지 않게 하려는 것이 요지다.

판정:
- **PASS** — 그대로 위임
- **미설치** — 실패가 아니다. handoff.md §2의 "직접 수행" 사다리로 내려간다(exit 0)
- **FAIL** — 설치돼 있는데 앵커가 사라진 것. **우리 SKILL.md를 고친다**(후단 파일 수정 금지)

§8 제작에서 **첫 위임 직전에** 호출한다. 밀리초면 끝난다 —
예전엔 수동 마일스톤 루프에서만 확인해서, 이음새가 깨져도 한참 뒤에야 드러났다.


---

## E. 규칙팩 회귀

`bash tests/run-fixtures.sh` — 양성 픽스처는 기대한 HIT가, 음성 픽스처는 HIT 0건이 나와야 한다.
음성 쪽이 존재 이유다: 과거에 실제로 오탐을 냈던 케이스(`Inter`↔`interface`,
섹션 리듬↔버튼 패딩, 규칙을 설명한 주석이 자기 규칙에 걸림)를 고정해 둔다.
**규칙을 고치다 음성이 깨지면 예전에 잡은 오탐을 되살린 것이다.**

스택별 양성: tailwind+react / 순수 CSS / Vue(style 블록) / Svelte / 순수 HTML.
그리고 "읽을 파일 0개 → exit 3" — 스캔 불가는 통과가 아니다.

## F. 후단 이음새

`bash audit.sh --handoff` — 앵커 문자열이 후단 SKILL.md에 그대로 있는지 확인한다.
미설치는 실패가 아니라 "직접 수행 모드"다(exit 0).
FAIL이면 **우리 쪽을 고친다** — 폴백은 [handoff.md](../skills/ui-tells/handoff.md) §1 표의 오른쪽 열.

---

_드리프트 로그(프로젝트별 관찰 기록)는 이제 각 프로젝트의 `.design/drift-log.md`에 쌓인다._
_스킬 디렉터리는 읽기 전용으로 취급한다 — 공유 설치본에서 여러 프로젝트 로그가 섞이지 않도록._
