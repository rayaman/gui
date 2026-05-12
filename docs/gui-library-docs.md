# GUI Library Documentation

A LÖVE2D-based GUI framework with a dual-dimension layout system, event-driven architecture, theming, transitions, and a rich set of built-in widgets.

---

## Table of Contents

1. [Setup & Integration](#1-setup--integration)
2. [The Dual-Dimension Layout System](#2-the-dual-dimension-layout-system)
3. [Core Widget Reference](#3-core-widget-reference)
   - [Frame](#31-frame)
   - [TextLabel](#32-textlabel)
   - [TextButton](#33-textbutton)
   - [TextBox (Input)](#34-textbox-input)
   - [ImageLabel](#35-imagelabel)
   - [ImageButton](#36-imagebutton)
   - [Video](#37-video)
4. [Base Object API](#4-base-object-api)
   - [Positioning & Sizing](#41-positioning--sizing)
   - [Appearance](#42-appearance)
   - [Visibility & Lifecycle](#43-visibility--lifecycle)
   - [Interaction](#44-interaction)
   - [Shape & Form Factor](#45-shape--form-factor)
5. [Events & Connections](#5-events--connections)
   - [Per-Object Events](#51-per-object-events)
   - [Global Events](#52-global-events)
   - [Hotkeys](#53-hotkeys)
6. [Theming](#6-theming)
7. [Color Module](#7-color-module)
8. [Transitions & Animation](#8-transitions--animation)
9. [Add-on Widgets](#9-add-on-widgets)
   - [Window](#91-window)
   - [ScrollFrame](#92-scrollframe)
   - [Slide-in Menu](#93-slide-in-menu)
   - [Video Player](#94-video-player)
10. [Canvas](#10-canvas)
11. [Simulation (Testing)](#11-simulation-testing)
12. [Scheduler Probe (Load Monitoring)](#12-scheduler-probe-load-monitoring)
13. [Task Manager](#13-task-manager)
14. [Tips & Patterns](#14-tips--patterns)

---

## 1. Setup & Integration

Require the library at the top of your project. The library hooks into LÖVE's callbacks automatically.

```lua
local gui = require("gui")

function love.update(dt)
    gui.update(dt)
end

function love.draw()
    gui.draw()
end
```

That is all that is required. The library installs its own hooks for `love.keypressed`, `love.mousepressed`, `love.resize`, etc., so you do not need to forward those manually.

### Creating Additional Processors

The library runs on the `multi` scheduler. If you need background work to integrate with the GUI update cycle, use `gui:newProcessor`:

```lua
local proc = gui:newProcessor("MyProcessor")
proc:newThread(function() ... end)
```

---

## 2. The Dual-Dimension Layout System

Every object's size and position is described by **eight numbers** that combine pixel offsets with fractional (0–1) scale values relative to the parent. This is the library's central concept.

```
setDualDim(x, y, w, h, sx, sy, sw, sh)
```

| Parameter | Meaning |
|-----------|---------|
| `x`  | Pixel offset from parent's left edge |
| `y`  | Pixel offset from parent's top edge |
| `w`  | Pixel width |
| `h`  | Pixel height |
| `sx` | Fractional X position (0 = left, 1 = right of parent) |
| `sy` | Fractional Y position (0 = top, 1 = bottom of parent) |
| `sw` | Fractional width (0 = 0px, 1 = full parent width) |
| `sh` | Fractional height (0 = 0px, 1 = full parent height) |

The resolved absolute values are calculated as:

```
absolute_x = parent.w * sx + x + parent.x
absolute_y = parent.h * sy + y + parent.y
absolute_w = parent.w * sw + w
absolute_h = parent.h * sh + h
```

### Examples

```lua
-- Full-screen frame (fills parent completely)
frame:setDualDim(0, 0, 0, 0,   0, 0, 1, 1)

-- Fixed 200×50 button in the top-left corner
btn:setDualDim(10, 10, 200, 50)

-- Centered horizontally, 300px wide, 5% from the top
panel:setDualDim(-150, 0, 300, 0,   0.5, 0.05, 0, 0.4)
-- sx=0.5 puts the left edge at the parent's midpoint;
-- x=-150 shifts it left by half the panel's own width.

-- Right-aligned sidebar, 20% of parent width, full height
sidebar:setDualDim(0, 0, 0, 0,   0.8, 0, 0.2, 1)

-- Anchored to bottom-right corner, fixed 100×30
btn:setDualDim(-110, -40, 100, 30,   1, 1)
```

### Helper: `fullFrame()`

Sets the object to fill its parent completely (equivalent to `setDualDim(0,0,0,0,0,0,1,1)`).

```lua
frame:fullFrame()
```

### Reading Position

```lua
local x, y, w, h = obj:getAbsolutes()  -- resolved pixel values

local x, y, w, h, sx, sy, sw, sh = obj:getDualDim()  -- raw dual-dim values
```

### Squaring

Setting `obj.square = "w"` forces `h = w` (width-driven square). Setting `obj.square = "h"` forces `w = h` (height-driven square). Useful for icon buttons and circle elements.

---

## 3. Core Widget Reference

All constructors follow the same signature pattern:

```lua
parent:newXxx(x, y, w, h, sx, sy, sw, sh)
```

where `parent` is either `gui` (the root) or another object. Children are drawn on top of and clipped by (if `clipDescendants` is set) their parent.

---

### 3.1 Frame

A plain rectangular container. The base building block.

```lua
local panel = gui:newFrame(x, y, w, h, sx, sy, sw, sh)
```

```lua
-- Example: a full-screen dark overlay
local overlay = gui:newFrame(0, 0, 0, 0, 0, 0, 1, 1)
overlay.color = {0, 0, 0}
overlay.visibility = 0.6
```

**Virtual Frame** — exists in memory and updates but is never drawn. Used to move objects off-screen without destroying them.

```lua
local vframe = gui:newVirtualFrame(...)
```

**Visual Frame** — a frame that does not participate in mouse hit-testing. Children of a visual frame are also non-interactive.

```lua
local display = gui:newVisualFrame(...)
```

---

### 3.2 TextLabel

A non-interactive frame that renders text.

```lua
local label = parent:newTextLabel("Hello, World!", x, y, w, h, sx, sy, sw, sh)
```

**Key properties:**

| Property | Type | Description |
|----------|------|-------------|
| `text` | string | The displayed text |
| `textColor` | color | Text color (default: black) |
| `font` | Font | LÖVE font object |
| `align` | constant | `gui.ALIGN_LEFT`, `gui.ALIGN_CENTER`, or `gui.ALIGN_RIGHT` |
| `textOffsetX/Y` | number | Pixel nudge for text rendering |
| `textScaleX/Y` | number | Scale multiplier for text |
| `textVisibility` | number | 0–1 alpha for text only |

**Font methods:**

```lua
label:setFont(16)                      -- set by size (default font)
label:setFont("fonts/myfont.ttf", 18)  -- set by file + size
label:setFont(myLoveFont)              -- set by existing font object

label:fitFont(minSize, maxSize)        -- auto-fit text to the element's bounds
label:centerFont()                     -- vertically center text within element
```

---

### 3.3 TextButton

An interactive button with text. Automatically shows a hand cursor on hover.

```lua
local btn = parent:newTextButton("Click Me", x, y, w, h, sx, sy, sw, sh)
```

```lua
btn.OnReleased(function(self, x, y, button, istouch)
    print("Button clicked!")
end)
```

Buttons automatically integrate with the theming system inside a `newWindow` — they receive button colors, hover highlights, and the button font.

---

### 3.4 TextBox (Input)

An editable single-line text input field. Gains focus on click and shows a blinking cursor.

```lua
local input = parent:newTextBox("placeholder", x, y, w, h, sx, sy, sw, sh)
```

**Key properties:**

| Property | Type | Description |
|----------|------|-------------|
| `text` | string | Current text value |
| `cur_pos` | number | Cursor position (character index) |
| `blink` | boolean | Whether cursor blinks (default: true) |

**Selection API:**

```lua
input:HasSelection()      -- boolean
input:GetSelection()      -- start, stop (always start <= stop)
input:GetSelectedText()   -- string
input:ClearSelection()
```

**Events:**

```lua
input.OnReturn(function(self, text)
    print("Submitted:", text)
end)
```

**Built-in hotkeys** (active when the textbox has focus):
- `Ctrl+A` — select all
- `Ctrl+C` — copy selection
- `Ctrl+V` — paste
- `Ctrl+X` — cut selection
- `Left/Right` — move cursor
- `Backspace/Delete` — delete character

---

### 3.5 ImageLabel

Displays an image. Supports PNG, JPG, and GIF.

```lua
local img = parent:newImageLabel("path/to/image.png", x, y, w, h, sx, sy, sw, sh)
```

The image is stretched to fill the element's bounds. GIFs animate automatically.

**Changing the image:**

```lua
img:setImage("path/to/other.png")
img:setImage(loveImageObject)
-- Tile from a spritesheet:
img:setImage("spritesheet.png", srcX, srcY, srcW, srcH)
```

**Flipping:**

```lua
img:flip()        -- flip horizontally
img:flip(true)    -- flip vertically
```

**Gradient fill** (applies a gradient image to any frame or image element):

```lua
panel:applyGradient("vertical", color1, color2, color3)
panel:applyGradient("horizontal", {1,0,0,1}, {0,0,1,1})
```

**Pre-loading images into cache:**

```lua
gui.cacheImage(gui, "assets/hero.png")
gui.cacheImage(gui, {"assets/a.png", "assets/b.png"})
```

---

### 3.6 ImageButton

An image that responds to click events. Shows a hand cursor on hover.

```lua
local btn = parent:newImageButton("icon.png", x, y, w, h, sx, sy, sw, sh)

btn.OnReleased(function(self)
    self:setImage("icon_pressed.png")
end)
```

---

### 3.7 Video

Plays a LÖVE-supported video file inside an element.

```lua
local vid = parent:newVideo("movie.ogv", x, y, w, h, sx, sy, sw, sh)
```

**Playback control:**

```lua
vid:play()
vid:pause()
vid:stop()      -- pause + rewind
vid:rewind()
vid:seek(t)     -- seek to time in seconds
vid:tell()      -- returns current time in seconds
vid:getDuration()
vid:setVolume(0.8)
```

**Events:**

```lua
vid.OnVideoFinished(function(self)
    print("Video ended")
end)
```

---

## 4. Base Object API

Every object in the hierarchy inherits the following API.

---

### 4.1 Positioning & Sizing

```lua
obj:setDualDim(x, y, w, h, sx, sy, sw, sh)  -- update position/size; nil preserves current value
obj:getAbsolutes()                             -- returns resolved x, y, w, h in pixels
obj:getDualDim()                               -- returns all 8 raw values
obj:move(dx, dy)                               -- increment pixel offset (fires OnPositionChanged)
obj:size(dx, dy)                               -- increment pixel size (fires OnSizeChanged)
obj:moveInBounds(dx, dy)                       -- move but keep within parent bounds
obj:fullFrame()                                -- shorthand for 100%×100% fill
obj:centerX(true)                              -- auto-center horizontally within parent
obj:centerY(true)                              -- auto-center vertically within parent
```

---

### 4.2 Appearance

```lua
obj.color = {r, g, b}              -- background color (0–1 range)
obj.borderColor = {r, g, b}        -- border color
obj.drawBorder = true/false        -- show/hide border
obj.visibility = 0.8               -- overall opacity 0–1
obj.rotation = 45                  -- rotation in degrees

obj:setRoundness(rx, ry, segments) -- round all corners
obj:setRoundness(rx, ry, seg, "top")    -- round top corners only
obj:setRoundness(rx, ry, seg, "bottom") -- round bottom corners only

obj.shader = myShader              -- apply a LÖVE shader (image elements only)
obj.clipDescendants = true         -- clip child rendering to this element's bounds
```

---

### 4.3 Visibility & Lifecycle

```lua
obj.visible = false   -- hide (and stop receiving events)
obj.active  = false   -- deactivate without hiding

obj:isActive()        -- true if active and not in the virtual tree
obj:isOffScreen()     -- true if fully outside the window

obj:topStack()        -- move to top of parent's draw order (drawn last = on top)
obj:bottomStack()     -- move to bottom of draw order

obj:destroy()         -- remove from tree, disconnect all events, free resources
obj:removeChildren()  -- destroy all children but keep the object itself
```

---

### 4.4 Interaction

```lua
-- Drag support
obj:enableDragging(gui.MOUSE_PRIMARY)    -- enable drag with left mouse button
obj:enableDragging(gui.MOUSE_SECONDARY)  -- enable drag with right button
obj:enableDragging(false)                -- disable dragging

-- Hierarchy hit-testing: only fires events when not occluded by a sibling
obj:respectHierarchy(true)

-- Tag system (used for identifying objects and filtering events)
obj:tag("myTag")          -- set the primary tag (accessible via :getTag())
obj:setTag("category")    -- set an arbitrary tag key
obj:hasTag("category")    -- boolean
obj:parentHasTag("visual") -- checks the ancestor chain

-- Tree queries
obj:getChildren()         -- immediate children table
obj:getAllChildren()       -- flat list of all visible descendants
obj:isDescendantOf(other) -- boolean
obj:canPress(mx, my)      -- boolean: would a click at mx,my hit this object?

-- Cloning
local copy = obj:clone()
local copy = obj:clone({copyTo = parent, connections = true})
```

---

### 4.5 Shape & Form Factor

By default elements are rectangles. You can change an element's form factor:

```lua
-- Circle
obj:makeCircle(x, y, radius, sx, sy, sr, segments)

-- Arc
obj:makeArc(arcType, x, y, radius, sx, sy, sr, angle1, angle2, segments)
-- arcType is a LÖVE arc type string: "open", "closed", or "pie"
```

The `formFactor` property can also be set directly:

```lua
obj.formFactor = gui.FORM_RECTANGLE  -- default
obj.formFactor = gui.FORM_CIRCLE
obj.formFactor = gui.FORM_ARC
```

---

## 5. Events & Connections

The library uses the `multi` connection system. Connections are called with the syntax:

```lua
obj.OnSomeEvent(function(self, ...)
    -- handler
end)
```

Multiple handlers can be attached to a single event. Connections can be combined:

```lua
-- OR: fires the handler if either event fires
(obj.OnReleased + obj.OnReleasedOuter)(function() ... end)

-- AND: fires the handler only when both have fired
(conn1 * conn2)(function() ... end)
```

---

### 5.1 Per-Object Events

| Event | Arguments | Description |
|-------|-----------|-------------|
| `OnPressed` | `self, x, y, dx, dy, istouch` | Mouse pressed inside the element |
| `OnReleased` | `self, x, y, button, istouch, presses` | Mouse released inside the element |
| `OnReleasedOuter` | same | Released after a press, but outside the element |
| `OnReleasedOther` | same | Released with no previous press on this element |
| `OnPressedOuter` | `self, x, y, button, istouch, presses` | Pressed outside this element |
| `OnEnter` | `self, x, y` | Mouse moved onto the element |
| `OnExit` | `self, x, y` | Mouse moved off the element |
| `OnMoved` | `self, x, y, dx, dy, istouch` | Mouse moved while over the element |
| `OnDragStart` | `self, dx, dy, x, y, istouch` | Drag began |
| `OnDragging` | `self, dx, dy, x, y, istouch` | Drag in progress |
| `OnDragEnd` | `self, dx, dy, x, y, istouch, presses` | Drag ended |
| `OnWheelMoved` | `x, y` | Scroll wheel moved while cursor is over element |
| `OnSizeChanged` | `self, ...` | Element size changed |
| `OnPositionChanged` | `self, ...` | Element position changed |
| `OnDestroy` | `self` | Element is being destroyed |
| `OnCreated` | `element` | Fires for any descendant created under this element |
| `OnLoad` | — | Fires once when the element is first set up |
| `OnUpdate` | `self, dt` | Fires every update frame |

**Gamepad / joystick events** are also available on every object:

```lua
obj.OnLeftStickUp / Down / Left / Right
obj.OnRightStickUp / Down / Left / Right
```

**TextLabel / TextButton / TextBox extras:**

```lua
obj.OnFontUpdated(function(self) end)  -- font changed
input.OnReturn(function(self, text) end) -- Enter key pressed in textbox
```

**Video extras:**

```lua
vid.OnVideoFinished(function(self) end)
```

---

### 5.2 Global Events

All global events live under `gui.Events`:

```lua
gui.Events.OnKeyPressed(function(key, scancode, isrepeat) end)
gui.Events.OnKeyReleased(function(key, scancode) end)
gui.Events.OnTextInputed(function(text) end)
gui.Events.OnMouseMoved(function(x, y, dx, dy, istouch) end)
gui.Events.OnMousePressed(function(x, y, button, istouch, presses) end)
gui.Events.OnMouseReleased(function(x, y, button, istouch, presses) end)
gui.Events.OnWheelMoved(function(x, y) end)
gui.Events.OnResized(function(w, h) end)
gui.Events.OnQuit(function() end)
gui.Events.OnFilesDropped(function(x, y, files) end)
gui.Events.OnFocus(function(focus) end)
gui.Events.OnObjectFocusChanged(function(previous, current) end)

-- Gamepad / joystick
gui.Events.OnGamepadPressed(function(joystick, button) end)
gui.Events.OnGamepadAxis(function(joystick, axis, value) end)
```

---

### 5.3 Hotkeys

Register a hotkey and get back a connection object:

```lua
local conn = obj:setHotKey({"lctrl", "s"})
conn(function(ref)
    print("Save triggered from", ref)
end)
```

Multiple key combinations for the same action:

```lua
local onSave = gui:setHotKey({"lctrl", "s"}) + gui:setHotKey({"rctrl", "s"})
onSave(function() save() end)
```

**Built-in hotkeys:**

| Hotkey | Connection |
|--------|-----------|
| Ctrl+A | `gui.HotKeys.OnSelectAll` |
| Ctrl+C | `gui.HotKeys.OnCopy` |
| Ctrl+V | `gui.HotKeys.OnPaste` |
| Ctrl+X | `gui.HotKeys.OnCut` |
| Ctrl+Z | `gui.HotKeys.OnUndo` |
| Ctrl+Y / Ctrl+Shift+Z | `gui.HotKeys.OnRedo` |
| Ctrl+T | Toggle Task Manager |

---

## 6. Theming

The `theme` module generates consistent color palettes for use with `newWindow` and other themed widgets.

```lua
local theme = require("gui.core.theme")
```

### Creating a Theme

**From explicit colors:**

```lua
local t = theme:new(primaryColor, primaryText, buttonText, buttonNormal, primaryFont, buttonFont)

-- Using hex strings (most convenient):
local t = theme:new("#2d6a9f", "#f0f0f0", "#ffffff")
```

**From a table (preferred for full control):**

```lua
local t = theme:new({
    primary          = "#124559",
    primaryDark      = "#01161E",
    primaryText      = "#AEC3B0",
    buttonNormal     = "#1e6f8a",
    buttonHighlight  = "#2a9bbf",
    buttonText       = "#ffffff",
    textFont         = myFont,
    buttonTextFont   = myBoldFont,
    -- Any extra keys are kept and accessible on the theme object
})
```

**Random harmonious theme:**

```lua
local t = theme:random()              -- any brightness
local t = theme:random(nil, "dark")   -- dark palette
local t = theme:random(nil, "light")  -- light palette
local t = theme:random(12345)         -- reproducible from a seed
print(t:getSeed())                    -- retrieve the seed
print(t:dump())                       -- export as hex string
```

### Theme Properties

| Property | Description |
|----------|-------------|
| `colorPrimary` | Main background color |
| `colorPrimaryDark` | Darker variant (headers, accents) |
| `colorPrimaryText` | Text on primary backgrounds |
| `colorButtonNormal` | Button resting color |
| `colorButtonHighlight` | Button hover color |
| `colorButtonText` | Text on buttons |
| `fontPrimary` | Font for labels |
| `fontButton` | Font for buttons |

### Applying a Theme to a Window

Pass the theme as the last argument to `newWindow` — the window will automatically style all child buttons and labels that are created inside it:

```lua
local win = gui:newWindow(x, y, w, h, "Title", draggable, myTheme)
```

---

## 7. Color Module

The `color` module handles color creation, conversion, and manipulation. All colors in the library are `{r, g, b}` or `{r, g, b, a}` tables with values in the 0–1 range.

```lua
local color = require("gui.core.color")
```

### Creating Colors

```lua
-- Hex string
color.new("#ff5500")
color.new("#ff550088")      -- with alpha

-- CSS-style strings
color.new("rgb(255,85,0)")
color.new("rgba(255,85,0,0.5)")
color.new("hsl(20,100,50)")
color.new("hsla(20,100,50,0.8)")

-- Raw 0–1 floats
color.new(1, 0.33, 0)

-- HSL (hue 0–360, sat 0–100, light 0–100)
color.new(color.hsl(200, 60, 40))

-- HSV (hue 0–360, sat 0–1, val 0–1)
color.new(color.hsv(200, 0.6, 0.8))
```

### Manipulation

```lua
color.lighten(c, amount)         -- amount is 0–1 factor
color.darken(c, amount)
color.saturate(c, amount)
color.desaturate(c, amount)
color.invert(c)
color.lerp(c1, c2, t)            -- blend; t is 0–1
color.mix(c1, c2, t)             -- alias for lerp
```

### Queries

```lua
color.isLight(c)                 -- boolean
color.getAverageLightness(c)     -- 0–1 float
color.rgbToHex(c)                -- returns hex string without "#"
```

### Arithmetic

Color objects support `+`, `-`, `*`, `/`, `%`, `^`, and unary `-` operators, applied component-wise.

### Named Colors

```lua
color.white
color.black
color.red
color.green
color.blue
color.highlighter_blue
-- (and more — check core_color.lua for the full list)
```

---

## 8. Transitions & Animation

The `transitions` module provides smooth interpolated animations for numeric values.

```lua
local transition = require("gui.elements.transitions")
```

### Built-in Transitions

Currently `transition.glide` is provided — a linear glide from a start value to a stop value.

### Using a Transition

A transition factory is created by calling `transition.glide(start, stop, duration)`. This returns a **factory function** that, when called, starts the animation and returns a handle.

```lua
-- Animate a panel sliding in from the left
local slideIn = transition.glide(-200, 0, 0.3)   -- from -200 to 0 in 0.3 seconds

local t = slideIn()   -- start the animation
t.OnStep(function(position)
    panel:setDualDim(position)
end)
t.OnStop(function()
    print("Animation complete")
end)
```

### Overriding Values at Runtime

The factory function accepts optional overrides:

```lua
local t = slideIn(newStart, newStop, newDuration)
```

### Stopping Early

```lua
t.Kill()
```

### Custom Transitions

```lua
local myTransition = transition:newTransition(function(t, start, stop, time)
    -- t.fps is the target FPS for this transition
    local steps = t.fps * time
    local piece = time / steps
    t.running = true
    for i = 0, steps do
        if not t.kill then
            thread.sleep(piece)
            -- push the current interpolated value as a status update
            thread.pushStatus(start + i * ((stop - start) / steps))
        end
    end
    t.running = false
    t.kill = false
end)
```

### Changing FPS

```lua
transition.glide:SetFPS(30)   -- lower for performance-sensitive animations
```

---

## 9. Add-on Widgets

These widgets live in `gui/addons/` and extend the core library.

---

### 9.1 Window

A resizable, draggable floating window with a title bar and a close button.

```lua
require("gui.addons.system")  -- loads the window addon

local win = gui:newWindow(x, y, width, height, "Window Title", draggable, theme)
```

The returned object is the **inner content frame** (inside the title bar). Add children directly to `win`.

**API:**

```lua
win:setTitle("New Title")
win:close()           -- moves the window to the virtual tree (hides it)
win:open()            -- brings the window back to the main tree
win:setTheme(theme)   -- re-apply a different theme
win:getTheme()        -- returns current theme

win.OnClose(function(self)
    -- fires when the X button is pressed
end)
```

**Minimum dimensions:** 200px wide, 100px tall (enforced by resize handles).

**Children auto-styled:** Any `TYPE_BUTTON` or `TYPE_TEXT` created inside the window automatically receives the theme's colors and fonts via the `OnCreated` event.

---

### 9.2 ScrollFrame

A viewport with automatic vertical and horizontal scrollbars. Returns the **content frame** — add children to that.

```lua
require("gui.addons.system")

local content = gui:newScrollFrame(x, y, w, h, sx, sy, sw, sh)
-- Add children to `content`:
local row = content:newFrame(0, rowY, 0, 30, 0, 0, 1)
```

**Scrolling API (on the content frame):**

```lua
content:scrollTo(scrollY, scrollX)    -- jump to absolute scroll position
content:scrollBy(deltaY, deltaX)      -- scroll by a relative amount
content:scrollToTop()
content:scrollToBottom()
content:setScrollSpeed(speed)         -- default is 40 pixels per wheel tick
content:getScrollPos()                -- returns scrollX, scrollY
content:getMaxScroll()                -- returns maxScrollX, maxScrollY
content:setContentSize(width, height) -- explicitly set the content dimensions
```

The scrollbars appear automatically when the content overflows the viewport and hide when it does not.

---

### 9.3 Slide-in Menu

A panel that slides in from the left, right, or top with an animated transition.

```lua
local transition = require("gui.elements.transitions")

local menu = gui:newMenu(title, size, position, trans)
-- title    : string label (required)
-- size     : fractional width/height (e.g. 0.25 for 25% of screen)
-- position : gui.ALIGN_LEFT (default), gui.ALIGN_RIGHT, or gui.ALIGN_CENTER
-- trans    : transition factory (default: transition.glide)
```

**API:**

```lua
menu:Open(true)    -- slide open
menu:Open(false)   -- slide closed
menu:isOpen()      -- boolean
```

**Example:**

```lua
local sidebar = gui:newMenu("Navigation", 0.2, gui.ALIGN_LEFT)

-- Add content to the menu frame
local navBtn = sidebar:newTextButton("Home", 10, 60, 180, 40)

-- Wire toggle
toggleBtn.OnReleased(function()
    sidebar:Open(not sidebar:isOpen())
end)
```

---

### 9.4 Video Player

A pre-built media player widget with play/pause toggle and a seek bar.

```lua
require("gui.addons.players")

gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh)
```

The player creates its own themed window containing the video, a play/pause button, and a progress bar.

---

## 10. Canvas

The `canvas` module creates full-screen root frames.

```lua
local newCanvas = require("gui.core.canvas")

local visual  = newCanvas("visual")   -- visual frame: non-interactive, for backgrounds/effects
local regular = newCanvas()           -- regular interactive frame
```

**Swapping child trees between canvases:**

```lua
visual:swap(frameA, frameB)
-- Exchanges the children of frameA and frameB, re-parenting correctly.
-- Useful for scene transitions.
```

---

## 11. Simulation (Testing)

The `simulate` module lets you programmatically fire mouse events, useful for automated testing or scripted UI demos.

```lua
local simulate = require("gui.core.simulate")
```

### Methods

```lua
-- Immediate (synchronous) mouse press and release
simulate:Press(button, x, y, istouch)
simulate:Release(button, x, y, istouch)

-- Async click (press then release after one scheduler tick)
simulate.Click(obj, button, x, y, istouch)

-- Animated mouse movement
simulate.Move(obj, dx, dy, x, y, istouch)
```

When called on an object (`obj:Press()`), the position defaults to the object's center. When called on `simulate` directly, `x` and `y` default to the current mouse position.

**Example:**

```lua
-- Programmatically click a button
simulate.Click(myButton)

-- Simulate a drag from one point to another
simulate.Move(nil, 100, 0, startX, startY)  -- move 100px to the right
```

---

## 12. Scheduler Probe (Load Monitoring)

Measures scheduler responsiveness using tick-slip detection. Gives a 0–100% load estimate without blocking.

```lua
local probe = require("gui.addons.probe")
probe:install(multi)
```

**Options:**

```lua
probe:install(multi, {
    interval = 0.05,   -- probe fires every N seconds (default: 0.05)
    alpha    = 0.15,   -- EMA smoothing factor 0–1 (default: 0.15, lower = smoother)
    maxLag   = 0.5,    -- seconds of lag that equals 100% load (default: 0.5)
})
```

**Reading load:**

```lua
-- Both are non-blocking — safe to call every frame
local load, lagMs = multi:getLoad()
-- load  : integer 0–100
-- lagMs : smoothed scheduler lag in milliseconds

local lagMs, lagRatio = multi:getSchedulerLag()
```

The probe is automatically installed when `gui:showTaskManager()` is called.

---

## 13. Task Manager

A built-in debug overlay showing all active scheduler tasks, their state, uptime, and priority.

```lua
require("gui.addons.system")
gui:showTaskManager()
```

**Default hotkey:** `Ctrl+T` toggles it open/closed.

The task manager window provides:
- A list of all processors, threads, and tasks with live state
- Pause/Resume buttons for individual tasks
- Kill buttons to terminate tasks
- Clickable priority column to cycle a task's scheduler priority
- An Error Log tab that captures all thread errors in real-time
- A load bar showing current scheduler utilization

---

## 14. Tips & Patterns

### Aspect Ratio Locking

```lua
-- Lock the root to a 16:9 canvas; letterbox on resize
gui:setAspectSize(1920, 1080)
gui.aspect_ratio = true
```

### Clipping Children

```lua
local container = gui:newFrame(x, y, w, h)
container.clipDescendants = true  -- children are scissored to container bounds
```

### Tag-Based Queries

```lua
-- Mark a group of elements and query by tag
for _, child in ipairs(parent:getAllChildren()) do
    if child:hasTag("card") then
        child.color = selectedColor
    end
end
```

### Using `gui.apply` for Bulk Property Setting

`gui.apply` sets properties on multiple objects at once. It understands connection names (`C_` prefix), invoke-style functions (`I_` prefix), and plain properties.

```lua
gui.apply({
    color = {0.2, 0.2, 0.2},
    drawBorder = false,
    I_enableDragging = {gui.MOUSE_PRIMARY},
    OnReleased = function(self) print("clicked", self:getTag()) end,
}, btn1, btn2, btn3)
```

### Stacking Order

Objects are drawn in the order they appear in their parent's `children` table. The last child is drawn on top.

```lua
obj:topStack()     -- draw on top of siblings
obj:bottomStack()  -- draw below all siblings
```

### Responsive Layouts

Combine fractional scale with negative pixel offsets for padding:

```lua
-- A frame inset 10px on all sides within its parent
inner:setDualDim(10, 10, -20, -20, 0, 0, 1, 1)
```

### Intersection Testing

```lua
local ix, iy, iw, ih = obj:intersecpt(x, y, w, h)
-- Returns the overlapping rectangle, or 0,0,0,0 if no overlap
```

### Programmatic Focus

```lua
local focused = gui:getObjectFocus()   -- the currently focused object
```

### OnUpdate (per-frame callback)

```lua
obj:OnUpdate(function(self, dt)
    -- runs every frame while the object exists
    self.rotation = self.rotation + 90 * dt
end)
```
