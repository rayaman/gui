-- gui:newNumberPicker — text box flanked by -/+ buttons, with clamping,
-- decimals, scroll-wheel and arrow-key stepping, and typed input sanitising
local shared = require("gui.addons.extensions.shared")
local gui    = shared.gui
local th     = shared.th

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

    picker.color = th.primaryNav
    textbox.color = th.primaryFG

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
        left.textColor  = canDec and th.primaryText or th.primaryNav
        right.textColor = canInc and th.primaryText or th.primaryNav
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
