# Core Support Modules

The [`gui/core/`](../core) modules that aren't color/theme (covered in
[theming-and-color.md](theming-and-color.md)).

---

## Table of Contents

1. [font — cached font loader](#1-font--cached-font-loader)
2. [transitions — interpolation engine](#2-transitions--interpolation-engine)
3. [gifloader — GIF decoder & animator](#3-gifloader--gif-decoder--animator)
4. [svgloader — SVG vector renderer](#4-svgloader--svg-vector-renderer)
5. [canvas — full-frame roots](#5-canvas--full-frame-roots)
6. [menus — menu registry](#6-menus--menu-registry)
7. [simulate — synthetic input](#7-simulate--synthetic-input)
8. [probe — scheduler load](#8-probe--scheduler-load)

---

## 1. font — cached font loader

[`core/font.lua`](../core/font.lua). A tiny cache keyed by `"path:size"` so repeated
`setFont`/`fitFont` calls don't churn LÖVE font objects.

```lua
local font = require("gui.core.font")

local f = font.set("assets/fonts/gyparody.ttf", 24)  -- load-or-fetch, returns Font
local d = font.set(nil, 16)                          -- default face at 16
local g = font.get("assets/fonts/gyparody.ttf", 24)  -- fetch without loading twice

font.evict(nil, 16)      -- drop one entry
font.clear()             -- drop all
print(font.size())       -- entries cached
```

The core uses this internally when `scaleFont` re-derives a font at draw time
([`init.lua` L2136](../init.lua:2136)).

---

## 2. transitions — interpolation engine

[`core/transitions.lua`](../core/transitions.lua). Runs on its own `Transition Processor`.
A transition **factory** is created by calling a transition with `(start, stop, duration)`;
calling the factory starts the animation and returns a handle.

```lua
local transition = require("gui.core.transitions")

-- glide = linear interpolation (the built-in)
local slide = transition.glide(-200, 0, 0.3)   -- factory: -200 → 0 over 0.3 s

local t = slide()                              -- start it
t.OnStep(function(value, elapsed)              -- fires at the transition's FPS
    panel:rawSetDualDim(value)
end)
t.OnStop(function() print("done") end)         -- OnReturn + OnError combined
t.Kill()                                       -- cancel mid-flight
```

- **Factory overrides:** `slide(newStart, newStop, newDuration)` — any nil falls back to
  the original values.
- **Trivial case:** `start == stop` short-circuits (fires `OnStop` next task, no thread).
- **FPS control:** `transition.glide:SetFPS(30)` / `:GetFPS()` — sample rate of `OnStep`.

### Custom transitions

`transition:newTransition(func)` wraps a coroutine body that pushes values via
`thread.pushStatus`:

```lua
local ease = transition:newTransition(function(t, start, stop, time)
    local steps = t.fps * time
    t.running = true
    for i = 0, steps do
        if t.kill then break end
        thread.sleep(1 / t.fps)
        local u = i / steps
        local eased = 1 - (1-u)*(1-u)               -- easeOutQuad
        thread.pushStatus(start + (stop - start) * eased, u)
    end
    t.running = false
    t.kill = false
end])
```

The README's "Better Transitions" list (easeInOut, bounce, elastic, back, cubic variants)
is planned — only `glide` ships today; the `newTransition` pattern above is how to add
them.

Used internally by [`simulate.Move`](#7-simulate--synthetic-input).

---

## 3. gifloader — GIF decoder & animator

[`core/gifloader.lua`](../core/gifloader.lua). Pure-Lua GIF87a/89a decoder (LZW included —
LÖVE's `love.data` doesn't do LZW). Image elements wire this automatically for `.gif`
sources ([elements §4.3](elements.md#43-animated-gifs)); standalone API:

```lua
local gif = require("gui.core.gifloader")

local g = gif.load("assets/anim.gif")   -- {frames, delays, currentFrame, width, height, ...}

-- choose ONE driving model:
gif.Updater(g, drawer)                  -- spawns a "Gif Handler" thread on a processor
-- or, in your own update loop:
gif.update(g, love.timer.getDelta())

gif.draw(g, x, y, r, sx, sy, ox, oy)    -- draw current frame
gif.play(g) / gif.pause(g) / gif.reset(g)
gif.setFixedFramerate(g, 24)            -- override all per-frame delays
print(gif.getInfo(g))                   -- {width, height, frameCount, delays, totalDuration}
```

Decoding notes:

- Frames are **composited**: each frame's `ImageData` starts as a copy of the previous
  frame, then the frame's dirty rectangle is painted (handles partial frames &
  transparency index).
- Delay policy: 0 → 100 ms; ≤2 cs → 20 ms floor; else `delay/100` s. NaN/zero delays are
  sanitized after parse.
- `gif.kill = true` terminates a thread-driven gif (the element does this on `destroy`).
- Interlaced GIFs are parsed but not de-interlaced.
- `gif.Updater` sleeps `delay * 4` — thread-driven playback runs ~4× slower than the
  encoded delays; use `gif.update(g, dt)` for accurate timing.

```mermaid
sequenceDiagram
    participant L as Gif Handler thread
    participant G as gif table
    participant D as draw pass [1]
    loop forever
        L->>L: hold(playing or kill), sleep(delay*4)
        L->>G: currentFrame += 1 (wrap / stop if not loop)
    end
    D->>G: read frames[currentFrame] each render
```

---

## 4. svgloader — SVG vector renderer

[`core/svgloader.lua`](../core/svgloader.lua). Pure-Lua SVG **vector** renderer (no
rasterization, no native deps). Image elements wire this automatically for `.svg`
sources ([elements §4.4](elements.md#44-svg-vectors)); standalone API:

```lua
local svg = require("gui.core.svgloader")

local s = svg.load("assets/icon.svg")   -- parsed once, cached per filepath

s:draw(x, y, w, h)                       -- absolute window space, meet-fit into the box
s:draw(x, y, w, h, { rotation = 45, scaleX = -1, scaleY = 1, alpha = 0.5 })

print(s.width, s.height)                 -- intrinsic px (from width/height attrs, else viewBox)
print(svg.getInfo(s))                    -- {sourcePath, viewBox, width, height, shapeCount, hasStrokes}

svg.clearCache()                         -- drop parses + their meshes (hot-reload/tests)
```

How it works — the SVG is parsed **once** into vector geometry, then **drawn live
every frame** at the element's *current* box size, so it stays crisp at any scale
(flex/dualDim resizes included):

```mermaid
flowchart LR
    A[load filepath] --> B[XML-lite parse]
    B --> C[curves flattened to polylines]
    C --> D[love.math.triangulate per contour -> Mesh]
    D --> E[one love.graphics.stencil invert parity pass]
    E --> F[setStencilTest + fill box]
    F --> G[crisp at any box size]
```

- The element hookup installs a `post` overlay hook that re-reads
  `getAbsolutes()` each frame and calls `s:draw(...)`; `c.image` stays `nil`, so
  the image draw pass is a no-op for SVG elements
  ([`init.lua` setImage](../init.lua:2025)).
- Even-odd fill (`fill-rule="evenodd"`) is computed as **stencil parity**: all
  contour meshes are drawn inside one `love.graphics.stencil(..., "invert")`
  call, so nested holes cancel correctly.
- Anti-aliasing comes from **window MSAA** (`t.window.msaa = 4` in the demo
  conf), not from the loader.

Standalone use without an element:

```lua
local s = svg.load("bookmark.svg")
function love.draw()
    s:draw(100, 100, 256, 256)   -- any size; redraws sharp every frame
end
```

Supported subset & limitations:

- **Root:** `width`/`height` (px/unitless, or `pt`/`pc`/`mm`/`cm`/`in`/`em`/`%`),
  `viewBox`, default `fill`, `preserveAspectRatio`
  (`xMin|xMid|xMax` + `YMin|YMid|YMax` + `meet|slice` + `none`).
- **Elements:** `path`, `rect` (incl. `rx`/`ry` rounded corners), `circle`,
  `ellipse`, `line`, `polyline`, `polygon`, `g` (paint inheritance + group
  `opacity`), `defs` + `use` (`href`/`xlink:href`, `x`/`y`, presentation attrs,
  `transform`) + `symbol` (its `viewBox` scaled into the `use` box); depth-capped,
  forward references OK.
- **Transforms:** `translate`, `scale`, `rotate(θ [cx cy])`, `skewX`, `skewY`,
  `matrix` — full 2×3 affine composition.
- **Path commands:** `M m L l H h V v Z z` exact; `C c S s` and `Q q T t`
  flattened to polylines; `A a` elliptical arcs (cubic-segment approximation).
- **Paint:** solid fills (`#RGB`, `#RRGGBB`, `rgb()`, named, `none`),
  `fill-opacity`, `fill-rule` (evenodd parity; nonzero winding — exact for
  uniform-orientation contours, even-odd approximation + warn on mixed),
  `stroke` + `stroke-width` + `stroke-opacity` + `stroke-dasharray`/
  `stroke-dashoffset` + `stroke-linejoin` + butt/square `stroke-linecap`.
- **Gradients:** `linearGradient` / `radialGradient` (`stop` offsets +
  `stop-color`/`stop-opacity`, `gradientUnits`, `spreadMethod`) via `fill="url(#id)"`.
- **clip-path:** `clipPath` (rect/circle/ellipse/convex-polygon children) applied
  geometrically at load (Sutherland–Hodgman); multiple children intersect; concave
  regions warn once and are skipped.
- **mask:** `mask` rasterized at load to a 96px luminance→alpha texture
  (`maskUnits`, `maskContentUnits`); solid-fill mask children only.
- **Not supported:** patterns, filters, SMIL animation, `text`/`image` elements,
  true round line caps/joins (this LÖVE build has no `setLineCap`; `round`
  approximated via `setLineStyle("smooth")`), `gradientTransform`, radial focal
  points (`fx`/`fy` treated as center), gradients inside masks, `imageColor`
  tinting of SVGs.
- Cost model: geometry + meshes are built once per file (cached); per-frame
  cost is draw calls only — trivial for icons. Very complex SVGs are better
  pre-baked to PNG.

---

## 5. canvas — full-frame roots

[`core/canvas.lua`](../core/canvas.lua). The module *is* the constructor function:

```lua
local newCanvas = require("gui.core.canvas")

local bg   = newCanvas("visual")   -- non-interactive full-screen frame
local root = newCanvas()           -- interactive full-screen frame
```

Each canvas fills the screen (`fullFrame()`) and gains:

```lua
newCanvas:swap(a, b)   -- exchange the children tables of a and b, re-parenting both
```

`swap` is the scene-transition primitive: build the next screen off in a virtual canvas,
then swap it with the live one in one step.

---

## 6. menus — menu registry

Lazy, single-visible menu manager. Full API documented in
[widgets §11](widgets.md#11-menu-registry-core).

Key behaviors: `registerMenu(name, buildFn[, delete])` stores a factory; the first
`:visible(true, ...)` builds the frame inside the current menu container, subsequent calls
just re-show it; `hideMenus()` parks (or destroys, with `delete`) the others.

---

## 7. simulate — synthetic input

Drive the GUI from scripts/tests ([`core/simulate.lua`](../core/simulate.lua)); practical
guide in [events §10](events-and-input.md#10-simulation-synthetic-input).

```lua
local simulate = require("gui.core.simulate")

simulate:Press()                 -- at current mouse pos, primary button
simulate:Release()
simulate:Press(nil, 400, 300)    -- explicit position
btn:Press()                      -- object form → object center
simulate.Click(btn)              -- press → tick → release (async, scheduler function)
simulate.Move(nil, 100, 0, sx, sy)  -- animated cursor glide + OnMouseMoved stream
```

`Move` glides the real OS cursor with two `glide` transitions and fires the moved event
stream, so hover/drag chains behave as with a human.

---

## 8. probe — scheduler load

[`core/probe.lua`](../core/probe.lua) replaces `multi:getLoad()` with a cheap,
non-blocking estimate. Despite the header's tick-slip theory, the installed
implementation measures **FPS shortfall vs. refresh rate**:

```lua
local probe = require("gui.core.probe")
probe:install(multi)          -- once, at startup

local loadPct, frameMs = multi:getLoad()     -- e.g. 12, 16.6
local lagMs, ratio     = multi:getSchedulerLag()
```

| `opts` | default | note |
|---|---|---|
| `interval` | 0.05 | accepted but unused by the installed FPS-based getter |
| `alpha` | 0.15 | EMA smoothing (state kept for diagnostics) |
| `maxLag` | 0.1 | lag seconds that would map to 100 % |

`load% = ceil((1 - fps/targetFPS) * 100)`, clamped at 0. The task-manager add-on displays
this as its load bar.
