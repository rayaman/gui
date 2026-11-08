# GUI Library — Getting Started

A LÖVE2D GUI framework with a dual-dimension layout system, connection-based events,
theming, shaders, GIF/video playback, declarative YAML UI, and a widget add-on library.

> **This document is the quick-start.** Deep dives live in the rest of this folder —
> start with the [documentation index](README.md).
>
> Previously this file carried a full single-file reference; it drifted from the code
> (stale theming API, add-on widgets that moved modules, hotkeys that don't exist).
> Everything below has been re-verified against
> [`gui/init.lua`](../init.lua) and the current modules.

---

## Table of Contents

1. [Requirements & setup](#1-requirements--setup)
2. [Your first screen](#2-your-first-screen)
3. [Layout in one minute](#3-layout-in-one-minute)
4. [Responding to input](#4-responding-to-input)
5. [Common recipes](#5-common-recipes)
6. [Where to read next](#6-where-to-read-next)

---

## 1. Requirements & setup

- LÖVE 11.x and the [`multi`](../../multi) library on your `love.filesystem` path
  (`gui` requires `multi`, `multi.integration.loveManager`, and LuaJIT's `bit`).
- Place the `gui/` folder at the root of your project.

```lua
local gui = require("gui")            -- core: everything in gui/init.lua
require("gui.addons")                 -- optional: checkbox, pickers, progress bar, …
require("gui.addons.system")          -- optional: newWindow, newScrollFrame, task manager
```

Wire the two entry points into LÖVE — the library hooks **input** callbacks itself:

```lua
function love.update(dt)
    gui.update(dt)
end

function love.draw()
    gui.draw()
end
```

That's the whole integration. `love.mousepressed`, `love.keypressed`, `love.resize`,
etc. are chained onto your own callbacks if you define them
([architecture §5](architecture.md#5-event-routing)).

---

## 2. Your first screen

```lua
local gui = require("gui")

-- A panel filling the middle 60% × 50% of the window
local panel = gui:newFrame(-0.3, -0.25, 0, 0, 0.3, 0.25, 0.4, 0.5)  -- see §3
panel.color = {0.12, 0.13, 0.16}
panel:setRoundness(12, 12)

-- Title
local title = panel:newTextLabel("MAIN MENU", 0, 10, 0, 48, 0, 0, 1)
title.align = gui.ALIGN_CENTER
title:scaleFont(0.6)                 -- font size = 60 % of label height (responsive)

-- A button
local play = panel:newTextButton("Play", 0, 80, 220, 48, 0.5, 0.3)
play:setDualDim(-110, 80, 220, 48, 0.5, 0.3)   -- centered horizontally
play:OnReleased(function(self, x, y, button)
    print("Play pressed")
end)

-- An editable field
local name = panel:newTextBox("", 0, 140, 260, 34, 0.5, 0.55)
name:setDualDim(-130, 140, 260, 34, 0.5, 0.55)
name.OnReturn(function(self, text) print("Player:", text) end)
```

Notes:

- Every constructor takes the 8-number **dualDim** tail; scale values (last four) are
  fractions of the parent, offsets (first four) are pixels.
- Children are drawn in order — later siblings on top.
- `destroy()` removes an element and disconnects everything it registered.

---

## 3. Layout in one minute

```
absolute_x = parent.w * sx + x + parent.x
absolute_y = parent.h * sy + y + parent.y
absolute_w = parent.w * sw + w
absolute_h = parent.h * sh + h
```

```lua
obj:setDualDim(x, y, w, h, sx, sy, sw, sh)   -- nil slot keeps current value
obj:fullFrame()                              -- fill parent
inner:setDualDim(10, 10, -20, -20, 0, 0, 1, 1)  -- 10 px inset
tray:setDualDim(-110, -50, 100, 40, 1, 1)       -- bottom-right, fixed size
obj:centerX(true)                            -- keep centered as things resize
```

Full anchoring cookbook, centering, square-locking, aspect ratio, stacking, and clipping:
[layout-system.md](layout-system.md).

---

## 4. Responding to input

```lua
btn:OnReleased(function(self, x, y, button, istouch, presses) end)
btn:OnEnter(function(self) self.color = hover end)
panel:OnWheelMoved(function(self, dx, dy) end)
card:enableDragging(gui.MOUSE_PRIMARY)
card:OnDragging(function(self, dx, dy) self:move(dx, dy) end)

obj:OnUpdate(function(self, dt) self.rotation = self.rotation + 90 * dt end)

local save = obj:setHotKey({"lctrl", "s"})
save(function() saveGame() end)
```

Event tables (including `OnPressedOuter`/`OnReleasedOther` semantics, focus, drag state
machine, and connection `+`/`*` algebra):
[events-and-input.md](events-and-input.md).

---

## 5. Common recipes

### Make a dialog window *(system add-on)*

```lua
require("gui.addons.system")

local win = gui:newWindow(200, 120, 420, 300, nil, nil, nil, nil,
                          "Options", true, myTheme)
-- win is the CONTENT frame; children get auto-styled
local ok = win:newTextButton("OK", 10, 250, 120, 34)
ok:OnReleased(function() win:close() end)
```

See [widgets §1](widgets.md#1-window) for the theme table shape and `OnClose`.

### Scrollable list *(system add-on)*

```lua
local content = parent:newScrollFrame(0, 0, 300, 400)
for i = 1, 50 do
    content:newTextLabel("row " .. i, 0, (i-1)*24, 0, 24, 0, 0, 1)
end
content:setContentSize(nil, 50 * 24)
content:scrollToBottom()
```

### Responsive text that fits its box

```lua
label:scaleFont(0.5)     -- font size tracks element height on every draw
label:fitFont(8, 200)    -- or: largest fixed size that fits, cached
```

### Click-through decorations

```lua
local deco = gui:newVisualFrame():fullFrame()   -- never eats clicks
deco:newImageLabel("assets/vignette.png"):fullFrame()
```

### Animated feedback with transitions

```lua
local transition = require("gui.core.transitions")
local slide = transition.glide(-200, 0, 0.25)
local t = slide()
t.OnStep(function(v) panel:setDualDim(v) end)
t.OnStop(function() panel:respectHierarchy(true) end)
```

### Blur a panel

```lua
panel:setBlur(10)          -- shaders/blur.lua extension, loaded automatically
```

### Aspect-locked, letterboxed design

```lua
gui:setAspectSize(1920, 1080)
gui.aspect_ratio = true    -- whole tree scales to the safe area
```

### Declarative screens

```lua
local gui_yaml = require("gui.yaml.builder")
local screen = gui_yaml.fromString(gui, yamlText, {
    onPlayClicked = function() startGame() end,
})
```

Schema: [yaml-declarative-ui.md](yaml-declarative-ui.md) and the annotated sample
[yaml-based-elements.yaml](yaml-based-elements.yaml).

### Debug the scheduler

```lua
require("gui.addons.system")
gui:showTaskManager()      -- Ctrl+` toggles; live threads, states, priorities, errors
```

---

## 6. Where to read next

| If you want… | Read |
|---|---|
| how everything fits together, threads, draw pipeline | [architecture.md](architecture.md) |
| every layout knob | [layout-system.md](layout-system.md) |
| widget-by-widget API (frames → video) | [elements.md](elements.md) |
| event signatures, hotkeys, focus, drag | [events-and-input.md](events-and-input.md) |
| shapes, roundness, shaders, blur | [appearance-and-shaders.md](appearance-and-shaders.md) |
| color parsing, palettes, theme presets | [theming-and-color.md](theming-and-color.md) |
| add-on widgets | [widgets.md](widgets.md) |
| YAML schema | [yaml-declarative-ui.md](yaml-declarative-ui.md) |
| font/GIF/transitions/simulate/probe | [core-modules.md](core-modules.md) |
| one-line lookup tables | [api-quick-reference.md](api-quick-reference.md) |

Known quirks and open bugs are collected in
[architecture §15](architecture.md#15-known-caveats) and tracked in
[`gui/fixes.md`](../fixes.md).
