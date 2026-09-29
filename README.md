# ui-tells

**Reads the UI. Finds the tells. Won't fake a pass.**

A design skill for coding assistants — rules the agent follows, plus two checkers it runs.
It audits a frontend for the giveaways that say *"an AI designed this"*, then runs a full redesign
pipeline — reference research, design DNA, one committed direction, build, and visual verification.

The audit half is the part that matters: **it refuses to report a pass on files it could not read.**

```bash
$ ui-tells audit ./src            # a Vue project
== 0. scan target ==
  config      none (detected)
  code files  48
  style files 12
  dialects    css [detected]

  HIT  AI purple / default palette   4 occurrences
  HIT  transition: all               1 occurrence
  SKIP brand glow                    (TOKEN_BRAND not declared)

ran 8 / skipped 5 / HIT 2
partial scan. the 5 skipped checks were NOT verified — [list]
exit 4
```

Most linters print `0 issues` when they silently matched nothing. This one exits `3` and tells you
which globs it tried and which file extensions actually exist.

---

## What is a "tell"

A poker term: the unconscious signal that leaks through when someone is bluffing.

In UI, tells are what give away machine authorship. The skill ships **48 of them** across 7 axes —
color, typography, layout, components, content, motion, plus recurring field findings:

- Purple-to-blue gradient (`#6366f1` → `#a855f7`) on a hero background
- Every card is `rounded-2xl` + `shadow-lg` + `p-6` + `border border-gray-200`
- Paragraphs run the full viewport width (no `max-w`)
- Status colors (done / error / warning) borrowed for data that isn't a status
- A color chosen because it's pretty — **if you can't say why this color in one sentence, it fails**
- Avatars are Unsplash portraits

Machine-checkable tells go to `audit.sh`. The rest are judged from screenshots, because
saturation flatness, missing hierarchy, and "what is this motion for" don't survive a regex.

### Two checkers, different subjects

`audit.sh` reads **code**. `measure.mjs` measures the **rendered page**. Neither installs anything —
`measure.mjs` drives an already-installed Chrome over CDP using Node's built-in WebSocket, because
installing a new dependency is a stop-and-ask condition in the pipeline.

```bash
$ node measure.mjs contrast http://localhost:3000 --theme light,dark
  검사 24쌍 / 실패 2
  FAIL  4.48:1 (필요 4.5) 13px/400 rgb(99,113,125) on rgb(244,242,237)  "..."
```

That failure is the reason it exists: the ink token passed against the page background (4.79:1) and
failed against the recessed panel background (4.48:1). One token, two grounds — a static checker
cannot see the second one.

`overflow` is the same idea. It reports the element that **refuses to shrink**, not the wide one:

```
  뷰포트 390px / 넘침 200px / 원인 후보 3
  LEAK <div> w=574 right=590  lg:col-span-7
       → grid/flex 자식의 min-width:auto — 부모에 min-w-0 을 주면 해소될 수 있다
```

---

## Design principles it enforces

1. **Conviction** — one direction, with reasoning. Never a menu of options.
2. **System first** — count every consumer of a shared token before touching it.
3. **Eyes** — describe the screenshot in words *before* measuring. 17:1 contrast does not mean it looks good.
4. **Translation** — reproduce the *effect* of a reference, not its elements.

---

## The audit

### Rules are selected by dialect, not by file extension

Tailwind utilities live in `.vue` and `.html` too. CSS declarations live inside `<style>` blocks.
Keying rules to `.tsx` misses entire stacks — so the runner detects how styling is *expressed*.

| pack | covers | reaches |
|---|---|---|
| `core` | values — hex, font names, easing curves | every stack |
| `css` | CSS declaration syntax | **Vue · Svelte · Astro · plain HTML, for free** |
| `tailwind` | utility classes | anywhere they appear |
| `react` | JSX syntax | `.tsx` / `.jsx` |
| `locale.ko` | Korean typography | Korean products only |

`css` is where portability actually comes from: stacks without Tailwind put their design decisions
in `<style>` blocks, and that pack reads them.

**Checks count intent, not one syntax.** Letter-spacing tuned in a base stylesheet, vertical rhythm
built from `mt-*` instead of `py-*`, `tabular-nums` set once on `body`, dark mode driven by
`[data-theme]` instead of `dark:` — all of these used to read as "not done" because the check only
looked for the Tailwind spelling. A check that knows one spelling measures stack preference, not
quality. `tests/fixtures/css-first/` pins that (L23).

### Four grades, and `SKIP` is the important one

| grade | meaning |
|---|---|
| `HIT` | violation found |
| `ok` | check **ran** and was clean |
| `확인` / review | ran, needs a human call |
| `SKIP` | **could not run** — empty corpus or undeclared config. Never a pass |

`"machine checks passed"` prints only when `SKIPPED == 0 && HITS == 0`.

| exit | meaning |
|---|---|
| 0 | all checks ran, no hits |
| 1 | hits present |
| 2 | usage error |
| 3 | **cannot scan** — 0 files, unknown stack, or broken install |
| 4 | partial — some checks skipped, and they are listed |

---

## Configuration

Optional. Without it the runner guesses and prints `[detected]`. With it, checks that depend on
project facts stop being skipped.

```sh
# <project>/.design/audit.conf
DIALECTS="tailwind css jsx locale.ko"
TOKEN_BRAND="--accent"
TOKEN_STATUS="status-"
THEME_STRATEGY="class"          # custom-variant | class | media

# Suppressions require a reason. Silent regex edits are not a suppression mechanism.
IGNORE_HEX="FEE500|03C75A|4285F4"
IGNORE_HEX_REASON="OAuth provider brand colors — must not follow the theme"
```

Project-specific checks go in `.design/rules.local.sh` — no need to fork the skill.

---

## Tool support

| tool | status |
|---|---|
| **Claude Code** | verified |
| **Kiro** | adapter planned — format confirmed, not yet run |
| **Cursor** | planned |
| **Codex** | planned |

The pipeline body and the audit are tool-agnostic (markdown + bash/awk, zero dependencies).
Only the frontmatter and install path differ per tool, so support is an adapter, not a rewrite.

**This table only lists what has actually been run.** Claiming otherwise would be the same failure
the audit exists to prevent.

---

## Install

```bash
npx skills add byunggwan-kim0918/ui-tells -s ui-tells -a claude-code -y --copy
```

Then invoke it:

```
@ui-tells redesign      # existing product
@ui-tells new           # from scratch
```

With no argument it decides the mode from the codebase — routes and tokens present means redesign.

### Optional downstream skills

It delegates code generation and motion when these are installed, and **does the work itself when
they are not**. Missing dependencies degrade the output; they never stop the run.

- [`Leonxlnx/taste-skill`](https://github.com/Leonxlnx/taste-skill) — code generation
- [`emilkowalski/skills`](https://github.com/emilkowalski/skills) — motion (`animate`, `animation-vocabulary`)

---

## Repository layout

```
skills/ui-tells/          ← what gets installed
├── SKILL.md              pipeline — §0 mode → brief → inventory → research → DNA → decide → build → verify
├── ai-tells.md           48 visual tells, 7 axes
├── typography.md         type selection, scale, CJK handling
├── greenfield.md         what §2/§3/§8 become with no existing code
├── handoff.md            downstream anchors, fallback ladders, install pitfalls
├── lessons.md            L1–L23 — the failures each rule came from
├── audit.sh              static checker: preflight, 5 rule sets, dialect detection,
│                         comment stripper, and `--handoff` for downstream seams
└── measure.mjs           runtime checker: drives real Chrome over CDP, zero deps
                          contrast · overflow · census · fonts · motion · recon · shot · icon

tests/                    ← repo maintenance, not shipped to users
├── run-fixtures.sh       24 fixtures: Tailwind · CSS · Vue · Svelte · HTML · CSS-first
├── triggers.md           trigger matrix, dry-run checklist
└── fixtures/
```

Run the regression suite:

```bash
bash tests/run-fixtures.sh   # PASS 24 / FAIL 0
```

Negative fixtures exist because three false positives were shipped and caught in production use
(`Inter` matching `interface`, button padding counted as section rhythm, a rule-describing comment
matching its own rule). If those fixtures break, a fix was reverted.

---

## Rules in Korean

The rule documents are written in Korean. The agent reads them fine in any locale, and the audit
output is Korean. If that blocks you, open an issue — English rules are feasible, just not done yet.

---

## Why the rules look oddly specific

Because they are. `lessons.md` records the 20 failures each rule came from:

- A logo was signed off as "renders correctly" — at 16px it was a white smudge
- Contrast passed at both endpoints; the gradient between them turned khaki
- 9 of 10 records were in one state, so a status color became the de-facto brand color
- A type scale was reported as normalized after counting only one of two notations

None of these are reachable by reasoning about design. They came from being wrong.

---

## License

MIT
