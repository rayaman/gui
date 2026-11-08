# GuiManager

> 📚 **Full documentation lives in [`gui/docs/`](docs/README.md)** — architecture, layout system,
> elements, events, theming, shaders, widgets, and the YAML builder.

This library due to the changes in love2d. Too many things are broken and instead of doing patch work, I've decided to do a total rewrite. Also I'll be able to make use of the new multi manager features and build a better library from the ground up.

Core Objects:
- ~~Frame~~ ✔️
- Text:
  - ~~Label~~ ✔️
  - ~~Box~~ ✔️
  - ~~Button~~ ✔️
  - utf8 support with textbox (Forgot about this, will have to rework some things)
- Image:
  - ~~Label~~ ✔️
  - ~~Button~~ ✔️
  - Animation
- ~~Video~~ ✔️

Events:
- Mouse Events
  - ~~Enter~~ ✔️
  - ~~Exit~~ ✔️
  - ~~Pressed~~ ✔️
  - ~~Released~~ ✔️
  - ~~Moved~~ ✔️
  - ~~WheelMoved~~ ✔️
  - ~~DragStart~~ ✔️
  - ~~Dragging~~ ✔️
  - ~~DragEnd~~ ✔️
- Keyboard Events
  - ~~Hotkey~~ ✔️ Refer to [KeyConstants](https://love2d.org/wiki/KeyConstant) wiki page
    - Some default hotkeys have been added:
      - ~~(conn)gui.HotKeys.OnSelectAll~~ ✔️ `Ctrl + A`
      - ~~(conn)gui.HotKeys.OnCopy~~ ✔️ `Ctrl + C`
      - ~~(conn)gui.HotKeys.OnPaste~~ ✔️ `Ctrl + V`
      - ~~(conn)gui.HotKeys.OnUndo~~ ✔️ `Ctrl + Z`
      - ~~(conn)gui.HotKeys.OnRedo~~ ✔️ `Ctrl + Y, Ctrl + Shift + Z`
- Other Events
  - ~~OnUpdate~~ ✔️
  - ~~OnDraw~~ ✔️
Polish:
  - ~~gui:newCheckbox()~~
  - ~~gui:isOnScreen()~~
  - ~~gui:newRadioGroup()~~
  - gui:newSlider()
  - ~~gui:newProgressBar()~~
  - gui:newTooltip()
  - gui:newTextArea()
    - TODO: selection, hotkeys
  - ~~gui:newListFrame()~~ (selection, hover/press motion, add/remove animation, keyboard nav — see docs/widgets.md §12)
  - gui:newGridFrame()

Better Transistions:
  - ease.easeIn(start, stop, time)      -- accelerates from start
  - ease.easeOut(start, stop, time)     -- decelerates into stop
  - ease.easeInOut(start, stop, time)   -- smooth S-curve
  - ease.easeInCubic(...)               -- more aggressive acceleration
  - ease.easeOutCubic(...)              -- more aggressive deceleration
  - ease.bounce(start, stop, time)      -- bounces at the end
  - ease.elastic(start, stop, time)     -- overshoots then settles
  - ease.back(start, stop, time)        -- slight pull-back before moving

Focus Management:
  -   gui.focus.set(element)       -- programmatically set focus
  -   gui.focus.get()              -- returns currently focused element (or nil)
  -   gui.focus.clear()            -- clear focus (no element focused)
  -   gui.focus.setTabOrder(list)  -- set a list of elements for Tab navigation
  -   gui.focus.tabNext()          -- focus the next element in the tab order
  -   gui.focus.tabPrev()          -- focus the previous element

Z-index Enhancments:
 - gui:setLayer(n)
 - gui:getLayer()

## Flexbox layout (opt-in)

Auto-layout on top of the dual-dim system — a scoped port of
Clay v0.14's flex engine. Opt in per subtree with
`setFlex` / `setSizing`; everything else is untouched (manual writes on a
managed child escape it back to dualDim).

```lua
local row = gui:newFrame(20, 20, 400, 100)
row:setFlex{ direction = "row", gap = 8, padding = 12, alignY = "center" }
local a = row:newFrame(); a:setSizing{ width = 100, height = "grow" }
local b = row:newFrame(); b:setSizing{ width = "grow" }  -- takes the rest
```

Docs: [flexbox guide](docs/flexbox.md) (API reference, escape-hatch
semantics, dirty-flag scheduling, virtual-tree & scroll integration,
design rationale, limitations vs Clay) ·
YAML keys `flex:`/`sizing:` in [yaml-declarative-ui.md](docs/yaml-declarative-ui.md).

Try it:

```
love examples/flex-demo                 # interactive scenarios + debug overlays
love examples/flex-demo --flex-autotest # 78 assertions + per-frame write-back invariant, exit 0 on pass
```

Honest caveats: no grid inside the flex pass itself (grid is a separate root
mode — see below), no zIndex/flex-wrap, no immediate mode; animating a flex
container's size fights the pass (external writes escape the element); a
flex root's parent box is read from the one-frame draw cache (same staleness
every existing `getAbsolutes` consumer has, closed for resizes by the
parent-watch).

## Grid layout (opt-in)

CSS-Grid-style containers and items — tracks (`fr`/`px`/`auto`/`minmax`/
`repeat`), template areas, explicit lines/spans/dense auto-placement,
content + item alignment. It runs as a second root mode inside the same
scheduler, so flex and grid nest freely and share the escape hatch, dirty
gating, write-back and events. A container is `setFlex` *or* `setGrid`.

```lua
local board = gui:newFrame(20, 20, 600, 200)
board:setGrid{ areas = { "header header", "side main" },
               columns = "200px 400px", gap = 10 }
board:newFrame():setGridPlacement{ column = "header / header" }  -- spans both cols
```

Docs: [grid guide](docs/grid.md) (property reference, track/placement
grammar, cross-mode nesting, limitations vs CSS) · YAML keys
`grid:`/`grid-placement:` in [yaml-declarative-ui.md](docs/yaml-declarative-ui.md).

Try it:

```
love examples/grid-demo                 # labeled scenarios + debug overlays
love examples/grid-demo --grid-autotest # 79 assertions + per-frame invariant, exit 0 on pass
```
