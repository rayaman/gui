local multi, thread = require("multi"):init()
local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")

local TM_THEME = theme:new({
    primary     = "#124559",
    primaryDark = "#01161E",
    primaryText = "#AEC3B0"
})

local default_theme = TM_THEME
-- ── layout constants ──────────────────────────────────────────────────────────
-- Columns: Indent+Name, State, Status, Uptime, Priority, Pause, Kill
--          Name shrunk so data columns have room to breathe
local COL_WIDTHS = { 300, 130, 120, 100, 130, 100, 100, 70 }
local COL_KEYS   = { "name", "kind", "state", "status", "uptime", "priority", "pause", "kill" }
local COL_LABELS = { "Name", "Type", "State", "Status", "Uptime", "Priority", "–", "–" }
local SORT_COLS  = { "name", "kind", "state", "status", "uptime", "priority" }

local ROW_H  = 28
local COL_X  = {}
do
    local acc = 0
    for i, w in ipairs(COL_WIDTHS) do
        COL_X[i] = acc
        acc = acc + w
    end
end
local TOTAL_W = COL_X[#COL_X] + COL_WIDTHS[#COL_WIDTHS]  -- 700

-- ── thread state names ────────────────────────────────────────────────────────
local STATE_NAMES = {
    [1] = "holding",
    [2] = "sleeping",
    [3] = "hold+time",
    [4] = "skipping",
    [5] = "hold+cyc",
    [6] = "yielding",
    [7] = "running",
}
local function fmtState(obj)
    if obj._isPaused then return "paused" end
    local t = obj.task
    if t == nil then return "running" end
    return STATE_NAMES[t] or ("state:"..tostring(t))
end

local PRIORITY_NAMES = {
    [1]     = "Core",
    [4]     = "V.High",
    [16]    = "High",
    [64]    = "Above",
    [256]   = "Normal",
    [1024]  = "Below",
    [4096]  = "Low",
    [16384] = "V.Low",
    [65536] = "Idle",
}
local PRIORITY_CYCLE = { 1, 4, 16, 64, 256, 1024, 4096, 16384, 65536 }
local function fmtPriority(obj)
    local p = rawget(obj, "Priority") or rawget(obj, "priority")
    if not p then return "n/a" end
    return PRIORITY_NAMES[p] or tostring(p)
end
local function nextPriority(current)
    for i, v in ipairs(PRIORITY_CYCLE) do
        if v == current then
            return PRIORITY_CYCLE[(i % #PRIORITY_CYCLE) + 1]
        end
    end
    return 256
end

-- ── helpers ───────────────────────────────────────────────────────────────────
local function fmtUptime(secs)
    secs = math.floor(secs)
    if secs < 60   then return secs .. "s" end
    if secs < 3600 then return math.floor(secs/60).."m "..(secs%60).."s" end
    return math.floor(secs/3600).."h "..math.floor((secs%3600)/60).."m"
end

local nowClock = require("socket").gettime

-- ── data collection ───────────────────────────────────────────────────────────
-- Returns a flat list of rows with depth so the UI can indent names.
local function collectTasks()
    local rows = {}
    local stats = multi:getStats()

    local function addProc(fullname, proc, depth)
        -- Processor header row
        rows[#rows+1] = {
            isProc    = true,
            depth     = depth,
            name      = proc.name or fullname,
            fullname  = fullname,
            kind      = "processor",
            conns     = proc.connections or 0,
            subs      = proc.subscriptions or 0,
        }
        -- Tasks (Mainloop actors)
        local tasks = proc.tasks or {}
        for _, task in pairs(tasks) do
            if not task.isProcessThread then
                rows[#rows+1] = {
                    isProc   = false,
                    depth    = depth + 1,
                    name     = task:getName() or "?",
                    fullname = fullname,
                    kind     = tostring(task.Type),
                    state    = fmtState(task),
                    active   = not task:isPaused(),
                    uptime   = nowClock() - (task.UPTIME or nowClock()),
                    priority = rawget(task, "Priority") or 256,
                    fmtPri   = fmtPriority(task),
                    obj      = task,
                    isThread = false,
                }
            end
        end
        -- Threads
        local threads = proc.threads or {}
        for _, th in pairs(threads) do
            rows[#rows+1] = {
                isProc   = false,
                depth    = depth + 1,
                name     = th:getName() or "?",
                fullname = fullname,
                kind     = tostring(th.Type),
                state    = fmtState(th),
                active   = not th:isPaused(),
                uptime   = nowClock() - (th.UPTIME or nowClock()),
                priority = rawget(th, "Priority") or 256,
                fmtPri   = fmtPriority(th),
                obj      = th,
                isThread = true,
            }
        end
    end

    -- Root first, then sub-processors sorted
    if stats["root"] then
        addProc("root", stats["root"], 0)
    end
    local procNames = {}
    for k in pairs(stats) do
        if k ~= "root" then procNames[#procNames+1] = k end
    end
    table.sort(procNames)
    for _, k in ipairs(procNames) do
        addProc(k, stats[k], 1)
    end

    return rows
end

function gui:newScrollFrame(x, y, w, h, sx, sy, sw, sh)
    local viewport = self:newFrame(x, y, w, h, sx, sy, sw, sh)
    viewport.clipDescendants = true
    viewport.drawBorder = false

    local content = viewport:newFrame(0, 0, w, 0)
    content.drawBorder = false

    local scrollY    = 0
    local maxScrollY = 0
    local scrollX    = 0
    local maxScrollX = 0
    local SCROLL_SPEED  = 40
    local SCROLL_BAR_W  = 8

    local vBar = viewport:newFrame(-SCROLL_BAR_W, 0, SCROLL_BAR_W, 0, 1, 0, 0, 1)
    vBar.color = {0.3, 0.3, 0.3}
    vBar.drawBorder = false
    vBar.visible = false

    local vThumb = vBar:newFrame(0, 0, SCROLL_BAR_W, 40)
    vThumb.color = {0.6, 0.6, 0.6}
    vThumb.drawBorder = false

    local hBar = viewport:newFrame(0, -SCROLL_BAR_W, 0, SCROLL_BAR_W, 0, 1, 1)
    hBar.color = {0.3, 0.3, 0.3}
    hBar.drawBorder = false
    hBar.visible = false

    local hThumb = hBar:newFrame(0, 0, 40, SCROLL_BAR_W)
    hThumb.color = {0.6, 0.6, 0.6}
    hThumb.drawBorder = false

    local applying = false

    local function getViewSize()
        local _, _, vw, vh = viewport:getAbsolutes()
        return vw, vh
    end

    local function clamp(val, lo, hi)
        return math.max(lo, math.min(hi, val))
    end

    local function updateScrollbars()
        local vw, vh = getViewSize()
        local _, _, cw, ch = content:getAbsolutes()

        maxScrollY = math.max(0, ch - vh)
        if maxScrollY > 0 then
            vBar.visible = true
            local thumbH = math.max(20, vh * (vh / ch))
            local thumbY = (scrollY / maxScrollY) * (vh - thumbH)
            vThumb:setDualDim(nil, thumbY, nil, thumbH)
        else
            vBar.visible = false
            scrollY = 0
        end

        maxScrollX = math.max(0, cw - vw)
        if maxScrollX > 0 then
            hBar.visible = true
            local thumbW = math.max(20, vw * (vw / cw))
            local thumbX = (scrollX / maxScrollX) * (vw - thumbW)
            hThumb:setDualDim(thumbX, nil, thumbW, nil)
        else
            hBar.visible = false
            scrollX = 0
        end
    end

    local function applyScroll()
        if applying then return end
        applying = true
        scrollY = clamp(scrollY, 0, maxScrollY)
        scrollX = clamp(scrollX, 0, maxScrollX)
        content:setDualDim(-scrollX, -scrollY)
        applying = false          -- release BEFORE updateScrollbars
        updateScrollbars()        -- now applying=false, no guard needed
    end

    viewport:OnWheelMoved(function(x, y)
        scrollY = scrollY - y * SCROLL_SPEED
        applyScroll()
    end)

    vThumb:enableDragging(gui.MOUSE_PRIMARY)
    vThumb:OnDragging(function(self, dx, dy)
        local _, vh = getViewSize()
        local _, _, _, thumbH = vThumb:getAbsolutes()
        local trackH = vh - thumbH
        if trackH <= 0 then return end
        scrollY = scrollY + dy * (maxScrollY / trackH)
        applyScroll()
    end)

    hThumb:enableDragging(gui.MOUSE_PRIMARY)
    hThumb:OnDragging(function(self, dx, dy)
        local vw, _ = getViewSize()
        local _, _, thumbW = hThumb:getAbsolutes()
        local trackW = vw - thumbW
        if trackW <= 0 then return end
        scrollX = scrollX + dx * (maxScrollX / trackW)
        applyScroll()
    end)

    content:OnSizeChanged(function()
        if applying then return end
        local _, _, cw, ch = content:getAbsolutes()
        local vw, vh = getViewSize()
        maxScrollY = math.max(0, ch - vh)
        maxScrollX = math.max(0, cw - vw)
        scrollY = clamp(scrollY, 0, maxScrollY)
        scrollX = clamp(scrollX, 0, maxScrollX)
        updateScrollbars()
    end)

    viewport:OnSizeChanged(function()
        if applying then return end
        applyScroll()
    end)

    function content:scrollTo(sy, sx)
        scrollY = sy or scrollY
        scrollX = sx or scrollX
        applyScroll()
    end
    function content:scrollBy(dy, dx)
        scrollY = scrollY + (dy or 0)
        scrollX = scrollX + (dx or 0)
        applyScroll()
    end
    function content:scrollToBottom() scrollY = maxScrollY; applyScroll() end
    function content:scrollToTop()    scrollY = 0;          applyScroll() end
    function content:setScrollSpeed(speed) SCROLL_SPEED = speed end
    function content:getScrollPos()   return scrollX, scrollY end
    function content:getMaxScroll()   return maxScrollX, maxScrollY end

    local _baseSDD = content.setDualDim
    function content:setContentSize(cw, ch, full)
        if full then
            _baseSDD(self, nil, nil, nil, ch,nil,nil,1)
        else
            _baseSDD(self, nil, nil, cw or select(3, self:getAbsolutes()), ch)
        end
        applyScroll()
    end

    local _baseDestroy = viewport.destroy
    function viewport:destroy()
        content:destroy()
        _baseDestroy(self)
    end

    applyScroll()
    return content
end

-- ── gui:newMessageBox() ───────────────────────────────────────────────────────
--
-- Creates a modal-style draggable message box built on top of gui:newWindow().
--
-- SIGNATURE:
--   gui:newMessageBox(options)
--
-- OPTIONS TABLE:
--   title       (string)          Window/header title.           Default: "Message"
--   message     (string|nil)      Body description text.         Default: nil (no body label)
--   buttons     (table|nil)       List of button label strings.  Default: { "OK" }
--   theme       (theme|nil)       gui theme object.              Default: TM_THEME (or default_theme)
--   x, y        (number|nil)      Initial position.              Default: centered on screen
--   width       (number|nil)      Box width.                     Default: 340
--   onChoice    (function|nil)    Called as onChoice(label, index) when any button is pressed.
--                                 Also accessible via returned connection object.
--
-- RETURNS: window object (same as gui:newWindow)
--   window:OnChoice  — multi connection; fires with (label, index)
--   window:close()   — hides the window (as usual)
--   window:open()    — shows the window (as usual)
--
-- EXAMPLE:
--   gui:newMessageBox({
--       title   = "Confirm Action",
--       message = "Are you sure you want to delete this task?",
--       buttons = { "Yes", "No", "Cancel" },
--       onChoice = function(label, idx)
--           print("User chose:", label, "at index", idx)
--       end,
--   })
--
-- ─────────────────────────────────────────────────────────────────────────────

function gui:newMessageBox(options)
    options = options or {}

    -- ── defaults ──────────────────────────────────────────────────────────────
    local title    = options.title   or "Message"
    local message  = options.message or nil
    local buttons  = options.buttons or { "OK" }
    local msgTheme = options.theme   or default_theme

    local BOX_W    = options.width  or 340

    -- Layout constants
    local PAD        = 14   -- horizontal padding inside window body
    local MSG_PAD_T  = 12   -- top padding for message text
    local MSG_PAD_B  = 10   -- gap between message and buttons
    local BTN_H      = 30
    local BTN_GAP    = 8    -- gap between buttons
    local BTN_ROW_PB = 14   -- padding below button row

    -- Calculate body height dynamically
    -- We approximate: message gets ~3 lines max, then buttons below.
    local MSG_H = 0
    if message and message ~= "" then
        -- Allow up to ~3 lines at ~18px each; wrapped by the label widget.
        -- We give it a fixed height; if text overflows, the box still looks clean.
        MSG_H = 60
    end

    local BTN_ROW_H = BTN_H + BTN_ROW_PB
    local BOX_H     = MSG_PAD_T + MSG_H + (message and MSG_PAD_B or 0) + BTN_ROW_H

    -- Center on screen by default
    local sw, sh = love.graphics.getDimensions()
    local wx = options.x or math.floor((sw - BOX_W) / 2)
    local wy = options.y or math.floor((sh - (BOX_H + 35)) / 2)  -- 35 = header height

    -- ── create window ─────────────────────────────────────────────────────────
    local win = gui:newWindow(wx, wy, BOX_W, BOX_H,
                              nil, nil, nil, nil,
                              title, true, msgTheme)

    -- ── OnChoice connection ───────────────────────────────────────────────────
    win.OnChoice = multi:newConnection()
    if options.onChoice then
        win:OnChoice(options.onChoice)
    end

    -- ── message label ─────────────────────────────────────────────────────────
    if message and message ~= "" then
        local msgLbl = win:newTextLabel(
            message,
            PAD, MSG_PAD_T,
            BOX_W - PAD * 2, MSG_H
        )
        msgLbl.align    = gui.ALIGN_CENTER
        msgLbl.wordWrap = true          -- enable word-wrap if the GUI supports it
        msgLbl.ignore   = true
    end

    -- ── button row ────────────────────────────────────────────────────────────
    -- Buttons are evenly distributed across the box width.
    local n        = #buttons
    local totalGap = BTN_GAP * (n - 1)
    local btnW     = math.floor((BOX_W - PAD * 2 - totalGap) / n)
    local btnY     = MSG_PAD_T + MSG_H + (message and MSG_PAD_B or MSG_PAD_T * 0.5)

    for i, label in ipairs(buttons) do
        local btnX = PAD + (i - 1) * (btnW + BTN_GAP)
        local btn  = win:newTextButton(label, btnX, btnY, btnW, BTN_H)
        btn.align  = gui.ALIGN_CENTER

        -- Capture loop vars
        local capturedLabel = label
        local capturedIdx   = i

        btn:OnReleased(function()
            win.OnChoice:Fire(capturedLabel, capturedIdx)
            win:close()
        end)
    end

    -- ── close button also fires OnChoice with nil ─────────────────────────────
    win.XButton:OnPressed(function()
        win.OnChoice:Fire(nil, nil)
    end)

    return win
end

-- ── window constructor (unchanged from original) ──────────────────────────────
local windowCount = 0
function gui:newWindow(x, y, w, h, sx, sy, sw, sh, text, draggable, theme)
    local process = gui:newProcessor(text or "window_"..windowCount)
    windowCount = windowCount + 1
    local parent = self
    local pointer = love.mouse.getCursor()
    local sizewe   = love.mouse.getSystemCursor("sizewe")
    local sizens   = love.mouse.getSystemCursor("sizens")
    local sizenesw = love.mouse.getSystemCursor("sizenesw")
    local sizenwse = love.mouse.getSystemCursor("sizenwse")
    local theme = theme or default_theme

    local header = self:newFrame(x, y, w, 35, sx, sy, sw)
    header:setRoundness(10, 10, nil, "top")
    local window = header:newFrame(0, 35, 0, h, sx, sy, 1, sh)
    window.clipDescendants = true
    local left        = window:newFrame(0, -4, 4, 0, 0, 0, 0, 1):tag("left")
    local right       = window:newFrame(-4, -4, 4, 0, 1, 0, 0, 1):tag("right")
    local bottom      = window:newFrame(4, -4, -8, 4, 0, 1, 1):tag("bottom")
    local bottomleft  = window:newFrame(0, -4, 4, 4, 0, 1):tag("bleft")
    local bottomright = window:newFrame(-4, -4, 4, 4, 1, 1):tag("bright")
    gui.apply({
        visibility = 0,
        I_enableDragging = {gui.MOUSE_PRIMARY},
        respectHierarchy = {false},
        OnUpdate = function(self) self:topStack() end,
        OnDragging = function(self, dx, dy)
            local ox, oy, ow, oh = header:getAbsolutes()
            local tag = self:getTag()
            if tag == "left" or tag == "bleft" then
                window:size(0, dy)
                header:move(dx, 0)
                header:size(-dx, 0)
            else
                window:size(0, dy)
                header:size(dx, 0)
            end
            local x, y, w, h = header:getAbsolutes()
            if w < 200 and (tag == "left" or tag == "bleft") then
                header:setDualDim(ox, nil, 200)
            elseif w < 200 then
                header:setDualDim(nil, nil, 200)
            end
            local x, y, w, h = window:getAbsolutes()
            if h < 100 then window:setDualDim(nil, nil, nil, 100) end
        end,
        OnDragEnd = function(self) love.mouse.setCursor(pointer) end,
        OnEnter = function(self)
            local tag = self:getTag()
            if tag == "left" or tag == "right" then
                love.mouse.setCursor(sizewe)
            elseif tag == "bleft" then
                love.mouse.setCursor(sizenesw)
            elseif tag == "bright" then
                love.mouse.setCursor(sizenwse)
            else
                love.mouse.setCursor(sizens)
            end
        end,
        OnExit = function(self) love.mouse.setCursor(pointer) end,
    }, left, right, bottom, bottomleft, bottomright)

    local title = header:newTextLabel(text or "", 5, 0, w - 35, 35)
    title.clipDescendants = true
    title.visibility = 0
    title.ignore = true
    title:setFont(theme.fontPrimary)
    title:fitFont()

    function window:setTitle(t) title.text = t title:fitFont() end

    local X = header:newTextButton("", -25, -25, 20, 20, 1, 1)
    X:setRoundness(10, 10)
    X:respectHierarchy(false)
    X.align = gui.ALIGN_CENTER
    X.color = color.new("#e50000")
    window.XButton = X

    local darkenX = color.darken(color.new("#e50000"), .2)
    X:OnEnter(function(self) self.color = darkenX end)
    X:OnExit(function(self) self.color = color.new("#e50000") end)

    if draggable then
        header:enableDragging(gui.MOUSE_PRIMARY)
        header:OnDragging(function(self, dx, dy) self:move(dx, dy) end)
        header:OnDragEnd(function(self)
            local x, y, w, h = self:getAbsolutes()
            local width, height = love.graphics.getDimensions()
            if x <= 0 then self:setDualDim(0) end
            if y <= 0 then self:setDualDim(nil, 0) end
            if x + w >= width  then self:setDualDim(width - w) end
            if y + h >= height then self:setDualDim(nil, height - 35) end
        end)
    end

    window.OnClose = multi:newConnection()
    X:OnPressed(function(self, ...)
        window.OnClose:Fire(window, ...)
    end)
    window:OnClose(function()
        header:setParent(gui.virtual)
        love.mouse.setCursor(pointer)
    end)
    function window:close() window.OnClose:Fire(self) end
    function window:open()  header:setParent(parent) end

    function window:setTheme(th)
        theme = th
        title.textColor  = theme.colorPrimaryText
        header.color     = theme.colorPrimaryDark
        window.color     = theme.colorPrimary
    end
    function window:getTheme() return theme end

    process:newThread(function() window:setTheme(theme) end)

    window:OnSizeChanged(function() window:refresh() end)
    function window:refresh() window:setTheme(theme) end

    window.process = process
    window:OnCreated(function(element)
        if element:hasType(gui.TYPE_BUTTON) then
            element:setFont(theme.fontButton)
            element.color     = theme.colorButtonNormal
            element.textColor = theme.colorButtonText
            if not element.__registeredTheme then
                element:OnEnter(function(self) self.color = theme.colorButtonHighlight end)
                element:OnExit(function(self)  self.color = theme.colorButtonNormal end)
            end
            element:fitFont()
            element.__registeredTheme = true
        elseif element:hasType(gui.TYPE_TEXT) then
            element.color     = theme.colorPrimary
            element:setFont(theme.fontPrimary)
            element.textColor = theme.colorPrimaryText
            element:fitFont()
        elseif element:hasType(gui.TYPE_FRAME) then
            if element.__isHeader then
                element.color = theme.colorPrimaryDark
            else
                element.color = theme.colorPrimary
            end
        end
    end)
    return window
end

-- ── row pool ──────────────────────────────────────────────────────────────────
local COLOR_PROC_ROW  = TM_THEME.colorPrimaryDark
local COLOR_ROW_EVEN  = TM_THEME.colorPrimary
local COLOR_ROW_ODD   = TM_THEME.colorPrimaryDark
local COLOR_DEAD      = { 0.5, 0.1, 0.1 }

local function makeRowPool(scrollFrame)
    local pool = { rows = {}, active = 0 }

    local function makeRow(idx)
        local yOff = (idx - 1) * ROW_H
        local bg   = scrollFrame:newFrame(0, yOff, TOTAL_W, ROW_H)
        bg.drawBorder = false

        -- Name label (col 1) with indent support
        local nameLabel = bg:newTextLabel("", COL_X[1] + 4, 0, COL_WIDTHS[1] - 4, ROW_H)
        nameLabel.align  = gui.ALIGN_LEFT
        nameLabel.ignore = true

        -- Type, State, Status, Uptime, Priority labels
        local kindLbl     = bg:newTextLabel("", COL_X[2], 0, COL_WIDTHS[2], ROW_H)
        local stateLbl    = bg:newTextLabel("", COL_X[3], 0, COL_WIDTHS[3], ROW_H)
        local statusLbl   = bg:newTextLabel("", COL_X[4], 0, COL_WIDTHS[4], ROW_H)
        local uptimeLbl   = bg:newTextLabel("", COL_X[5], 0, COL_WIDTHS[5], ROW_H)
        local priorityLbl = bg:newTextLabel("", COL_X[6], 0, COL_WIDTHS[6], ROW_H)
        for _, lbl in ipairs({kindLbl, stateLbl, statusLbl, uptimeLbl, priorityLbl}) do
            lbl.align  = gui.ALIGN_CENTER
            lbl.ignore = true
        end

        -- Pause / Resume button
        local pauseBtn = bg:newTextButton("", COL_X[7] + 2, 2, COL_WIDTHS[7] - 4, ROW_H - 4)
        pauseBtn.align = gui.ALIGN_CENTER

        -- Kill button (red)
        local killBtn  = bg:newTextButton("Kill", COL_X[8] + 2, 2, COL_WIDTHS[8] - 4, ROW_H - 4)
        killBtn.align  = gui.ALIGN_CENTER
        killBtn.color  = color.darken(color.new("#e50000"), .1)

        local row = {
            bg          = bg,
            nameLabel   = nameLabel,
            kindLbl     = kindLbl,
            stateLbl    = stateLbl,
            statusLbl   = statusLbl,
            uptimeLbl   = uptimeLbl,
            priorityLbl = priorityLbl,
            pauseBtn    = pauseBtn,
            killBtn     = killBtn,
            obj         = nil,
            isProc      = false,
        }

        pauseBtn:OnReleased(function()
            if not row.obj then return end
            if row.obj:isPaused() then
                row.obj:Resume()
            else
                row.obj:Pause()
            end
            statusLbl.text = row.obj:isPaused() and "Paused" or "Running"
            pauseBtn.text  = row.obj:isPaused() and "Resume" or "Pause"
        end)

        killBtn:OnReleased(function()
            if not row.obj or row.isProc then return end
            if row.obj.Kill then
                row.obj:Kill()
            elseif row.obj.Destroy then
                row.obj:Destroy()
            end
            bg.color = COLOR_DEAD
        end)

        -- Priority label is clickable to cycle priority
        priorityLbl.ignore = false
        priorityLbl:OnReleased(function()
            if not row.obj or row.isProc then return end
            local cur  = rawget(row.obj, "Priority") or 256
            local next = nextPriority(cur)
            if row.obj.setPriority then
                row.obj:setPriority(next)
                priorityLbl.text = PRIORITY_NAMES[next] or tostring(next)
            end
        end)

        return row
    end

    function pool:ensure(n)
        while #self.rows < n do
            self.rows[#self.rows + 1] = makeRow(#self.rows + 1)
        end
    end

    function pool:apply(data)
        self:ensure(#data)
        self.active = #data

        for i, d in ipairs(data) do
            local row = self.rows[i]
            row.isProc = d.isProc
            row.obj    = d.isProc and nil or d.obj

            -- Row y position
            row.bg:setDualDim(nil, (i - 1) * ROW_H)
            row.bg.visible = true

            if d.isProc then
                -- Processor header row
                row.bg.color = COLOR_PROC_ROW
                row.nameLabel.text   = string.rep("  ", d.depth) .. "[" .. d.name .. "]"
                row.kindLbl.text     = "processor"
                row.stateLbl.text    = ""
                row.statusLbl.text   = ""
                row.uptimeLbl.text   = d.conns .. "c/" .. d.subs .. "s"
                row.priorityLbl.text = ""
                row.pauseBtn.text    = ""
                row.pauseBtn.visible = false
                row.killBtn.visible  = false
            else
                row.bg.color = (i % 2 == 0) and COLOR_ROW_EVEN or COLOR_ROW_ODD
                row.nameLabel.text   = string.rep("  ", d.depth) .. d.name
                row.kindLbl.text     = d.kind or ""
                row.stateLbl.text    = d.state or ""
                row.statusLbl.text   = d.active and "Running" or "Paused"
                row.uptimeLbl.text   = fmtUptime(d.uptime)
                row.priorityLbl.text = d.fmtPri or ""
                row.pauseBtn.text    = d.active and "Pause" or "Resume"
                row.pauseBtn.visible = true
                row.killBtn.visible  = true
            end
        end

        -- Hide unused rows
        for i = #data + 1, #self.rows do
            self.rows[i].bg.visible = false
            self.rows[i].obj = nil
        end

        scrollFrame:setDualDim(nil, nil, nil, math.max(#data * ROW_H, 1))
    end

    return pool
end

-- ── error log pool ────────────────────────────────────────────────────────────
local ERROR_ROW_H = 22
local MAX_ERRORS  = 200

local function makeErrorPool(scrollFrame)
    local pool = { rows = {}, entries = {} }

    local function makeRow(idx)
        local yOff = (idx - 1) * ERROR_ROW_H
        local bg   = scrollFrame:newFrame(0, yOff, TOTAL_W, ERROR_ROW_H)
        bg.color       = (idx % 2 == 0) and COLOR_ROW_EVEN or COLOR_ROW_ODD
        bg.drawBorder  = false
        local lbl = bg:newTextLabel("", 4, 0, TOTAL_W - 4, ERROR_ROW_H)
        lbl.align  = gui.ALIGN_LEFT
        lbl.ignore = true
        return { bg = bg, lbl = lbl }
    end

    function pool:ensure(n)
        while #self.rows < n do
            self.rows[#self.rows + 1] = makeRow(#self.rows + 1)
        end
    end

    function pool:addEntry(msg, source)
        if #self.entries >= MAX_ERRORS then
            table.remove(self.entries, 1)
        end
        local ts = string.format("[%.1fs]", os.clock())
        self.entries[#self.entries + 1] = ts .. " [" .. (source or "?") .. "] " .. tostring(msg)
        self:refresh()
    end

    function pool:refresh()
        local n = #self.entries
        self:ensure(n)
        for i, entry in ipairs(self.entries) do
            local row = self.rows[i]
            row.bg:setDualDim(nil, (i - 1) * ERROR_ROW_H)
            row.bg.visible = true
            row.lbl.text   = entry
        end
        for i = n + 1, #self.rows do
            self.rows[i].bg.visible = false
        end
        scrollFrame:setDualDim(nil, nil, nil, math.max(n * ERROR_ROW_H, 1))
        scrollFrame:scrollToBottom()
    end

    function pool:clear()
        self.entries = {}
        self:refresh()
    end

    return pool
end

-- ── column header row ─────────────────────────────────────────────────────────
local function makeHeader(parent, onSort)
    local hdr = parent:newFrame(0, 0, TOTAL_W, ROW_H)
    hdr.color      = TM_THEME.colorPrimaryDark
    hdr.drawBorder = false

    local sortCol = nil
    local sortAsc = true
    local indicators = {}

    for i, t in ipairs(COL_LABELS) do
        local isSortable = false
        for _, k in ipairs(SORT_COLS) do
            if k == COL_KEYS[i] then isSortable = true; break end
        end

        if isSortable then
            local btn = hdr:newTextButton(t, COL_X[i], 0, COL_WIDTHS[i], ROW_H)
            btn.align = (i == 1) and gui.ALIGN_LEFT or gui.ALIGN_CENTER
            indicators[COL_KEYS[i]] = btn
            local key = COL_KEYS[i]
            btn:OnReleased(function()
                if sortCol == key then
                    sortAsc = not sortAsc
                else
                    sortCol = key
                    sortAsc = true
                end
                -- Reset all sortable headers, then mark the active one
                for j, label in ipairs(COL_LABELS) do
                    local b = indicators[COL_KEYS[j]]
                    if b then
                        if COL_KEYS[j] == sortCol then
                            b.text = label .. (sortAsc and " ▲" or " ▼")
                        else
                            b.text = label
                        end
                    end
                end
                if onSort then onSort(key, sortAsc) end
            end)
        else
            local lbl = hdr:newTextLabel(t, COL_X[i], 0, COL_WIDTHS[i], ROW_H)
            lbl.align  = gui.ALIGN_CENTER
            lbl.ignore = true
            lbl.textColor = TM_THEME.colorPrimaryText
        end
    end
    return hdr
end

-- ── tab bar ───────────────────────────────────────────────────────────────────
local TAB_H = 28
local function makeTabBar(parent, tabs, onSwitch)
    local bar = parent:newFrame(0, 0, 0, TAB_H, 0, 0, 1)
    bar.color      = TM_THEME.colorPrimaryDark
    bar.drawBorder = false
    local tabW = math.floor(TOTAL_W / #tabs)
    local btns = {}
    for i, label in ipairs(tabs) do
        local btn = bar:newTextButton(label, (i-1)*tabW, 0, tabW, TAB_H)
        btn.align = gui.ALIGN_CENTER
        btns[i] = btn
        btn:OnReleased(function()
            onSwitch(i)
        end)
    end
    return bar, btns
end

-- ── sort helper ───────────────────────────────────────────────────────────────
local function sortRows(rows, key, asc)
    local function cmp(a, b)
        -- Processor rows always float to top within their group; we keep them stable
        if a.isProc and b.isProc then return a.fullname < b.fullname end
        if a.isProc then return true end
        if b.isProc then return false end
        local va, vb
        if key == "name"     then va, vb = a.name or "", b.name or ""
        elseif key == "kind"     then va, vb = a.kind or "", b.kind or ""
        elseif key == "state"    then va, vb = a.state or "", b.state or ""
        elseif key == "status" then va, vb = (a.active and 0 or 1), (b.active and 0 or 1)
        elseif key == "uptime" then va, vb = a.uptime or 0, b.uptime or 0
        elseif key == "priority" then va, vb = a.priority or 256, b.priority or 256
        else va, vb = tostring(a[key] or ""), tostring(b[key] or "")
        end
        if asc then return va < vb else return va > vb end
    end
    -- Stable-ish sort: keep proc header immediately before its children
    -- For simplicity we sort the flat list but keep proc rows pinned before
    -- the first non-proc row that shares the same fullname.
    table.sort(rows, cmp)
end

-- ── public API ────────────────────────────────────────────────────────────────
local taskManager

function gui:showTaskManager()
    if taskManager then return end

    local WIN_W = TOTAL_W + 20
    local WIN_H = 620

    taskManager = gui:newWindow(0, 0, WIN_W, WIN_H, nil, nil, nil, nil, "Task Manager", true, TM_THEME)
    taskManager.clipDescendants = true

    -- ── tab bar ──────────────────────────────────────────────────────────────
    local currentTab = 1  -- 1 = tasks, 2 = errors
    local taskPanel, errorPanel

    local tabBar, tabBtns = makeTabBar(taskManager, {"Tasks", "Errors"}, function(idx)
        currentTab = idx
        taskPanel.visible  = (idx == 1)
        errorPanel.visible = (idx == 2)
    end)

    -- ── tasks panel ──────────────────────────────────────────────────────────
    taskPanel = taskManager:newFrame(0, TAB_H, 0, -TAB_H, 0, 0, 1, 1)
    taskPanel.drawBorder = false
    taskPanel.clipDescendants = true

    -- Load bar strip (sits below tab bar, above column headers)
    local LOAD_H   = 20
    local loadStrip = taskPanel:newFrame(0, 0, 0, LOAD_H, 0, 0, 1)
    loadStrip.color      = TM_THEME.colorPrimaryDark
    loadStrip.drawBorder = false

    local loadFill = loadStrip:newFrame(0, 2, 1, LOAD_H - 4)  -- absolute w=1, no relative anchors
    loadFill.color      = { 0.1, 0.6, 0.3 }
    loadFill.drawBorder = false

    -- Label is created AFTER fill so it draws on top of it
    local loadLbl = loadStrip:newTextLabel("Load: …", 4, 0, TOTAL_W - 8, LOAD_H)
    loadLbl.align  = gui.ALIGN_LEFT
    loadLbl.ignore = true
    loadLbl.visibility = 0

    local sortKey = nil
    local sortAsc = true

    local colHdr = makeHeader(taskPanel, function(key, asc)
        sortKey = key
        sortAsc = asc
    end)
    colHdr:setDualDim(nil, LOAD_H)

    local scrollFrame = taskPanel:newScrollFrame(0, LOAD_H + ROW_H, 0, -(LOAD_H + ROW_H), 0, 0, 1, 1)
    local pool = makeRowPool(scrollFrame)

    -- ── error panel ──────────────────────────────────────────────────────────
    errorPanel = taskManager:newFrame(0, TAB_H, 0, -TAB_H, 0, 0, 1, 1)
    errorPanel.drawBorder = false
    errorPanel.clipDescendants = true
    errorPanel.visible    = false

    local errHdr = errorPanel:newFrame(0, 0, 0, ROW_H, 0, 0, 1)
    errHdr.color      = TM_THEME.colorPrimaryDark
    errHdr.drawBorder = false
    local errTitle = errHdr:newTextLabel("Error Log", 4, 0, 200, ROW_H)
    errTitle.align  = gui.ALIGN_LEFT
    errTitle.ignore = true

    local clearBtn = errHdr:newTextButton("Clear", -70, 2, 66, ROW_H - 4, 1)
    clearBtn.align = gui.ALIGN_CENTER

    local errScroll   = errorPanel:newScrollFrame(0, ROW_H, 0, -ROW_H, 0, 0, 1, 1)
    local errorPool   = makeErrorPool(errScroll)

    clearBtn:OnReleased(function() errorPool:clear() end)

    -- ── wire up error capture ─────────────────────────────────────────────────
    -- Thread errors fire on the *thread's own* OnError, not the processor's.
    -- We use OnObjectCreated to hook every thread as it is born, on every
    -- processor (including ones created after the task manager opens).
    -- We also walk existing threads retroactively for processors already running.

    local hookedThreads = {}  -- weak set so we don't prevent GC

    local function hookThread(th, procName)
        if not th.OnError then return end
        if hookedThreads[th] then return end
        hookedThreads[th] = true
        th.OnError(function(self, err,t)
            local msg = type(err) == "string" and err or tostring(err or "unknown error")
            local name = (th.getName and th:getName()) or "?"
            errorPool:addEntry(msg, procName .. "/" .. name)
        end)
    end

    local function hookProc(proc, procName)
        -- Hook threads already alive on this processor
        local threads = proc.threads or {}
        for _, th in ipairs(threads) do
            hookThread(th, procName)
        end
        -- Hook threads created in future on this processor
        proc.OnObjectCreated(function(obj)
            if obj.Type == multi.registerType("thread", "threads") then
                hookThread(obj, procName)
            end
        end)
    end

    -- Root process
    hookProc(multi, "root")
    -- All processors currently registered
    for _, proc in ipairs(multi:getProcessors()) do
        hookProc(proc, proc:getName())
    end
    -- Any processors created after this point
    multi.OnObjectCreated(function(obj)
        if obj.Type == multi.registerType("process", "processes") then
            hookProc(obj, obj:getName())
        end
    end)

    -- ── stat line ─────────────────────────────────────────────────────────────
    local function setStatLine(n)
        taskManager:setTitle("Task Manager  —  " .. n .. " objects")
    end

    -- ── background thread: collect tasks ──────────────────────────────────────
    local function isOpen()
        return not taskManager:isDescendantOf(gui.virtual)
    end

    local pendingData = nil
    local dirty       = false

    taskManager.process:newThread("TM_collect", function()
        while true do
            thread.hold(isOpen)
            local data = collectTasks()
            pendingData = data
            dirty = true
            thread.sleep(1)
        end
    end)

    -- ── load probe ────────────────────────────────────────────────────────────
    -- Install once. getLoad() is now non-blocking — just reads the EMA state.
    local schedulerProbe = require("gui.core.probe")
    schedulerProbe:install(multi)

    -- ── main-thread update ────────────────────────────────────────────────────
    taskManager:OnUpdate(function()
        taskManager:topStack()
        -- Apply task data
        if dirty and pendingData then
            dirty = false
            local data = pendingData
            pendingData = nil

            if sortKey then
                sortRows(data, sortKey, sortAsc)
            end

            pool:apply(data)
            setStatLine(#data)
        end

        -- Load bar — getLoad() is now non-blocking, safe to call every frame
        local pct, lagMs = multi:getLoad()
        local _, _, barW, _ = loadStrip:getAbsolutes()
        local fillW = math.max(1, math.floor(barW * pct / 100))
        loadFill:setDualDim(nil, nil, fillW)
        if pct < 50 then
            loadFill.color = { 0.1, 0.6, 0.3 }
        elseif pct < 80 then
            loadFill.color = { 0.8, 0.6, 0.1 }
        else
            loadFill.color = { 0.8, 0.15, 0.1 }
        end
        loadLbl.text = string.format("Load: %d%%  Lag: %.1fms", pct, lagMs)
    end)
end

-- ── hotkey ────────────────────────────────────────────────────────────────────
ToggleTaskManager = gui:setHotKey({"lctrl","t"}) +
                    gui:setHotKey({"rctrl","t"})

ToggleTaskManager(function()
    if not taskManager then
        -- gui:showTaskManager()
    elseif taskManager:isActive() then
        taskManager:close()
    else
        taskManager:open()
    end
end)

ToggleTaskManager:Fire()
-- taskManager:close()

local PATH_SEP   = love.system.getOS() == "Windows" and "\\" or "/"
local IS_WINDOWS = love.system.getOS() == "Windows"

-- ── filesystem helpers (io.popen only) ───────────────────────────────────────

local function pread(cmd)
    local handle
    if IS_WINDOWS then
        handle = io.popen('cmd /c "' .. cmd .. '"')
    else
        handle = io.popen(cmd)
    end
    if not handle then return nil end
    local out = handle:read("*a")
    handle:close()
    return out
end

-- POSIX single-quote escape for shell arguments.
local function posixQuote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Return true if `path` is a directory.
local function isDir(path)
    if IS_WINDOWS then
        local p = path:gsub('"', '')
        if p:sub(-1) ~= "\\" then p = p .. "\\" end
        local out = pread('if exist "' .. p .. '*" (echo YES)')
        return out ~= nil and out:match("YES") ~= nil
    else
        local out = pread('test -d ' .. posixQuote(path) .. ' && echo YES')
        return out ~= nil and out:match("YES") ~= nil
    end
end

-- Return sorted {dirs}, {files} inside `path`.
local function listDir(path, showHidden)
    local dirs, files = {}, {}

    if IS_WINDOWS then
        local p = path:gsub('"', '')
        local dout = pread('dir /A:D /B "' .. p .. '" 2>nul')
        if dout then
            for name in dout:gmatch("[^\r\n]+") do
                name = name:match("^%s*(.-)%s*$")
                if name ~= "" and name ~= "." and name ~= ".." then
                    dirs[#dirs+1] = name
                end
            end
        end

        local fout = pread('dir /A:-D /B "' .. p .. '" 2>nul')
        if fout then
            for name in fout:gmatch("[^\r\n]+") do
                name = name:match("^%s*(.-)%s*$")
                if name ~= "" then
                    files[#files+1] = name
                end
            end
        end
    else
        local out = pread('ls -la ' .. posixQuote(path) .. ' 2>/dev/null')
        if out then
            for line in out:gmatch("[^\n]+") do
                if line:match("^[dlrwx%-]") then
                    local perms = line:sub(1, 1)
                    -- Skip 8 tokens to reach filename (handles month/day/time cols)
                    local _, pos = line:find("^%S+%s+%S+%s+%S+%s+%S+%s+%S+%s+%S+%s+%S+%s+%S+%s+")
                    local name = pos and line:sub(pos + 1) or ""
                    -- Trim whitespace
                    name = name:match("^%s*(.-)%s*$") or ""
                    -- Strip symlink arrow
                    name = name:match("^(.-)%s+%->%s+") or name

                    if name ~= "" and name ~= "." and name ~= ".." then
                        if showHidden or name:sub(1,1) ~= "." then
                            if perms == "d" then
                                dirs[#dirs+1] = name
                            else
                                files[#files+1] = name
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(dirs,  function(a,b) return a:lower() < b:lower() end)
    table.sort(files, function(a,b) return a:lower() < b:lower() end)
    return dirs, files
end

-- Join two path components.
local function joinPath(dir, name)
    if IS_WINDOWS then
        dir = dir:gsub("/", "\\")
        if dir:sub(-1) == "\\" then return dir .. name end
        return dir .. "\\" .. name
    else
        if dir:sub(-1) == "/" then return dir .. name end
        return dir .. "/" .. name
    end
end

-- Normalise path (forward slashes, no trailing slash except root).
local function normPath(path)
    if IS_WINDOWS then
        path = path:gsub("/", "\\")
        if #path > 3 then path = path:gsub("\\$", "") end
    else
        path = path:gsub("\\", "/")
        if #path > 1 then path = path:gsub("/$", "") end
    end
    return path
end

-- Return the parent of a path.
local function parentOf(path)
    path = normPath(path)
    if IS_WINDOWS then
        -- "C:\\foo\\bar" -> "C:\\foo",  "C:\\" -> "C:\\"
        local parent = path:match("^(.+)\\[^\\]+$")
        if not parent then return path end
        if parent:match("^%a:$") then parent = parent .. "\\" end
        return parent
    else
        if path == "/" then return "/" end
        local parent = path:match("^(.+)/[^/]+$")
        if not parent or parent == "" then return "/" end
        return parent
    end
end

-- Get the home directory.
local function homeDir()
    if IS_WINDOWS then
        return normPath(os.getenv("USERPROFILE") or os.getenv("HOMEDRIVE") .. os.getenv("HOMEPATH") or "C:\\")
    else
        return normPath(os.getenv("HOME") or "/")
    end
end

-- Get current working directory via os.getenv or a popen fallback.
local function getCwd()
    local cwd
    if IS_WINDOWS then
        local f = io.popen("cd")
        if f then cwd = f:read("*a"):match("^%s*(.-)%s*$"); f:close() end
    else
        local f = io.popen("pwd")
        if f then cwd = f:read("*a"):match("^%s*(.-)%s*$"); f:close() end
    end
    return normPath(cwd or homeDir())
end

-- Filter a file list by allowed extensions.
local function filterFiles(files, filter)
    if not filter or #filter == 0 then return files end
    local allowed = {}
    for _, ext in ipairs(filter) do allowed[ext:lower()] = true end
    local out = {}
    for _, f in ipairs(files) do
        local ext = f:match("%.([^%.]+)$") or ""
        if allowed[ext:lower()] then out[#out+1] = f end
    end
    return out
end

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

local ROW_H  = 28

local function makeRowPool(scrollFrame, callback)
    local pool = { rows = {}, active = 0 }

    local function makeRow(idx)
        local yOff = (idx - 1) * ROW_H
        local bg = scrollFrame:newFrame(0, yOff, 0, ROW_H, 0, 0, 1)  -- scale w=1, no captured w
        bg.drawBorder = false
        local nameLabel = bg:newTextLabel("", 0, 0, 0, ROW_H, 0, 0, 1)  -- fills parent width
        nameLabel.color = color.new("#0343df")
        nameLabel.align  = gui.ALIGN_CENTER
        nameLabel.ignore = true
        if not bg.callback then
            bg:OnReleased(callback)
            bg.callback = true
            nameLabel:OnEnter(function(self)
                self:setShader(gui.SHADERS.glow)
                self:shaderTime(true)
            end)
            nameLabel:OnExit(function(self)
                self:setShader()
                self:shaderTime(false)
            end)
        end
        nameLabel:fitFont()
        return { bg = bg, nameLabel = nameLabel }
    end

    function pool:ensure(n)
        while #self.rows < n do
            self.rows[#self.rows + 1] = makeRow(#self.rows + 1)
        end
    end

    function pool:apply(data)
        self:ensure(#data)
        self.active = #data

        for i, d in ipairs(data) do
            local row = self.rows[i]
            row.bg:setDualDim(nil, (i - 1) * ROW_H)
            row.bg.visible = true
            row.bg.text = d[1]
            row.bg.isDir = d[2]
            row.nameLabel.visible = true
            row.nameLabel.text = d[1]
            if d[2] then
                row.nameLabel.color = color.new("#F5C842")
            else
                row.nameLabel.color = color.new("#4A90D9")
            end
        end

        -- Hide unused rows
        for i = #data + 1, #self.rows do
            self.rows[i].bg.visible = false
            self.rows[i].nameLabel.visible = false
        end

        thread:newThread(function()
            scrollFrame:setContentSize(400, math.max(#data * ROW_H, 1),true)
        end)
    end

    return pool
end

function gui.OpenSaveDir(root)
    local path = love.filesystem.getSaveDirectory() .. (root or "")
    if love.system.getOS() == "Windows" then
        os.execute('explorer "' .. path:gsub("/", "\\") .. '"')
    elseif love.system.getOS() == "OS X" then
        os.execute('open "' .. path .. '"')
    else
        os.execute('xdg-open "' .. path .. '"')
    end
end

-- Should only have one instance
local pickerWindow
local doCallback
local selected
local workingDir
function gui:newFilePicker(title, root, filter, callback)
    if root and root:sub(1,1) ~= "/" then
        root = "/" .. root
    end
    
    workingDir = love.filesystem.getSaveDirectory() .. (root or "")

    doCallback = function()
        callback(selected)
    end

    if pickerWindow then
        pickerWindow.visible = true
        pickerWindow:removeTag("visual")
        pickerWindow:list(workingDir)
        return
    end

    pickerWindow = self:newFrame(0,0,0,0,.25,.15,.5,.7)
    local header = pickerWindow:newFrame(5,5,-10,-10,0,0,1,.075)
    local save = header:newTextButton("Open game directory", noOf(0,0,1,1))
    local refresh = pickerWindow:newTextButton("Refresh Directory", 5, 0, -15, -10, 0, .075, 1/3, .05)
    local sel = pickerWindow:newTextLabel("Parent Directory", -5,0,-5,-10,1/3,.075,1/3,.05)
    local cancel = pickerWindow:newTextLabel("Cancel", -5,0,0,-10,2/3,.075,1/3,.05)

    local scrollContent = pickerWindow:newScrollFrame(0, -5, 0, 5, 0, .125, 1, .875)

    local buttons = {save, sel, refresh, cancel}

    local function setWDir(wdir)
        workingDir = wdir
    end

    pickerWindow.color = color.new("#374151")

    thread:newThread(function()
        thread.skip(2)
        gui.apply({
            align = gui.ALIGN_CENTER,
            fitFont = {},
            color = color.new("#2c4989"),
            OnEnter = function(self)
                self:setShader(gui.SHADERS.glow)
                self:shaderTime(true)
            end,
            OnExit = function(self)
                self:setShader()
                self:shaderTime(false)
            end,
        }, unpack(buttons))
        sel.color = color.new("#0D7377")
        refresh.color = color.new("#83a8e7")
    end)

    gui.Events.OnResized(thread:newFunction(function()
        thread.skip(2)
        gui.apply({
            fitFont = {},
        }, unpack(buttons))
    end))

    save:OnReleased(function()
        gui.OpenSaveDir(root)
    end)

    refresh:OnReleased(function()
        pickerWindow:list()
    end)

    sel:OnReleased(function()
        local fmt = workingDir:gsub("\\","/")
        if fmt == love.filesystem.getSaveDirectory() .. (root or "") then
            return 
        end
        pickerWindow:list(parentOf(workingDir))
    end)

    cancel:OnReleased(function()
        pickerWindow.visible = false
    end)

    local pool = makeRowPool(scrollContent,function(self)
        if self.isDir then
            pickerWindow:list(workingDir .. PATH_SEP .. self.text)
        else
            selected = workingDir .. "/" .. self.text
            gui:newMessageBox({
                title    = "Confirm",
                message  = "Do you want to select this file ".. self.text.. "?",
                buttons  = { "Yes", "No" },
                onChoice = function(label, idx)
                    if label == "Yes" then 
                        doCallback(selected)
                        pickerWindow.visible = false
                        pickerWindow:setTag("visual")
                    end
                end,
            })
        end
    end)
    
    function pickerWindow:list(wdir)
        if wdir then
            setWDir(wdir)
        end

        local entries = {}
        local dirs, files = listDir(workingDir, false)

        for i, dir in pairs(dirs) do
            table.insert(entries, {dir, true})
        end

        for i, file in pairs(files) do
            table.insert(entries, {file, false})
        end
        pool:apply(entries)
    end
    
    pickerWindow:list()
end