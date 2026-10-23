# API Quick Reference

Condensed tables for the whole public surface. Links jump to the deep-dive docs.
Core entries reference [`gui/init.lua`](../init.lua); add-ons reference
[`addons/extensions.lua`](../addons/extensions.lua) (E) or
[`addons/system.lua`](../addons/system.lua) (S).

Legend: *(E)* loaded with `require("gui.addons")` · *(S)* needs
`require("gui.addons.system")` · *(core)* always available.

---

## 1. Module-level (`gui`)

| Entry | Description |
|---|---|
| `gui.update(dt)` | run update processors — call from `love.update` |
| `gui.draw()` | run the draw loop — call from `love.draw` |
| `gui.update/draw` roots `gui.w/h`, `gui.x/y` | root geometry (letterboxed when aspect-locked) |
| `gui:setAspectSize(w, h)` + `gui.aspect_ratio = true` | fixed-design letterboxing |
| `gui:GetSizeAdjustedToAspectRatio(w, h)` | → `nw, nh, offX, offY` |
| `gui:newProcessor(name)` | add a scheduler processor to the update set |
| `gui:getProcessor()` | the UpdateManager processor |
| `gui.newFunction` | create an async function on UpdateManager |
| `gui:newThread(fn)` (on any object) | spawn a named thread owned by the object's type |
| `gui:getObjectFocus()` | currently focused element |
| `gui:setHotKey(keys[, conn])` | register a held-key chord → connection |
| `gui.HotKeys.OnSelectAll/Copy/Paste/Cut/Undo/Redo` | built-in chord connections |
| `gui.apply(table, ...objects)` | bulk set/invoke/bind — see [events §9](events-and-input.md#9-bulk-wiring-with-guiapply) |
| `gui.cacheImage(pathOrList)` | async preload into the image cache |
| `gui.getTile(imagedata, x, y, w, h)` | → `imagedata, quad` |
| `gui.registerExtension(template)` | methods copied onto every new element |
| `gui:extend(c)` | apply extensions to an element (used in `newBase`) |
| `gui.SHADERS.<name>` / `gui.NewShader(name, glsl[, opts])` | shader registry |
| `gui.virtual` | off-screen root (updates, never draws) |
| `gui.Events.*` | global connections — see [events §3](events-and-input.md#3-global-events) |
| `gui.TYPE_FRAME/IMAGE/TEXT/BOX/VIDEO/BUTTON/ANIM` | type bitmask constants |
| `gui.FORM_RECTANGLE/CIRCLE/ARC` | form factors |
| `gui.ALIGN_LEFT/CENTER/RIGHT/JUSTIFY` (1,0,2,3) | text alignment |
| `gui.MOUSE_PRIMARY/SECONDARY/MIDDLE` (1,2,3) | buttons |
| `gui.draw_handler(child[, no_draw, dt])` | manual single-element render |

---

## 2. Constructors

| Call | Returns | Docs |
|---|---|---|
| `parent:newFrame(dd)` | container | [elements §2](elements.md#2-frames) |
| `parent:newVirtualFrame(dd)` | off-screen container | §2 |
| `parent:newVisualFrame(dd)` | mouse-transparent container | §2 |
| `parent:newTextLabel(txt, dd)` | text | [§3.1](elements.md#31-textlabel) |
| `parent:newTextButton(txt, dd)` | interactive text | [§3.2](elements.md#32-textbutton) |
| `parent:newTextBox(txt, dd)` | single-line input | [§3.3](elements.md#33-textbox) |
| `parent:newTextArea(txt, dd)` | multiline editor *(core)* | [§3.4](elements.md#34-textarea-multiline) |
| `parent:newImageLabel(src, dd)` | image/gif | [§4.1](elements.md#41-imagelabel) |
| `parent:newImageButton(src, dd)` | image w/ input | [§4.2](elements.md#42-imagebutton) |
| `parent:newVideo(src, dd)` | video | [§5](elements.md#5-video) |
| `parent:newWindow(x,y,w,h,sx,sy,sw,sh, title, draggable, theme)` (S) | window content frame | [widgets §1](widgets.md#1-window) |
| `parent:newScrollFrame(dd)` (S) | scrollable content frame | [widgets §2](widgets.md#2-scrollframe) |
| `gui:newMessageBox(opts)` (S) | dialog window | [widgets §3](widgets.md#3-messagebox) |
| `parent:newCheckbox(label, x, y, size, sx, sy)` (E) | checkbox | [widgets §4](widgets.md#4-checkbox--radiogroup) |
| `parent:newRadioGroup(options, x, y, sx, sy, size)` (E) | radio group | §4 |
| `parent:newNumberPicker(dd, opts)` (E) | stepper | [widgets §5](widgets.md#5-numberpicker) |
| `gui:newColorPicker(dd, opts)` (E) | HSV picker | [widgets §6](widgets.md#6-colorpicker) |
| `parent:newProgressBar(dd, count, value)` (E) | `bar, fill, label, fillframe` | [widgets §7](widgets.md#7-progressbar) |
| `gui:newVideoPlayer(src, dd, draggable, theme)` (E) | media window | [widgets §8](widgets.md#8-videoplayer) |
| `gui:newFilePicker(title, root, filter, cb)` (S) | file dialog window | [widgets §9](widgets.md#9-filepicker) |
| `gui.OpenSaveDir(root)` (S) | open save dir in OS browser | §9 |
| `gui:showTaskManager()` (S) | scheduler debug window | [widgets §10](widgets.md#10-task-manager) |

`dd` = the eight-value dualDim tail `x, y, w, h, sx, sy, sw, sh`
([layout doc](layout-system.md)). Helper `noOf(sx,sy,sw,sh)` = `nil,nil,nil,nil,sx,sy,sw,sh`.

---

## 3. Base element methods

### Layout

| Method | Description |
|---|---|
| `setDualDim(...8)` / `rawSetDualDim(...8)` | set geometry (with / without `OnSizeChanged`) |
| `getDualDim()` | → 8 raw values |
| `getAbsolutes([transform])` | → resolved `x, y, w, h` |
| `move(dx,dy)` / `size(dw,dh)` | incremental, fires changed events |
| `moveInBounds(dx,dy)` | clamp-movement inside parent |
| `fullFrame()` | fill parent |
| `centerX(bool)` / `centerY(bool)` | live centering |
| `intersecpt(x,y,w,h)` | overlap rect with another box |
| `getLocalCords(mx,my)` | → mouse coords local to element |
| `obj.square = "w"/"h"` | lock square aspect |

### Tree & lifecycle

| Method | Description |
|---|---|
| `getChildren()` / `getAllChildren()` | direct / flat visible descendants |
| `isDescendantOf(obj)` | ancestry test |
| `setParent(p)` | reparent (p nil = detach) |
| `destroy()` / `removeChildren()` | teardown (disconnects events) |
| `topStack()` / `bottomStack()` | draw order among siblings |
| `isActive()` / `isOnScreen()` / `isOffScreen()` | state queries |
| `clone([opt])` | duplicate subtree — [elements §7](elements.md#7-cloning) |

### Appearance

| Method / field | Description |
|---|---|
| `color`, `borderColor`, `drawBorder`, `visibility` | fill & border |
| `rotation` | degrees |
| `setRoundness(rx, ry[, seg, side])` | rounded corners; `side="top"/"bottom"` |
| `makeCircle(x,y,r,sx,sy,sr[,seg])` | circle form |
| `makeArc(tp,x,y,r,sx,sy,sr,a1,a2[,seg])` | arc/pie form |
| `setShader(src|table|obj[, env])`, `clearShader` | shader attach |
| `setShaderUniform(name, ...)`, `shaderTime(bool)` | uniform control |
| `setBlur(r)` / `clearBlur()` / `setBlurRadius(r)` | *(extension)* gaussian blur |
| `clipDescendants = true` | scissor + hit-clip children |
| `obj.effect = fn` / `obj.post = fn` | draw wrappers/hooks |
| `applyGradient(dir, colors...)` | gradient image fill |

### Interaction

| Method | Description |
|---|---|
| `enableDragging(button|false)` | drag enable (default button 2) |
| `respectHierarchy(bool)` | occlusion-aware input |
| `canPress(mx,my)` / `isBeingCovered(mx,my,r)` | hit tests |
| `hasType(t)` | bitmask test |
| `tag(t)` / `setTag` / `hasTag` / `removeTag` / `getTag` | tagging |
| `ancestorHasTag(t)` / `parentHasTag(t)` | ancestry tag queries |
| `addConnection(conn)` | register for auto-cleanup |
| `setHotKey(keys[, conn])` | per-object hotkey |
| `run(fn)` | `fn(self)` — apply-friendly |
| `newProcessor()`, `newThread(fn)` | object-scoped scheduling |

---

## 4. Per-object events

Attach: `obj.OnX(fn)` or `obj:OnX(fn)`. Full semantics & signatures:
[events doc](events-and-input.md#2-per-object-event-table).

`OnPressed` · `OnReleased` · `OnPressedOuter` · `OnReleasedOuter` · `OnReleasedOther` ·
`OnEnter` · `OnExit` · `OnMoved` · `OnWheelMoved` ·
`OnDragStart` · `OnDragging` · `OnDragEnd` ·
`OnSizeChanged` · `OnPositionChanged` · `OnLoad` · `OnDestroy` · `OnCreated` ·
`OnUpdate` (method) · `OnFontUpdated` ·
`OnLeftStickUp/Down/Left/Right` · `OnRightStickUp/Down/Left/Right` (declared, unfired)

Element extras: `OnReturn` (textbox) · `OnVideoFinished` (video) · `OnChanged` (checkbox,
textarea) · `OnSelectionChanged` (radio) · `OnProgressUpdated` (progress bar) ·
`OnClose`/`OnChoice` (window/message box).

---

## 5. Element fields cheat-sheet

| Field | Element(s) | Meaning |
|---|---|---|
| `type` | all | capability bitmask |
| `visible` / `active` / `ignore` | all | draw / event gating |
| `dualDim` | all | raw layout table |
| `x,y,w,h` | all | cached absolutes |
| `text`, `align`, `font`, `textColor`, `textVisibility`, `textScaleX/Y`, `textOffsetX/Y`, `textShearingFactorX/Y`, `adjust` | text | rendering |
| `cur_pos`, `selection`, `blink`, `seek`, `bar_show` | textbox | editing |
| `image`, `quad`, `imageColor`, `imageVisibility`, `scaleX/Y`, `__isGif` | image | rendering |
| `video`, `playing`, `videoColor`, `videoVisibility`, `audioLength` | video | playback |
| `draggable`, `dragging`, `dragbutton`, `pressed`, `entered` | all | interaction state |
| `shader`, `__blur`, `roundness`, `__rx/__ry/__segments`, `formFactor`, `arcType`, `__radius`, `__angleS/E` | all | appearance |
| `parent`, `children`, `tags`, `primaryTag` | all | tree |

---

## 6. Core module functions

| Module | Entry points | Docs |
|---|---|---|
| [`core/color`](../core/color.lua) | `new`, `hsl`, `hsv`, `oklab`, `oklch`, `newPalette`, `getPalette`, `getDefaultPalette`, `lighten`, `darken`, `hueShift`, `rgbToHsl`, `rgbToOklab`, `rgbToOklch`, `rgbToHex`, `isLight`, `getAverageLightness`, `setV3` | [theming](theming-and-color.md) · [Oklch §6.2](theming-and-color.md#62-oklab--oklch) |
| [`core/theme`](../core/theme.lua) | `getTheme`, `setTheme`, `newTheme(ref, opts)`, `presets`, 12 preset methods | [theming §4–5](theming-and-color.md#4-the-theme-module) |
| [`core/font`](../core/font.lua) | `set`, `get`, `evict`, `clear`, `size` | [core-modules §1](core-modules.md#1-font--cached-font-loader) |
| [`core/transitions`](../core/transitions.lua) | `glide`, `newTransition`, handle `OnStep/OnStop/Kill`, `SetFPS/GetFPS` | [§2](core-modules.md#2-transitions--interpolation-engine) |
| [`core/gifloader`](../core/gifloader.lua) | `load`, `Updater`, `update`, `draw`, `play`, `pause`, `reset`, `setFixedFramerate`, `getInfo` | [§3](core-modules.md#3-gifloader--gif-decoder--animator) |
| [`core/canvas`](../core/canvas.lua) | `newCanvas(domain)`, `:swap(a,b)` | [§4](core-modules.md#4-canvas--full-frame-roots) |
| [`core/menus`](../core/menus.lua) | `registerMenu`, `getMenu`, `init`, `hideMenus`, `getCurrentMenu`, `:visible` | [§5](core-modules.md#5-menus--menu-registry) |
| [`core/simulate`](../core/simulate.lua) | `Press`, `Release`, `Click`, `Move` | [§6](core-modules.md#6-simulate--synthetic-input) |
| [`core/probe`](../core/probe.lua) | `install(multi, opts)` → `multi:getLoad()`, `:getSchedulerLag()` | [§7](core-modules.md#7-probe--scheduler-load) |
| [`yaml/builder`](../yaml/builder.lua) | `build`, `buildMany`, `fromString` | [yaml doc](yaml-declarative-ui.md) |
| [`yaml/toyaml`](../yaml/toyaml.lua) | `guiToYaml(obj, opts)` | [yaml §6](yaml-declarative-ui.md#6-serializer-toyaml) |
| [`shaders/shaders`](../shaders/shaders.lua) | `gui.SHADERS.*`, `gui.NewShader`, `GetShaderUniforms` | [shaders §9](appearance-and-shaders.md#9-shader-library-reference) |
| [`shaders/blur`](../shaders/blur.lua) | per-element `setBlur`/`clearBlur`/`setBlurRadius` | [shaders §7](appearance-and-shaders.md#7-blur) |

---

## 7. Constants

```lua
gui.TYPE_FRAME  = 0    gui.FORM_RECTANGLE = 1
gui.TYPE_IMAGE  = 1    gui.FORM_CIRCLE    = 2
gui.TYPE_TEXT   = 2    gui.FORM_ARC       = 3
gui.TYPE_BOX    = 4
gui.TYPE_VIDEO  = 8    gui.ALIGN_CENTER   = 0
gui.TYPE_BUTTON = 16   gui.ALIGN_LEFT     = 1
gui.TYPE_ANIM   = 32   gui.ALIGN_RIGHT    = 2
gui.MOUSE_PRIMARY   = 1   gui.ALIGN_JUSTIFY = 3
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE    = 3
```
