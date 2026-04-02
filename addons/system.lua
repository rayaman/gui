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

local function nowClock() return os.clock() end

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

-- ── window constructor (unchanged from original) ──────────────────────────────
local windowCount = 0
function gui:newWindow(x, y, w, h, text, draggable, theme)
    local process = gui:newProcessor(text or "window_"..windowCount)
    windowCount = windowCount + 1
    local parent = self
    local pointer = love.mouse.getCursor()
    local sizewe   = love.mouse.getSystemCursor("sizewe")
    local sizens   = love.mouse.getSystemCursor("sizens")
    local sizenesw = love.mouse.getSystemCursor("sizenesw")
    local sizenwse = love.mouse.getSystemCursor("sizenwse")
    local theme = theme or default_theme

    local header = self:newFrame(x, y, w, 35)
    header:setRoundness(10, 10, nil, "top")
    local window = header:newFrame(0, 35, 0, h - 35, 0, 0, 1)
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

    function window:setTitle(t) title.text = t end

    local X = header:newTextButton("", -25, -25, 20, 20, 1, 1)
    X:setRoundness(10, 10)
    X.align = gui.ALIGN_CENTER
    X.color = color.red
    local darkenX = color.darken(color.red, .2)
    X.OnEnter(function(self) self.color = darkenX end)
    X.OnExit(function(self) self.color = color.red end)

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

    window.OnClose = function() return window end % X.OnPressed
    window.OnClose(function()
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

    window.OnSizeChanged(function() window:refresh() end)
    function window:refresh() window:setTheme(theme) end

    window.process = process
    window.OnCreated(function(element)
        if element:hasType(gui.TYPE_BUTTON) then
            element:setFont(theme.fontButton)
            element.color     = theme.colorButtonNormal
            element.textColor = theme.colorButtonText
            if not element.__registeredTheme then
                element.OnEnter(function(self) self.color = theme.colorButtonHighlight end)
                element.OnExit(function(self)  self.color = theme.colorButtonNormal end)
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

-- ── scroll frame (unchanged from original) ────────────────────────────────────
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
        if applying then return end
        local vw, vh = getViewSize()
        local _, _, cw, ch = content:getAbsolutes()

        maxScrollY = math.max(0, ch - vh)
        if maxScrollY > 0 then
            vBar.visible = true
            local thumbH = math.max(20, vh * (vh / ch))
            local thumbY = (scrollY / maxScrollY) * (vh - thumbH)
            vThumb:setDualDim(0, thumbY, SCROLL_BAR_W, thumbH)
        else
            vBar.visible = false
            scrollY = 0
        end

        maxScrollX = math.max(0, cw - vw)
        if maxScrollX > 0 then
            hBar.visible = true
            local thumbW = math.max(20, vw * (vw / cw))
            local thumbX = (scrollX / maxScrollX) * (vw - thumbW)
            hThumb:setDualDim(thumbX, 0, thumbW, SCROLL_BAR_W)
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
        updateScrollbars()
        applying = false
    end

    viewport.OnWheelMoved(function(x, y)
        scrollY = scrollY - y * SCROLL_SPEED
        applyScroll()
    end)

    vThumb:enableDragging(gui.MOUSE_PRIMARY)
    vThumb.OnDragging(function(self, dx, dy)
        local _, vh = getViewSize()
        local _, _, _, thumbH = vThumb:getAbsolutes()
        local trackH = vh - thumbH
        if trackH <= 0 then return end
        scrollY = scrollY + dy * (maxScrollY / trackH)
        applyScroll()
    end)

    hThumb:enableDragging(gui.MOUSE_PRIMARY)
    hThumb.OnDragging(function(self, dx, dy)
        local vw, _ = getViewSize()
        local _, _, thumbW = hThumb:getAbsolutes()
        local trackW = vw - thumbW
        if trackW <= 0 then return end
        scrollX = scrollX + dx * (maxScrollX / trackW)
        applyScroll()
    end)

    content.OnSizeChanged(function()
        if applying then return end
        local _, _, cw, ch = content:getAbsolutes()
        local vw, vh = getViewSize()
        maxScrollY = math.max(0, ch - vh)
        maxScrollX = math.max(0, cw - vw)
        scrollY = clamp(scrollY, 0, maxScrollY)
        scrollX = clamp(scrollX, 0, maxScrollX)
        updateScrollbars()
    end)

    viewport.OnSizeChanged(function()
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
    function content:setContentSize(cw, ch)
        _baseSDD(self, nil, nil, cw or select(3, self:getAbsolutes()), ch)
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
        killBtn.color  = color.darken(color.red, .1)

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

        pauseBtn.OnReleased(function()
            if not row.obj then return end
            if row.obj:isPaused() then
                row.obj:Resume()
            else
                row.obj:Pause()
            end
            statusLbl.text = row.obj:isPaused() and "Paused" or "Running"
            pauseBtn.text  = row.obj:isPaused() and "Resume" or "Pause"
        end)

        killBtn.OnReleased(function()
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
        priorityLbl.OnReleased(function()
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
            btn.OnReleased(function()
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
        btn.OnReleased(function()
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

    taskManager = gui:newWindow(0, 0, WIN_W, WIN_H, "Task Manager", true, TM_THEME)
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

    clearBtn.OnReleased(function() errorPool:clear() end)

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
    local schedulerProbe = require("gui.addons.probe")
    schedulerProbe:install(multi)

    -- ── main-thread update ────────────────────────────────────────────────────
    taskManager.OnUpdate(function()
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
        gui:showTaskManager()
    elseif taskManager:isActive() then
        taskManager:close()
    else
        taskManager:open()
    end
end)

ToggleTaskManager:Fire()
taskManager:close()
