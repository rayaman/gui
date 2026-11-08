# Grid Layout

Opt-in CSS-Grid-style container/item layout for the retained element tree —
a scoped implementation of the [CSS-Tricks complete-guide](https://css-tricks.com/snippets/css/complete-guide-grid/)
subset, running as a second root mode inside the flexbox scheduler.
This is the user guide; the grid design-plan file has been removed from the
repo, so design rationale lives here and in the
[`core/grid.lua`](../core/grid.lua) source headers.

**Opt-in and additive:** nothing happens until you call `setGrid` on an
element. Subtrees without grid keys are untouched — grid containers register
into the same weak root registry the flex pass already walks, and grid roots
count in the same `stats` / dirty-gate machinery
([Flexbox Layout §7](flexbox.md#7-dirty-flags-scheduling--stats)).

Engine: [`gui/core/grid.lua`](../core/grid.lua) (~1350 lines: parsers,
placement engine, track sizing, alignment) + the shared scheduler in
[`gui/core/flexbox.lua`](../core/flexbox.lua) (roots, seeding, write-back,
events — single-sourced, see §7). `flexbox.init` installs
`gui.setGrid`/`gui.setGridPlacement` at the same late-injection point as
`setFlex`/`setSizing`; it lazy-requires `core/grid.lua` (pcall + nil-guard),
so **deleting `core/grid.lua` disables grid while flex keeps working** —
`__grid` elements simply stay inert (mirrors the "removing `flexbox.lua`
disables the feature" property in [flexbox.md](flexbox.md)).

A container may be flex *or* grid, never both: `setGrid` on a `__flex`
element errors ("setFlex(false) first") and vice versa.

---

## Table of Contents

1. [Quick start](#1-quick-start)
2. [`setGrid` — container config](#2-setgrid--container-config)
3. [Track grammar (`columns` / `rows`)](#3-track-grammar-columns--rows)
4. [`setGridPlacement` — item placement](#4-setgridplacement--item-placement)
5. [Alignment](#5-alignment)
6. [Item sizing — interplay with `setSizing`](#6-item-sizing--interplay-with-setsizing)
7. [Cross-mode nesting & the shared scheduler](#7-cross-mode-nesting--the-shared-scheduler)
8. [YAML keys](#8-yaml-keys)
9. [Running the demo / autotest](#9-running-the-demo--autotest)
10. [Limitations vs CSS](#10-limitations-vs-css)

---

## 1. Quick start

```lua
local frame = gui:newFrame(20, 20, 300, 100, 0, 0, 0, 0)
frame:setGrid{ columns = "1fr 1fr", rows = "40px 40px", gap = 10 }

frame:newFrame(0, 0, 0, 0, 0, 0, 0, 0)   -- auto-placed: (row 1, col 1)
frame:newFrame(0, 0, 0, 0, 0, 0, 0, 0)   -- auto-placed: (row 1, col 2)
local c3 = frame:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
c3:setGridPlacement{ column = 2, row = 2 }  -- explicit line pair
frame:newFrame(0, 0, 0, 0, 0, 0, 0, 0)   -- auto-placed: (row 2, col 1)
```

Children with no placement are auto-placed along the flow axis (default
`autoFlow = "row"`); items without `setSizing` **stretch to fill their grid
area** (§6). Like flex, the pass runs automatically at the top of the draw
loop and rewrites children's `dualDim`, so the normal draw resolver
reproduces the computed pixels exactly (`getAbsolutes() == __flexComputed`,
verified to 1e-9 every frame by the demo's `verify.lua`).

A grid container is a **root** unless its parent is itself grid: a `__grid`
element whose parent is not grid lays out its own children as a top-level
root of the shared scheduler; a `__grid` element inside a `__grid` parent is
descended recursively inside the parent's pass (§7).

## 2. `setGrid` — container config

```lua
elem:setGrid{
    columns = "1fr 200px repeat(2, minmax(100px, 1fr)) auto",  -- string grammar
              -- or Lua array form: { "1fr", "200px", "repeat(2, minmax(auto, 1fr))", "auto" }
    rows    = ...,                       -- same grammar as columns
    areas   = { "header header",         -- array of row strings; name tokens are
              "side main" },             -- identifier-ish; "." = empty cell
    gap     = 8,                         -- number, or { row = 8, column = 12 } (clamped >= 0)
    autoFlow = "row" | "column",         -- default "row"
    dense  = true,                       -- boolean, default false
    justifyItems / alignItems     = "start"|"end"|"center"|"stretch",  -- default "stretch"
    justifyContent / alignContent = "start"|"end"|"center"|
                                    "space-between"|"space-around"|"space-evenly",  -- default "start"
    placeItems / placeContent / placeSelf = "v h",  -- shorthand, see §5
}
elem:setGrid(false)   -- remove grid config (same contract as setFlex(false))
```

Everything is parsed **once**, at `setGrid` time, and cached on the element
(never re-parsed per frame). Invalid keys/values raise a Lua error naming the
element — configuration mistakes are loud, not silent (same style as
`setFlex`). `setGrid` also installs the root's own
`OnSizeChanged`/`OnPositionChanged` dirty-marking connections, mirroring
`setFlex` ([flexbox §7](flexbox.md#7-dirty-flags-scheduling--stats)).

There is **no `padding` key** in the grid model (unlike `setFlex`): the
content box equals the container box. Unrecognized keys are rejected as
unknown options.

`areas` defines the explicit grid extent: the row strings set the implicit
row count and the widest row the column count, even when `rows`/`columns`
name fewer tracks. Area names match `[%a_][%a%d_%-]*`; every row must have
the same cell count; `"."` is an empty cell. A repeated name is merged into
one rectangular area (its bounding cells).

## 3. Track grammar (`columns` / `rows`)

Both axes accept a whitespace-separated track list (string) or an array of
strings (each entry tokenized the same way). Tokens, exactly as accepted by
[`parseTrackList`, core/grid.lua:181](../core/grid.lua:181):

| Token | Meaning |
|---|---|
| `200px` | fixed track |
| `200` (bare number) | fixed pixels — shorthand for `200px` |
| `1fr` / `2.5fr` | flexible track: share of the free space left after fixed/auto tracks and gaps |
| `auto` | sized to the max-content contribution of the items in that track |
| `min-content` | sized to the widest single word of the items in that track |
| `minmax(A, B)` | lower bound `A` ∈ `px`/`auto`/`min-content`, upper bound `B` ∈ `px`/`fr`/`auto`/`min-content` (`A` may not be `fr`) |
| `repeat(3, 100px auto)` | expands at parse time to `100px auto 100px auto 100px auto`; the count must be a positive integer; **nested `repeat()` is rejected** |

Parentheses inside `minmax(...)`/`repeat(...)` are protected during the
whitespace split, so `"repeat(2, minmax(100px, 1fr))"` survives as one
token. Unbalanced parentheses, malformed `minmax()`/`repeat()` (not exactly
two comma-separated arguments), a non-integer `repeat` count, and unknown
tokens all error naming the element and the offending token.

`fr` distribution: free space = container size along the axis − Σ non-fr
track bases − Σ gaps; each `fr` track gets `max(its lower bound, free × f ÷
Σfr)`. A `minmax` whose **max** is `fr` participates with that weight, its
lower bound counted as a non-fr track. Free space below zero collapses `fr`
tracks to their lower bound (see §10).

## 4. `setGridPlacement` — item placement

```lua
child:setGridPlacement{
    column = "1 / 3"          -- start line / end line (end-exclusive, like CSS)
              | "span 2"      -- auto position, extent 2
              | "2"           -- bare line number (also plain number 2)
              | "-1 / -1"     -- negative lines: resolved against the FINAL
                              -- track count incl. implicit tracks (-1 = last line)
              | "areaName"    -- resolves through the container's `areas`
              | "areaA / areaB",
    row    = ...,             -- same grammar, row axis
    justifySelf / alignSelf = "start"|"end"|"center"|"stretch",  -- override *-items (§5)
    placeSelf = "v h",        -- shorthand: align then justify (§5)
}
child:setGridPlacement(false)  -- back to auto-placement (also clears a §5 escape float)
```

Grammar rules ([`parsePlacement`, core/grid.lua:319](../core/grid.lua:319)):
at most one `/`; each side is a non-zero signed integer line, a `span <n>`
(positive integer, only standalone or after `/`), or an area name. An area
name with no explicit end/span spans the whole area. Start > end is
normalized (swapped), like CSS. Bare numeric lines may also be Lua numbers —
the YAML builder's `coerceNumericStrings` turns `column: 2` into the number
`2`, which this grammar accepts.

Placement phases, in order: explicit positive-line/area/span placements →
implicit tracks created at the far end from those → negative-line resolution
against the extent built so far → auto-placement cursor honoring `autoFlow`
(`row` or `column`), with `dense = true` rewinding the cursor to the first
fitting gap for each auto item. Items placed outside the explicit template
create implicit **auto-sized** tracks. A bare `span`/line on one axis leaves
the other axis auto (that axis advances its own cursor).

`setGridPlacement(false)` returns the item to auto-placement *and* clears an
escape-hatch float (§7): an explicit request to (re)join placement overrides
the manual-geometry escape (mirrors `setSizing{...}` re-enabling management
in flex).

## 5. Alignment

Two levels, CSS cascade semantics:

- **Container defaults** — `justifyItems`/`alignItems`
  (`start|end|center|stretch`, default `stretch`) position every item inside
  its grid area; `justifyContent`/`alignContent`
  (`start|end|center|space-between|space-around|space-evenly`, default
  `start`) offset the whole track group inside the container. With no free
  space (overflow) all content-alignment offsets are zero.
- **Per-item overrides** — `justifySelf`/`alignSelf` on
  `setGridPlacement` beat the container's `*-items` values.

Shorthands take `"v h"` — **vertical (align) first, then horizontal
(justify)**; a single value applies to both. `placeItems` →
`alignItems`/`justifyItems`; `placeContent` →
`alignContent`/`justifyContent`; `placeSelf` (per item, and also accepted at
container level as a default for all items) → `alignSelf`/`justifySelf`. A
shorthand in the same table wins over longhands listed with it (applied
after, like a later CSS declaration).

Alignment only positions items that are *smaller* than their area — see §6:
an unstretched item (a `fit` one, §6) is placed per `justify-self`/`align-self`;
`stretch` on a fit-sized item behaves as `start`.

## 6. Item sizing — interplay with `setSizing`

Grid items reuse the existing [`setSizing`](flexbox.md#3-setsizing--child-sizing)
primitive unchanged — no new sizing API. The default, however, is the **CSS
default, not the flex port's**:

| Item `setSizing` | Result along one axis |
|---|---|
| *(no `setSizing` at all)* | **stretch to fill the grid area** (CSS default) — unlike flex, where the default axis spec is `fit` |
| `fit` | natural size (measured text / image dims / `grid.intrinsic` for a nested grid), positioned per `justify-self`/`align-self` with `*-items` fallback |
| `grow` | fills the area (same as stretch) |
| `{mode="percent", value=0.5}` | fraction of the grid area |
| `{mode="fixed", value=120}` / bare `120` | the authored value |
| `min=` / `max=` on any spec | px clamp bounds, applied after the mode math |

`aspectRatio` is honored after both axes are computed (skipped for text,
same rule as flex), and `square = "w"/"h"` items are baked so the resolver's
square re-application is a no-op — the write-back invariant holds either way.

Text items measure twice: after the column widths are final, wrapped heights
are re-measured at the item's final width and auto/implicit **rows** re-solve
from them (the Pass-B analogue, [flexbox §4](flexbox.md#4-measured-text-fit-content)).
Auto **columns** keep their max-content seed — no column-axis wrap re-solve
(§10).

## 7. Cross-mode nesting & the shared scheduler

Grid is not a second engine — it is a second **root mode** inside the flex
scheduler. What that means
for you:

- **Roots:** `isFlexRoot` was generalized — a `__grid` element whose parent
  is not `__grid` (or which is floating) is its own top-level root. So a grid
  container inside a flex container, and a flex container inside a grid
  container, are each independent roots laid out in depth order in the same
  pass (demo `8a`/`8b`).
- **grid-in-grid:** a `__grid` child of a `__grid` parent is *not* a separate
  root — the parent's pass descends it recursively after its own write-back,
  seeding from the box just placed (demo `8c`).
- **Cross-mode intrinsic size:** a `__grid` child of a `__flex` parent seeds
  its `fit` size from `grid.intrinsic` — the grid's computed track sums
  (template + gaps + auto contributions) — and feeds the flex `fit` sums
  through the same source, so the two can never disagree. The feedback loop
  converges one frame late (documented, §10).
- **Shared bookkeeping:** the escape hatch (`__flexEscaped` — any manual
  `setDualDim`/`move`/`size` floats a grid item out of placement, siblings
  close ranks), dirty marking, re-entrancy guards, delta-gated
  `OnSizeChanged`/`OnPositionChanged`, and the write-back math are the *same
  single implementation* flex uses ([`writeBack`/`fireGeometryEvents`,
  core/flexbox.lua:600](../core/flexbox.lua:600)).
- **Scroll containers:** `flexbox.sizeManaged(root, true)` works on a grid
  root exactly as on a flex root — a `fit`-height scroll content frame becomes
  Σ rows + gaps, `maxScrollY` derives from it, and scroll position writes
  never escape the root (demo `scroll fit`, same contract as
  [flexbox §9](flexbox.md#9-scroll-containers-fit-content)).
- **Virtual tree / parked subtrees, idle gate, stats:** identical — grid
  roots count in `passes`/`visited`/`rootsScanned`, and a quiet frame visits
  0 elements.

## 8. YAML keys

`yaml/builder.lua` accepts `grid:` and `grid-placement:` on any element
definition, beside `flex:`/`sizing:`
([`applyShared`, yaml/builder.lua:198](../yaml/builder.lua:198)) — additive,
definitions without them behave exactly as before:

```yaml
type: frame
x: 340
y: 1040
w: 300
h: 100
grid: { columns: "1fr 1fr", rows: "40px 40px", gap: 10 }   # true == {} (all defaults)
children:
  - type: frame
  - type: frame
  - type: frame
    grid-placement: { column: 2, row: 2 }   # bare numeric line, coerced to number 2
  - type: frame
```

CSS grammar strings pass through verbatim (`"1fr"`, `"span 2"`, `"1 / 3"`
are untouched by the builder's numeric coercion; see
[yaml-declarative-ui.md §3 "Grid layout"](yaml-declarative-ui.md#3-shared--type-specific-properties)
and [yaml-based-elements.yaml](yaml-based-elements.yaml)). Validation errors
are the same loud `setGrid`/`setGridPlacement` errors naming the element.

## 9. Running the demo / autotest

```
love examples/grid-demo                 # interactive window: labeled scenarios + debug overlays
love examples/grid-demo --grid-autotest # runs 79 assertions, prints summary, exits 0 on pass
love examples/grid-demo --grid-headless # no window; layout + checks only
```

In the window: `R` rebuilds all scenarios, `Esc` quits. Cyan overlay rects
are `__flexComputed`; amber marks escaped items. The status line prints
`checks / invariantFails / passes / visited / frame`.

Scenario names referenced in this guide map to the demo's labeled blocks
(hand-computed expected rects): `1` fr tracks + gap
(`columns = "1fr 2fr 100px"`), `2` areas / `span 2` / explicit `"2"` lines /
negative `"-1 / -2"`, `3`/`3b` auto-flow row overflow + `autoFlow = "column"`
implicit columns, `4`/`4b` `dense = true` fills the hole vs the non-dense
twin, `5`/`5b` `minmax(50px, 1fr)` + `auto` text track + fr collapse on
overflow, `6` `justifyContent = "space-between"` / `alignItems = "center"` /
`justifySelf = "end"` / `placeSelf = "center end"` / stretch default, `7`
YAML twin ≡ imperative twin, `8a`/`8b`/`8c` cross-mode nesting, `9` escape
hatch + `setGridPlacement(false)` rejoin, `wrap` auto row grows to the
wrapped text height, `scroll fit` size-managed grid scroll content.

The write-back invariant (`getAbsolutes() == __flexComputed` to 1e-9 for
every managed element, flex *and* grid roots) is checked **every draw frame**
via [`examples/grid-demo/verify.lua`](../examples/grid-demo/verify.lua)
(delegates to `flexbox.debugVerifySubtree`) — not an opt-in. Autotest exit
code is 0 only when `failed == 0 and invariantFails == 0`. The flex-demo
autotest runs unedited alongside as the existing-behavior regression proof.

## 10. Limitations vs CSS

Honest list (port non-goals + the deviations documented in the
[`layoutGridRoot` header, core/grid.lua:596-623](../core/grid.lua:596)):

- **No subgrid** — planned non-goal.
- **No standalone named grid lines** — only *area-derived* names:
  `grid-template-areas` names resolve to the area's start/end lines in
  `setGridPlacement`; `[header-start]`-style line naming is not accepted.
- **No masonry** — not implemented.
- **Spanning items use uniform excess top-up** — multi-track-spanning items
  do not participate in CSS's iterative base-size growth: if their combined
  contribution exceeds the tracks they span, the excess is distributed
  *uniformly* across the spanned auto/minmax-family tracks (spans over
  fr-only tracks grow nothing). `minmax(min-content, …)` lower bounds are
  therefore approximate in span-heavy grids.
- **Negative-start lines never push front implicit tracks** — negative lines
  resolve against the explicit grid plus implicit tracks already created at
  the end; they do not grow the grid at the *front*.
- **`fr` collapses to its lower bound on overflow** — when free space goes
  negative, `fr` tracks shrink to `0` (or the `minmax` min) and items
  overflow; CSS floors `fr` at its content base instead.
- **`minmax` content uppers are growth limits** — `minmax(A, auto|min-content)`
  caps at the max-content (widest-word) contribution; `minmax(A, px)` is a
  hard clamp. No beyond-base content resolution.
- **No column-axis wrap re-solve** — after text wrap, auto/implicit **rows**
  re-solve but auto **columns** keep their max-content seed
  (`autoFlow = "column"` included).
- **`grid.intrinsic` is template-only on the first frame for implicit
  grids** — a grid relying on implicit tracks beyond its template reports
  its template-only size to a `fit` flex parent on frame 1 and converges the
  next frame, once the root's own pass has cached the real track sums (same
  documented one-frame-late class as the flex seed/propagation contract).
- **Cross-mode `fit` feedback converges one frame late** — when a grid
  root's track sums change, fit-sized flex ancestors are re-dirtied and
  settle on the following frame; self-limiting (sums only move while the
  layout is still moving).
- **Flex children do not feed size back into auto grid tracks** — a `__flex`
  child inside a grid contributes its seeded size, not its live laid-out
  size; the grid refreshes when dirtied through the shared `markDirty` seam.
- **Nesting is supported in both shapes** — grid-in-flex and flex-in-grid
  ride the independent-roots seam (depth-ordered in one pass); grid-in-grid
  is descended recursively inside the parent grid's pass.
