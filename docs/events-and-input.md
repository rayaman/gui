# Events, Connections & Input

The GUI's event system is built on `multi` **connections** (multi-cast signal objects).
Two layers exist:

1. **Global connections** — `gui.Events.*`, one per LÖVE input callback, fired by
   automatically-installed hooks.
2. **Per-object events** — `obj.OnPressed(...)`, filtered bridges of the same signals that
   only fire for the relevant element.

Internal mechanics are covered in [architecture §5–6](architecture.md#5-event-routing);
this document is the practical reference.

---

## Table of Contents

1. [Connection basics & algebra](#1-connection-basics--algebra)
2. [Per-object event table](#2-per-object-event-table)
3. [Global events](#3-global-events)
4. [Event classes & filters](#4-event-classes--filters)
5. [Focus](#5-focus)
6. [Dragging](#6-dragging)
7. [Hotkeys](#7-hotkeys)
8. [Gamepad / joystick events](#8-gamepad--joystick-events)
9. [Bulk wiring with `gui.apply`](#9-bulk-wiring-with-guiapply)
10. [Simulation (synthetic input)](#10-simulation-synthetic-input)
11. [Gotchas](#11-gotchas)

---

## 1. Connection basics & algebra

Attach a handler by *calling* the connection:

```lua
obj.OnReleased(function(self, x, y, button, istouch, presses)
    print("clicked at", x, y)
end)
```

- Multiple handlers can be bound; all fire on emit.
- Connections compose ([`init.lua` L205 comment](../init.lua:205)):
  - `a + b` — **OR**: handler runs when *either* fires
  - `a * b` — **AND**: handler runs only when *both* have fired

```lua
-- fire when released either inside or just outside the element:
(obj.OnReleased + obj.OnReleasedOuter)(function(self) ... end)
```

- Connections you create yourself can be tracked for auto-cleanup:
  `obj:addConnection(conn)` → disconnected automatically by `obj:destroy()`.
- `conn:Unconnect(handler)` removes a specific handler; `conn:Destroy()` kills the
  connection.
- `obj:OnUpdate(fn)` is *not* a stored connection — it wraps `gui.Events.OnUpdate`
  with the object's delta time ([`init.lua` L1011](../init.lua:1011)).

---

## 2. Per-object event table

Any element supports all of the following (arguments as fired by the bridges in
[`initEvents`, init.lua L920–983](../init.lua:920)):

### Mouse / pointer

| Event | Handler signature | Fires when |
|---|---|---|
| `OnPressed` | `(self, x, y, button, istouch)` | press lands inside the element |
| `OnReleased` | `(self, x, y, button, istouch, presses)` | release lands inside (after any press) |
| `OnPressedOuter` | `(self, x, y, button, istouch, presses)` | press happens **outside** the element |
| `OnReleasedOuter` | `(self, x, y, button, istouch, presses)` | release outside, but this element held the last press (drag-off release) |
| `OnReleasedOther` | `(self, x, y, button, istouch, presses)` | release with no prior press on this element |
| `OnEnter` | `(self, x, y)` | cursor moves onto the element |
| `OnExit` | `(self, x, y)` | cursor leaves the element |
| `OnMoved` | `(self, x, y, dx, dy, istouch)` | cursor moves while over it (or while it's dragging) |
| `OnWheelMoved` | `(self, dx, dy)` | wheel moved with cursor over the element |

### Dragging

| Event | Handler signature |
|---|---|
| `OnDragStart` | `(self, x, y, button, istouch)` |
| `OnDragging` | `(self, dx, dy, x, y, istouch)` |
| `OnDragEnd` | `(self, x, y, istouch, presses)` |

### Layout & lifecycle

| Event | Handler signature | Fires when |
|---|---|---|
| `OnPositionChanged` | `(self, dx, dy)` | `move()` or dualDim offset change |
| `OnSizeChanged` | `(self, ...)` | `size()`/`setDualDim` change |
| `OnLoad` | `(self)` | first time the object's events initialize |
| `OnDestroy` | `(self)` | `destroy()` begins teardown |
| `OnCreated` | `(element)` | **on ancestors**: a descendant was created |
| `OnFontUpdated` | `(self)` | text element's font changed |
| `OnUpdate` | `(self, dt)` | every update tick (see note above) |

### Element-specific

| Element | Extra events |
|---|---|
| TextBox | `OnReturn(self, text)` |
| Video | `OnVideoFinished(self)` |
| Checkbox | `OnChanged(value)` |
| RadioGroup | `OnSelectionChanged(group, selected)` |
| ProgressBar | `OnProgressUpdated(self, percent, value, drag)` |
| Window | `OnClose(self)`, `OnChoice(label, idx)` (message box) |
| TextArea | `OnChanged(self, fullText)` |

### The `OnCreated` ancestor pattern

`newFrame`/`newTextLabel`/etc. fire `gui.Events.OnCreated:Fire(child)` at construction.
`obj:OnCreated(fn)` filters to descendants of `obj` — this is how `newWindow` auto-styles
children created later ([`addons/system.lua` L559](../addons/system.lua:559)):

```lua
win:OnCreated(function(element)
    if element:hasType(gui.TYPE_BUTTON) then
        element.color = myButtonColor
    end
end)
```

---

## 3. Global events

Every LÖVE callback is mirrored on `gui.Events` (fired via
[`core_conns` connections](architecture.md#2-processors-the-three-schedulers)):

```lua
-- System
gui.Events.OnQuit(fn)
gui.Events.OnFocus(fn(hasFocus))
gui.Events.OnVisible(fn(isVisible))
gui.Events.OnResized(fn(w, h))            -- debounced: fires 2 cycles after resize
gui.Events.OnDisplayRotated(fn)
gui.Events.OnFilesDropped(fn(x, y, files))
gui.Events.OnDirectoryDropped(fn(x, y, dirs))
gui.Events.OnMouseFocus(fn(hasFocus))

-- Keyboard
gui.Events.OnKeyPressed(fn(key, scancode, isrepeat))
gui.Events.OnKeyReleased(fn(key, scancode))
gui.Events.OnTextInputed(fn(text))         -- love.textinput
gui.Events.OnTextEdited(fn(text, newlines, repeats))

-- Mouse
gui.Events.OnMouseMoved(fn(x, y, dx, dy, istouch))
gui.Events.OnMousePressed(fn(x, y, button, istouch, presses))
gui.Events.OnMouseReleased(fn(x, y, button, istouch, presses))
gui.Events.OnWheelMoved(fn(dx, dy))

-- Touch
gui.Events.OnTouchPressed / OnTouchMoved / OnTouchReleased

-- Gamepad / joystick
gui.Events.OnGamepadPressed / OnGamepadReleased / OnGamepadAxis
gui.Events.OnJoystickPressed / OnJoystickReleased / OnJoystickHat
gui.Events.OnJoystickAdded / OnJoystickRemoved

-- Internal
gui.Events.OnObjectFocusChanged(fn(previous, current))
gui.Events.OnCreated(fn(element))
gui.Events.OnUpdate(fn())                  -- use obj:OnUpdate instead, usually
```

> `OnResized` deliberately `thread.skip(2)` before firing so resize bursts collapse to one
> event ([`init.lua` L118–121](../init.lua:118)).

---

## 4. Event classes & filters

Per-object handlers pass through up to three gates
([`init.lua` L1017–1066](../init.lua:1017)):

```
your handler
   ▲
   │ gate 3 (Hierarchy events only): obj:testHierarchy(x,y)
   │    → true unless respectHierarchy(true) AND (global_drag OR isBeingCovered)
   │
   │ gate 2 (all but Basic): testVisual(obj)
   │    → true unless obj or an ancestor has the "visual" tag
   │
   │ gate 1: obj == self (and isActive() inside the bridges)
   └─ shared per-event connection gui._OnXxx
```

Practical consequences:

- Elements under a `newVisualFrame` never receive mouse events (gate 2).
- `respectHierarchy(true)` gives you **occlusion-aware** input: if a sibling drawn later
  covers the point, the lower element doesn't get `OnPressed` (gate 3). Buttons and
  textboxes enable it by default.
- Elements with `ignore = true` are skipped by the occlusion test — they can be visible
  but click-through.
- `visible = false` or `active = false` (or living under `gui.virtual`) suppresses all
  mouse events (the bridges check `isActive()`).

---

## 5. Focus

```lua
local focused = gui:getObjectFocus()

gui.Events.OnObjectFocusChanged(function(previous, current)
    print("focus moved from", previous, "to", current)
end)
```

Focus changes when a press lands on a new interactive element. Textboxes use focus to gate
typing and caret blinking. Widgets that need "commit on click-away" use
`OnPressedOuter` (see the [number picker](widgets.md#5-number-picker) pattern).

Planned-but-not-implemented (from the README): `gui.focus.set/get/clear`, tab-order
navigation.

---

## 6. Dragging

```lua
obj:enableDragging(gui.MOUSE_PRIMARY)     -- default drag button is secondary (2)
obj:enableDragging(false)                 -- disable

obj:OnDragStart(function(self, x, y, button) end)
obj:OnDragging(function(self, dx, dy, x, y) self:move(dx, dy) end)
obj:OnDragEnd(function(self, x, y) end)
```

- Only **one** drag can be active globally (`global_drag` latch).
- While dragging, `OnPressed`/`OnMoved` keep firing even when the cursor leaves the
  element; `OnDragEnd` fires on release of the drag button regardless of position.
- With `respectHierarchy(true)`, a drag can't start if another element is on top.

State machine diagram: [architecture §8](architecture.md#8-drag-state-machine).

---

## 7. Hotkeys

```lua
-- Bind a chord; returns a connection you can attach handlers to:
local save = obj:setHotKey({"lctrl", "s"})
save(function(ref)   -- ref = the object that registered the chord
    saveGame()
end)

-- Union multiple chords (OR algebra):
local undo = gui:setHotKey({"lctrl", "z"}) + gui:setHotKey({"lctrl", "y"})
undo(function() ... end)
```

Chords are **held-key sets** — every listed key must be down simultaneously. The hotkey
thread re-arms a chord only after one of its keys is released, so holding `Ctrl+S` fires
once ([`init.lua` L156–192](../init.lua:156)).

| Built-in | Chords |
|---|---|
| `gui.HotKeys.OnSelectAll` | Ctrl+A |
| `gui.HotKeys.OnCopy` | Ctrl+C |
| `gui.HotKeys.OnPaste` | Ctrl+V |
| `gui.HotKeys.OnCut` | Ctrl+X |
| `gui.HotKeys.OnUndo` | Ctrl+Z |
| `gui.HotKeys.OnRedo` | Ctrl+Y, Ctrl+Shift+Z |
| `ToggleTaskManager` (system add-on) | Ctrl+\` |

Key names follow the [LÖVE KeyConstant](https://love2d.org/wiki/KeyConstant) list
(`"lctrl"`, `"rshift"`, `"escape"`, `"f1"`, …).

---

## 8. Gamepad / joystick events

Per-object stick-direction events exist for every element (Visual class):

```lua
obj.OnLeftStickUp / OnLeftStickDown / OnLeftStickLeft / OnLeftStickRight
obj.OnRightStickUp / OnRightStickDown / OnRightStickLeft / OnRightStickRight
```

> The raw gamepad/joystick signals arrive on `gui.Events.*` — the per-object stick events
> are declared but nothing in the core *fires* them yet; wire them yourself from the
> global events if you need them:

```lua
gui.Events.OnGamepadPressed(function(joy, button) ... end)
```

---

## 9. Bulk wiring with `gui.apply`

`gui.apply(table, obj1, obj2, ...)` sets properties, calls methods, and binds connections
across many objects in one call ([`init.lua` L253–277](../init.lua:253)). It inspects each
key:

| Key form | Meaning | Example |
|---|---|---|
| `C_Name` | bind connection | `C_OnReleased = fn` |
| `I_method` | invoke method with table args | `I_enableDragging = {1}` |
| plain name that *is* a connection | bind | `OnReleased = fn` |
| plain name that is a method | invoke with table args | `run = {fn}` |
| anything else | assign property | `color = c` |

```lua
gui.apply({
    color = {0.2, 0.2, 0.2},
    drawBorder = false,
    I_enableDragging = {gui.MOUSE_PRIMARY},
    I_scaleFont = {0.5},
    OnReleased = function(self) print("clicked", self:getTag()) end,
}, tileA, tileB, tileC)
```

Used extensively by the add-on widgets (number picker, color picker, radio group).

---

## 10. Simulation (synthetic input)

[`core/simulate.lua`](../core/simulate.lua) fires real GUI events for testing and scripted
demos:

```lua
local simulate = require("gui.core.simulate")

simulate:Press(button, x, y)          -- move mouse + fire OnMousePressed
simulate:Release(button, x, y)
simulate.Click(btn)                   -- async: press, tick, release at btn center
simulate.Move(nil, dx, dy, x, y)      -- animated glide, fires OnMouseMoved stream

btn:Press()                           -- called on an object: uses its center
```

Diagrams/uses: automated smoke tests, replaying user flows, AI-driven UI.

---

## 11. Gotchas

Collected quirks worth knowing (cross-referenced with [`gui/fixes.md`](../fixes.md)):

- `OnWheelMoved` passes `(self, dx, dy)` but internally calls an undefined
  `defaultCheck(x, y)` with stray globals — works in practice because `defaultCheck`
  ignores its arguments and reads `love.mouse.getPosition()` itself.
- `OnCreated` on an object checks `self.parent:isDescendantOf(self)`, which reads oddly;
  in practice it fires for descendants created under the object.
- `OnPressed` args are `(self, x, y, button, istouch)` — one fewer than the comment block
  near [L879](../init.lua:879) suggests. Trust the table in §2.
- Textbox `insert` double-advances `cur_pos` for multi-char pastes
  ([`init.lua` L1759–1773](../init.lua:1759)); caret may sit ahead by the paste length.
- Left/Right caret movement has no bounds check against `#text` — the caret can leave the
  string visually; `getTextPosition` clamps on click.
- Connections created with `updater:newConnection()` are **not** auto-destroyed with the
  object unless you register them via `addConnection` (the library does this for its own).
- `obj.OnChanged` on custom widgets (checkbox, textarea) are plain connections created on
  the object — safe to bind with `obj.OnChanged(fn)` and cleaned up on destroy for
  textareas; checkbox connections live on the shared `misc-updater` processor.
