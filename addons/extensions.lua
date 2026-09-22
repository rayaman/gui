local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local multi, thread = require("multi"):init()
local mediaProc = gui:newProcessor("media-updater")
local miscProc = gui:newProcessor("misc-updater")

local palette = color.newPalette("extensions")
palette:indexColor("white","#ffffff")
palette:indexColor("blue","#10465c")
palette:indexColor("black","#000000")
palette:indexColor("orange","#CC5500")

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh, draggable, th)
    local window = self:newWindow(x, y, w, h, sx, sy, sw, sh, "", draggable, th or theme:new({
        primary     = palette.black,
        primaryDark = palette.blue,
        primaryText = palette.white
    }))
    local video = window:newVideo(source, 0, 0, 0, 0, 0, .05, 1, .75)
    local length = video:getDuration()
    local play_pause = window:newImageButton("gui/assets/play.png",0,0,0,0,.45,.86,0,.14)
    local seek = window:newProgressBar(0,0,0,0,0,.8,1,.05,length*100,0)
    seek:OnProgressUpdated(function(self,_,value, drag)
        if drag then
            local status = video:isPlaying()
            video:seek(value/100)
            if status then
                video:play()
            else
                video:stop()
            end
        end
    end)
    seek:isClickable(true)
    play_pause.square = "h"
    play_pause.isPaused = true
    play_pause:OnReleased(function(self)
        if self.isPaused then
            self:setImage("gui/assets/pause.png")
            video:play()
        else
            self:setImage("gui/assets/play.png")
            video:pause()
        end
        self.isPaused = not self.isPaused
    end)
    
    mediaProc:newThread(function()
        while true do
            thread.hold(function() return video:isPlaying() end)
            local p = video:tell()
            seek:update(p*100)
        end
    end)

    function window:seek(...)
        video.video:seek(...)
    end

    function window:play()
        video:play()
    end

    function window:stop()
        video:stop()
    end

    window:OnClose(function()
        video:pause()
    end)

    return window
end

function gui:newCheckbox(label, x, y, size, sx, sy, checked)
    local checkbox = self:newFrame(x, y, size, size, sx, sy)
    checkbox.color = palette.black
    local border = checkbox:newVisualFrame(noOf(.1,.1,.8,.8))
    border.color = palette.white
    local toggle = border:newFrame(noOf(.3,.3,.4,.4))
    toggle.color = palette.black
    toggle.visible = false

    checkbox:OnReleased(function()
        checkbox:check(not toggle.visible)
    end)
    
    if label ~= "" then
        local text = checkbox:newTextLabel(label, noOf(1.25,0,15,1))
        text:centerFont()
        text:setFont(size-2)
        text.visibility = 0
    end

    function checkbox:check(value)
        toggle.visible = value
        self.OnChanged:Fire(value)
    end

    function checkbox:isChecked()
        return toggle.visible
    end

    function checkbox:getLabel()
        return label or ""
    end

    checkbox.OnChanged = miscProc:newConnection()

    return checkbox
end

function gui:newRadioGroup(options, x, y, sx, sy, size)
    local group = {}
    local rg = self:newFrame()
    local selected

    rg.OnSelectionChanged = miscProc:newConnection()

    for i,v in ipairs(options or {}) do
        table.insert(group,self:newCheckbox(tostring(v),x,y+((i-1)*size+((options.padding or 0)*(i-1))),size,sx,sy))
    end

    gui.apply({
        OnReleased=function(self)
            gui.apply({check={false}},unpack(group))
            self:check(true)
            if selected ~= self then
                rg.OnSelectionChanged:Fire(rg, self)
            end
            selected = self
        end,
    },unpack(group))

    function rg:getSelectedOption()
        return selected
    end

    return rg
end

function gui:newProgressBar(x, y, w, h, sx, sy, sw, sh, count, value)
    local value = value or 0
    local count = count or 100
    local progressbar = self:newFrame(x,y,w,h,sx,sy,sw,sh)
    local fillframe = progressbar:newFrame(2,2,-4,-4,0,0,1,1)
    local fill = fillframe:newFrame(noOf(0, 0, 1, 1))
    local percentDisplay = fillframe:newTextLabel("",noOf(0,0,1,1))
    percentDisplay.align = gui.ALIGN_CENTER
    percentDisplay.textColor = palette.black
    fillframe.visibility = 0
    progressbar.color = palette.black
    fill.color = palette.white
    progressbar.fillframe = fillframe
    progressbar.fill = fill
    progressbar.display = percentDisplay
    progressbar.OnProgressUpdated = miscProc:newConnection()
    percentDisplay.visibility = 0
    local displayPercent = false

    function progressbar:showPercent(bool)
        displayPercent = bool
        if bool then
            miscProc:newThread(function()
                thread.skip(2)
                _,_,_h = percentDisplay:getAbsolutes()
                percentDisplay:setFont(math.floor(h/1.3))
                self:update()
            end)
        end
    end

    function progressbar:isClickable(bool)
        fillframe:respectHierarchy(not bool)
        -- Makes the bar updatable by clicking on it
        fillframe:enableDragging(bool and gui.MOUSE_PRIMARY)
    end

    local calcFunc = function(self, dx, dy, x, y, istouch)
        local sx, sy, sw, sh = self:getAbsolutes()
        if x >= sx and x <= sx + sw then
            progressbar:update((((x - sx)/sw) * count), true)
        end
    end

    fillframe:OnDragStart(calcFunc)
    
    fillframe:OnDragging(calcFunc)

    fillframe:OnPressed(function(self, x, y, dx, dy, istouch)
        calcFunc(self, dx, dy, x, y, istouch)
    end)
    
    percentDisplay:centerFont()
    
    function progressbar:update(v, drag)
        v = v or value
        if v > count then v = count end
        if v < 0 then v = 0 end
        local percent = value/count
        fill:setDualDim(noOf(nil,nil,percent))
        if displayPercent then
            percentDisplay.text = math.floor((percent*100)+.5).. "%"
            
        end
        value = v
        self.OnProgressUpdated:Fire(self, percent, value, drag)
    end

    function progressbar:add(n)
        if value >= count then
            return
        end
        value = value + n
        self:update(value)
    end

    function progressbar:sub(n)
        if value <= 0 then
            return
        end
        value = value - n
        self:update(value)
    end

    function progressbar:max()
        self:update(count)
    end

    function progressbar:min()
        self:update(0)
    end

    function progressbar:half()
        self:update(math.floor(count/2))
    end

    function progressbar:getPercent()
        return math.floor(((value/count)*100)+.5)
    end

    function progressbar:getValue()
        return value
    end

    progressbar:update(value)

    -- to change colors and modify main components
    return progressbar, fill, percentDisplay, fillframe
end

function gui:newNumberPicker(x, y, w, h, sx, sy, sw, sh, opts)
    opts = opts or {}
    opts.value    = opts.value    or 0
    opts.inc      = opts.inc      or 1
    opts.decimals = opts.decimals or 0   -- 0 = integers only
    -- opts.min / opts.max / opts.onChange are optional, leave nil for "no limit"

    local picker = self:newFrame(x, y, w, h, sx, sy, sw, sh)
    picker:setRoundness(6, 6)
    picker.active = false

    
    local leftF   = picker:newFrame(0, 0, 0, 0, 0, 0, .15, 1)
    local left    = leftF:newTextButton("-", 0, 0, 0, 0, 0, 0, 1, 1)
    local rightF  = picker:newFrame(0, 0, 0, 0, .85, 0, .15, 1)
    local right   = rightF:newTextButton("+", 0, 0, 0, 0, 0, 0, 1, 1)
    local textbox = picker:newTextBox("", 0, 0, 0, 0, .15, 0, .7, 1)

    textbox.blink = false

    gui.apply({
        scaleFont  = {.45},
        centerFont = {},
        run = {function(self)
            if self.text == "-" or self.text == "+" then
                self:centerX(true)
                self:centerY(true)   -- also center vertically, not just horizontally
            end
        end},
        align = gui.ALIGN_CENTER,
    }, textbox, left, right)

    gui.apply({
        visibility = 0,
        drawBorder = false,          -- flat, no boxy outline around the arrows
    }, left, right, leftF, rightF)

    -- ---- value handling ----------------------------------------------

    local function clamp(n)
        if opts.min and n < opts.min then n = opts.min end
        if opts.max and n > opts.max then n = opts.max end
        return n
    end

    local function round(n)
        if opts.decimals > 0 then
            local mult = 10 ^ opts.decimals
            return math.floor(n * mult + 0.5) / mult
        end
        return math.floor(n + 0.5)
    end

    local function format(n)
        if opts.decimals > 0 then
            return string.format("%." .. opts.decimals .. "f", n)
        end
        return tostring(math.floor(n))
    end

    local function updateButtons()
        local canDec = (opts.min == nil) or (opts.value > opts.min)
        local canInc = (opts.max == nil) or (opts.value < opts.max)
        left.active, right.active = canDec, canInc
        left.textColor  = canDec and {0, 0, 0, 1} or {.6, .6, .6, 1}
        right.textColor = canInc and {0, 0, 0, 1} or {.6, .6, .6, 1}
    end

    function picker:setValue(n, silent)
        n = round(clamp(n))
        opts.value = n
        textbox.text = format(n)
        textbox.cur_pos = #textbox.text
        updateButtons()
        if not silent and opts.onChange then opts.onChange(n) end
    end

    function picker:getValue()
        return opts.value
    end

    picker:setValue(opts.value, true)

    left:OnReleased(function() picker:setValue(opts.value - opts.inc) end)
    right:OnReleased(function() picker:setValue(opts.value + opts.inc) end)

    textbox:OnWheelMoved(function(_,dx, dy)
        if dy > 0 then picker:setValue(opts.value + opts.inc)
        elseif dy < 0 then picker:setValue(opts.value - opts.inc) end
    end)

    -- ---- restrict typing to numbers only -------------------------------

    local allowNegative = opts.min == nil or opts.min < 0
    local allowDecimal  = opts.decimals > 0

    local function sanitize(s)
        local out, seenDot = {}, false
        for i = 1, #s do
            local ch = s:sub(i, i)
            if ch:match("%d") then
                out[#out + 1] = ch
            elseif ch == "-" and i == 1 and allowNegative then
                out[#out + 1] = ch
            elseif ch == "." and allowDecimal and not seenDot then
                out[#out + 1] = ch
                seenDot = true
            end
        end
        return table.concat(out)
    end

    local tiRef = gui.Events.OnTextInputed(function(input)
        if gui:getObjectFocus() ~= textbox then return end
        local clean = sanitize(textbox.text)
        if clean ~= textbox.text then
            textbox.text = clean
            textbox.cur_pos = math.min(textbox.cur_pos, #clean)
        end
    end)

    local kpRef = gui.Events.OnKeyPressed(function(key)
        if gui:getObjectFocus() ~= textbox then return end
        if key == "up" then picker:setValue(opts.value + opts.inc)
        elseif key == "down" then picker:setValue(opts.value - opts.inc) end
    end)

    -- re-normalize (round/clamp/reformat) whatever was typed once they
    -- hit enter or click away, so "3." or "-" don't linger as invalid text
    local function commit()
        picker:setValue(tonumber(textbox.text) or opts.value)
    end
    textbox:OnReturn(commit)
    textbox:OnPressedOuter(commit)

    textbox:OnDestroy(function()
        gui.Events.OnTextInputed:Unconnect(tiRef)
        gui.Events.OnKeyPressed:Unconnect(kpRef)
    end)

    return picker
end

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

    local hexLabel = hexFrame:newTextLabel("#", 0, 0, 0, 0, 0, 0, .18, 1)
    hexBox = hexFrame:newTextBox("", 0, 0, 0, 0, .18, 0, .82, 1)
    hexBox.blink = false

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