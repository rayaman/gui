# GUI Library Documentation

A component-based UI framework for LÖVE2D (Love2D) built on top of the `multi` concurrency library. The library provides a scene graph with dual-dimension layout, event-driven input handling, and a rich set of built-in element types.

---

## Table of Contents

1. [Setup & Initialization](#setup--initialization)
2. [Core Concepts](#core-concepts)
   - [The Scene Graph](#the-scene-graph)
   - [Dual-Dimension Layout (DualDim)](#dual-dimension-layout-dualdim)
   - [Element Types (Bitmask)](#element-types-bitmask)
   - [Form Factors](#form-factors)
3. [Creating Elements](#creating-elements)
   - [Frames](#frames)
   - [Text Labels](#text-labels)
   - [Text Buttons](#text-buttons)
   - [Text Boxes (Input)](#text-boxes-input)
   - [Image Labels](#image-labels)
   - [Image Buttons](#image-buttons)
   - [Videos](#videos)
4. [Layout & Positioning](#layout--positioning)
5. [Events & Connections](#events--connections)
   - [Global GUI Events](#global-gui-events)
   - [Per-Element Events](#per-element-events)
   - [Hot Keys](#hot-keys)
6. [Element Methods](#element-methods)
   - [Positioning & Sizing](#positioning--sizing)
   - [Visual Properties](#visual-properties)
   - [Hierarchy & Parenting](#hierarchy--parenting)
   - [Utilities](#utilities)
7. [Text Elements](#text-elements)
   - [Font Management](#font-management)
   - [Text Box Internals](#text-box-internals)
8. [Image Elements](#image-elements)
9. [Clipping & Scissor](#clipping--scissor)
10. [Roundness & Shape](#roundness--shape)
11. [Aspect Ratio & Resize Handling](#aspect-ratio--resize-handling)
12. [The `apply` Helper](#the-apply-helper)
13. [Tagging System](#tagging-system)
14. [Cloning Elements](#cloning-elements)
15. [Processors & Threading](#processors--threading)
16. [Drawing Internals](#drawing-internals)
17. [Virtual GUI](#virtual-gui)

---

## Setup & Initialization

```lua
local gui = require("path.to.gui")
```

The library self-initializes on `require`. It hooks into LÖVE's callback system automatically (quit, resize, mouse, keyboard, touch, gamepad, etc.) and starts its internal update and draw processors.

In your `love.update` and `love.draw`:

```lua
function love.update(dt)
    gui.update(dt)
end

function love.draw()
    gui.draw()
end
```

> **Note:** The library hooks LÖVE callbacks via a `Hook` function that wraps any pre-existing handler you define. Define your own `love.*` callbacks **before** `require`-ing the library, or they will be chained automatically.

---

## Core Concepts

### The Scene Graph

The library maintains two root nodes:

| Root | Description |
|---|---|
| `gui` | The main scene root. All elements created with `gui:newXxx()` are parented here by default. |
| `gui.virtual` | A secondary root for off-screen or hidden elements. Children here are not drawn but still have their absolute positions updated. |

Elements form a tree. Every element has a `parent`, a `children` table, and inherits methods from `gui` via `__index`.

### Dual-Dimension Layout (DualDim)

Every element stores its position and size as a **dual dimension**: a combination of a scale component (relative to the parent) and an offset component (absolute pixels).

```
actualX = parent.w * scale.pos.x  + offset.pos.x + parent.x
actualY = parent.h * scale.pos.y  + offset.pos.y + parent.y
actualW = parent.w * scale.size.x + offset.size.x
actualH = parent.h * scale.size.y + offset.size.y
```

Constructor signature for `newDualDim` / all `newXxx` creation functions:

```
x, y, w, h          -- pixel offset for position and size
sx, sy, sw, sh      -- scale (0–1) for position and size
```

Examples:

```lua
-- 200×100 box at pixel position (50, 50):
gui:newFrame(50, 50, 200, 100)

-- Full-screen frame (uses scale only):
local f = gui:newFrame()
f:fullFrame()           -- sets scale size to (1,1) and offset to (0,0,0,0)

-- Half-width, 40px tall, starting at 25% from left:
gui:newFrame(0, 100, 0, 40, 0.25, 0, 0.5, 0)
```

Retrieve the computed screen-space rectangle at any time:

```lua
local x, y, w, h = element:getAbsolutes()
```

### Element Types (Bitmask)

Types are stored as a bitmask so an element can have multiple roles:

| Constant | Value | Meaning |
|---|---|---|
| `gui.TYPE_FRAME` | 0 | Basic container |
| `gui.TYPE_IMAGE` | 1 | Renders an image |
| `gui.TYPE_TEXT` | 2 | Renders text |
| `gui.TYPE_BOX` | 4 | Text input cursor/selection overlay |
| `gui.TYPE_VIDEO` | 8 | Renders a video |
| `gui.TYPE_BUTTON` | 16 | Interactive button (sets hand cursor) |
| `gui.TYPE_ANIM` | 32 | Animation / spritesheet |

Test membership:

```lua
if element:hasType(gui.TYPE_TEXT) then ... end
if element:hasType(gui.TYPE_TEXT + gui.TYPE_BOX) then ... end  -- is a text box
```

### Form Factors

Controls the shape used for both fills and hit-testing:

| Constant | Shape |
|---|---|
| `gui.FORM_RECTANGLE` | Rounded or plain rectangle (default) |
| `gui.FORM_CIRCLE` | Circle; `w` and `h` are set to `2*r` |
| `gui.FORM_ARC` | Arc segment |

---

## Creating Elements

All creation functions are called on a **parent** element (or on `gui` itself for top-level elements). The new element is automatically inserted into the parent's `children` table.

### Frames

A plain container with a background fill and optional border.

```lua
local frame = parent:newFrame(x, y, w, h, sx, sy, sw, sh)
```

A **virtual frame** is parented to `gui.virtual` regardless of the caller:

```lua
local vframe = parent:newVirtualFrame(x, y, w, h, sx, sy, sw, sh)
```

A **visual frame** is a regular frame tagged `"visual"`. Mouse events on it and its descendants are suppressed (useful for purely decorative overlays):

```lua
local overlay = parent:newVisualFrame(x, y, w, h, sx, sy, sw, sh)
```

### Text Labels

A non-interactive text element.

```lua
local label = parent:newTextLabel("Hello world", x, y, w, h, sx, sy, sw, sh)
```

### Text Buttons

A text element that fires pointer events and shows a hand cursor on hover.

```lua
local btn = parent:newTextButton("Click me", x, y, w, h, sx, sy, sw, sh)
btn.OnPressed(function(self, x, y) print("pressed!") end)
```

### Text Boxes (Input)

A single-line text input field.

```lua
local box = parent:newTextBox("default text", x, y, w, h, sx, sy, sw, sh)
box.OnReturn(function(self, text) print("Submitted:", text) end)
```

Keyboard navigation, backspace/delete, selection (click-drag or Ctrl+A), copy/paste/cut, and undo/redo are all handled automatically when the box has focus.

### Image Labels

A non-interactive image element.

```lua
local img = parent:newImageLabel("path/to/image.png", x, y, w, h, sx, sy, sw, sh)
```

GIF files are detected automatically by the `.gif` extension and animated.

### Image Buttons

An image element that fires pointer events and shows a hand cursor on hover.

```lua
local ibtn = parent:newImageButton("icon.png", x, y, w, h, sx, sy, sw, sh)
ibtn.OnPressed(function(self, x, y) print("image clicked") end)
```

### Videos

Wraps a LÖVE `Video` object.

```lua
local vid = parent:newVideo("clip.ogv", x, y, w, h, sx, sy, sw, sh)
vid:play()
vid.OnVideoFinished(function(self) print("done") end)
```

Video methods:

| Method | Description |
|---|---|
| `vid:setVideo(path_or_video)` | Load or swap the video source |
| `vid:play()` | Start playback |
| `vid:pause()` | Pause without rewinding |
| `vid:stop()` | Pause and rewind |
| `vid:rewind()` | Seek to start |
| `vid:seek(seconds)` | Jump to position |
| `vid:tell()` | Return current playback position (seconds) |
| `vid:getDuration()` | Return total duration (seconds) |
| `vid:setVolume(vol)` | Set audio volume (0–1) |
| `vid:getVideo()` | Return the underlying LÖVE Video object |

---

## Layout & Positioning

### Setting the Dual Dimension

```lua
-- Fires OnSizeChanged
element:setDualDim(x, y, w, h, sx, sy, sw, sh)

-- Silent version (no event)
element:rawSetDualDim(x, y, w, h, sx, sy, sw, sh)

-- Read back
local x, y, w, h, sx, sy, sw, sh = element:getDualDim()
```

Pass `nil` for any argument to keep the current value.

### Moving and Resizing

```lua
-- Delta move (fires OnPositionChanged)
element:move(dx, dy)

-- Delta resize (fires OnSizeChanged)
element:size(dw, dh)

-- Move but clamp to parent bounds
element:moveInBounds(dx, dy)
```

### Centering

```lua
element:centerX(true)   -- horizontally center within parent
element:centerY(true)   -- vertically center within parent
```

These attach internal loops that continuously recompute the offset whenever the element's size or position changes.

### Convenience

```lua
element:fullFrame()     -- scale size (1,1), offset (0,0,0,0) — fills parent
```

### Dragging

```lua
element:enableDragging(button)   -- button = love mouse button number (1=left, 2=right, …)
element:enableDragging(nil)      -- disable dragging
```

While dragging, `OnDragging`, `OnDragStart`, and `OnDragEnd` are fired.

### Z-Order

```lua
element:topStack()      -- move to end of parent.children (drawn last = on top)
element:bottomStack()   -- move to front of parent.children (drawn first = behind)
```

---

## Events & Connections

Events use the `multi` connection system. Connect a handler by calling the connection as a function:

```lua
element.OnPressed(function(self, x, y, button, istouch, presses)
    -- ...
end)
```

Connections support composition:

```lua
-- OR: fires when either fires
(connA + connB)(handler)

-- AND: fires only when both conditions are met
(connA * connB)(handler)
```

### Global GUI Events

These fire for the entire application window regardless of which element is focused.

| Event | LÖVE callback | Arguments |
|---|---|---|
| `gui.Events.OnQuit` | `love.quit` | — |
| `gui.Events.OnDirectoryDropped` | `love.directorydropped` | `dir` |
| `gui.Events.OnDisplayRotated` | `love.displayrotated` | `index, orient` |
| `gui.Events.OnFilesDropped` | `love.filedropped` | `file` |
| `gui.Events.OnFocus` | `love.focus` | `focused` |
| `gui.Events.OnMouseFocus` | `love.mousefocus` | `focused` |
| `gui.Events.OnResized` | `love.resize` | `w, h` |
| `gui.Events.OnVisible` | `love.visible` | `visible` |
| `gui.Events.OnKeyPressed` | `love.keypressed` | `key, scancode, isrepeat` |
| `gui.Events.OnKeyReleased` | `love.keyreleased` | `key, scancode` |
| `gui.Events.OnTextEdited` | `love.textedited` | `text, start, length` |
| `gui.Events.OnTextInputed` | `love.textinput` | `text` |
| `gui.Events.OnMouseMoved` | `love.mousemoved` | `x, y, dx, dy, istouch` |
| `gui.Events.OnMousePressed` | `love.mousepressed` | `x, y, button, istouch, presses` |
| `gui.Events.OnMouseReleased` | `love.mousereleased` | `x, y, button, istouch, presses` |
| `gui.Events.OnWheelMoved` | `love.wheelmoved` | `x, y` |
| `gui.Events.OnTouchMoved` | `love.touchmoved` | `id, x, y, dx, dy, pressure` |
| `gui.Events.OnTouchPressed` | `love.touchpressed` | `id, x, y, dx, dy, pressure` |
| `gui.Events.OnTouchReleased` | `love.touchreleased` | `id, x, y, dx, dy, pressure` |
| `gui.Events.OnGamepadPressed` | `love.gamepadpressed` | `joystick, button` |
| `gui.Events.OnGamepadReleased` | `love.gamepadreleased` | `joystick, button` |
| `gui.Events.OnGamepadAxis` | `love.gamepadaxis` | `joystick, axis, value` |
| `gui.Events.OnJoystickAdded` | `love.joystickadded` | `joystick` |
| `gui.Events.OnJoystickRemoved` | `love.joystickremoved` | `joystick` |
| `gui.Events.OnJoystickHat` | `love.joystickhat` | `joystick, hat, dir` |
| `gui.Events.OnJoystickPressed` | `love.joystickpressed` | `joystick, button` |
| `gui.Events.OnJoystickReleased` | `love.joystickreleased` | `joystick, button` |
| `gui.Events.OnCreated` | internal | `element` — fires when any element is created |
| `gui.Events.OnObjectFocusChanged` | internal | `old, new` — fires when click focus changes |

### Per-Element Events

These are attached to each element instance. All mouse/pointer events are automatically pre-filtered: they only fire when the element is `active` and (for most events) when the pointer is within the element's bounds.

| Event | Fires when… |
|---|---|
| `OnLoad` | (manual) element is "loaded" — user-defined |
| `OnPressed` | pointer pressed **inside** element |
| `OnPressedOuter` | pointer pressed **outside** element |
| `OnReleased` | pointer released **inside** element |
| `OnReleasedOuter` | pointer released **outside** (but was pressed inside) |
| `OnReleasedOther` | pointer released with no relevant press history |
| `OnDragStart` | drag begins (element must have `enableDragging` set) |
| `OnDragging` | pointer moves while dragging |
| `OnDragEnd` | drag ends |
| `OnEnter` | pointer enters the element bounds |
| `OnExit` | pointer leaves the element bounds |
| `OnMoved` | pointer moves while inside (or while dragging) |
| `OnWheelMoved` | scroll wheel moves while pointer is inside element |
| `OnSizeChanged` | `setDualDim` or `size` called |
| `OnPositionChanged` | `setDualDim` or `move` called |
| `OnDestroy` | element is about to be destroyed |
| `OnCreated` | element was created (forwarded from `gui.Events.OnCreated`) |
| `OnReturn` | (text boxes only) Enter/Return key pressed |
| `OnFontUpdated` | (text elements only) font changed via `setFont` |
| `OnVideoFinished` | (video elements only) video reaches its end |
| `OnLeftStickUp/Down/Left/Right` | gamepad left-stick events |
| `OnRightStickUp/Down/Left/Right` | gamepad right-stick events |

#### Hierarchy Mode

By default events fire if another element is not on top. Call:

```lua
element:respectHierarchy(false) -- events will fire regardless
```

to make `OnPressed`, `OnReleased`, `OnEnter`, and `OnMoved` skip when the element is covered by a sibling.

---

### Hot Keys

Register a keyboard shortcut that fires a connection:

```lua
local conn = element:setHotKey({"lctrl", "s"})   -- returns a connection
conn(function(ref) print("Ctrl+S on", ref) end)
```

You may pass an existing connection as the second argument to reuse it.

#### Built-in Hot Keys

| Hot Key | Trigger |
|---|---|
| `gui.HotKeys.OnSelectAll` | Ctrl+A |
| `gui.HotKeys.OnCopy` | Ctrl+C |
| `gui.HotKeys.OnPaste` | Ctrl+V |
| `gui.HotKeys.OnCut` | Ctrl+X |
| `gui.HotKeys.OnUndo` | Ctrl+Z |
| `gui.HotKeys.OnRedo` | Ctrl+Y / Ctrl+Shift+Z |

These are already wired to the currently-focused text box for standard editing operations.

---

## Element Methods

### Positioning & Sizing

| Method | Description |
|---|---|
| `el:getAbsolutes([transform])` | Returns `x, y, w, h` in screen space. Optional `transform` function is applied to each value. |
| `el:setDualDim(x,y,w,h,sx,sy,sw,sh)` | Set layout, fires `OnSizeChanged`. |
| `el:rawSetDualDim(...)` | Set layout, no event. |
| `el:getDualDim()` | Returns all 8 dual-dim components. |
| `el:move(dx, dy)` | Translate by delta, fires `OnPositionChanged`. |
| `el:size(dw, dh)` | Resize by delta, fires `OnSizeChanged`. |
| `el:moveInBounds(dx, dy)` | Translate while keeping element inside parent. |
| `el:fullFrame()` | Fill parent entirely. |
| `el:centerX(bool)` | Auto-center horizontally. |
| `el:centerY(bool)` | Auto-center vertically. |
| `el:getLocalCords(mx, my)` | Convert screen coordinates to element-local coordinates. |

### Visual Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `color` | `{r,g,b}` | `{0.6, 0.6, 0.6}` | Background fill color |
| `borderColor` | `{r,g,b}` | black | Border color |
| `drawBorder` | boolean | `true` | Whether to draw the border |
| `visibility` | number | `1` | Background alpha (0–1) |
| `rotation` | number | `0` | Rotation in degrees |
| `active` | boolean | `true` | When `false`, element and all descendants ignore input |
| `visible` | boolean | `true` | Controls `getAllChildren` visibility filter |
| `ignore` | boolean | — | When `true`, element is skipped in coverage tests |

Set color (also sets `visibility` if a 4th component is present):

```lua
element:setColor("color", {1, 0, 0, 0.8})
element:setColor("borderColor", {0, 0, 0})
```

Apply a LÖVE shader:

```lua
element.shader = love.graphics.newShader(...)
```

Apply an effect wrapper (called around the draw call):

```lua
element.effect = function(drawFunc)
    love.graphics.push()
    -- setup
    drawFunc()
    love.graphics.pop()
end
```

Apply a post-draw hook:

```lua
element.post = function(self)
    -- called after drawing, inside the same scissor/shader state
end
```

### Hierarchy & Parenting

| Method | Description |
|---|---|
| `el:setParent(newParent)` | Re-parent element. Pass `nil` to detach. |
| `el:getChildren()` | Returns direct children table. |
| `el:getAllChildren([includeHidden])` | Returns all visible descendants recursively. |
| `el:isDescendantOf(obj)` | Returns `true` if `obj` is an ancestor of `el`. |
| `el:topStack()` | Draw on top of siblings. |
| `el:bottomStack()` | Draw behind siblings. |
| `el:destroy()` | Destroy element, its children, and all connections. |
| `el:removeChildren()` | Destroy all children but leave element itself. |
| `el:isActive()` | `true` if `active` and not parented under `gui.virtual`. |
| `el:isOffScreen()` | `true` if element rect is entirely outside screen bounds. |

### Utilities

| Method | Description |
|---|---|
| `el:hasType(t)` | Bitmask type test. |
| `el:canPress(mx, my)` | `true` if point is inside element (respects clip area). |
| `el:isBeingCovered(mx, my)` | `true` if a sibling is in front of this element at the given point. |
| `el:intersecpt(x, y, w, h)` | Returns intersection rect with a given AABB. |
| `el:newThread(func)` | Spawn a coroutine-style thread scoped to this element. |
| `el:getObjectFocus()` | Returns the currently focused element. |
| `el:getProcessor()` | Returns the internal updater processor. |

---

## Text Elements

All text elements (`newTextLabel`, `newTextButton`, `newTextBox`) inherit from `newTextBase`.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `text` | string | — | Displayed string |
| `textColor` | `{r,g,b}` | black | Text color |
| `font` | Font | 12px default | LÖVE Font object |
| `align` | constant | `ALIGN_LEFT` | `gui.ALIGN_LEFT`, `ALIGN_CENTER`, `ALIGN_RIGHT` |
| `textOffsetX/Y` | number | `0` | Additional pixel offset for text drawing |
| `textScaleX/Y` | number | `1` | Scale applied to text rendering |
| `textShearingFactorX/Y` | number | `0` | Shearing factor for text transform |
| `textVisibility` | number | `1` | Text alpha (0–1) |

### Font Management

```lua
-- By size (default font)
element:setFont(14)

-- By path and size
element:setFont("fonts/myfont.ttf", 18)

-- By LÖVE font object
element:setFont(love.graphics.newFont("fonts/myfont.ttf", 18))
```

Automatically resize font to fill element bounds:

```lua
-- Binary-search fit between min and max size
element:fitFont(minSize, maxSize, {scale = 1})
-- Returns bestFont, bestSize
```

Center text vertically inside the element:

```lua
element:centerFont(y_offset)
```

Calculate where the top and bottom of rendered text actually are (pixel offsets within element):

```lua
local top, bottom = element:calculateFontOffset(font, adjust)
```

### Text Box Internals

| Property | Description |
|---|---|
| `cur_pos` | Integer cursor position (0 = before first character) |
| `selection` | `{start, stop}` character indices (may be reversed) |
| `bar_show` | `true` when the cursor bar should be visible (blinks via internal thread) |
| `doSelection` | `true` while a drag-selection is in progress |

Methods:

```lua
box:HasSelection()          -- returns true/false
box:GetSelection()          -- returns start, stop (always start ≤ stop)
box:GetSelectedText()       -- returns selected substring
box:ClearSelection()        -- clear selection state
```

---

## Image Elements

All image elements (`newImageLabel`, `newImageButton`) inherit from `newImageBase`.

### `setImage`

```lua
-- From a file path (PNG, JPG, etc.)
element:setImage("path/to/image.png")

-- GIF animation (auto-detected by extension)
element:setImage("path/to/anim.gif")

-- From a LÖVE Image object
element:setImage(loveImageObject)
```

### Properties

| Property | Description |
|---|---|
| `imageColor` | Tint color applied when drawing |
| `imageVisibility` | Image alpha (0–1) |
| `scaleX / scaleY` | Flip/scale. Negative values flip the axis. |
| `quad` | LÖVE Quad used for rendering (sub-region) |

### Flipping

```lua
element:flip(false)   -- flip horizontally
element:flip(true)    -- flip vertically
```

### Gradient

Apply a gradient as the image of any element:

```lua
element:applyGradient("horizontal", {r,g,b,a}, {r,g,b,a}, ...)
element:applyGradient("vertical",   {r,g,b,a}, {r,g,b,a}, ...)
```

### Image Caching

```lua
-- Pre-load a single image into the cache
gui.cacheImage(gui, "path/to/img.png")

-- Pre-load multiple images; reports progress via OnStatus
gui.cacheImage(gui, {"img1.png", "img2.png"})

-- Tile helper: returns imagedata and quad
local imgdata, quad = gui:getTile("sheet.png", tileX, tileY, tileW, tileH)
```

---

## Clipping & Scissor

Clipping is set on a **parent** and affects all descendants:

```lua
parent.clipDescendants = true
```

During each draw pass, the parent propagates its screen-space rectangle to each child's `__variables.clip`. Children then apply LÖVE's scissor test to avoid drawing outside the parent.

---

## Roundness & Shape

```lua
-- Rounded corners
element:setRoundness(rx, ry, segments, side)
-- rx, ry: x/y radius (default 5)
-- segments: arc segments (default 30)
-- side: "top", "bottom", or true (all corners)

-- Directional override
element:setRoundnessDirection(horizontal, vertical)
```

Circle and arc shapes are set at creation time:

```lua
-- Circle
element:makeCircle(x, y, radius, sx, sy, sr, segments)

-- Arc
element:makeArc(arcType, x, y, radius, sx, sy, sr, startAngle, endAngle, segments)
-- arcType: "open", "closed", or "pie" (passed to love.graphics.arc)
-- Angles in radians
```

---

## Aspect Ratio & Resize Handling

Lock the root GUI to a design resolution:

```lua
gui:setAspectSize(1920, 1080)    -- set design resolution
gui.aspect_ratio = true          -- enable aspect-ratio mode
```

When the window resizes, the library calculates letterbox/pillarbox offsets and adjusts `gui.x`, `gui.y`, `gui.w`, `gui.h` (and the same on `gui.virtual`) so all elements remain proportional.

Disable it:

```lua
gui:setAspectSize(nil, nil)
gui.aspect_ratio = false
```

Utility to compute the scaled size manually:

```lua
local nw, nh, offsetX, offsetY = gui:GetSizeAdjustedToAspectRatio(windowW, windowH)
```

---

## The `apply` Helper

`gui.apply` is a batch property setter that inspects each field name for a prefix:

| Prefix | Meaning |
|---|---|
| `C_` | Connect to the named connection (value = handler function) |
| `I_` | Invoke the named method with args from a table |
| *(none)* | Direct assignment or smart detection (connection vs function vs value) |

```lua
gui.apply({
    color         = {1, 0, 0},
    C_OnPressed   = function(self) print("pressed") end,
    I_setFont     = {"fonts/bold.ttf", 16},
}, buttonA, buttonB, buttonC)
```

---

## Tagging System

Arbitrary string tags can be attached to any element:

```lua
element:setTag("draggable")
element:setTag("ui-panel")

element:hasTag("draggable")        -- true / false (direct tag)
element:parentHasTag("ui-panel")   -- true if any ancestor has the tag
```

The built-in `"visual"` tag suppresses all mouse event connections:

```lua
local deco = parent:newVisualFrame(...)   -- automatically gets "visual" tag
```

---

## Cloning Elements

Deep-copy an element and optionally its connection handlers:

```lua
local copy = element:clone({
    copyTo      = targetParent,   -- parent for the clone (default: gui.virtual)
    connections = true,           -- also copy connection handlers
})
```

`clone` recurses through all children. Connection handlers from the original are **bound** (not moved) to the clone's connections, so both elements remain independently connected.

---

## Processors & Threading

The library uses two internal processors from the `multi` library:

| Processor | Purpose |
|---|---|
| `updater` | Input hooks, hot keys, text-box blink, video completion, image loading |
| `drawer` | Per-frame draw loop, virtual element position pass |

Create a new processor that participates in `gui.update`:

```lua
local proc = gui:newProcessor("MyProcessor")
-- proc is a multi Processor; attach tasks/loops to it normally
```

Spawn a coroutine thread scoped to an element:

```lua
element:newThread(function(self, thread)
    while true do
        thread.sleep(1)
        print("tick", self.text)
    end
end)
```

Attach a per-frame update callback (called every update loop):

```lua
gui:OnUpdate(function(self, dt)
    -- called every frame
end)

element:OnUpdate(function(self, dt)
    -- called every frame with element as self
end)
```

Create a one-shot or reusable function that runs asynchronously:

```lua
local fn = gui.newFunction(function(arg1, arg2)
    -- runs in updater context
end)
fn(arg1, arg2)
```

---

## Drawing Internals

The draw loop iterates `gui:getAllChildren()` each frame and calls `draw_handler` on each element in order (back-to-front).

`draw_handler` does, in order:

1. Compute and cache `child.x/y/w/h` via `getAbsolutes`.
2. Propagate clip rects to descendants if `clipDescendants` is set.
3. Activate shader if present.
4. Apply LÖVE scissor (clip or roundness-based).
5. Fill background with `child.color` and `child.visibility`.
6. Draw border with `child.borderColor`.
7. Handle special roundness sides ("top"/"bottom").
8. Dispatch to type-specific draw functions (video → image → text → box cursor/selection).
9. Call `child:post()` if defined.
10. Remove scissor and shader.

`gui.draw_handler` is exposed publicly so custom renderers can call it directly.

---

## Virtual GUI

`gui.virtual` is a root node whose children are never rendered on screen but still participate in the layout pass (absolute positions are computed). Use it to keep pre-built off-screen components ready to be re-parented:

```lua
-- Create off-screen
local popup = gui.virtual:newFrame(0, 0, 400, 300)

-- Show it by re-parenting
popup:setParent(gui)

-- Hide it again
popup:setParent(gui.virtual)
```

`gui.virtual` shares the same screen dimensions as `gui`, so positions remain correct when an element moves between them.
