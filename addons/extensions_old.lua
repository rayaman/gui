--[[
    gui_extensions.lua
    ------------------
    Drop-in enhancements for the gui library. Patches bugs, fills gaps,
    and adds new widgets without modifying any original source files.

    USAGE
        require("gui_extensions")   -- after requiring "gui"

    CONTENTS
        BUG FIXES
          1. color arithmetic blue-channel bug
          2. gui:isOnScreen() stub

        NEW WIDGETS
          3.  Checkbox
          4.  RadioGroup
          5.  Slider (horizontal or vertical)
          6.  ProgressBar
          7.  Tooltip
          8.  TextArea (multiline input)

        LAYOUT CONTAINERS
          9.  ListFrame   (auto-stacking vertical/horizontal list)
          10. GridFrame   (fixed-column grid)

        SCROLL FRAME AUTO-SIZING
          11. Auto-measure patch for newScrollFrame content

        EASING LIBRARY
          12. transition.easings  (ease-in/out, cubic, bounce, elastic, back)

        FOCUS MANAGEMENT
          13. gui.focus.*  (set/get focus, OnFocusGained, OnFocusLost per element)

        Z-INDEX / LAYER SYSTEM
          14. gui:setLayer(n) / gui:getLayer()
]]

local gui        = require("gui")
local color      = require("gui.core.color")
local transition = require("gui.elements.transitions")
local multi, thread = require("multi"):init()

local ext = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. BUG FIX: color arithmetic metamethods (blue channel was always c[2])
-- ─────────────────────────────────────────────────────────────────────────────

-- We reach into the metatable that color.new sets on every color table and
-- replace the broken metamethods with correct ones. All existing color objects
-- share this metatable so the fix is retroactive.
do
    local probe = color.new(1, 0, 0)    -- make a throwaway color to get the MT
    local mt    = getmetatable(probe)
    if mt then
        mt.__add = function(a, b) return color.new(a[1]+b[1], a[2]+b[2], a[3]+b[3]) end
        mt.__sub = function(a, b) return color.new(a[1]-b[1], a[2]-b[2], a[3]-b[3]) end
        mt.__mul = function(a, b) return color.new(a[1]*b[1], a[2]*b[2], a[3]*b[3]) end
        mt.__div = function(a, b) return color.new(a[1]/b[1], a[2]/b[2], a[3]/b[3]) end
        mt.__mod = function(a, b) return color.new(a[1]%b[1], a[2]%b[2], a[3]%b[3]) end
        mt.__pow = function(a, b) return color.new(a[1]^b[1], a[2]^b[2], a[3]^b[3]) end
        mt.__unm = function(a)    return color.new(-a[1], -a[2], -a[3]) end
        mt.__eq  = function(a, b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
        mt.__lt  = function(a, b) return a[1]< b[1] and a[2]< b[2] and a[3]< b[3] end
        mt.__le  = function(a, b) return a[1]<=b[1] and a[2]<=b[2] and a[3]<=b[3] end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. BUG FIX: gui:isOnScreen() was an empty stub
-- ─────────────────────────────────────────────────────────────────────────────

function gui:isOnScreen()
    return not self:isOffScreen()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. WIDGET: Checkbox
--
--   local cb = parent:newCheckbox(label, x, y, size, sx, sy, checked)
--
--   Properties  cb.checked  (boolean)
--   Events      cb.OnChanged(function(self, checked) end)
--   Methods     cb:setValue(bool)  cb:toggle()
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newCheckbox(label, x, y, size, sx, sy, checked)
    size = size or 20

    local container = self:newFrame(x, y, 0, size, sx, sy, 0, 0)
    container.drawBorder = false
    container.color      = {0, 0, 0, 0}
    container.visibility = 0

    -- The clickable box
    local box = container:newTextButton("", 0, 0, size, size)
    box:setRoundness(3, 3)
    box.color = color.new("#dddddd")

    -- The checkmark label (drawn inside the box)
    local check = box:newTextLabel("✓", 0, 0, size, size)
    check.align       = gui.ALIGN_CENTER
    check.textColor   = color.new("#ffffff")
    check.visibility  = 0
    check.ignore      = true
    check:setFont(math.floor(size * 0.7))

    -- The text label to the right of the box
    local lbl = container:newTextLabel(label or "", size + 6, 0, 0, size, 0, 0, 1)
    lbl.drawBorder = false
    lbl.color      = {0, 0, 0, 0}
    lbl.visibility = 0
    lbl.textColor  = color.new("#222222")
    lbl.align      = gui.ALIGN_LEFT
    lbl.ignore     = true

    container.OnChanged = multi:newConnection()
    container.checked   = checked or false

    local normalColor  = color.new("#dddddd")
    local checkedColor = color.new("#4a90d9")

    local function refresh()
        if container.checked then
            box.color        = checkedColor
            check.visibility = 1
        else
            box.color        = normalColor
            check.visibility = 0
        end
    end

    function container:setValue(v)
        self.checked = v
        refresh()
        self.OnChanged:Fire(self, self.checked)
    end

    function container:toggle()
        self:setValue(not self.checked)
    end

    box.OnReleased(function()
        container:toggle()
    end)

    refresh()
    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. WIDGET: RadioGroup
--
--   local rg = parent:newRadioGroup(options, x, y, w, itemHeight, sx, sy)
--   -- options: {"Option A", "Option B", ...}
--
--   Properties  rg.selected  (1-based index of the selected option, or nil)
--   Events      rg.OnChanged(function(self, index, label) end)
--   Methods     rg:select(index)
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newRadioGroup(options, x, y, w, itemHeight, sx, sy)
    itemHeight = itemHeight or 28
    local totalH = #options * itemHeight

    local container = self:newFrame(x, y, w or 0, totalH, sx, sy, w and 0 or 1)
    container.drawBorder = false
    container.color      = {0, 0, 0, 0}
    container.visibility = 0

    container.OnChanged = multi:newConnection()
    container.selected  = nil

    local dotSize    = math.floor(itemHeight * 0.55)
    local dotRadius  = math.floor(dotSize / 2)
    local normalBorder   = color.new("#aaaaaa")
    local selectedBorder = color.new("#4a90d9")
    local dotColor       = color.new("#4a90d9")

    local buttons = {}

    for i, optLabel in ipairs(options) do
        local row = container:newFrame(0, (i-1)*itemHeight, 0, itemHeight, 0, 0, 1)
        row.drawBorder = false
        row.color      = {0, 0, 0, 0}
        row.visibility = 0

        -- Outer ring
        local ring = row:newTextButton("", 0, math.floor((itemHeight - dotSize)/2), dotSize, dotSize)
        ring:makeCircle(0, math.floor((itemHeight - dotSize)/2), dotRadius)
        ring.color       = {1, 1, 1}
        ring.borderColor = normalBorder

        -- Inner filled dot (hidden when unselected)
        local innerR = math.floor(dotRadius * 0.5)
        local innerOff = dotRadius - innerR
        local dot = ring:newFrame(innerOff, innerOff, innerR*2, innerR*2)
        dot:makeCircle(innerOff, innerOff, innerR)
        dot.color      = dotColor
        dot.drawBorder = false
        dot.visibility = 0
        dot.ignore     = true

        local lbl = row:newTextLabel(optLabel, dotSize + 8, 0, 0, itemHeight, 0, 0, 1)
        lbl.drawBorder = false
        lbl.color      = {0, 0, 0, 0}
        lbl.visibility = 0
        lbl.textColor  = color.new("#222222")
        lbl.align      = gui.ALIGN_LEFT
        lbl.ignore     = true

        buttons[i] = {ring = ring, dot = dot, label = optLabel}

        local idx = i
        ring.OnReleased(function()
            container:select(idx)
        end)
    end

    function container:select(index)
        -- deselect previous
        if self.selected and buttons[self.selected] then
            local prev = buttons[self.selected]
            prev.ring.borderColor = normalBorder
            prev.dot.visibility   = 0
        end
        self.selected = index
        if buttons[index] then
            local cur = buttons[index]
            cur.ring.borderColor = selectedBorder
            cur.dot.visibility   = 1
        end
        self.OnChanged:Fire(self, index, options[index])
    end

    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. WIDGET: Slider
--
--   local sl = parent:newSlider(min, max, value, x, y, w, h, sx, sy, vertical)
--
--   Properties  sl.value  (current value, clamped to [min,max])
--   Events      sl.OnChanged(function(self, value) end)
--   Methods     sl:setValue(n)   sl:setRange(min, max)
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newSlider(min, max, value, x, y, w, h, sx, sy, vertical)
    min   = min   or 0
    max   = max   or 100
    value = value or min

    local container = self:newFrame(x, y, w or 0, h or (vertical and 0 or 20), sx, sy, w and 0 or 1, h and 0 or 0)
    container.drawBorder = false
    container.color      = {0, 0, 0, 0}
    container.visibility = 0

    -- Track
    local track = container:newFrame(0, 0, 0, 0, 0, 0, 1, 1)
    track.drawBorder = false
    track.color      = color.new("#cccccc")
    if vertical then
        track:setDualDim(math.floor((w or 20)/2)-3, 0, 6, 0, 0, 0, 0, 1)
    else
        track:setDualDim(0, math.floor((h or 20)/2)-3, 0, 6, 0, 0, 1, 0)
    end
    track:setRoundness(3, 3)

    -- Fill (colored part up to the thumb)
    local fill = track:newFrame(0, 0, 0, 0, 0, 0, 0, 1)
    fill.drawBorder = false
    fill.color      = color.new("#4a90d9")
    fill:setRoundness(3, 3)
    if vertical then
        fill:setDualDim(0, 0, 0, 0, 0, 0, 1, 0)  -- will be sized by setValue
    end

    -- Thumb
    local thumbSize = vertical and (w or 20) or (h or 20)
    local thumb = container:newFrame(0, 0, thumbSize, thumbSize)
    thumb:makeCircle(0, 0, math.floor(thumbSize/2))
    thumb.color = color.new("#ffffff")
    thumb.borderColor = color.new("#4a90d9")
    thumb:enableDragging(gui.MOUSE_PRIMARY)
    thumb:respectHierarchy(true)

    container.OnChanged = multi:newConnection()
    container.value     = value
    container._min      = min
    container._max      = max

    local function normalize(v)
        return (v - container._min) / (container._max - container._min)
    end

    local function positionThumb(v)
        local t = normalize(v)
        local ax, ay, aw, ah = container:getAbsolutes()
        if vertical then
            local travel = ah - thumbSize
            local py = travel * (1 - t)  -- 0 = top = max
            thumb:rawSetDualDim(math.floor((aw - thumbSize)/2), math.floor(py))
            fill:setDualDim(0, math.floor(py + thumbSize/2), 0, 0, 0, 0, 1, 1 - t)
        else
            local travel = aw - thumbSize
            local px = travel * t
            thumb:rawSetDualDim(math.floor(px), math.floor((ah - thumbSize)/2))
            fill:setDualDim(0, 0, 0, 0, 0, 0, t, 1)
        end
    end

    function container:setValue(v)
        v = math.max(self._min, math.min(self._max, v))
        self.value = v
        positionThumb(v)
        self.OnChanged:Fire(self, v)
    end

    function container:setRange(newMin, newMax)
        self._min = newMin
        self._max = newMax
        self:setValue(math.max(newMin, math.min(newMax, self.value)))
    end

    -- Drag handling
    thumb.OnDragging(function(self, dx, dy)
        local ax, ay, aw, ah = container:getAbsolutes()
        local t
        if vertical then
            local travel = ah - thumbSize
            if travel <= 0 then return end
            local _, ty = thumb:getAbsolutes()
            local newY = ty - ay + dy
            t = 1 - math.max(0, math.min(1, newY / travel))
        else
            local travel = aw - thumbSize
            if travel <= 0 then return end
            local tx, _ = thumb:getAbsolutes()
            local newX = tx - ax + dx
            t = math.max(0, math.min(1, newX / travel))
        end
        local newVal = container._min + t * (container._max - container._min)
        container:setValue(newVal)
    end)

    -- Click on track to jump
    track.OnReleased(function(self, mx, my)
        local ax, ay, aw, ah = container:getAbsolutes()
        local t
        if vertical then
            t = 1 - math.max(0, math.min(1, (my - ay) / ah))
        else
            t = math.max(0, math.min(1, (mx - ax) / aw))
        end
        local newVal = container._min + t * (container._max - container._min)
        container:setValue(newVal)
    end)

    -- Initial position (after first layout pass)
    container.OnSizeChanged(function() positionThumb(container.value) end)
    container:OnUpdate(function()
        -- only run once to set initial position
        positionThumb(container.value)
        -- replace with no-op after first run
        container.OnUpdate = function() end
    end)

    return container
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. WIDGET: ProgressBar
--
--   local pb = parent:newProgressBar(min, max, value, x, y, w, h, sx, sy)
--
--   Properties  pb.value
--   Methods     pb:setValue(n)   pb:setRange(min, max)
--               pb:setColors(bg, fill)
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newProgressBar(min, max, value, x, y, w, h, sx, sy)
    min   = min   or 0
    max   = max   or 100
    value = value or min

    local bar = self:newFrame(x, y, w or 0, h or 20, sx, sy, w and 0 or 1)
    bar.color = color.new("#cccccc")
    bar:setRoundness(4, 4)

    local fill = bar:newFrame(0, 0, 0, 0, 0, 0, 0, 1)
    fill.drawBorder = false
    fill.color      = color.new("#4a90d9")
    fill:setRoundness(4, 4)

    bar._min   = min
    bar._max   = max
    bar.value  = value

    local function refresh()
        local t = (bar.value - bar._min) / (bar._max - bar._min)
        t = math.max(0, math.min(1, t))
        fill:setDualDim(0, 0, 0, 0, 0, 0, t, 1)
    end

    function bar:setValue(v)
        self.value = math.max(self._min, math.min(self._max, v))
        refresh()
    end

    function bar:setRange(newMin, newMax)
        self._min = newMin
        self._max = newMax
        self:setValue(self.value)
    end

    function bar:setColors(bg, fg)
        if bg then self.color = color.new(bg) end
        if fg then fill.color = color.new(fg) end
    end

    refresh()
    return bar
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. WIDGET: Tooltip
--
--   local tt = gui:newTooltip(text, delay)
--   tt:attach(someElement)   -- show tooltip when hovering someElement
--
--   Or attach inline:
--   gui:attachTooltip(element, text, delay)
--
--   The tooltip lives at the root and always renders on top.
-- ─────────────────────────────────────────────────────────────────────────────

do
    -- Shared tooltip panel (one global instance)
    local _panel, _label
    local _visible = false
    local _timer   = nil

    local function ensurePanel()
        if _panel then return end
        _panel = gui:newFrame(0, 0, 0, 0)
        _panel.color      = color.new("#333333")
        _panel.visibility = 0
        _panel.drawBorder = false
        _panel:setRoundness(4, 4)
        _panel:topStack()

        _label = _panel:newTextLabel("", 6, 4, 0, 0, 0, 0, 1, 1)
        _label.textColor  = color.new("#ffffff")
        _label.drawBorder = false
        _label.color      = {0, 0, 0, 0}
        _label.visibility = 0
        _label.ignore     = true
        _label:setFont(13)
    end

    local function showAt(text, x, y)
        ensurePanel()
        _label.text  = text
        local fw     = _label.font:getWidth(text) + 12
        local fh     = _label.font:getHeight() + 8
        local sw, sh = love.graphics.getDimensions()
        -- keep tooltip on screen
        local px = math.min(x + 14, sw - fw - 4)
        local py = math.min(y + 14, sh - fh - 4)
        _panel:rawSetDualDim(px, py, fw, fh)
        _panel.visibility = 0.92
        _panel:topStack()
        _visible = true
    end

    local function hide()
        if _panel then _panel.visibility = 0 end
        _visible = false
    end

    function gui:attachTooltip(element, text, delay)
        delay = delay or 0.6
        ensurePanel()

        local hoverTimer = nil
        local timerDone  = false

        element.OnEnter(function(self, mx, my)
            timerDone = false
            hoverTimer = 0
        end)

        element.OnMoved(function(self, mx, my)
            if not timerDone then
                -- show once timer expires; track mouse position
                if hoverTimer and hoverTimer >= delay then
                    showAt(text, mx, my)
                    timerDone = true
                end
            end
        end)

        element.OnExit(function()
            hoverTimer = nil
            timerDone  = false
            hide()
        end)

        -- We need a per-frame tick to advance the hover timer.
        -- OnUpdate is on the element itself so it cleans up when the element dies.
        local elapsed = 0
        element:OnUpdate(function(self, dt)
            if hoverTimer ~= nil and not timerDone then
                hoverTimer = hoverTimer + dt
                if hoverTimer >= delay then
                    local mx, my = love.mouse.getPosition()
                    showAt(text, mx, my)
                    timerDone = true
                end
            end
        end)

        element.OnDestroy(function() hide() end)
    end

    -- Standalone tooltip object (attach to multiple targets)
    function gui:newTooltip(text, delay)
        local tt = { text = text, delay = delay or 0.6 }
        function tt:attach(element)
            gui:attachTooltip(element, self.text, self.delay)
        end
        function tt:setText(t)
            self.text = t
        end
        return tt
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. WIDGET: TextArea (multiline input)
--
--   local ta = parent:newTextArea(text, x, y, w, h, sx, sy, sw, sh)
--
--   Properties  ta.text  (string, may contain "\n")
--               ta.readOnly  (boolean, default false)
--   Events      ta.OnChanged(function(self, text) end)
--   Methods     ta:getText()  ta:setText(s)  ta:appendLine(s)
--               ta:scrollToBottom()
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newTextArea(initialText, x, y, w, h, sx, sy, sw, sh)
    -- Outer viewport (clips content)
    local viewport = self:newFrame(x, y, w or 0, h or 0, sx, sy, sw, sh)
    viewport.clipDescendants = true
    viewport.color = color.new("#f9f9f9")
    viewport:setRoundness(3, 3)

    -- Inner content frame (scrolled by offsetting its y)
    local content = viewport:newFrame(2, 2, -4, -4, 0, 0, 1, 0)
    content.drawBorder = false
    content.color      = {0, 0, 0, 0}
    content.visibility = 0

    -- Cursor line rendering happens via a separate frame
    local cursorBar = viewport:newFrame(0, 0, 1, 0)
    cursorBar.color      = color.new("#222222")
    cursorBar.drawBorder = false
    cursorBar.ignore     = true
    cursorBar.visibility = 0

    local lines    = {}
    local lineObjs = {}   -- TextLabel per line
    local LINE_H   = 18
    local scrollY  = 0
    local cursorLine = 1
    local cursorCol  = 0
    local blinkOn    = true
    local blinkTimer = 0
    local BLINK_RATE = 0.5
    local focused    = false

    viewport.OnChanged = multi:newConnection()
    viewport.readOnly  = false

    -- Split a string into lines
    local function splitLines(s)
        local result = {}
        local pos = 1
        while true do
            local nl = s:find("\n", pos, true)
            if nl then
                result[#result + 1] = s:sub(pos, nl - 1)
                pos = nl + 1
            else
                result[#result + 1] = s:sub(pos)
                break
            end
        end
        return result
    end

    -- Join lines back to a single string
    local function joinLines()
        return table.concat(lines, "\n")
    end

    -- Rebuild all line label objects
    local function rebuildLabels()
        for _, obj in ipairs(lineObjs) do
            obj:destroy()
        end
        lineObjs = {}

        for i, lineText in ipairs(lines) do
            local lbl = content:newTextLabel(lineText, 0, (i-1)*LINE_H, 0, LINE_H, 0, 0, 1)
            lbl.drawBorder = false
            lbl.color      = {0, 0, 0, 0}
            lbl.visibility = 0
            lbl.textColor  = color.new("#222222")
            lbl.align      = gui.ALIGN_LEFT
            lbl.ignore     = true
            lbl:setFont(13)
            lineObjs[i] = lbl
        end

        -- Resize content frame to fit all lines
        local totalH = #lines * LINE_H + 4
        content:setDualDim(nil, nil, nil, totalH)
    end

    -- Apply vertical scroll so the cursor stays visible
    local function applyScroll()
        local _, _, _, vh = viewport:getAbsolutes()
        local contentH = #lines * LINE_H + 4
        local maxScroll = math.max(0, contentH - vh)
        scrollY = math.max(0, math.min(scrollY, maxScroll))
        content:rawSetDualDim(2, 2 - scrollY)
    end

    local function ensureCursorVisible()
        local _, _, _, vh = viewport:getAbsolutes()
        local cursorY = (cursorLine - 1) * LINE_H
        if cursorY < scrollY then
            scrollY = cursorY
        elseif cursorY + LINE_H > scrollY + vh then
            scrollY = cursorY + LINE_H - vh
        end
        applyScroll()
    end

    -- Update the cursor bar position
    local function updateCursor()
        if not focused then
            cursorBar.visibility = 0
            return
        end
        local ax, ay = viewport:getAbsolutes()
        local lineText = lines[cursorLine] or ""
        local font = love.graphics.newFont(13)
        local cx = 2 + font:getWidth(lineText:sub(1, cursorCol))
        local cy = 2 + (cursorLine - 1) * LINE_H - scrollY
        cursorBar:rawSetDualDim(cx, cy, 1, LINE_H)
        cursorBar.visibility = blinkOn and 1 or 0
    end

    local function setText(s)
        lines = splitLines(s or "")
        if #lines == 0 then lines = {""} end
        rebuildLabels()
        cursorLine = math.min(cursorLine, #lines)
        cursorCol  = math.min(cursorCol, #lines[cursorLine])
        applyScroll()
        updateCursor()
    end

    function viewport:getText()
        return joinLines()
    end

    function viewport:setText(s)
        setText(s)
        self.OnChanged:Fire(self, joinLines())
    end

    function viewport:appendLine(s)
        lines[#lines + 1] = s
        rebuildLabels()
        applyScroll()
    end

    function viewport:scrollToBottom()
        scrollY = math.huge
        applyScroll()
    end

    -- Insert text at cursor
    local function insertText(s)
        if viewport.readOnly then return end
        local line = lines[cursorLine] or ""
        -- Handle newlines in inserted text
        if s == "\n" then
            local before = line:sub(1, cursorCol)
            local after  = line:sub(cursorCol + 1)
            lines[cursorLine] = before
            table.insert(lines, cursorLine + 1, after)
            cursorLine = cursorLine + 1
            cursorCol  = 0
        else
            lines[cursorLine] = line:sub(1, cursorCol) .. s .. line:sub(cursorCol + 1)
            cursorCol = cursorCol + #s
        end
        rebuildLabels()
        ensureCursorVisible()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    local function deleteBack()
        if viewport.readOnly then return end
        if cursorCol > 0 then
            local line = lines[cursorLine]
            lines[cursorLine] = line:sub(1, cursorCol - 1) .. line:sub(cursorCol + 1)
            cursorCol = cursorCol - 1
        elseif cursorLine > 1 then
            -- merge with previous line
            local prevLine = lines[cursorLine - 1]
            cursorCol = #prevLine
            lines[cursorLine - 1] = prevLine .. lines[cursorLine]
            table.remove(lines, cursorLine)
            cursorLine = cursorLine - 1
        end
        rebuildLabels()
        ensureCursorVisible()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    local function deleteForward()
        if viewport.readOnly then return end
        local line = lines[cursorLine]
        if cursorCol < #line then
            lines[cursorLine] = line:sub(1, cursorCol) .. line:sub(cursorCol + 2)
        elseif cursorLine < #lines then
            lines[cursorLine] = line .. lines[cursorLine + 1]
            table.remove(lines, cursorLine + 1)
        end
        rebuildLabels()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    -- Mouse click to position cursor
    viewport.OnPressed(function(self, mx, my)
        focused = true
        local _, vy = viewport:getAbsolutes()
        local relY = my - vy + scrollY - 2
        cursorLine = math.max(1, math.min(#lines, math.floor(relY / LINE_H) + 1))
        local lineText = lines[cursorLine] or ""
        local font     = love.graphics.newFont(13)
        local _, vx    = viewport:getAbsolutes()
        local relX     = mx - vx - 2
        -- binary-search for cursor column
        local col = 0
        for i = 1, #lineText do
            local w = font:getWidth(lineText:sub(1, i))
            if w > relX then break end
            col = i
        end
        cursorCol = col
        updateCursor()
    end)

    viewport.OnPressedOuter(function()
        focused = false
        updateCursor()
    end)

    -- Keyboard input (only when focused)
    gui.Events.OnTextInputed(function(t)
        if not focused then return end
        insertText(t)
    end)

    gui.Events.OnKeyPressed(function(key)
        if not focused then return end
        if key == "return" or key == "kpenter" then
            insertText("\n")
        elseif key == "backspace" then
            deleteBack()
        elseif key == "delete" then
            deleteForward()
        elseif key == "up" then
            cursorLine = math.max(1, cursorLine - 1)
            cursorCol  = math.min(cursorCol, #(lines[cursorLine] or ""))
            ensureCursorVisible(); updateCursor()
        elseif key == "down" then
            cursorLine = math.min(#lines, cursorLine + 1)
            cursorCol  = math.min(cursorCol, #(lines[cursorLine] or ""))
            ensureCursorVisible(); updateCursor()
        elseif key == "left" then
            if cursorCol > 0 then
                cursorCol = cursorCol - 1
            elseif cursorLine > 1 then
                cursorLine = cursorLine - 1
                cursorCol  = #lines[cursorLine]
            end
            ensureCursorVisible(); updateCursor()
        elseif key == "right" then
            local lineLen = #(lines[cursorLine] or "")
            if cursorCol < lineLen then
                cursorCol = cursorCol + 1
            elseif cursorLine < #lines then
                cursorLine = cursorLine + 1
                cursorCol  = 0
            end
            ensureCursorVisible(); updateCursor()
        elseif key == "home" then
            cursorCol = 0; updateCursor()
        elseif key == "end" then
            cursorCol = #(lines[cursorLine] or ""); updateCursor()
        end
    end)

    -- Scroll wheel
    viewport.OnWheelMoved(function(_, dy)
        scrollY = scrollY - dy * 30
        applyScroll()
        updateCursor()
    end)

    -- Cursor blink
    viewport:OnUpdate(function(self, dt)
        blinkTimer = blinkTimer + dt
        if blinkTimer >= BLINK_RATE then
            blinkTimer = 0
            blinkOn = not blinkOn
            if focused then
                cursorBar.visibility = blinkOn and 1 or 0
            end
        end
    end)

    setText(initialText or "")
    return viewport
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. LAYOUT: ListFrame (auto-stacking container)
--
--   local list = parent:newListFrame(x, y, w, h, sx, sy, sw, sh, opts)
--   opts = { direction = "vertical"|"horizontal", gap = 4, padding = 6 }
--
--   The list watches OnSizeChanged on each child and re-stacks automatically.
--   Methods  list:reflow()   list:setGap(n)   list:setPadding(n)
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newListFrame(x, y, w, h, sx, sy, sw, sh, opts)
    opts = opts or {}
    local direction = opts.direction or "vertical"
    local gap       = opts.gap       or 4
    local padding   = opts.padding   or 0

    local frame = self:newFrame(x, y, w or 0, h or 0, sx, sy, sw, sh)
    frame.drawBorder = false
    frame.color      = {0, 0, 0, 0}
    frame.visibility = 0

    -- Track insertion order separately from frame.children (which can be
    -- reordered by topStack/bottomStack).
    local managed = {}

    local function reflow()
        local cursor = padding
        for _, child in ipairs(managed) do
            if child.visible ~= false then
                local _, _, cw, ch = child:getAbsolutes()
                if direction == "vertical" then
                    child:rawSetDualDim(padding, cursor)
                    cursor = cursor + ch + gap
                else
                    child:rawSetDualDim(cursor, padding)
                    cursor = cursor + cw + gap
                end
            end
        end
        -- Auto-size the frame to fit its content if no fractional scale given
        if (sw or 0) == 0 and direction == "vertical" then
            -- don't auto-resize width; height grows to fit
            frame:rawSetDualDim(nil, nil, nil, cursor + padding - gap)
        elseif (sh or 0) == 0 and direction == "horizontal" then
            frame:rawSetDualDim(nil, nil, cursor + padding - gap)
        end
    end

    frame.reflow = reflow

    function frame:setGap(n)
        gap = n
        reflow()
    end

    function frame:setPadding(n)
        padding = n
        reflow()
    end

    -- Override newFrame etc. on this frame so children auto-register
    local function wrapChild(child)
        managed[#managed + 1] = child
        child.OnSizeChanged(reflow)
        child.OnDestroy(function()
            for i, v in ipairs(managed) do
                if v == child then table.remove(managed, i); break end
            end
            reflow()
        end)
        reflow()
        return child
    end

    -- Intercept common constructors so anything added to this list is tracked.
    -- We do this by wrapping the frame's methods after creation.
    local _newFrame       = frame.newFrame
    local _newTextButton  = frame.newTextButton
    local _newTextLabel   = frame.newTextLabel
    local _newTextBox     = frame.newTextBox
    local _newImageLabel  = frame.newImageLabel
    local _newImageButton = frame.newImageButton
    local _newProgressBar = frame.newProgressBar
    local _newCheckbox    = frame.newCheckbox
    local _newSlider      = frame.newSlider

    function frame:newFrame(...)       return wrapChild(_newFrame(self, ...))       end
    function frame:newTextButton(...)  return wrapChild(_newTextButton(self, ...))  end
    function frame:newTextLabel(...)   return wrapChild(_newTextLabel(self, ...))   end
    function frame:newTextBox(...)     return wrapChild(_newTextBox(self, ...))     end
    function frame:newImageLabel(...)  return wrapChild(_newImageLabel(self, ...))  end
    function frame:newImageButton(...) return wrapChild(_newImageButton(self, ...)) end
    function frame:newProgressBar(...) return wrapChild(_newProgressBar(self, ...)) end
    function frame:newCheckbox(...)    return wrapChild(_newCheckbox(self, ...))    end
    function frame:newSlider(...)      return wrapChild(_newSlider(self, ...))      end

    -- Allow manually registering an externally created child
    function frame:register(child)
        return wrapChild(child)
    end

    reflow()
    return frame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. LAYOUT: GridFrame (fixed-column auto grid)
--
--   local grid = parent:newGridFrame(cols, cellW, cellH, x, y, sx, sy, gap, padding)
--
--   Methods  grid:reflow()   grid:setColumns(n)
--   Children are placed left-to-right, wrapping at `cols` columns.
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newGridFrame(cols, cellW, cellH, x, y, sx, sy, gap, padding)
    cols    = cols    or 3
    cellW   = cellW   or 100
    cellH   = cellH   or 100
    gap     = gap     or 4
    padding = padding or 0

    local totalW = cols * cellW + (cols - 1) * gap + padding * 2
    local frame  = self:newFrame(x or 0, y or 0, totalW, 0, sx, sy)
    frame.drawBorder = false
    frame.color      = {0, 0, 0, 0}
    frame.visibility = 0

    local managed = {}

    local function reflow()
        local row, col = 0, 0
        for _, child in ipairs(managed) do
            local px = padding + col * (cellW + gap)
            local py = padding + row * (cellH + gap)
            child:rawSetDualDim(px, py, cellW, cellH)
            col = col + 1
            if col >= cols then
                col = 0
                row = row + 1
            end
        end
        local rows = math.ceil(#managed / cols)
        frame:rawSetDualDim(nil, nil, totalW, rows * (cellH + gap) - gap + padding * 2)
    end

    frame.reflow = reflow

    function frame:setColumns(n)
        cols   = n
        totalW = cols * cellW + (cols - 1) * gap + padding * 2
        self:rawSetDualDim(nil, nil, totalW)
        reflow()
    end

    local function wrapChild(child)
        managed[#managed + 1] = child
        child.OnDestroy(function()
            for i, v in ipairs(managed) do
                if v == child then table.remove(managed, i); break end
            end
            reflow()
        end)
        reflow()
        return child
    end

    local _newFrame       = frame.newFrame
    local _newTextButton  = frame.newTextButton
    local _newTextLabel   = frame.newTextLabel
    local _newImageLabel  = frame.newImageLabel
    local _newImageButton = frame.newImageButton

    function frame:newFrame(...)       return wrapChild(_newFrame(self, ...))       end
    function frame:newTextButton(...)  return wrapChild(_newTextButton(self, ...))  end
    function frame:newTextLabel(...)   return wrapChild(_newTextLabel(self, ...))   end
    function frame:newImageLabel(...)  return wrapChild(_newImageLabel(self, ...))  end
    function frame:newImageButton(...) return wrapChild(_newImageButton(self, ...)) end

    function frame:register(child) return wrapChild(child) end

    return frame
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. SCROLL FRAME AUTO-SIZING PATCH
--
--   Patches gui:newScrollFrame so the content frame automatically measures its
--   children and grows to fit them. No manual setContentSize() needed.
--
--   The original newScrollFrame is preserved as gui:newScrollFrameRaw if you
--   need the unpatched version.
-- ─────────────────────────────────────────────────────────────────────────────

do
    -- Store the original (defined in addons/system.lua after require)
    -- We wrap it after the module is loaded. Using a post-load hook via
    -- the next iteration of the updater is not practical here, so we patch
    -- directly. If addons.system hasn't been required yet this is a no-op and
    -- the patch is applied lazily on first call.
    local _original

    local function wrap()
        if _original then return end
        _original = gui.newScrollFrame
        if not _original then return end  -- system addon not loaded yet

        gui.newScrollFrameRaw = _original

        gui.newScrollFrame = function(self, x, y, w, h, sx, sy, sw, sh)
            local content = _original(self, x, y, w, h, sx, sy, sw, sh)

            -- After each child is created under content, measure and resize.
            local function measure()
                local maxH = 0
                local maxW = 0
                for _, child in ipairs(content:getChildren()) do
                    local cx, cy, cw, ch = child:getAbsolutes()
                    local _, contentY = content:getAbsolutes()
                    local relBottom = (cy - contentY) + ch
                    local relRight  = (cx - (select(1, content:getAbsolutes()))) + cw
                    if relBottom > maxH then maxH = relBottom end
                    if relRight  > maxW then maxW = relRight  end
                end
                -- Only grow, don't shrink (prevents thrash while items are being added)
                local _, _, curW, curH = content:getAbsolutes()
                if maxH > curH then content:setDualDim(nil, nil, nil, maxH + 4) end
            end

            content.OnCreated(function(child)
                child.OnSizeChanged(measure)
                child.OnDestroy(measure)
                measure()
            end)

            return content
        end
    end

    -- Attempt to patch immediately; if the addon isn't loaded yet this becomes
    -- a one-shot deferred patch triggered on first call.
    wrap()

    -- Deferred fallback: wrap on first call if not already done
    local _deferred = gui.newScrollFrame
    if _deferred == _original or _original == nil then
        gui.newScrollFrame = function(self, ...)
            wrap()  -- try again now that more modules may be loaded
            return gui.newScrollFrame(self, ...)
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. EASING LIBRARY
--
--   Extended transition easings to complement transition.glide.
--
--   USAGE (same pattern as glide):
--
--     local ease = transition.easings
--
--     local t = ease.easeInOut(0, 100, 0.4)()
--     t.OnStep(function(v) panel:setDualDim(v) end)
--     t.OnStop(function()  print("done") end)
--
--   Available:
--     ease.easeIn(start, stop, time)      -- accelerates from start
--     ease.easeOut(start, stop, time)     -- decelerates into stop
--     ease.easeInOut(start, stop, time)   -- smooth S-curve
--     ease.easeInCubic(...)               -- more aggressive acceleration
--     ease.easeOutCubic(...)              -- more aggressive deceleration
--     ease.bounce(start, stop, time)      -- bounces at the end
--     ease.elastic(start, stop, time)     -- overshoots then settles
--     ease.back(start, stop, time)        -- slight pull-back before moving
-- ─────────────────────────────────────────────────────────────────────────────

do
    local easings = {}
    transition.easings = easings

    -- Helper: build a transition from an easing function f(t) where t is 0→1
    local function makeEasing(f)
        return transition:newTransition(function(t, start, stop, time)
            local steps = t.fps * time
            local piece = time / steps
            local range = stop - start
            t.running   = true
            for i = 0, steps do
                if not t.kill then
                    thread.sleep(piece)
                    local progress = i / steps
                    thread.pushStatus(start + f(progress) * range)
                end
            end
            t.running = false
            t.kill    = false
        end)
    end

    easings.easeIn = makeEasing(function(t)
        return t * t
    end)

    easings.easeOut = makeEasing(function(t)
        return t * (2 - t)
    end)

    easings.easeInOut = makeEasing(function(t)
        return t < 0.5 and (2 * t * t) or (-1 + (4 - 2*t) * t)
    end)

    easings.easeInCubic = makeEasing(function(t)
        return t * t * t
    end)

    easings.easeOutCubic = makeEasing(function(t)
        local u = t - 1
        return u * u * u + 1
    end)

    easings.bounce = makeEasing(function(t)
        if t < 1/2.75 then
            return 7.5625 * t * t
        elseif t < 2/2.75 then
            t = t - 1.5/2.75
            return 7.5625 * t * t + 0.75
        elseif t < 2.5/2.75 then
            t = t - 2.25/2.75
            return 7.5625 * t * t + 0.9375
        else
            t = t - 2.625/2.75
            return 7.5625 * t * t + 0.984375
        end
    end)

    easings.elastic = makeEasing(function(t)
        if t == 0 or t == 1 then return t end
        local p = 0.3
        local s = p / 4
        local u = t - 1
        return -(math.pow(2, 10 * u) * math.sin((u - s) * (2 * math.pi) / p))
    end)

    easings.back = makeEasing(function(t)
        local s = 1.70158
        return t * t * ((s + 1) * t - s)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. FOCUS MANAGEMENT
--
--   gui.focus.set(element)       -- programmatically set focus
--   gui.focus.get()              -- returns currently focused element (or nil)
--   gui.focus.clear()            -- clear focus (no element focused)
--   gui.focus.setTabOrder(list)  -- set a list of elements for Tab navigation
--   gui.focus.tabNext()          -- focus the next element in the tab order
--   gui.focus.tabPrev()          -- focus the previous element
--
--   Per-element events (added to every element at creation via OnCreated):
--     element.OnFocusGained(function(self) end)
--     element.OnFocusLost(function(self) end)
--
--   NOTE: gui.focus tracks focus independently of the internal object_focus.
--   It is the public, programmable layer on top.
-- ─────────────────────────────────────────────────────────────────────────────

do
    gui.focus = {}

    local _current  = nil
    local _tabOrder = {}

    -- Attach focus events to every new element
    gui.Events.OnCreated(function(element)
        if not element.OnFocusGained then
            element.OnFocusGained = multi:newConnection()
        end
        if not element.OnFocusLost then
            element.OnFocusLost = multi:newConnection()
        end
    end)

    function gui.focus.set(element)
        if _current == element then return end
        if _current and _current.OnFocusLost then
            _current.OnFocusLost:Fire(_current)
        end
        _current = element
        if element and element.OnFocusGained then
            element.OnFocusGained:Fire(element)
        end
    end

    function gui.focus.get()
        return _current
    end

    function gui.focus.clear()
        gui.focus.set(nil)
    end

    function gui.focus.setTabOrder(list)
        _tabOrder = list
    end

    function gui.focus.tabNext()
        if #_tabOrder == 0 then return end
        local idx = 1
        for i, v in ipairs(_tabOrder) do
            if v == _current then idx = i + 1; break end
        end
        if idx > #_tabOrder then idx = 1 end
        gui.focus.set(_tabOrder[idx])
    end

    function gui.focus.tabPrev()
        if #_tabOrder == 0 then return end
        local idx = #_tabOrder
        for i, v in ipairs(_tabOrder) do
            if v == _current then idx = i - 1; break end
        end
        if idx < 1 then idx = #_tabOrder end
        gui.focus.set(_tabOrder[idx])
    end

    -- Wire Tab / Shift+Tab globally
    gui.Events.OnKeyPressed(function(key)
        if key == "tab" then
            if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
                gui.focus.tabPrev()
            else
                gui.focus.tabNext()
            end
        end
    end)

    -- Keep gui.focus in sync with mouse clicks on interactive elements.
    -- We listen to the global ObjectFocusChanged which fires whenever any
    -- element is pressed.
    gui.Events.OnObjectFocusChanged(function(prev, next)
        gui.focus.set(next)
    end)

    -- Elements that are destroyed should be removed from the tab order
    -- and should lose focus if they currently hold it.
    gui.Events.OnCreated(function(element)
        element.OnDestroy(function(self)
            if _current == self then gui.focus.clear() end
            for i, v in ipairs(_tabOrder) do
                if v == self then table.remove(_tabOrder, i); break end
            end
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. Z-INDEX / LAYER SYSTEM
--
--   obj:setLayer(n)    -- set a numeric z-index (higher = drawn on top)
--   obj:getLayer()     -- returns current layer (default 0)
--
--   The draw order within each parent is sorted by layer every frame.
--   Elements with the same layer retain their insertion order (stable sort).
--   This replaces the need to call topStack() in OnUpdate for persistent
--   ordering requirements.
--
--   NOTE: Sorting the children table every frame is O(n log n) in the number
--   of siblings. For large flat hierarchies, assign layers once and call
--   gui.layers.pause() to skip re-sorting when nothing has changed.
-- ─────────────────────────────────────────────────────────────────────────────

do
    gui.layers = {}
    local _dirty = false  -- set to true when any layer changes

    function gui:setLayer(n)
        self.__layer = n
        _dirty = true
    end

    function gui:getLayer()
        return self.__layer or 0
    end

    -- Stable sort: preserve relative order for equal layers
    local function stableSort(t, lt)
        -- insertion sort (stable and fast for small-to-medium sibling counts)
        for i = 2, #t do
            local key = t[i]
            local j   = i - 1
            while j >= 1 and lt(key, t[j]) do
                t[j + 1] = t[j]
                j = j - 1
            end
            t[j + 1] = key
        end
    end

    local function sortChildren(parent)
        stableSort(parent.children, function(a, b)
            return (a.__layer or 0) < (b.__layer or 0)
        end)
        for _, child in ipairs(parent.children) do
            if #child.children > 0 then
                sortChildren(child)
            end
        end
    end

    function gui.layers.pause()  _dirty = false end
    function gui.layers.resume() _dirty = true  end

    -- Re-sort the tree when layers change. We piggy-back on OnUpdate so this
    -- runs before the draw loop.
    gui:OnUpdate(function(_, dt)
        if not _dirty then return end
        _dirty = false
        sortChildren(gui)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Return the extension table for optional introspection
-- ─────────────────────────────────────────────────────────────────────────────

return ext
