# Appearance, Shapes & Shaders

How elements are painted: background/border styling, corner roundness, form factors
(rectangle/circle/arc), scissor clipping, per-element shaders, blur, and the built-in
shader library.

---

## Table of Contents

1. [Paint model](#1-paint-model)
2. [Colors & alpha](#2-colors--alpha)
3. [Borders & roundness](#3-borders--roundness)
4. [Form factors: rectangle, circle, arc](#4-form-factors-rectangle-circle-arc)
5. [Rotation, flipping, square lock](#5-rotation-flipping-square-lock)
6. [Shaders](#6-shaders)
7. [Blur](#7-blur)
8. [Effects & post hooks](#8-effects--post-hooks)
9. [Shader library reference](#9-shader-library-reference)

---

## 1. Paint model

Per element, per frame, `draw_handler` ([`init.lua` L2206](../init.lua:2206)) performs:

```
[scissor from clip / roundness] → fill shape (color, visibility)
→ stroke border (borderColor) → type passes (video/image/text/box)
→ post() hook → restore
```

Diagram: [architecture §9](architecture.md#9-the-draw-pipeline).

---

## 2. Colors & alpha

```lua
obj.color        = {r,g,b}        -- background fill (0–1 floats)
obj.borderColor  = color.new("#222222")
obj.visibility   = 0.7            -- alpha for the background+border pass
obj.textVisibility   = 1          -- alpha for text pass only
obj.imageVisibility  = 1          -- alpha for image pass only
obj.videoVisibility  = 1
obj.imageColor   = {1,1,1}        -- tint multiplier for images
obj.textColor    = color.new("#30C5FF")
```

Color objects from [`core/color`](theming-and-color.md) are just `{r,g,b[,a]}` tables —
assign raw tables or color objects interchangeably. `obj:setColor(key, col)` additionally
copies `col[4]` into `obj.visibility` when present.

Layered alpha example — a dim overlay whose text stays fully opaque:

```lua
overlay.color = {0,0,0}
overlay.visibility = 0.6        -- background at 60 %
label.textVisibility = 1        -- label unaffected
```

---

## 3. Borders & roundness

```lua
obj.drawBorder = false                      -- remove the 1px stroke
obj:setRoundness(rx, ry)                    -- rounded corners (default 5,5; 30 segments)
obj:setRoundness(rx, ry, segments)
obj:setRoundness(rx, ry, seg, "top")        -- round TOP corners only (scissor trick)
obj:setRoundness(rx, ry, seg, "bottom")     -- round BOTTOM corners only
obj:setRoundnessDirection(hori, vert)       -- per-axis hints (__rhori/__rvert)
```

`"top"`/`"bottom"` modes are composited with extra fills/lines and a scissor box to fake
half-rounded windows — used by `newWindow`'s header
([`addons/system.lua` L453](../addons/system.lua:453)).

---

## 4. Form factors: rectangle, circle, arc

The `formFactor` selects which primitive fills/strokes the element
([`draw_factor`, init.lua L2194](../init.lua:2194)):

```lua
gui.FORM_RECTANGLE   -- default
gui.FORM_CIRCLE
gui.FORM_ARC
```

Convenience constructors:

```lua
-- Circle: bounding box is derived from the radius
avatar:makeCircle(x, y, radius, sx, sy, sr, segments)

-- Arc: partial ring / pie slice
gauge:makeArc("pie", x, y, radius, sx, sy, sr, angleStart, angleEnd, segments)
-- arc type: "open" | "closed" | "pie" (LÖVE convention)
```

Notes:

- Circle/arc geometry is anchored at the element's top-left; the center is
  `(x + __radius, y + __radius)`.
- `square = "w"`/`"h"` keeps circles round under non-uniform parents.
- For text inside circles the wrap width doubles (`mul = 2`) so lines can use the full
  chord ([draw pass `[2]`](../init.lua:2132)).

---

## 5. Rotation, flipping, square lock

```lua
obj.rotation = 45                 -- degrees; applied to shape, image, and text passes
img:flip()                        -- image pass only: scaleX *= -1
img:flip(true)                    -- scaleY *= -1
obj.square = "w"                  -- layout: force h := w (see layout doc §7)
```

---

## 6. Shaders

Three ways to attach a shader to an element
([`setShader`, init.lua L760–790](../init.lua:760)):

```lua
-- 1) GLSL source string
obj:setShader([[ extern float amount; ... ]])

-- 2) A compiled love Shader object
obj:setShader(love.graphics.newShader(src))

-- 3) A shader *table* from the registry (see §9): named uniforms are
--    auto-sent from the element's own fields or a supplied env table
obj:setShader(gui.SHADERS.grayscale, { amount = 1 })
```

Uniform helpers:

```lua
obj:setShaderUniform("amount", 0.5)     -- ignored if the uniform doesn't exist
obj:shaderTime(true)                    -- auto-feed a `time` uniform each OnUpdate
obj:shaderTime(false)                   -- stop feeding
obj:clearShader()
```

Automatic uniforms: before each draw the pipeline sends `size = {w,h}` and
`position = {x,y}` **if the shader declares them**
([`init.lua` L2238–2246](../init.lua:2238)) — so most built-ins "just work" when the
element resizes.

---

## 7. Blur

The [`shaders/blur.lua`](../shaders/blur.lua) extension adds to **every** element:

```lua
panel:setBlur(8)          -- radius; enables 3-pass gaussian blur (default 8)
panel:setBlurRadius(16)   -- live-adjust
panel:clearBlur()
```

The element and its entire subtree render to offscreen canvases and come back blurred
([diagram, architecture §9](architecture.md#9-the-draw-pipeline)). Descendants of blurred
elements are automatically skipped in the main loop to avoid double-draw.

---

## 8. Effects & post hooks

Two escape hatches into the draw pipeline:

```lua
-- effect: wraps the element's draw call — receives a thunk that performs the
-- normal draw; call it 0..n times, or wrap it in canvas/transform work.
obj.effect = function(drawOriginal)
    love.graphics.push()
    love.graphics.translate(math.sin(clock()) * 2, 0)   -- wobble
    drawOriginal()
    love.graphics.pop()
end

-- post: runs *after* all of the element's own passes — custom overlays.
obj.post = function(self)
    local x, y, w, h = self:getAbsolutes()
    love.graphics.setColor(1,1,1,0.15)
    love.graphics.rectangle("fill", x, y, w, h / 2)     -- glossy sheen
end
```

The color picker uses `post` to paint its SV gradient square
([`extensions.lua` L481](../addons/extensions.lua:481)).

---

## 9. Shader library reference

Every file in [`gui/shaders/`](../shaders) is auto-loaded at require time; `shaders.lua`
registers effects into the **`gui.SHADERS`** namespace and exposes `gui.NewShader` for
your own ([`shaders.lua` L274](../shaders/shaders.lua:274)).

`NewShader` scans the GLSL for `extern` uniforms (ignoring `time`/`size`) and wraps the
shader in a table with a `usage()` help string — enabling the *shader table* form of
`setShader` and uniform validation.

| `gui.SHADERS.<name>` | Uniforms (extern) | Effect |
|---|---|---|
| `glow` | `time` | pulsing brightness (time-driven) |
| `grayscale` | `amount` 0–1 | desaturate (disabled-state look) |
| `chromatic_aberration` | `amount` ~0.003–0.012 | RGB channel split |
| `blur` | `direction {1,0}/{0,1}`, `size` | 9-tap single-axis gaussian |
| `scanlines` | `strength`, `count` | CRT lines |
| `pixelate` | `pixels`, `size` | chunky pixels |
| `vignette` | `intensity`, `smoothness` | darkened edges |
| `hue_shift` | `hue` (radians) | rotate hue |
| `dissolve` ⚠ | `threshold`, `edge_width`, `edge_color` | noise dissolve w/ glowing edge |
| `wave` ⚠ | `time`, `amplitude`, `frequency` | UV distortion |
| `rainbow` ⚠ | `time`, `speed`, `spread` | iridescent overlay |
| `flash` | `flash` 0–1, `flash_color` | hit-flash |
| `invert` | `amount` 0–1 | invert colors |

⚠ = marked "needs testing" upstream.

Usage patterns:

```lua
-- Static effect:
card:setShader(gui.SHADERS.grayscale, { amount = 1 })

-- Animated: time-driven uniforms via shaderTime
card:shaderTime(true)
card:setShader(gui.SHADERS.glow)

-- Per-frame control:
card:OnUpdate(function(self, dt)
    self:setShaderUniform("amount", math.min(1, self.__t + dt))
end)
```

Adding your own:

```lua
gui.NewShader("myEffect", [[ extern float power; vec4 effect(...){...} ]])
-- now: obj:setShader(gui.SHADERS.myEffect, { power = 2 })
-- or:  obj:setShader("shader source string")
```

`GetShaderUniforms(name)` returns `{uniform = type}` for introspection.
