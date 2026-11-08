-- gui:newColorPicker — SV square, hue strip, RGB number pickers and hex input.
-- Depends on gui:newNumberPicker (numberpicker.lua), which the loader requires
-- before this file.
local shared  = require("gui.addons.extensions.shared")
local gui     = shared.gui
local palette = shared.palette
local th      = shared.th

-- ---- HSV <-> RGB helpers ----
local function hsvToRgb(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

local function rgbToHsv(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local d = max - min
    local h = 0
    if d ~= 0 then
        if max == r then h = ((g - b) / d) % 6
        elseif max == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h * 60
    end
    local s = (max == 0) and 0 or (d / max)
    return h, s, max
end

local function clampNum(n, lo, hi) return math.max(lo, math.min(hi, n)) end

local function newCornerGradient(tl, tr, br, bl)
    return love.graphics.newMesh({
        {0, 0, 0, 0, tl[1], tl[2], tl[3], tl[4]},
        {1, 0, 0, 0, tr[1], tr[2], tr[3], tr[4]},
        {1, 1, 0, 0, br[1], br[2], br[3], br[4]},
        {0, 1, 0, 0, bl[1], bl[2], bl[3], bl[4]},
    }, "fan")
end

local _whiteFade, _blackFade
local function getFadeImages()
    if not _whiteFade then
        -- opaque white on the left fading to transparent on the right
        _whiteFade = newCornerGradient(
            {1,1,1,1}, {1,1,1,0}, {1,1,1,0}, {1,1,1,1}
        )
        -- transparent at top fading to opaque black at bottom
        _blackFade = newCornerGradient(
            {0,0,0,0}, {0,0,0,0}, {0,0,0,1}, {0,0,0,1}
        )
    end
    return _whiteFade, _blackFade
end

function gui:newColorPicker(x, y, w, h, sx, sy, sw, sh, opts)
    opts = opts or {}
    local r0 = (opts.r or 255) / 255
    local g0 = (opts.g or 0)   / 255
    local b0 = (opts.b or 0)   / 255

    local picker = self:newFrame(x, y, w, h, sx, sy, sw, sh)
    picker.active = false      -- container only; don't compete for focus with its children
    picker.drawBorder = false
    picker.visibility = 1
    picker.color = palette.new("#777777")

    local hue, sat, val = rgbToHsv(r0, g0, b0)
    local hueR, hueG, hueB = hsvToRgb(hue, 1, 1)

    -- ---- Saturation/Value square ----
    local svFrame = picker:newFrame(6, 6, -12, -12, 0, 0, .55, 1)
    svFrame.drawBorder = false
    svFrame.visibility = 0

    local whiteFade, blackFade = getFadeImages()
    svFrame.post = function(self)
    local sx2, sy2, sw2, sh2 = self:getAbsolutes()
        love.graphics.setColor(hueR, hueG, hueB, 1)
        love.graphics.rectangle("fill", sx2, sy2, sw2, sh2)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(whiteFade, sx2, sy2, 0, sw2, sh2)
        love.graphics.setColor(1, 1, 1, .95)
        love.graphics.draw(blackFade, sx2, sy2, 0, sw2, sh2)
        love.graphics.setColor(0, 0, 0, .4)
        love.graphics.rectangle("line", sx2, sy2, sw2, sh2)
        love.graphics.setColor(1, 1, 1, 1)
    end

    local svThumb = svFrame:newFrame(0, 0, 0, 0)
    svThumb:makeCircle(0, 0, 6)
    svThumb.color = {1, 1, 1}
    svThumb.borderColor = {0, 0, 0}
    svThumb.drawBorder = true

    -- ---- Hue strip ----
    local hueSlider = picker:newFrame(0, 6, 0, -12, .57, 0, .10, 1)
    -- applyGradient's "horizontal"/"vertical" naming is backwards from what
    -- you'd expect visually (it names how colors are laid out in the source
    -- image, not the on-screen direction) -- if this renders sideways for
    -- you, just flip the string to "vertical".
    hueSlider:applyGradient("horizontal",
        {1, 0, 0, 1}, {1, 1, 0, 1}, {0, 1, 0, 1},
        {0, 1, 1, 1}, {0, 0, 1, 1}, {1, 0, 1, 1}, {1, 0, 0, 1})
    hueSlider.drawBorder = false

    local hueThumb = hueSlider:newFrame(0, 0, 0, 4, 0, 0, 1, 0)
    hueThumb.color = {1, 1, 1}
    hueThumb.borderColor = {0, 0, 0}
    hueThumb.drawBorder = true

    -- ---- Preview + numeric fields ----
    -- Right-hand column (x .70-1.0) is split into 5 even rows: the preview
    -- swatch, R, G, B, and (new) a hex input at the bottom. h=.184 per row
    -- with a .02 gap between rows fills the 0..1 range exactly.
    local preview = picker:newFrame(6, 6, -12, -6, .70, 0, .30, .184)
    preview:setRoundness(4, 4)

    local rPicker, gPicker, bPicker, hexBox
    palette:indexColor("preview","#000000")
    preview.color = palette.preview
    local function refresh(fireChange)
        local r, g, b = hsvToRgb(hue, sat, val)
        hueR, hueG, hueB = hsvToRgb(hue, 1, 1)

        -- preview.color = {r, g, b}
        palette:reindexColor("preview",r,g,b) -- avoid creating new memory

        local _, _, sw2, sh2 = svFrame:getAbsolutes()
        svThumb:rawSetDualDim(sat * sw2 - 12, (1 - val) * sh2 - 6)

        local _, _, _, hh2 = hueSlider:getAbsolutes()
        hueThumb:rawSetDualDim(nil, (hue / 360) * hh2 - 2)

        local r255 = math.floor(r * 255 + .5)
        local g255 = math.floor(g * 255 + .5)
        local b255 = math.floor(b * 255 + .5)
        if rPicker then
            rPicker:setValue(r255, true)
            gPicker:setValue(g255, true)
            bPicker:setValue(b255, true)
        end
        if hexBox then
            hexBox.text = string.format("%02X%02X%02X", r255, g255, b255)
            hexBox.cur_pos = #hexBox.text
        end

        if fireChange ~= false and opts.onChange then
            opts.onChange(r255, g255, b255)
        end
    end

    local function onRGBEdited()
        local r = rPicker:getValue() / 255
        local g = gPicker:getValue() / 255
        local b = bPicker:getValue() / 255
        hue, sat, val = rgbToHsv(r, g, b)
        refresh(true)
    end

    -- small "R" / "G" / "B" tags to the left of each field, so the row
    -- itself doesn't require memorizing top-to-bottom order
    local rLabel = picker:newTextLabel("R", 0, 6, 0, -6, .70, .204, .08, .184)
    local gLabel = picker:newTextLabel("G", 0, 6, 0, -6, .70, .408, .08, .184)
    local bLabel = picker:newTextLabel("B", 0, 6, 0, -6, .70, .612, .08, .184)

    gui.apply({
        scaleFont  = {.5},
        centerFont = {},
        align      = gui.ALIGN_CENTER,
        drawBorder = false,
        visibility = 0,
    }, rLabel, gLabel, bLabel)
    rLabel.textColor = {.85, .25, .25, 1}
    gLabel.textColor = {.20, .60, .25, 1}
    bLabel.textColor = {.20, .40, .85, 1}

    rPicker = picker:newNumberPicker(0, 0, -6, -6, .78, .204, .22, .184,
        {value = math.floor(r0 * 255 + .5), min = 0, max = 255, onChange = onRGBEdited})
    gPicker = picker:newNumberPicker(0, 0, -6, -6, .78, .408, .22, .184,
        {value = math.floor(g0 * 255 + .5), min = 0, max = 255, onChange = onRGBEdited})
    bPicker = picker:newNumberPicker(0, 0, -6, -6, .78, .612, .22, .184,
        {value = math.floor(b0 * 255 + .5), min = 0, max = 255, onChange = onRGBEdited})

    gui.apply({
        scaleFont={.1}
    },rPicker,gPicker,bPicker)

    -- ---- Hex input (new) ----
    local hexFrame = picker:newFrame(6, 0, -12, -6, .70, .816, .30, .184)
    hexFrame:setRoundness(6, 6)
    hexFrame.color = th.primaryLabel

    local hexLabel = hexFrame:newTextLabel("#", 0, 0, 0, 0, 0, 0, .18, 1)
    hexBox = hexFrame:newTextBox("", 0, 0, 0, 0, .18, 0, .82, 1)
    hexBox.blink = false
    hexBox.color = th.secondaryLabel

    gui.apply({
        scaleFont  = {.4},
        centerFont = {},
        align = gui.ALIGN_CENTER,
    }, hexLabel, hexBox)

    hexLabel.drawBorder = false
    hexLabel.visibility = 0

    -- keep only valid hex digits, max 6 chars (RRGGBB)
    local function sanitizeHex(s)
        local out = {}
        for i = 1, #s do
            local ch = s:sub(i, i)
            if ch:match("%x") then
                out[#out + 1] = ch:upper()
            end
        end
        local clean = table.concat(out)
        if #clean > 6 then clean = clean:sub(1, 6) end
        return clean
    end

    local hexTiRef = gui.Events.OnTextInputed(function(input)
        if gui:getObjectFocus() ~= hexBox then return end
        local clean = sanitizeHex(hexBox.text)
        if clean ~= hexBox.text then
            hexBox.text = clean
            hexBox.cur_pos = math.min(hexBox.cur_pos, #clean)
        end
    end)

    -- accept "RRGGBB" or shorthand "RGB"; anything else just snaps back to
    -- the current color rather than leaving a half-typed value on screen
    local function commitHex()
        local clean = sanitizeHex(hexBox.text)
        if #clean == 3 then
            local expanded = {}
            for i = 1, 3 do
                local c = clean:sub(i, i)
                expanded[#expanded + 1] = c .. c
            end
            clean = table.concat(expanded)
        end
        if #clean == 6 then
            local r255 = tonumber(clean:sub(1, 2), 16)
            local g255 = tonumber(clean:sub(3, 4), 16)
            local b255 = tonumber(clean:sub(5, 6), 16)
            hue, sat, val = rgbToHsv(r255 / 255, g255 / 255, b255 / 255)
        end
        refresh(true)
    end
    hexBox:OnReturn(commitHex)
    hexBox:OnPressedOuter(commitHex)

    hexBox:OnDestroy(function()
        gui.Events.OnTextInputed:Unconnect(hexTiRef)
    end)

    -- ---- drag interaction (same press/move/release pattern the built-in
    -- textbox uses for its own text-selection dragging) ----
    local function setSV(mx, my)
        local sx2, sy2, sw2, sh2 = svFrame:getAbsolutes()
        local lx = clampNum(mx - sx2, 0, sw2)
        local ly = clampNum(my - sy2, 0, sh2)
        sat = sw2 > 0 and (lx / sw2) or 0
        val = sh2 > 0 and (1 - ly / sh2) or 0
        refresh(true)
    end

    local svDragging = false
    svFrame:OnPressed(function(_, mx, my) svDragging = true; setSV(mx, my) end)
    svFrame:OnMoved(function(_, mx, my) if svDragging then setSV(mx, my) end end)
    svFrame:OnReleased(function() svDragging = false end)
    svFrame:OnReleasedOuter(function() svDragging = false end)

    local function setHue(mx, my)
        local _, sy2, _, sh2 = hueSlider:getAbsolutes()
        local ly = clampNum(my - sy2, 0, sh2)
        hue = sh2 > 0 and (ly / sh2) * 360 or 0
        refresh(true)
    end

    local hueDragging = false
    hueSlider:OnPressed(function(_, mx, my) hueDragging = true; setHue(mx, my) end)
    hueSlider:OnMoved(function(_, mx, my) if hueDragging then setHue(mx, my) end end)
    hueSlider:OnReleased(function() hueDragging = false end)
    hueSlider:OnReleasedOuter(function() hueDragging = false end)

    -- ---- public API ----
    function picker:getColor()
        local r, g, b = hsvToRgb(hue, sat, val)
        return math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5)
    end

    function picker:setColor(r255, g255, b255)
        hue, sat, val = rgbToHsv(r255 / 255, g255 / 255, b255 / 255)
        refresh(false)
    end

    refresh(false)
    return picker
end
