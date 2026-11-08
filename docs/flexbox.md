# Flexbox Layout

Opt-in flex layout for the retained element tree — a scoped port of
[Clay v0.14](../reference/clay/clay.h)'s auto-layout engine, adapted to
`gui`'s dual-dimension system. The design document is
[`docs/flexbox-integration-plan.md`](flexbox-integration-plan.md); this is the
user guide.

**Opt-in and additive:** nothing happens until you call `setFlex` on an
element. Subtrees without flex keys are byte-identical to before — the layout
pass visits only elements reachable from `__flex` containers.

Engine: [`gui/core/flexbox.lua`](../core/flexbox.lua) (~1160 lines) +
[`gui/core/measure.lua`](../core/measure.lua) (cached text measurement).
Hooks into [`init.lua`](../init.lua) are six nil-guarded call sites; removing
`core/flexbox.lua` disables the feature without breaking anything.

---

## Table of Contents

1. [Quick start](#1-quick-start)
2. [`setFlex` — container config](#2-setflex--container-config)
3. [`setSizing` — child sizing](#3-setsizing--child-sizing)
4. [Measured text (fit-content)](#4-measured-text-fit-content)
5. [Escape hatch & floating children](#5-escape-hatch--floating-children)
6. [Interaction with existing layout features](#6-interaction-with-existing-layout-features)
7. [Dirty flags, scheduling & stats](#7-dirty-flags-scheduling--stats)
8. [Virtual tree / parked subtrees](#8-virtual-tree--parked-subtrees)
9. [Scroll containers (fit-content)](#9-scroll-containers-fit-content)
10. [YAML keys](#10-yaml-keys)
11. [Running the demo / autotest](#11-running-the-demo--autotest)
12. [Limitations vs Clay](#12-limitations-vs-clay)

---

## 1. Quick start

```lua
local container = gui:newFrame(20, 20, 400, 100, 0, 0, 0, 0)
container:setFlex{ direction = "row", gap = 8, padding = 12, alignY = "center" }

local a = container:newFrame()              -- no dualDim needed
a:setSizing{ width = 100, height = "grow" } -- fixed 100px wide, full height
local b = container:newFrame()
b:setSizing{ width = "percent", height = "grow" } -- percent needs a value:
b:setSizing{ width = { mode = "percent", value = 0.5 }, height = "grow" }
local c = container:newFrame()
c:setSizing{ width = "grow" }               -- takes the remaining space
```

The pass runs automatically at the top of the draw loop
([`init.lua:2418-2422`](../init.lua:2418)); children's `dualDim` is rewritten
so the normal parent-first draw resolver reproduces the computed pixels
exactly (`getAbsolutes() == __flexComputed`, verified to 1e-9 by the demo's
`verify.lua` every frame).

A flex container is a **root** unless its parent is itself flex: a
`__flex` element whose parent is not flex lays out its own children; a
`__flex` element inside a flex parent is both a child (sized by the parent's
pass) and a container (its own children lay out in the same pass).

## 2. `setFlex` — container config

```lua
elem:setFlex{
    direction = "row" | "column",   -- default "row"
    gap       = 8,                  -- px between children (clamped >= 0)
    padding   = 12,                 -- number, or {l=,r=,t=,b=} (also left/right/top/bottom)
    alignX    = "start"|"center"|"end",  -- default "start"
    alignY    = "start"|"center"|"end",  -- default "start"
}
elem:setFlex(false)   -- remove flex config (children return to raw dualDim)
```

`alignX/alignY` align the *line* of children inside the content box. On-axis
(`alignX` on a row) leads with a fixed offset; off-axis pushes each child
without stretching it (a child wanting the full cross axis uses
`setSizing{ height = "grow" }`). Invalid keys/values raise a Lua error naming
the element — configuration mistakes are loud, not silent.

## 3. `setSizing` — child sizing

```lua
child:setSizing{
    width  = <axis spec>,
    height = <axis spec>,
    aspectRatio = 2,      -- optional: w = h * ratio (or h = w / ratio)
}
child:setSizing(false)    -- permanent escape: child becomes floating (§5)
```

An axis spec is one of:

| Spec | Meaning |
|---|---|
| `"fit"` (default) | hug content: measured text width/lines, children sums, or 0 |
| `"grow"` | share leftover container space (largest-first grow, `clay.h:2455`) |
| `"percent"` / `{mode="percent", value=0.5}` | fraction (0–1) of parent content box |
| `200` (bare number) | fixed pixels — shorthand for the table form below |
| `{mode="fixed", value=200}` | fixed pixels (`value` nil → treated as `fit`) |
| `min=` / `max=` on any spec | clamp bounds in px, applied after mode math |

Overflow (fixed children too wide for the container) shrinks the largest
child down to its `min`, matching Clay's shrink-largest loop
(`clay.h:2411-2445`); underfull space grows the smallest grow-capable child.
Off-axis, a `fit` child **stretches** to the container content box unless
clamped by `min`/`max` (Clay's default sizing is fit on both axes,
`clay.h:302` — the port keeps it; visible in the demo's `O2` scenario where
fixed children keep their authored cross-axis size only via `min`/`max`
clamps).

`aspectRatio` applies after the X pass and after the Y pass (like
`clay.h:2638-2643, 2696-2700`), and is skipped for text elements
(`clay.h:2355`).

## 4. Measured text (fit-content)

Text children (`TextLabel`/`TextButton`/`TextBox`/`TextArea`) seed from
[`core/measure.lua`](../core/measure.lua), which wraps the **same**
`font:getWrap` LÖVE uses internally and applies the same circle/arc `*2`
width rule and `adjust`/`textOffsetX` insets as the draw path — so *measured
lines == rendered lines* (the demo asserts this, Phase 1).

- `width = "fit"` → natural (unwrapped) text width.
- Constrained width (`fixed`/`percent`/`grow`, or fit inside a narrower box) →
  Pass B re-measures wrapped lines; height becomes `lines * font:getHeight()`.
- A fit-height parent's height then grows by the wrapped text via Pass C
  upward propagation (`clay.h:2646-2691`).
- The measure cache is generation-swept per pass (`beginPass()`), so repeated
  (font, text, width) lookups within a frame are hits.

## 5. Escape hatch & floating children

**Any manual geometry write on a flex-managed child escapes it permanently:**
`setDualDim`, `rawSetDualDim`, `move`, `size` ([hooks at
`init.lua:302/309/417/423`](../init.lua:302)). The element gets
`__flexEscaped = true`, leaves flow (siblings close ranks around it — Clay
floating semantics, plan §4), keeps its manual rect, and is **not**
re-adopted — except by an explicit `setSizing{...}` call, which re-enables
management.

`setSizing(false)` escapes without touching geometry: the child stays at its
current dualDim and floats. Escape is one-way per element for
`setDualDim`-style writes; the demo's `EH`/`FL`/`CXR` scenarios pin this.

Inside a flex **container**, escaped children are skipped in sizing sums and
cursor advancement but remain normal descendants (draw order, events,
`getAllChildren`). A `__flex` container that itself escaped (dragged window,
centered box) still lays out its own children normally — it just becomes a
root whose box is manual.

`clipDescendants` containers stamp `__clip` on descendants; escaped children
inside one are clipped to the container's absolutes like any other child.

## 6. Interaction with existing layout features

| Feature | Behavior |
|---|---|
| `square = "w"/"h"` | Honored through the pass (Pass E tail bakes `__fw == __fh`, so the resolver's square re-application at [`init.lua:385`](../init.lua:385) is a no-op on managed elements). Demo `SC`. |
| `centerX`/`centerY` | The centering loop writes dualDim every frame → the child **auto-escapes** (documented consequence of §5). Use `alignX/alignY = "center"` instead. Demo `CXR`. |
| `fullFrame()` | On a flex root: ordinary dualDim seed. On a managed child: escape hatch (it's a `setDualDim`). |
| `setAspectSize` letterbox | The resize/letterbox thread ([`init.lua:2532-2563`](../init.lua:2532)) mutates `gui.x/y/w/h` fields directly and fires no events — covered by the parent-watch safety net (§7). |
| `move`/`size` incremental drags | Escape hatch by contract — dragging a flex child opts it out. Drag a managed child in the demo: it stays where dropped. |
| Transitions animating a managed child | Any external `setDualDim` auto-escapes it — the transition wins, the element becomes floating. Animating a *container's* size while flex reflows it is unsupported (v1 caveat). |
| Blur / shaders / `canPress` | See flex geometry for free — write-back keeps `dualDim` truthful, and the draw cache is refreshed parent-first from it. |

## 7. Dirty flags, scheduling & stats

The pass runs at the top of `draw_loop` for both trees
([`init.lua:2418-2422`](../init.lua:2418)): after every update processor has
finished mutating geometry, before the parent-first draw DFS caches
absolutes — so hit-testing and rendering see flex geometry the same frame.

**What marks a flex root dirty** (plan §5.1, `flexbox.markDirty` walks up to
the nearest flex root, [`core/flexbox.lua:171`](../core/flexbox.lua:171)):

| Trigger | Mechanism |
|---|---|
| `setFlex` / `setSizing` | direct call in the API |
| manual geometry on a managed child | `onManualGeometry` escape-hatch hooks |
| child added / destroyed / reparented | `newBase` / `destroy` / `setParent` hooks ([`init.lua:1106/724/507-518`](../init.lua:1106)) |
| flex root's own box changed by an *evented* write | `OnSizeChanged`/`OnPositionChanged` connections installed by `setFlex` ([`core/flexbox.lua:1016-1028`](../core/flexbox.lua:1016)) — the core VisualEvents façade already filters `obj == self` ([`init.lua:1060`](../init.lua:1060)); the handlers' own `obj == self` check is belt-and-braces, and they ignore the pass's own fires via the `firing`/`writing` guards |
| parent box changed **without** events (letterbox/resize thread) | per-root **parent-watch safety net**: `runPass` re-checks the root's resolved seed (`__flexAX/AY/AW/AH`) and, for size-managed roots, the parent's cached `x/y/w/h` — cheap float compares ([`core/flexbox.lua:827-844`](../core/flexbox.lua:827)) |

A dirty root re-runs the full pipeline (seed → Pass A → B → aspect-h → C1 → D
→ aspect-w → F → square bake → write-back); roots are processed in increasing
depth so a nested flex root seeds from its parent's *same-frame* fresh
values, not last frame's cache.

**Idle frames:** nothing dirty → no root re-runs → `stats.visited` delta is 0.
The autotest asserts this (`idle frame visits 0 elements`). `stats`
([`core/flexbox.lua:53`](../core/flexbox.lua:53)):

| Field | Meaning |
|---|---|
| `passes` | root layouts executed (cumulative) |
| `visited` | elements laid out (cumulative) — the perf gate: idle delta 0 |
| `rootsScanned` | flex roots examined by `runPass` (cumulative) — the O(#roots) steady-state cost of the watch |

**Re-entrancy** (plan §5.3): the pass fires delta-gated
`OnSizeChanged`/`OnPositionChanged` after write-back (once per actual size
change, `firing` guard so those fires don't re-mark dirty). If a user event
handler calls back into `runPass` mid-pass, the `running` flag defers a
re-run after the current pass completes instead of recursing — mirroring the
`applying` flag pattern in `newScrollFrame`. The autotest proves one event
per change, deferred re-entry, and no recursion blowup.

## 8. Virtual tree / parked subtrees

Windows moved into `gui.virtual` (hidden; updated but never drawn) keep
working: `runPass(gui.virtual)` runs both in the draw loop and in the 100 ms
virtual-refresh thread ([`init.lua:2450`](../init.lua:2450)). The parked
subtree's `getAbsolutes()` invariant is asserted by the demo after the
refresh thread's first tick.

One subtlety documented in code: `safeAbsolutes`
([`core/flexbox.lua:127`](../core/flexbox.lua:127)) `rawget`s the parent's
cached fields because an element created the same frame as a flex root has
*no stamped cache* — a plain read would inherit `gui`'s boot values through
the element metatable and mis-seed the root. Unstamped parents are resolved
on the fly; `draw_handler` stamps them with exactly those values the same
frame (parent-first), preserving the invariant by construction.

## 9. Scroll containers (fit-content)

Plan §7, implemented. A `newScrollFrame`'s content frame can be flex-sized
so scroll extent derives from real content instead of manual
`setContentSize`:

```lua
require("gui.addons.system")
local sf = gui:newScrollFrame(700, 1340, 300, 80, 0, 0, 0, 0) -- returns CONTENT frame
sf:setFlex{ direction = "column", gap = 4 }
flexbox.sizeManaged(sf, true)          -- pass owns SIZE, host owns POSITION
-- add flex children; content height = sum + gaps (no setContentSize)
```

`flexbox.sizeManaged` marks the root **size-managed**: write-back touches
only `offsetW/offsetH` and never `offsetX/offsetY`, so the scroll frame's own
`content:setDualDim(-scrollX, -scrollY)`
([`addons/system.lua:234`](../addons/system.lua:234)) keeps working. That
manual write hits the escape-hatch hook, but a *flex root* never escapes
(escape only applies to managed children of a flex parent,
[`core/flexbox.lua:866-885`](../core/flexbox.lua:866)); it marks the root
dirty, and the next frame's pass re-anchors children against the new scroll
offset. `maxScrollY` then flows from the fit-content height through the
existing `content:OnSizeChanged` handler.

Non-flex scroll frames are unaffected: `newScrollFrame`'s behavior is
unchanged for content without `setFlex` (proven by a zero-impact boot test).
Two latent `newScrollFrame` bugs were fixed en route (see plan-deviation
notes in the demo source): the `OnSizeChanged` handlers now filter `obj`
(gui's VisualEvents are global — without the filter, *any* element's resize
re-entered `applyScroll`/`updateScrollbars`, and once flex fired size events
this became a stack overflow), and `theme:new` → `theme:newTheme`
(`addons/system.lua` could not even be required before).

## 10. YAML keys

`yaml/builder.lua` accepts `flex:` and `sizing:` on any element definition
(additive — definitions without them behave byte-identically):

```yaml
type: frame
x: 460
y: 1460
w: 200
h: 100
flex: { direction: column, gap: 4 }   # true == {} (all defaults)
children:
  - type: frame
    sizing: { width: { mode: fixed, value: 50 }, height: { mode: fixed, value: 30 } }
  - type: frame
    sizing: { width: grow, height: 30 }   # bare number == fixed px
```

Values map 1:1 onto `setFlex`/`setSizing` shorthands (§2, §3). `padding` also
accepts a `[l, r, t, b]` sequence (mirroring `parseDualDim`'s list leniency).
tinyyaml's flow style yields numbers as strings; the builder coerces numeric
strings inside `flex:`/`sizing:` tables before validation. See
[yaml-declarative-ui.md §3 "Flex layout"](yaml-declarative-ui.md#3-shared--type-specific-properties)
and [yaml-based-elements.yaml](yaml-based-elements.yaml).

## 11. Running the demo / autotest

```
love examples/flex-demo                 # interactive window: scenarios + debug overlays
love examples/flex-demo --flex-autotest # runs 78 assertions, prints summary, exits 0 on pass
love examples/flex-demo --flex-headless # no window; layout + checks only
```

In the window: `R` rebuilds all scenarios, `Esc` quits. Cyan overlay rects are
`__flexComputed`; amber marks escaped elements. The status line prints
`checks / invariantFails / passes / visited / frame`.

The write-back invariant (`getAbsolutes() == __flexComputed` to 1e-9 for
every managed element) is checked **every draw frame** via
[`examples/flex-demo/verify.lua`](../examples/flex-demo/verify.lua)
(delegates to `flexbox.debugVerifySubtree`,
[`core/flexbox.lua:1117`](../core/flexbox.lua:1117)) — not an opt-in.
Autotest exit code is 0 only when `failed == 0 and invariantFails == 0`.

## 12. Limitations vs Clay

Honest list (plan §10 non-goals + verified behavior):

- **No grid layout in the flex pass itself** — Clay v0.14 has none either;
  grid containers/items are a separate second root mode riding the same
  scheduler, see [Grid Layout](grid.md).
- **No `zIndex`** — stacking stays `children` order + `topStack`/`bottomStack`.
- **No immediate-mode API** — the retained tree is the only input; no
  arena allocator, no element-ID hashing.
- **No border/padding rendering by the pass** — flex `padding` affects layout
  only; drawing borders is still the element's own job.
- **No scroll-offset awareness inside the pass** (Clay's scroll containers
  skip overflow compression on the clipped axis, `clay.h:2407`; this port
  sizes the content fit instead and lets the host translate it, §9).
- **No `attach` points, pointer-capture modes, or `expand`** from Clay's
  floating config.
- **No text measurement replacement outside flex** — legacy
  `calculateFontOffset` pixel-scanning is untouched; `core/measure.lua` is
  used only by the flex pass.
- **One-frame seed staleness**: a flex root reads its parent's box from the
  draw cache refreshed last frame (or same-frame fresh values when the
  parent is an earlier flex root). This matches the staleness every existing
  `getAbsolutes` consumer has; the parent-watch closes the resize case.
- **Animating a flex container's size** with `transitions` while it reflows
  fights the pass (any external write escapes the element instead).
- **`percent` overflow** uses Clay's uint16-era clamps loosely; extreme
  percent sums behave like fixed overflow (shrink-to-min), not CSS wrapping.
- **No `flex-wrap`** — a single line per container, like Clay's
  `childCount`-per-container model without multi-line.
