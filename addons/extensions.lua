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

local th = theme:getTheme()

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh, draggable, th)
    local window = self:newWindow{
        x, y, w, h, sx, sy, sw, sh,
        title     = "",
        draggable = draggable,
        theme     = th or {
            primaryBG   = palette.black,
            primaryNav  = palette.blue,
            primaryText = palette.white,
        },
    }
    local video = window.content:newVideo(source, 0, 0, 0, 0, 0, .05, 1, .75)
    local length = video:getDuration()
    local play_pause = window.content:newImageButton("gui/assets/play.png",0,0,0,0,.45,.86,0,.14)
    local seek = window.content:newProgressBar(0,0,0,0,0,.8,1,.05,length*100,0)
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

-- ── newListFrame ──────────────────────────────────────────────────────────────
-- Scrollable single-selection list of rows, with hover / press / selection
-- transitions, animated add and remove, and optional keyboard navigation.
--
--   local box = parent:newListFrame(x, y, w, h, sx, sy, sw, sh, opts)
--
--   opts = {
--     items     = {"One", "Two"} or { {text = "One", value = 1}, ... },
--     rowHeight = 28, gap = 2, scale = .85, align = gui.ALIGN_LEFT,
--     keyboard  = false,       -- Up/Down/PgUp/PgDn/Home/End/Delete when focused
--     animate   = true,        -- enter / exit / selection transitions
--     striped   = false,       -- alternating row fill
--     emptyText = nil,         -- placeholder shown while the list is empty
--     backgroundColor = nil,   -- paints the viewport (default: transparent)
--     selectedColor / hoverColor / stripedColor / textColor / emptyTextColor,
--     onChange(index, value), onDoubleClicked(index, value),
--     onRightClick(index, value, mx, my),
--   }
--
--   box:add(text[, value])            box:insert(i, text[, value])
--   box:setItems(items)               box:remove(i) -> removed value
--   box:removeValue(value) -> index   box:clear([animate])
--   box:select(i[, animate])          box:setSelected(i[, animate])  (no event)
--   box:getSelected() -> index, value box:getItem(i) -> text, value
--   box:getItems() / getItemCount() / indexOf(value) / isEmpty()
--   box:scrollToShow(i)                    box:getRow(i)  (advanced)
--   box:isSettling()                       (transitions in flight)
--   box.OnSelectionChanged            -- :Fire(index, value)
--
-- Rows live inside a newScrollFrame with autoMeasure on, so the list scrolls
-- once items exceed its height. Row fill alpha rides on row.visibility (the
-- draw path uses visibility as the fill alpha, not the color's 4th slot) and
-- text alpha on label.textVisibility — that is what makes the fades and the
-- collapse-and-reflow on remove work. Selection is tracked by row identity, so
-- removals never shift a stale index. Requires gui.addons.system to be loaded
-- (addons/init.lua requires it, same as everything using newWindow).
--
local LIST_TAU         = .045   -- settle time-constant: ~150 ms to 95 %
local LIST_TEXT_TAU    = .025   -- dying rows lose their text before their box
local LIST_SCROLL_TAU  = .05
local LIST_STAGGER     = .04    -- per-row enter delay
local LIST_STAGGER_CAP = .24
local LIST_ENTER_DY    = 8      -- rows slide up into place, they don't pop in
local LIST_MIN_H       = 2      -- geometry floor: scaleFont derives size from h,
local LIST_EXIT_GUARD  = .6     --   and newFont(0) would error on a dead row
local LIST_DCLICK      = .35

function gui:newListFrame(x, y, w, h, sx, sy, sw, sh, opts)
    opts = opts or {}
    local rowH    = opts.rowHeight or 28
    local gap     = opts.gap or 2
    local align   = opts.align or gui.ALIGN_LEFT
    local scale   = opts.scale or .85
    local animOn  = opts.animate ~= false
    local striped = opts.striped == true

    local selColor    = opts.selectedColor or th.primaryNav
    local hoverColor  = opts.hoverColor   or color.lighten(th.primaryBG, .10)
    local stripeColor = opts.stripedColor or color.darken(th.primaryBG, .10)
    local textColor   = opts.textColor    or th.primaryText

    local box = self:newScrollFrame(x, y, w, h, sx, sy, sw, sh)
    box.drawBorder = false
    box.visibility = 0                  -- the content frame paints nothing itself
    box:autoMeasure(true)

    local viewport = box.parent
    viewport.drawBorder = false
    if opts.backgroundColor then
        viewport.color = opts.backgroundColor
    else
        viewport.visibility = 0         -- let the surface behind the list show through
    end

    -- Invisible full-width spacer. autoMeasure pins the content extent to the
    -- children's bounding box as fixed pixels; with zero rows (or only the
    -- inset placeholder) that box collapses and rows — which scale from the
    -- content width — would shrink to nothing. This spacer guarantees the
    -- measured width never drops below the content width itself, keeping the
    -- pin stable at (re-pinned on resize) the viewport width.
    local spacer = box:newFrame(0, 0, 0, 0, 0, 0, 1, 0)
    spacer.drawBorder = false
    spacer.visibility = 0
    spacer.ignore = true
    spacer.active = false
    spacer.__winInternal = true

    viewport:OnSizeChanged(function(obj)
        if obj ~= viewport then return end
        local _, _, vw, _ = viewport:getAbsolutes()
        local ox, oy, _, oh = box:getDualDim()
        box:setDualDim(ox, oy, vw, oh, 0, 0, 0, 0)
        box:markDirty()
    end)

    local rows        = {}
    local selectedRow
    local tweening     = false
    local scrollTarget, scrollTargetRow = nil, nil
    local boxFocused  = false
    local lastClick, lastClickT
    local emptyLabel

    box.OnSelectionChanged = miscProc:newConnection()

    -- Public indices are LIVE indices: rows[] may hold collapsing ghosts, and
    -- the API never exposes their positions.
    local function liveAt(i)
        local n = 0
        for _, r in ipairs(rows) do
            if not r.dying then
                n = n + 1
                if n == i then return r end
            end
        end
        return nil
    end

    local function indexOfRow(row)
        local n = 0
        for _, r in ipairs(rows) do
            if r == row then return row.dying and nil or n + 1 end
            if not r.dying then n = n + 1 end
        end
        return nil
    end

    local function liveCount()
        local n = 0
        for _, r in ipairs(rows) do
            if not r.dying then n = n + 1 end
        end
        return n
    end

    -- Resolve one row's fill (alpha + rgb) from its state. alpha 0 keeps the
    -- last color so a row fading out doesn't flash through a color change.
    local function retarget(row)
        if row.dying then
            row.__fillTo, row.__hTo, row.__textTo = 0, 0, 0
            return
        end
        local col, alpha
        if row.__down then
            col, alpha = row.__press or hoverColor, 1
        elseif row == selectedRow then
            col, alpha = selColor, 1
        elseif row.hover then
            col, alpha = hoverColor, 1
        elseif striped and row.__even then
            col, alpha = stripeColor, .40
        else
            alpha = 0
        end
        row.__fillTo = alpha
        if col then
            row.__cTo[1], row.__cTo[2], row.__cTo[3] = col[1], col[2], col[3]
        end
    end

    local function snap(row)
        row.__fill, row.__text = row.__fillTo, row.__textTo
        row.__c[1], row.__c[2], row.__c[3] = row.__cTo[1], row.__cTo[2], row.__cTo[3]
        row.__off, row.__delay = 0, 0
        -- write through immediately: with animate=false (or an instant
        -- keyboard selection) the pump may never run, and visibility is the
        -- actual fill alpha the draw path reads
        row.visibility = row.__fill
        row.__label.textVisibility = row.__text
    end

    local function fireSelection()
        local i = selectedRow and indexOfRow(selectedRow) or nil
        local v = i and selectedRow.value or nil
        box.OnSelectionChanged:Fire(i, v)
        if opts.onChange then opts.onChange(i, v) end
    end

    -- Only scroll when the row is actually clipped — a selection already on
    -- screen must not nudge the viewport. The desired position is RE-AIMED
    -- every tick from the row's live target geometry: right after setItems the
    -- scroll extent is still the old one (autoMeasure runs a pass later), so a
    -- scalar target computed once would clamp to the stale range and never
    -- follow the incoming rows.
    local function scrollAim(row)
        local _, _, _, vh = viewport:getAbsolutes()
        local _, sy = box:getScrollPos()
        local top, bottom = row.__yTo, row.__yTo + row.__hTo
        if top < sy + gap then
            return sy, math.max(0, top - gap)
        elseif bottom > sy + vh - gap then
            return sy, bottom - vh + gap   -- applyScroll clamps to the real range
        end
        return sy, sy
    end

    local function scrollToShowRow(row, smooth)
        if not row then return end
        local sy, target = scrollAim(row)
        if target == sy then return end
        if smooth and animOn then
            scrollTarget, scrollTargetRow = target, row
            tweening = true
        else
            scrollTarget, scrollTargetRow = nil, nil
            box:scrollTo(target)
        end
    end

    local function updateEmpty()
        if not opts.emptyText then return end
        if not emptyLabel then
            -- offsetH = rowH, not 0: an empty list has ~zero content height, and
            -- scaleFont derives the font size from the label's own height
            emptyLabel = box:newTextLabel(opts.emptyText, 12, 10, -24, rowH, 0, 0, 1, 0)
            emptyLabel.drawBorder     = false
            emptyLabel.color          = {0, 0, 0, 0}
            emptyLabel.visibility     = 0
            emptyLabel.textVisibility = 0
            emptyLabel.textColor      = opts.emptyTextColor or th.secondaryText or th.primaryText
            emptyLabel.align          = gui.ALIGN_CENTER
            emptyLabel.ignore         = true
            emptyLabel:centerFont()
            emptyLabel:scaleFont(scale)
            emptyLabel.__want = 0
        end
        local want = (liveCount() == 0) and 1 or 0
        if emptyLabel.__want ~= want then
            emptyLabel.__want = want
            tweening = true
        end
    end

    local function markLayout()
        box:markDirty()
        updateEmpty()
    end

    local function addRow(index, text, value)
        local yStart = gap
        for j = 1, index - 1 do
            yStart = yStart + rows[j].__hTo + gap
        end
        local row = box:newFrame(0, yStart, 0, rowH, 0, 0, 1, 0)
        row.drawBorder = false
        row.text  = tostring(text)
        row.value = value

        local label = row:newTextLabel(row.text, 4, 0, -8, 0, 0, 0, 1, 1)
        label.align          = align
        label.textColor      = textColor
        label.color          = {0, 0, 0, 0}   -- the label paints no box of its own
        label.visibility     = 0
        label.textVisibility = animOn and 0 or 1
        label.ignore         = true           -- clicks reach the row, not the label
        label:centerFont()
        label:scaleFont(scale)

        row.__label  = label
        row.__c      = { stripeColor[1], stripeColor[2], stripeColor[3] }
        row.__cTo    = { row.__c[1], row.__c[2], row.__c[3] }
        row.__fill, row.__fillTo = 0, 0
        row.__text, row.__textTo = label.textVisibility, 1
        row.__y, row.__yTo = yStart, yStart
        row.__h, row.__hTo = rowH, rowH
        row.__off   = animOn and LIST_ENTER_DY or 0
        row.__delay = 0
        row.color, row.visibility = row.__c, 0

        table.insert(rows, index, row)

        row:OnPressed(function(self, _, _, button)
            if self.dying or button ~= 1 then return end
            boxFocused = true
            local base = (self == selectedRow) and selColor or hoverColor
            self.__press = color.darken(base, .18)
            self.__down = true
            retarget(self)
            tweening = true
        end)

        -- note: the framework owns .pressed (it clears it before firing
        -- OnReleased), so press state uses __down
        local function unpress(self)
            if not self.__down then return end
            self.__down = false
            retarget(self)
            tweening = true
        end

        row:OnReleased(function(self, mx, my, button)
            unpress(self)
            if self.dying then return end
            if button == 2 then
                if opts.onRightClick then
                    opts.onRightClick(indexOfRow(self), self.value, mx, my)
                end
                return
            end
            if button ~= 1 then return end
            local now = love.timer.getTime()
            local doubled = (lastClick == self) and ((now - (lastClickT or 0)) < LIST_DCLICK)
            lastClick, lastClickT = self, now
            box:select(self)
            if doubled and opts.onDoubleClicked then
                opts.onDoubleClicked(indexOfRow(self), self.value)
            end
        end)
        row:OnReleasedOuter(unpress)

        row:OnEnter(function(self)
            if self.dying then return end
            self.hover = true
            retarget(self)
            tweening = true
        end)
        row:OnExit(function(self)
            self.hover = false
            retarget(self)
            tweening = true
        end)

        retarget(row)
        if not animOn then snap(row) end
        return row
    end

    -- silent: programmatic selection (setSelected) that must not fire events
    local function doSelect(i, animate, silent)
        local row = (type(i) == "table") and i or liveAt(i)
        if not row or row.dying then return end
        local smooth = (animate ~= false) and animOn
        if row ~= selectedRow then
            local prev = selectedRow
            selectedRow = row
            if prev then retarget(prev) end
            retarget(row)
            if smooth then
                tweening = true
            else
                -- keyboard selection lands instantly: no animation on a key
                -- that gets pressed hundreds of times a session. Still flag
                -- one tween pass so the snapped values reach visibility.
                if prev then snap(prev) end
                snap(row)
                tweening = true
            end
            if not silent then fireSelection() end
        end
        scrollToShowRow(row, smooth)
    end

    local function beginRemove(row)
        if row.dying then return end
        row.dying = true
        row.__dieT = 0
        row.active = false              -- stop reacting to hover/press while collapsing
        row.hover, row.__down = false, false
        if row == selectedRow then selectedRow = nil end
        if row == lastClick then lastClick = nil end
        retarget(row)
        tweening = true
    end

    local function reselectAt(i)
        local live = {}
        for j, r in ipairs(rows) do
            if not r.dying then live[#live + 1] = j end
        end
        if #live == 0 then
            fireSelection()             -- selection is now empty
            return
        end
        box:select(rows[live[math.max(1, math.min(i, #live))]], false)
    end

    function box:setItems(items)
        for i = #rows, 1, -1 do rows[i]:destroy() end
        rows = {}
        selectedRow, lastClick, lastClickT = nil, nil, nil
        scrollTarget = nil
        for _, item in ipairs(items or {}) do
            if type(item) == "table" then
                addRow(#rows + 1, item.text or "", item.value)
            else
                addRow(#rows + 1, item, item)
            end
        end
        if animOn then
            for i, row in ipairs(rows) do
                row.__delay = math.min((i - 1) * LIST_STAGGER, LIST_STAGGER_CAP)
            end
        end
        box:scrollToTop()
        markLayout()
        tweening = true
    end

    function box:add(text, value)
        local row = addRow(#rows + 1, text, value == nil and text or value)
        markLayout()
        tweening = true
        return row
    end

    -- public insert position is a LIVE index too: insert(2, x) lands before the
    -- current second live row, whatever ghosts are collapsing around it
    function box:insert(i, text, value)
        local n = liveCount()
        i = math.max(1, math.min(n + 1, tonumber(i) or (n + 1)))
        local pos, cnt = #rows + 1, 0
        if i <= n then
            for j, r in ipairs(rows) do
                if not r.dying then
                    cnt = cnt + 1
                    if cnt == i then pos = j break end
                end
            end
        end
        local row = addRow(pos, text, value == nil and text or value)
        markLayout()
        tweening = true
        return row
    end

    function box:remove(i)
        local row = (type(i) == "table") and i or liveAt(i)
        if not row or row.dying then return nil end
        local wasSelected = (row == selectedRow)
        local value = row.value
        beginRemove(row)
        if wasSelected then reselectAt(i) end
        markLayout()
        return value
    end

    function box:removeValue(value)
        local liveIdx = 0
        for i, row in ipairs(rows) do
            if not row.dying then
                liveIdx = liveIdx + 1
                if row.value == value then
                    local wasSelected = (row == selectedRow)
                    local text = row.text
                    beginRemove(row)
                    if wasSelected then reselectAt(liveIdx) end
                    markLayout()
                    return liveIdx, text
                end
            end
        end
        return nil
    end

    function box:clear(animate)
        local had = selectedRow ~= nil
        for _, row in ipairs(rows) do
            if animate == false then
                row:destroy()
            else
                beginRemove(row)
            end
        end
        if animate == false then rows = {} end
        selectedRow, lastClick, lastClickT = nil, nil, nil
        scrollTarget = nil
        if had then fireSelection() end
        markLayout()
    end

    function box:select(i, animate)
        doSelect(i, animate, false)
    end

    function box:setSelected(i, animate)
        doSelect(i, animate, true)
    end

    function box:getSelected()
        if not selectedRow then return nil, nil end
        return indexOfRow(selectedRow), selectedRow.value
    end

    function box:getItem(i)
        local row = liveAt(i)
        if not row then return nil end
        return row.text, row.value
    end

    function box:getItems()
        local out = {}
        for _, row in ipairs(rows) do
            if not row.dying then
                out[#out + 1] = { text = row.text, value = row.value }
            end
        end
        return out
    end

    function box:getItemCount() return liveCount() end
    function box:isEmpty()      return liveCount() == 0 end

    function box:indexOf(value)
        local n = 0
        for _, row in ipairs(rows) do
            if not row.dying then
                n = n + 1
                if row.value == value then return n end
            end
        end
        return nil
    end

    function box:scrollToShow(i)
        scrollToShowRow((type(i) == "table") and i or liveAt(i), true)
    end

    -- advanced access: the live row FRAME for styling hooks (row.color is
    -- driven by the tween loop — restyle via selectedColor/hoverColor opts,
    -- not by writing row.color directly)
    function box:getRow(i) return liveAt(i) end
    function box:getEmptyLabel() return emptyLabel end

    -- keyboard-nav focus: also tracked automatically (a press inside the list
    -- focuses it, a press outside clears it); this is the manual override for
    -- game code that manages focus itself
    function box:setFocused(b) boxFocused = b and true or false end
    function box:isFocused() return boxFocused end

    box.removeRox = box.remove          -- deprecated spelling, kept for compat

    -- debug/test helper: true while any row, the placeholder, or the smooth
    -- scroll is still settling
    function box:isSettling() return tweening end

    if opts.keyboard then
        local keyConn = gui.Events.OnKeyPressed(function(key)
            if not boxFocused then return end
            local live = {}
            for j, r in ipairs(rows) do
                if not r.dying then live[#live + 1] = j end
            end
            if #live == 0 then return end
            local pos = 0
            if selectedRow then
                for p, j in ipairs(live) do
                    if rows[j] == selectedRow then pos = p break end
                end
            end
            if key == "delete" or key == "backspace" then
                if pos > 0 then box:remove(pos) end
                return
            end
            local _, _, _, vh = viewport:getAbsolutes()
            local pageRows = math.max(1, math.floor(vh / (rowH + gap)))
            local np
            if     key == "down"     then np = math.min(#live, pos + 1)
            elseif key == "up"       then np = pos == 0 and 1 or math.max(1, pos - 1)
            elseif key == "home"     then np = 1
            elseif key == "end"      then np = #live
            elseif key == "pagedown" then np = math.min(#live, pos + pageRows)
            elseif key == "pageup"   then np = math.max(1, pos - pageRows)
            else return end
            box:select(rows[live[np]], false)
        end)

        local focusConn = gui.Events.OnObjectFocusChanged(function(_, new)
            boxFocused = (new == viewport)
                or (type(new) == "table" and new.isDescendantOf ~= nil
                    and new:isDescendantOf(viewport))
                or false
        end)
        -- click-away: a press anywhere outside this list clears focus
        viewport:OnPressedOuter(function() boxFocused = false end)

        box:OnDestroy(function()
            keyConn:Unconnect()
            focusConn:Unconnect()
        end)
    end

    -- One shared tween pass for the whole list: every row carries current and
    -- target values, and they chase their targets with an exponential ease
    -- (interruptible — a retarget mid-flight continues from where it is rather
    -- than restarting). The loop sleeps itself when nothing is moving.
    -- Wall-clock dt: OnUpdate is pumped by a multi thread, and
    -- love.timer.getDelta() is per-FRAME and shared with every other consumer,
    -- so it can be far smaller than the real time between pump ticks (which
    -- makes tweens crawl). Track the pump's own clock instead.
    local lastPump = love.timer.getTime()
    box:OnUpdate(function()
        if not tweening then return end
        tweening = false
        -- NO upper clamp: the updater thread can be starved for a second at a
        -- time (unfocused window = 10 FPS, thread scheduling). A starved tick
        -- then advances with k -> 1 and converges in one go instead of
        -- crawling on a fake 0.1s step.
        local now = love.timer.getTime()
        local dt = math.max(0, now - lastPump)
        lastPump = now

        local okp, errp = pcall(function()
        local k  = 1 - math.exp(-dt / LIST_TAU)
        local kf = 1 - math.exp(-dt / LIST_TEXT_TAU)
        local y, moved, live = gap, false, 0

        for i = 1, #rows do
            local row = rows[i]
            if not row.dying then live = live + 1 end
            row.__even = (live % 2 == 0)   -- parity counts LIVE rows, not ghosts

            -- stripe parity can shift when rows are removed above it; only
            -- touch the fill target for rows that hold no stronger state
            if striped and not row.dying and row ~= selectedRow
                and not row.hover and not row.__down then
                local want = row.__even and .40 or 0
                if row.__fillTo ~= want then
                    row.__fillTo = want
                    tweening = true
                end
            end

            if row.__delay > 0 then
                row.__delay = row.__delay - dt
                tweening = true
            end
            if row.dying then row.__dieT = row.__dieT + dt end

            -- Flow from TARGET heights, so a collapsing row's neighbours slide
            -- straight to where they will end up instead of chasing it. A dead
            -- row contributes neither height nor gap: its slot closes fully.
            row.__yTo = y
            y = y + row.__hTo + (row.dying and 0 or gap)

            local d = row.__yTo - row.__y
            if d > .5 or d < -.5 then row.__y = row.__y + d * k; tweening = true else row.__y = row.__yTo end
            d = row.__hTo - row.__h
            if d > .5 or d < -.5 then row.__h = row.__h + d * k; tweening = true else row.__h = row.__hTo end
            d = -row.__off
            if d > .5 or d < -.5 then row.__off = row.__off + d * k; tweening = true else row.__off = 0 end
            d = row.__fillTo - row.__fill
            if d > .004 or d < -.004 then row.__fill = row.__fill + d * k; tweening = true else row.__fill = row.__fillTo end
            d = row.__textTo - row.__text
            local kt = row.dying and kf or k
            if d > .004 or d < -.004 then row.__text = row.__text + d * kt; tweening = true else row.__text = row.__textTo end
            for ch = 1, 3 do
                local dc = row.__cTo[ch] - row.__c[ch]
                if dc > .004 or dc < -.004 then
                    row.__c[ch] = row.__c[ch] + dc * k
                    tweening = true
                else
                    row.__c[ch] = row.__cTo[ch]
                end
            end

            -- the floor keeps scaleFont (font size = h * textScale) out of
            -- newFont(0); the alpha fade covers the 2 px stub
            local py, ph = row.__y + row.__off, math.max(LIST_MIN_H, row.__h)
            if row.__wy ~= py or row.__wh ~= ph then
                row:rawSetDualDim(0, py, 0, ph, 0, 0, 1, 0)
                row.__wy, row.__wh = py, ph
                moved = true
            end
            row.visibility = row.__fill
            row.__label.textVisibility = row.__text
        end

        -- Retire rows whose exit has finished (with a wall-clock guard so a
        -- stalled collapse can never leave a dead row in the list). Retirement
        -- shifts the flow for every row below, so the pump MUST run again —
        -- otherwise neighbours freeze at targets computed while the ghost was
        -- still in the flow.
        local retired = false
        for i = #rows, 1, -1 do
            local row = rows[i]
            if row.dying and ((row.__h <= .05 and row.__fill <= .01) or row.__dieT > LIST_EXIT_GUARD) then
                row:destroy()
                table.remove(rows, i)
                moved = true
                retired = true
            end
        end
        if retired then tweening = true end

        if emptyLabel then
            local d = emptyLabel.__want - emptyLabel.textVisibility
            if d > .004 or d < -.004 then
                emptyLabel.textVisibility = emptyLabel.textVisibility + d * k
                tweening = true
            else
                emptyLabel.textVisibility = emptyLabel.__want
            end
        end

        if moved then box:markDirty() end

        if scrollTarget then
            if scrollTargetRow then
                local _, aim = scrollAim(scrollTargetRow)
                scrollTarget = aim
            end
            local _, sy = box:getScrollPos()
            local d = scrollTarget - sy
            if d > .5 or d < -.5 then
                tweening = true
                box:scrollTo(sy + d * (1 - math.exp(-dt / LIST_SCROLL_TAU)))
            else
                box:scrollTo(scrollTarget)
                scrollTarget, scrollTargetRow = nil, nil
            end
        end
        end)
        -- a broken frame must not kill the updater thread; log once and let
        -- the list freeze in place rather than spin forever
        if not okp then print("newListFrame: tween pump error: " .. tostring(errp)) end
    end)

    box:setItems(opts.items)
    return box
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
                local _,_,_h = percentDisplay:getAbsolutes()
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