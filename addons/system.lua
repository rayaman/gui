local multi, thread = require("multi"):init()
local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local fontMod = require("gui.core.font")

-- ── module setup ──────────────────────────────────────────────────────────────
-- The window/message-box/task-manager widgets consume the NEW theme-framework
-- slots directly (primaryBG / primaryNav / primaryFG / primaryText /
-- primaryButton) — no legacy colorPrimary… shape anywhere (docs §4.4).
--
-- clock: socket.gettime when available, love.timer fallback so this module can
-- load in environments without the socket library (flex/grid demos stub it).
local clockOK, socketMod = pcall(require, "socket")
local nowClock = clockOK and socketMod.gettime or function() return love.timer.getTime() end

local function noOf(sx, sy, sw, sh)
    return nil, nil, nil, nil, sx, sy, sw, sh
end

local DEFAULT_FONTS = {
    primary = fontMod.get(nil, 14),
    button  = fontMod.get(nil, 14),
}

local function defaultTheme()
    return theme:newTheme("#124559")
end

-- Build the window theme table from a new-framework theme (or preset).
-- Slots used: primaryBG (content), primaryNav (header), primaryText,
-- primaryButton (hover = lighten), primaryFG (accents). Missing slots fall
-- back to the default theme so partial tables work.
local function windowTheme(th, fonts)
    local d = th or defaultTheme()
    local f = fonts or DEFAULT_FONTS
    local button = d.primaryButton or defaultTheme().primaryButton
    return {
        bg        = d.primaryBG,
        header    = d.primaryNav or d.primaryBG,
        text      = d.primaryText,
        button    = button,
        buttonHi  = color.lighten(button, .15),
        accent    = d.primaryFG,
        fontPrimary = f.primary,
        fontButton  = f.button,
    }
end

-- ── newScrollFrame ────────────────────────────────────────────────────────────
--
-- Positional API (kept for compat with flex/grid demos and the file picker):
--   local content = parent:newScrollFrame(x, y, w, h, sx, sy, sw, sh)
--
-- Viewport clips descendants; wheel scroll + draggable thumbs; bars auto-hide.
-- New: content:autoMeasure(true) grows the scroll extent from the children's
-- bounding box every update pass (skip when the content is flex/grid managed,
-- where fit-content comes from the layout pass).
--
function gui:newScrollFrame(x, y, w, h, sx, sy, sw, sh)
    local viewport = self:newFrame(x, y, w, h, sx, sy, sw, sh)
    viewport.clipDescendants = true
    viewport.drawBorder = false
    viewport.__winInternal = true

    -- content starts at the viewport's own size: fixed pixel width when the
    -- caller passed one (flex demos), otherwise full-scale (windows/TM).
    local cw = (w and w > 0) and w or 0
    local csw = (w and w > 0) and 0 or 1
    local content = viewport:newFrame(0, 0, cw, 0, 0, 0, csw, 0)
    content.drawBorder = false
    content.__winInternal = true

    local scrollY    = 0
    local maxScrollY = 0
    local scrollX    = 0
    local maxScrollX = 0
    local SCROLL_SPEED = 40
    local SCROLL_BAR_W = 12
    local applying     = false
    local measureOn    = false
    local measureDirty = true

    local vBar = viewport:newFrame(-SCROLL_BAR_W, 0, SCROLL_BAR_W, 0, 1, 0, 0, 1)
    vBar.color = {0.3, 0.3, 0.3}
    vBar.drawBorder = false
    vBar.visible = false
    vBar.__winInternal = true

    local vThumb = vBar:newFrame(0, 0, SCROLL_BAR_W, 40)
    vThumb.color = {0.6, 0.6, 0.6}
    vThumb.drawBorder = false
    vThumb.__winInternal = true

    local hBar = viewport:newFrame(0, -SCROLL_BAR_W, 0, SCROLL_BAR_W, 0, 1, 1)
    hBar.color = {0.3, 0.3, 0.3}
    hBar.drawBorder = false
    hBar.visible = false
    hBar.__winInternal = true

    local hThumb = hBar:newFrame(0, 0, 40, SCROLL_BAR_W)
    hThumb.color = {0.6, 0.6, 0.6}
    hThumb.drawBorder = false
    hThumb.__winInternal = true

    local function clamp(val, lo, hi)
        return math.max(lo, math.min(hi, val))
    end

    local function getViewSize()
        local _, _, vw, vh = viewport:getAbsolutes()
        return vw, vh
    end

    local function updateScrollbars()
        local vw, vh = getViewSize()
        local _, _, cw, ch = content:getAbsolutes()

        maxScrollY = math.max(0, ch - vh)
        if maxScrollY > 0 then
            vBar.visible = true
            local thumbH = math.max(28, vh * (vh / ch))
            local thumbY = (scrollY / maxScrollY) * (vh - thumbH)
            vThumb:setDualDim(nil, thumbY, nil, thumbH)
        else
            vBar.visible = false
            scrollY = 0
        end

        maxScrollX = math.max(0, cw - vw)
        if maxScrollX > 0 then
            hBar.visible = true
            local thumbW = math.max(28, vw * (vw / cw))
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
        updateScrollbars()
    end

    -- The _OnXxx connections below are shared/global, so these handlers keep
    -- their own `obj` identity checks. The per-object façaches (init.lua:1060-
    -- 1078) now also filter `obj == self`, but the raw `:OnDragging`-style
    -- guards here stay as belt-and-braces against re-entrancy from other
    -- elements' events.
    viewport:OnWheelMoved(function(self,_, dy)
        scrollY = scrollY - dy * SCROLL_SPEED
        applyScroll()
    end)

    vThumb:OnDragging(function(obj, _, dy)
        if obj ~= vThumb then return end
        local _, vh = getViewSize()
        local _, _, _, thumbH = vThumb:getAbsolutes()
        local trackH = vh - thumbH
        if trackH <= 0 then return end
        scrollY = scrollY + dy * (maxScrollY / trackH)
        applyScroll()
    end)

    hThumb:OnDragging(function(obj, dx)
        if obj ~= hThumb then return end
        local vw = getViewSize()
        local _, _, thumbW = hThumb:getAbsolutes()
        local trackW = vw - thumbW
        if trackW <= 0 then return end
        scrollX = scrollX + dx * (maxScrollX / trackW)
        applyScroll()
    end)

    gui.apply({
        OnEnter = function() content:setTag("visual") end,
        OnExit = function () content:removeTag("visual") end,
        enableDragging = {gui.MOUSE_PRIMARY}
    },hThumb,vThumb)

    content:OnSizeChanged(function(obj)
        if obj ~= content or applying then return end
        local _, _, cw, ch = content:getAbsolutes()
        local vw, vh = getViewSize()
        maxScrollY = math.max(0, ch - vh)
        maxScrollX = math.max(0, cw - vw)
        scrollY = clamp(scrollY, 0, maxScrollY)
        scrollX = clamp(scrollX, 0, maxScrollX)
        updateScrollbars()
    end)

    viewport:OnSizeChanged(function(obj)
        if obj ~= viewport or applying then return end
        applyScroll()
    end)

    -- Auto-measure: one pass per update frame, debounced through a dirty flag
    -- so child size/position storms don't re-measure per event. Extent is
    -- computed from each child's dualDim arithmetic (deterministic) rather
    -- than absolute caches, which lag by a draw pass and shift with scrolling.
    local function measureExtent()
        if content.__flex then return nil end  -- flex/grid owns fit-content
        local _, _, cw0, ch0 = content:getAbsolutes()
        if cw0 <= 0 then cw0 = 0 end
        if ch0 <= 0 then ch0 = 0 end
        local maxX, maxY = 0, 0
        for _, c in ipairs(content.children) do
            if c.visible ~= false then
                local dx, dy, dw, dh, sx, sy, sw, sh = c:getDualDim()
                local right  = (sx or 0)*cw0 + (dx or 0) + (sw or 0)*cw0 + (dw or 0)
                local bottom = (sy or 0)*ch0 + (dy or 0) + (sh or 0)*ch0 + (dh or 0)
                if right  > maxX then maxX = right  end
                if bottom > maxY then maxY = bottom end
            end
        end
        return math.max(maxX, 1), math.max(maxY, 1)
    end

    viewport:OnUpdate(function()
        if not measureOn or applying or content.__flex then return end
        if not measureDirty then return end
        measureDirty = false
        local mw, mh = measureExtent()
        if not mw then return end
        local _, _, cw, ch = content:getAbsolutes()
        if math.abs(mw - cw) > 1 or math.abs(mh - ch) > 1 then
            -- pin extent as pure pixel offsets (scale 0) so the width is mw
            -- exactly; position slots keep whatever applyScroll wrote.
            local ox, oy = content:getDualDim()
            content:setDualDim(ox, oy, mw, mh, 0, 0, 0, 0)
        end
    end)

    local function markDirty() measureDirty = true end

    -- gui has no OnChildAdded; hook creation of content's direct children.
    local createdConn = gui.Events.OnCreated(function(obj)
        if obj.parent == content then markDirty() end
    end)
    content:OnSizeChanged(function(obj) if obj == content then markDirty() end end)
    content:OnPositionChanged(markDirty)
    viewport:OnSizeChanged(markDirty)

    function content:autoMeasure(on)
        measureOn = on ~= false
        measureDirty = true
    end
    function content:markDirty() measureDirty = true end

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
    content._baseSDD = _baseSDD
    function content:setContentSize(cw, ch, full)
        if full then
            _baseSDD(self, nil, nil, nil, ch, nil, nil, 1)
        else
            _baseSDD(self, nil, nil, cw or select(3, self:getAbsolutes()), ch)
        end
        applyScroll()
    end

    local _baseDestroy = viewport.destroy
    function viewport:destroy()
        createdConn:Unconnect()
        content:destroy()
        _baseDestroy(self)
    end

    applyScroll()
    return content
end

-- ── newWindow ─────────────────────────────────────────────────────────────────
--
--   local win = gui:newWindow{
--       x, y, w, h, sx, sy, sw, sh,   -- optional geometry (dualDim)
--       title      = "Title",
--       draggable  = true,            -- header drag (default true)
--       resizable  = false,           -- edge/corner resize handles
--       scrollable = false,           -- content auto-scrolls when children exceed it
--       minW = 200, minH = 120,       -- resize clamps
--       theme = theme:newTheme("#124559"),   -- new-framework theme table/preset
--       fonts = { primary = f1, button = f2 },
--       onClose = function(win) end,
--   }
--
-- Returns the window ROOT frame. Children go on win.content (the scroll
-- content when scrollable). win.header, win.title, win.XButton, win.process,
-- win.root == win.
--
local windowCount = 0
function gui:newWindow(opts)
    opts = opts or {}
    local parent = self

    windowCount = windowCount + 1
    local process = gui:newProcessor("window_" .. windowCount)

    local pointer  = love.mouse.getCursor()
    local sizewe   = love.mouse.getSystemCursor("sizewe")
    local sizens   = love.mouse.getSystemCursor("sizens")
    local sizenesw = love.mouse.getSystemCursor("sizenesw")
    local sizenwse = love.mouse.getSystemCursor("sizenwse")

    local th = windowTheme(opts.theme, opts.fonts)
    local HEADER_H = opts.headerHeight or 30
    local minW     = opts.minW or 200
    local minH     = opts.minH or 120
    local draggable = opts.draggable
    if draggable == nil then draggable = true end

    local root = self:newFrame(opts.x or 40, opts.y or 40,
                               opts.w or 480, opts.h or 320,
                               opts.sx, opts.sy, opts.sw, opts.sh)
    root.clipDescendants = true
    root.__isWindow = true
    root.process = process
    root.root = root

    -- header ────────────────────────────────────────────────────────────────
    local header = root:newFrame(0, 0, 0, HEADER_H, 0, 0, 1)
    header:setRoundness(10, 10, nil, "top")
    header.drawBorder = false
    header.color = th.header
    header.__winInternal = true

    local title = header:newTextLabel(opts.title or "", 5, 0, -28, HEADER_H, 0, 0, 1, 0)
    title.align = gui.ALIGN_LEFT
    title.ignore = true
    title.color = th.header
    title.textColor = th.text
    title:setFont(th.fontPrimary)
    title:fitFont()
    title.__winInternal = true

    local X = header:newTextButton("", -25, math.floor(HEADER_H/2 - 10), 20, 20, 1, 0)
    X:setRoundness(10, 10)
    X:respectHierarchy(false)
    X.align = gui.ALIGN_CENTER
    X.color = color.new("#e50000")
    X.__winInternal = true
    local darkenX = color.darken(color.new("#e50000"), .2)
    X:OnEnter(function(self) self.color = darkenX end)
    X:OnExit(function(self) self.color = color.new("#e50000") end)

    -- content (or scroll content) ───────────────────────────────────────────
    local content
    if opts.scrollable then
        content = root:newScrollFrame(0, HEADER_H, 0, -HEADER_H, 0, 0, 1, 1)
        content:autoMeasure(true)
        content.color = th.bg
        content.drawBorder = false
    else
        content = root:newFrame(0, HEADER_H, 0, -HEADER_H, 0, 0, 1, 1)
        content.color = th.bg
        content.drawBorder = false
    end
    content.clipDescendants = true

    -- resize handles ────────────────────────────────────────────────────────
    local HANDLE = 6
    local handles = {}
    if opts.resizable then
        local defs = {
            { tag = "w",  x = 0,        y = 0,        w = HANDLE, h = 0,   sx = 0, sy = 0, sw = 0, sh = 1, cur = sizewe },
            { tag = "e",  x = -HANDLE,  y = 0,        w = HANDLE, h = 0,   sx = 1, sy = 0, sw = 0, sh = 1, cur = sizewe },
            { tag = "n",  x = HANDLE,   y = 0,        w = -HANDLE*2, h = HANDLE, sx = 0, sy = 0, sw = 1, sh = 0, cur = sizens },
            { tag = "s",  x = HANDLE,   y = -HANDLE,  w = -HANDLE*2, h = HANDLE, sx = 0, sy = 1, sw = 1, sh = 0, cur = sizens },
            { tag = "nw", x = 0,        y = 0,        w = HANDLE, h = HANDLE, cur = sizenwse },
            { tag = "ne", x = -HANDLE,  y = 0,        w = HANDLE, h = HANDLE, sx = 1, cur = sizenesw },
            { tag = "sw", x = 0,        y = -HANDLE,  w = HANDLE, h = HANDLE, sy = 1, cur = sizenesw },
            { tag = "se", x = -HANDLE,  y = -HANDLE,  w = HANDLE, h = HANDLE, sx = 1, sy = 1, cur = sizenwse },
        }
        for _, d in ipairs(defs) do
            local hd = root:newFrame(d.x, d.y, d.w, d.h, d.sx, d.sy, d.sw, d.sh)
            hd.drawBorder = false
            hd.visibility = 0
            hd:respectHierarchy(false)
            hd.__winInternal = true
            hd:enableDragging(gui.MOUSE_PRIMARY)

            hd:OnEnter(function(obj) if obj == hd then love.mouse.setCursor(d.cur) end end)
            hd:OnExit(function(obj)  if obj == hd then love.mouse.setCursor(pointer) end end)
            hd:OnDragStart(function(obj)
                if obj ~= hd then return end
                -- break the window into absolute pixel geometry while resizing
                local rx, ry, rw, rh = root:getAbsolutes()
                root:setDualDim(rx, ry, rw, rh, 0, 0, 0, 0)
            end)
            hd:OnDragging(function(obj, dx, dy)
                if obj ~= hd then return end
                local rx, ry = root:getAbsolutes()
                local scrW, scrH = love.graphics.getDimensions()
                local ox, oy, ow, oh = root:getDualDim()
                local tag = d.tag
                if tag:find("w") then          -- left edge moves
                    local nw = math.max(minW, ow - dx)
                    local nx = ox + (ow - nw)
                    if nx < 0 then nw = nw + nx; nx = 0 end
                    root:setDualDim(nx, nil, nw, nil)
                end
                if tag:find("e") then          -- right edge moves
                    local nw = math.max(minW, ow + dx)
                    if rx + nw > scrW then nw = scrW - rx end
                    root:setDualDim(nil, nil, nw, nil)
                end
                if tag:find("n") then          -- top edge moves
                    local nh = math.max(minH, oh - dy)
                    local ny = oy + (oh - nh)
                    if ny < 0 then nh = nh + ny; ny = 0 end
                    root:setDualDim(nil, ny, nil, nh)
                end
                if tag:find("s") then          -- bottom edge moves
                    local nh = math.max(minH, oh + dy)
                    if ry + nh > scrH then nh = scrH - ry end
                    root:setDualDim(nil, nil, nil, nh)
                end
            end)
            hd:OnDragEnd(function(obj)
                if obj ~= hd then return end
                love.mouse.setCursor(pointer)
            end)
            handles[#handles + 1] = hd
        end
    end

    -- drag (header) + focus raise ───────────────────────────────────────────
    if draggable then
        header:enableDragging(gui.MOUSE_PRIMARY)
        header:OnDragging(function(obj, dx, dy)
            if obj ~= header then return end
            root:move(dx, dy)
        end)
        header:OnDragEnd(function(obj)
            if obj ~= header then return end
            local x, y, w, h = root:getAbsolutes()
            local width, height = love.graphics.getDimensions()
            if x <= 0 then root:setDualDim(0) end
            if y <= 0 then root:setDualDim(nil, 0) end
            if x + w >= width  then root:setDualDim(width - w) end
            if y + h >= height then root:setDualDim(nil, height - h) end
        end)
    end

    -- click anywhere in the window raises it above siblings
    local function raise() root:topStack() end
    root:OnPressed(raise)
    root:OnPressedOuter(raise)

    -- lifecycle ─────────────────────────────────────────────────────────────
    root.OnClose = multi:newConnection()
    X:OnPressed(function()
        root.OnClose:Fire(root)
    end)
    root:OnClose(function()
        root:setParent(gui.virtual)
        love.mouse.setCursor(pointer)
    end)
    function root:close() root.OnClose:Fire(root) end
    function root:open()  root:setParent(parent) end

    function root:setTitle(t)
        title.text = t
        title:fitFont()
    end
    function root:getTitle() return title.text end

    -- theme application (new-framework slots) ───────────────────────────────
    local function styleElement(el)
        if el.__winInternal then return end
        if el:hasType(gui.TYPE_BUTTON) then
            el:setFont(th.fontButton)
            el.color     = th.button
            el.textColor = th.text
            if not el.__themedHover then
                -- Capture the resting color before hovering so custom-colored
                -- buttons (e.g. red kill buttons) aren't clobbered by the
                -- shared theme tables on exit. Assign copies, not the shared
                -- th.button / th.buttonHi tables, so no two elements alias.
                el:OnEnter(function(self)
                    self.__restColor = self.color
                    self.color = color.new(th.buttonHi[1], th.buttonHi[2], th.buttonHi[3], th.buttonHi[4])
                end)
                el:OnExit(function(self)
                    local rest = self.__restColor or th.button
                    self.color = color.new(rest[1], rest[2], rest[3], rest[4])
                end)
                el.__themedHover = true
            end
            el:fitFont()
        elseif el:hasType(gui.TYPE_TEXT) then
            el:setFont(th.fontPrimary)
            el.textColor = th.text
            el:fitFont()
        elseif el:hasType(gui.TYPE_FRAME) then
            el.color = th.bg
        end
    end

    -- OnCreated is a GLOBAL connection: filter by descendant of this window.
    local createdConn = gui.Events.OnCreated(function(obj)
        if obj == root then return end
        if not obj:isDescendantOf(root) then return end
        styleElement(obj)
    end)

    function root:setTheme(th2, fonts)
        th = windowTheme(th2, fonts or opts.fonts)
        header.color  = th.header
        content.color = th.bg
        title.color   = th.header
        title.textColor = th.text
        title:setFont(th.fontPrimary)
        title:fitFont()
        for _, c in ipairs(content.children) do styleElement(c) end
    end
    function root:getTheme() return th end

    root.header, root.content, root.title, root.XButton = header, content, title, X
    root.handles = handles

    root:OnDestroy(function()
        createdConn:Unconnect()
        if process and process.Destroy then pcall(function() process:Destroy() end) end
    end)

    if opts.onClose then root:OnClose(opts.onClose) end

    return root
end

-- ── gui:newMessageBox(options) ────────────────────────────────────────────────
--
--   title / message / buttons / theme / x / y / width / onChoice(label, index)
--   box.OnChoice fires (label, index) on any button, (nil, nil) on X.
--
function gui:newMessageBox(options)
    options = options or {}

    local title    = options.title   or "Message"
    local message  = options.message or nil
    local buttons  = options.buttons or { "OK" }

    local BOX_W     = options.width or 340
    local PAD       = 14
    local MSG_H     = (message and message ~= "") and 60 or 0
    local BTN_H     = 30
    local BTN_GAP   = 8
    local BTN_ROW_PB = 14
    local HEADER_H  = 30

    local BTN_ROW_H = BTN_H + BTN_ROW_PB
    local BOX_H     = 12 + MSG_H + (message and 10 or 0) + BTN_ROW_H

    local sw, sh = love.graphics.getDimensions()
    local wx = options.x or math.floor((sw - BOX_W) / 2)
    local wy = options.y or math.floor((sh - (BOX_H + HEADER_H)) / 2)

    local win = gui:newWindow{
        x = wx, y = wy, w = BOX_W, h = BOX_H,
        title = title,
        draggable = true,
        theme = options.theme,
        headerHeight = HEADER_H,
    }

    win.OnChoice = multi:newConnection()
    if options.onChoice then win:OnChoice(options.onChoice) end

    local host = win.content

    if message and message ~= "" then
        local msgLbl = host:newTextLabel(message, PAD, 12, BOX_W - PAD * 2, MSG_H)
        msgLbl.align    = gui.ALIGN_CENTER
        msgLbl.wordWrap = true
        msgLbl.ignore   = true
    end

    local n        = #buttons
    local totalGap = BTN_GAP * (n - 1)
    local btnW     = math.floor((BOX_W - PAD * 2 - totalGap) / n)
    local btnY     = 12 + MSG_H + (message and 10 or 12)

    for i, label in ipairs(buttons) do
        local btnX = PAD + (i - 1) * (btnW + BTN_GAP)
        local btn  = host:newTextButton(label, btnX, btnY, btnW, BTN_H)
        btn.align  = gui.ALIGN_CENTER

        local capturedLabel, capturedIdx = label, i
        btn:OnReleased(function()
            win.OnChoice:Fire(capturedLabel, capturedIdx)
            win:close()
        end)
    end

    win.XButton:OnPressed(function()
        win.OnChoice:Fire(nil, nil)
    end)

    return win
end

-- ── filesystem helpers (io.popen only) ────────────────────────────────────────
local PATH_SEP   = love.system.getOS() == "Windows" and "\\" or "/"
local IS_WINDOWS = love.system.getOS() == "Windows"

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

-- ── file picker row pool ──────────────────────────────────────────────────────
local PICKER_ROW_H = 28

local function makePickerRowPool(scrollFrame, callback)
    local pool = { rows = {}, active = 0 }

    local function makeRow(idx)
        local yOff = (idx - 1) * PICKER_ROW_H
        local bg = scrollFrame:newFrame(0, yOff, 0, PICKER_ROW_H, 0, 0, 1)  -- scale w=1, no captured w
        bg.drawBorder = false
        local nameLabel = bg:newTextLabel("", 0, 0, 0, PICKER_ROW_H, 0, 0, 1)  -- fills parent width
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
            row.bg:setDualDim(nil, (i - 1) * PICKER_ROW_H)
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
            scrollFrame:setContentSize(400, math.max(#data * PICKER_ROW_H, 1), true)
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

    local pool = makePickerRowPool(scrollContent, function(self)
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

-- ══════════════════════════════════════════════════════════════════════════════
-- TASK MANAGER
--
-- Live table of every processor / actor / thread with sortable columns, a tab
-- bar (Tasks / Errors), a load bar, per-row quick actions, and an inspector
-- pane exposing the full multi control matrix. Data flows:
--
--   collector thread (1 Hz, gated on window open)
--     → snapshot published to `pendingGroups`
--   UpdateManager pass (taskManager:OnUpdate, dirty flag)
--     → pooled row apply + load bar + title
--
-- ══════════════════════════════════════════════════════════════════════════════

-- Columns: Name / Type / State / Status / Uptime / Priority / Pause / Kill
local TM_COLS = {
    { key = "name",     label = "Name",      w = 200, sort = true,  align = 1 },
    { key = "kind",     label = "Type",      w = 90,  sort = true },
    { key = "state",    label = "State",     w = 80,  sort = true },
    { key = "status",   label = "Status",    w = 70,  sort = true },
    { key = "uptime",   label = "Uptime",    w = 70,  sort = true },
    { key = "priority", label = "Priority",  w = 78,  sort = true },
    { key = "pause",    label = "–",         w = 62 },
    { key = "kill",     label = "–",         w = 52 },
}
local TM_ROW_H = 26
local TM_TOTAL_W = 0
for _, c in ipairs(TM_COLS) do TM_TOTAL_W = TM_TOTAL_W + c.w end

local INSPECTOR_W = 292

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

local PRIORITY_CYCLE = { 1, 4, 16, 64, 256, 1024, 4096, 16384, 65536 }
local function fmtPriority(obj)
    local p = rawget(obj, "Priority") or rawget(obj, "priority")
    if not p then return "n/a" end
    return multi.PriorityResolve and multi.PriorityResolve[p] or tostring(p)
end
local function nextPriority(current)
    for i, v in ipairs(PRIORITY_CYCLE) do
        if v == current then
            return PRIORITY_CYCLE[(i % #PRIORITY_CYCLE) + 1]
        end
    end
    return 256
end

local function fmtUptime(secs)
    secs = math.floor(secs)
    if secs < 60   then return secs .. "s" end
    if secs < 3600 then return math.floor(secs/60).."m "..(secs%60).."s" end
    return math.floor(secs/3600).."h "..math.floor((secs%3600)/60).."m"
end

-- Safe object queries: destroyed multi objects are black holes whose every
-- metamethod returns a stub — wrap everything in pcall.
local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r or nil
end

local function objType(obj)
    return safe(function(o) return o.Type end, obj)
end
local function objName(obj)
    return safe(function(o) return o:getName() end, obj) or "?"
end
local function objUptime(obj)
    return nowClock() - (safe(function(o) return o.UPTIME end, obj) or nowClock())
end
local function objPaused(obj)
    return safe(function(o) return o:isPaused() end, obj) or false
end

-- ── snapshot collection ───────────────────────────────────────────────────────
-- Returns ordered groups: { proc = {name, fullname, conns, subs}, rows = {...} }
local function collectGroups()
    local groups = {}
    local stats = multi:getStats()

    local function addProc(fullname, proc)
        local rows = {}
        local tasks = proc.tasks or {}
        for _, task in pairs(tasks) do
            if not task.isProcessThread then
                rows[#rows+1] = {
                    name     = objName(task),
                    fullname = fullname,
                    kind     = tostring(task.Type),
                    state    = fmtState(task),
                    active   = not objPaused(task),
                    uptime   = objUptime(task),
                    priority = rawget(task, "Priority") or 256,
                    fmtPri   = fmtPriority(task),
                    obj      = task,
                    isThread = false,
                }
            end
        end
        local threads = proc.threads or {}
        for _, th in pairs(threads) do
            rows[#rows+1] = {
                name     = objName(th),
                fullname = fullname,
                kind     = tostring(th.Type),
                state    = fmtState(th),
                active   = not objPaused(th),
                uptime   = objUptime(th),
                priority = rawget(th, "Priority") or 256,
                fmtPri   = fmtPriority(th),
                obj      = th,
                isThread = true,
            }
        end
        groups[#groups+1] = {
            proc = {
                name  = proc.name or fullname,
                full  = fullname,
                conns = proc.connections or 0,
                subs  = proc.subscriptions or 0,
            },
            rows = rows,
        }
    end

    if stats["root"] then addProc("root", stats["root"]) end
    local procNames = {}
    for k in pairs(stats) do
        if k ~= "root" then procNames[#procNames+1] = k end
    end
    table.sort(procNames)
    for _, k in ipairs(procNames) do
        addProc(k, stats[k])
    end
    return groups
end

local function sortGroupRows(rows, key, asc)
    table.sort(rows, function(a, b)
        local va, vb
        if key == "name"         then va, vb = a.name or "", b.name or ""
        elseif key == "kind"     then va, vb = a.kind or "", b.kind or ""
        elseif key == "state"    then va, vb = a.state or "", b.state or ""
        elseif key == "status"   then va, vb = (a.active and 0 or 1), (b.active and 0 or 1)
        elseif key == "uptime"   then va, vb = a.uptime or 0, b.uptime or 0
        elseif key == "priority" then va, vb = a.priority or 256, b.priority or 256
        else va, vb = tostring(a[key] or ""), tostring(b[key] or "") end
        if va == vb then
            if a.isThread ~= b.isThread then return a.isThread == false end
            return (a.name or "") < (b.name or "")
        end
        if asc then return va < vb else return va > vb end
    end)
end

-- ── task manager state ────────────────────────────────────────────────────────
local taskManager
local tmUI = {}   -- shared state the closure below fills in at build time

function gui:showTaskManager()
    if taskManager then return end

    local TM_THEME = windowTheme(theme:newTheme("#124559"))

    local WIN_W = TM_TOTAL_W + INSPECTOR_W + 20
    local WIN_H = 640

    local tm = gui:newWindow{
        x = 40, y = 40, w = WIN_W, h = WIN_H,
        title      = "Task Manager",
        draggable  = true,
        resizable  = true,
        minW       = 720,
        minH       = 380,
        theme      = theme:newTheme("#124559"),
    }
    taskManager = tm
    tmUI.win = tm

    local TAB_H   = 28
    local LOAD_H  = 20
    local TOOL_H  = 30

    -- tab bar ───────────────────────────────────────────────────────────────
    local currentTab = 1
    local taskPanel, errorPanel

    local tabBar = tm.content:newFrame(0, 0, 0, TAB_H, 0, 0, 1)
    tabBar.color      = TM_THEME.header
    tabBar.drawBorder = false

    local tabs = {"Tasks", "Errors"}
    for i, label in ipairs(tabs) do
        local btn = tabBar:newTextButton(label, (i-1)*90, 0, 90, TAB_H)
        btn.align = gui.ALIGN_CENTER
        btn:OnReleased(function()
            currentTab = i
            taskPanel.visible  = (i == 1)
            errorPanel.visible = (i == 2)
        end)
    end

    -- tasks panel ────────────────────────────────────────────────────────────
    taskPanel = tm.content:newFrame(0, TAB_H, 0, -TAB_H, 0, 0, 1, 1)
    taskPanel.drawBorder = false
    taskPanel.clipDescendants = true

    local loadStrip = taskPanel:newFrame(0, 0, TM_TOTAL_W, LOAD_H)
    loadStrip.color      = TM_THEME.header
    loadStrip.drawBorder = false
    local loadFill = loadStrip:newFrame(0, 2, 1, LOAD_H - 4)
    loadFill.color      = { 0.1, 0.6, 0.3 }
    loadFill.drawBorder = false
    local loadLbl = loadStrip:newTextLabel("Load: …", 4, 0, TM_TOTAL_W - 8, LOAD_H)
    loadLbl.align  = gui.ALIGN_LEFT
    loadLbl.ignore = true
    loadLbl.visibility = 0

    -- toolbar: search + filter + sort indicator
    local toolbar = taskPanel:newFrame(0, LOAD_H, TM_TOTAL_W, TOOL_H)
    toolbar.drawBorder = false

    local searchLbl = toolbar:newTextLabel("Search:", 4, 0, 52, TOOL_H)
    searchLbl.ignore = true
    searchLbl.textColor = TM_THEME.text
    local searchBox = toolbar:newTextBox("", 58, 2, 160, TOOL_H - 4)
    searchBox.filter = ""

    local filterNames = {"all", "threads", "actors", "processors", "services", "connectors"}
    local filterIdx = 1
    local filterBtn = toolbar:newTextButton("Filter: all", 226, 2, 110, TOOL_H - 4)
    filterBtn.align = gui.ALIGN_CENTER
    filterBtn:OnReleased(function()
        filterIdx = filterIdx % #filterNames + 1
        filterBtn.text = "Filter: " .. filterNames[filterIdx]
        tmUI.dirty = true
    end)

    local refreshBtn = toolbar:newTextButton("Refresh", 344, 2, 70, TOOL_H - 4)
    refreshBtn.align = gui.ALIGN_CENTER
    refreshBtn:OnReleased(function() tmUI.dirty = true end)

    -- column headers (sortable)
    local sortKey, sortAsc = "name", true
    local colHdr = taskPanel:newFrame(0, LOAD_H + TOOL_H, TM_TOTAL_W, TM_ROW_H)
    colHdr.color      = TM_THEME.header
    colHdr.drawBorder = false

    local function updateHeaderLabels()
        for i, c in ipairs(TM_COLS) do
            local lbl = colHdr.children[i]
            if lbl and c.sort then
                local arrow = (sortKey == c.key) and (sortAsc and " ▲" or " ▼") or ""
                lbl.text = c.label .. arrow
            end
        end
    end

    local colX = 0
    for i, c in ipairs(TM_COLS) do
        if c.sort then
            local btn = colHdr:newTextButton(c.label, colX, 0, c.w, TM_ROW_H)
            btn.align = c.align or gui.ALIGN_CENTER
            local key = c.key
            btn:OnReleased(function()
                if sortKey == key then sortAsc = not sortAsc
                else sortKey, sortAsc = key, true end
                updateHeaderLabels()
                tmUI.dirty = true
            end)
        else
            local lbl = colHdr:newTextLabel(c.label, colX, 0, c.w, TM_ROW_H)
            lbl.align  = gui.ALIGN_CENTER
            lbl.ignore = true
            lbl.textColor = TM_THEME.text
        end
        colX = colX + c.w
    end
    updateHeaderLabels()

    -- scrollable row area + inspector ───────────────────────────────────────
    local listTop = LOAD_H + TOOL_H + TM_ROW_H
    local rowScroll = taskPanel:newScrollFrame(0, listTop, TM_TOTAL_W, -listTop, 0, 0, 0, 1)
    rowScroll.drawBorder = false

    local inspector = tm.content:newFrame(TM_TOTAL_W + 12, TAB_H, INSPECTOR_W, -TAB_H, 0, 0, 0, 1)
    inspector.drawBorder = false
    inspector.clipDescendants = true
    local inspScroll = inspector:newScrollFrame(0, 0, INSPECTOR_W, 0, 0, 0, 0, 1)
    inspScroll.drawBorder = false
    inspScroll:autoMeasure(true)
    tmUI.inspector = inspScroll

    -- error panel ────────────────────────────────────────────────────────────
    errorPanel = tm.content:newFrame(0, TAB_H, 0, -TAB_H, 0, 0, 1, 1)
    errorPanel.drawBorder = false
    errorPanel.clipDescendants = true
    errorPanel.visible = false

    local errHdr = errorPanel:newFrame(0, 0, 0, TM_ROW_H, 0, 0, 1)
    errHdr.color      = TM_THEME.header
    errHdr.drawBorder = false
    local errTitle = errHdr:newTextLabel("Error Log", 4, 0, 200, TM_ROW_H)
    errTitle.align  = gui.ALIGN_LEFT
    errTitle.ignore = true

    local clearBtn = errHdr:newTextButton("Clear", -70, 2, 66, TM_ROW_H - 4, 1)
    clearBtn.align = gui.ALIGN_CENTER

    local errScroll = errorPanel:newScrollFrame(0, TM_ROW_H, 0, -TM_ROW_H, 0, 0, 1, 1)
    clearBtn:OnReleased(function() tmUI.errorPool:clear() end)

    -- row pool ───────────────────────────────────────────────────────────────
    local COLOR_DEAD = { 0.5, 0.1, 0.1 }

    local function makeRow(idx)
        local yOff = (idx - 1) * TM_ROW_H
        local bg = rowScroll:newFrame(0, yOff, TM_TOTAL_W, TM_ROW_H)
        bg.drawBorder = false
        bg:respectHierarchy(false)

        local labels = {}
        local cx = 0
        for i, c in ipairs(TM_COLS) do
            if c.key == "pause" or c.key == "kill" then
                local b = bg:newTextButton("", cx + 2, 2, c.w - 4, TM_ROW_H - 4)
                b.align = gui.ALIGN_CENTER
                if c.key == "kill" then
                    b.color = color.darken(color.new("#e50000"), .1)
                end
                labels[c.key] = b
            else
                local lbl = bg:newTextLabel("", cx + 2, 0, c.w - 4, TM_ROW_H)
                lbl.align = c.align or gui.ALIGN_CENTER
                lbl.ignore = true
                labels[c.key] = lbl
            end
            cx = cx + c.w
        end

        local row = { bg = bg, labels = labels, obj = nil, isProc = false }

        -- click empty row area → select for inspector
        bg:OnReleased(function()
            if row.isProc then return end
            tmUI.selected = row.obj
            tmUI.buildInspector()
        end)

        labels.pause:OnReleased(function()
            if not row.obj then return end
            if objPaused(row.obj) then
                safe(function(o) o:Resume() end, row.obj)
            else
                safe(function(o) o:Pause() end, row.obj)
            end
            tmUI.dirty = true
        end)

        labels.kill:OnReleased(function()
            if not row.obj then return end
            safe(function(o)
                if o.Kill then o:Kill()
                elseif o.Destroy then o:Destroy()
                elseif o.Break then o:Break() end
            end, row.obj)
            bg.color = COLOR_DEAD
        end)

        -- priority cell click cycles priority
        labels.priority.ignore = false
        labels.priority:OnReleased(function()
            if not row.obj then return end
            local cur = rawget(row.obj, "Priority") or 256
            local nx = nextPriority(cur)
            safe(function(o, v) o:setPriority(v) end, row.obj, nx)
            tmUI.dirty = true
        end)

        return row
    end

    local pool = { rows = {} }

    -- Hover tracking is gated on visibility, so elements that get hidden or
    -- reassigned while hovered never fire OnExit: their `entered` flag and
    -- hover color would stick onto the next row that reuses them. Reset the
    -- hover state (fire the themed OnExit, which restores __restColor) before
    -- hiding or recycling a row's elements.
    local function resetHover(el)
        if el.entered then
            el.entered = false
            el.OnExit:Fire(el)
        end
    end

    function pool:apply(groups)
        local idx = 0
        for _, g in ipairs(groups) do
            idx = idx + 1
            while #self.rows < idx do self.rows[#self.rows + 1] = makeRow(#self.rows + 1) end
            local row = self.rows[idx]
            row.isProc, row.obj = true, nil
            row.bg:setDualDim(nil, (idx - 1) * TM_ROW_H)
            row.bg.visible = true
            row.bg.color = TM_THEME.header
            for k, el in pairs(row.labels) do
                if el:hasType(gui.TYPE_BUTTON) then
                    resetHover(el)
                    el.visible = false
                else
                    el.text = ""
                end
            end
            row.labels.name.text  = "[" .. g.proc.name .. "]"
            row.labels.kind.text  = "processor"
            row.labels.uptime.text = g.proc.conns .. "c/" .. g.proc.subs .. "s"

            for _, d in ipairs(g.rows) do
                idx = idx + 1
                while #self.rows < idx do self.rows[#self.rows + 1] = makeRow(#self.rows + 1) end
                row = self.rows[idx]
                row.isProc, row.obj = false, d.obj
                row.bg:setDualDim(nil, (idx - 1) * TM_ROW_H)
                row.bg.visible = true
                row.bg.color = (idx % 2 == 0) and TM_THEME.bg or TM_THEME.header
                row.labels.name.text     = "  " .. (d.name or "")
                row.labels.kind.text     = d.kind or ""
                row.labels.state.text    = d.state or ""
                row.labels.status.text   = d.active and "Running" or "Paused"
                row.labels.uptime.text   = fmtUptime(d.uptime)
                row.labels.priority.text = d.fmtPri or ""
                row.labels.pause.visible = true
                row.labels.pause.text    = d.active and "Pause" or "Resume"
                row.labels.kill.visible  = true
            end
        end
        for i = idx + 1, #self.rows do
            for _, el in pairs(self.rows[i].labels) do
                resetHover(el)
            end
            self.rows[i].bg.visible = false
            self.rows[i].obj = nil
        end
        rowScroll:setContentSize(TM_TOTAL_W, math.max(idx * TM_ROW_H, 1))
    end

    -- error pool ─────────────────────────────────────────────────────────────
    local ERROR_ROW_H = 22
    local MAX_ERRORS  = 200
    local errorPool = { rows = {}, entries = {} }
    tmUI.errorPool = errorPool

    function errorPool:addEntry(msg, source)
        if #self.entries >= MAX_ERRORS then table.remove(self.entries, 1) end
        local ts = string.format("[%6.1fs]", nowClock())
        self.entries[#self.entries + 1] = ts .. " [" .. (source or "?") .. "] " .. tostring(msg)
        self:refresh()
    end

    function errorPool:refresh()
        local n = #self.entries
        while #self.rows < n do
            local yOff = (#self.rows) * ERROR_ROW_H
            local bg = errScroll:newFrame(0, yOff, TM_TOTAL_W, ERROR_ROW_H)
            bg.color      = (#self.rows % 2 == 0) and TM_THEME.bg or TM_THEME.header
            bg.drawBorder = false
            local lbl = bg:newTextLabel("", 4, 0, TM_TOTAL_W - 4, ERROR_ROW_H)
            lbl.align  = gui.ALIGN_LEFT
            lbl.ignore = true
            self.rows[#self.rows + 1] = { bg = bg, lbl = lbl }
        end
        for i, entry in ipairs(self.entries) do
            local row = self.rows[i]
            row.bg:setDualDim(nil, (i - 1) * ERROR_ROW_H)
            row.bg.visible = true
            row.lbl.text   = entry
        end
        for i = n + 1, #self.rows do self.rows[i].bg.visible = false end
        errScroll:setContentSize(TM_TOTAL_W, math.max(n * ERROR_ROW_H, 1))
        errScroll:scrollToBottom()
    end

    function errorPool:clear()
        self.entries = {}
        self:refresh()
    end

    -- error capture: thread errors fire on the thread's own OnError; hook
    -- existing + future threads on every processor (incl. thread manager).
    local hookedThreads = {}
    local function hookThread(th, procName)
        if not th.OnError then return end
        if hookedThreads[th] then return end
        hookedThreads[th] = true
        th.OnError(function(self, err)
            local msg = type(err) == "string" and err or tostring(err or "unknown error")
            local name = objName(th)
            errorPool:addEntry(msg, procName .. "/" .. name)
        end)
    end
    local function hookProc(proc, procName)
        local threads = safe(function(p) return p:getThreads() end, proc) or {}
        for _, th in ipairs(threads) do hookThread(th, procName) end
        safe(function(p)
            p.OnObjectCreated(function(obj)
                if obj.Type == "thread" then hookThread(obj, procName) end
            end)
        end, proc)
    end
    hookProc(multi, "root")
    for _, proc in ipairs(multi:getProcessors()) do
        hookProc(proc, objName(proc))
    end
    multi.OnObjectCreated(function(obj)
        if obj.Type == "process" then
            hookProc(obj, objName(obj))
        elseif obj.Type == "thread" then
            hookThread(obj, "root")
        end
    end)
    local tmulti = multi:getThreadManagerProcess()
    if tmulti then hookProc(tmulti, "threads") end

    -- ── inspector pane ──────────────────────────────────────────────────────
    local function actBtn(host, x, y, w, label, fn)
        local b = host:newTextButton(label, x, y, w, 24)
        b.align = gui.ALIGN_CENTER
        b:OnReleased(function()
            safe(fn)
            -- destroyed multi objects are black holes; Type stops being a string
            if tmUI.selected and type(objType(tmUI.selected)) ~= "string" then
                tmUI.selected = nil
            end
            tmUI.dirty = true
            tmUI.buildInspector()
        end)
        return b
    end

    local function infoLine(host, y, text)
        local l = host:newTextLabel(text, 0, y, INSPECTOR_W - 4, 18)
        l.align  = gui.ALIGN_LEFT
        l.ignore = true
        return l
    end

    function tmUI.buildInspector()
        local host = tmUI.inspector
        host:removeChildren()
        host:setContentSize(INSPECTOR_W, 1)

        local sel = tmUI.selected
        if not sel then
            infoLine(host, 0, "Select a row to inspect.")
            host:setContentSize(INSPECTOR_W, 24)
            return
        end

        local y = 0
        local t = objType(sel) or "?"
        infoLine(host, y, "Type: " .. tostring(t)); y = y + 18
        infoLine(host, y, "Name: " .. objName(sel)); y = y + 18
        infoLine(host, y, "Uptime: " .. fmtUptime(objUptime(sel))); y = y + 18
        local ts = safe(function(o) return o:GetCreationTimestamp() end, sel)
        if ts then infoLine(host, y, "Created: " .. tostring(ts)); y = y + 18 end
        local pri = fmtPriority(sel)
        if pri ~= "n/a" then infoLine(host, y, "Priority: " .. pri); y = y + 18 end
        y = y + 6

        local COL1, COL2 = math.floor((INSPECTOR_W - 12) / 2), math.floor((INSPECTOR_W - 12) / 2)

        -- rename (any named multi object)
        local nameBox = host:newTextBox(objName(sel), 0, y, INSPECTOR_W - 70, 24)
        actBtn(host, INSPECTOR_W - 66, y, 66, "Rename", function()
            safe(function(o, n) o:setName(n) end, sel, nameBox.text)
        end)
        y = y + 30

        -- priority controls
        if rawget(sel, "Priority") or objType(sel) ~= "connector" then
            actBtn(host, 0, y, COL1, "Priority +", function()
                sel:setPriority(nextPriority(rawget(sel, "Priority") or 256))
            end)
            actBtn(host, COL1 + 6, y, COL2, "Reset priority", function()
                safe(function(o) o:ResetPriority() end, sel)
            end)
            y = y + 28
        end

        -- actors (anything with an Act method)
        if safe(function(o) return o:IsAnActor() end, sel) then
            actBtn(host, 0, y, COL1, objPaused(sel) and "Resume" or "Pause", function()
                if sel:isPaused() then sel:Resume() else sel:Pause() end
            end)
            actBtn(host, COL1 + 6, y, COL2, "Break", function() sel:Break() end)
            y = y + 28
            actBtn(host, 0, y, COL1, "Reset", function() sel:Reset() end)
            actBtn(host, COL1 + 6, y, COL2, "Destroy", function() sel:Destroy() end)
            y = y + 28
            local timeBox = host:newTextBox("3", 0, y, INSPECTOR_W - 150, 24)
            actBtn(host, INSPECTOR_W - 144, y, 72, "SetTime", function()
                sel:SetTime(tonumber(timeBox.text) or 3)
            end)
            actBtn(host, INSPECTOR_W - 68, y, 68, "Resolve", function()
                safe(function(o) o:ResolveTimer() end, sel)
            end)
            y = y + 30
        end

        -- threads: kill + sleep
        if t == "thread" then
            actBtn(host, 0, y, COL1, "Kill", function() sel:Kill() end)
            local sleepBox = host:newTextBox("1", INSPECTOR_W - 140, y, 70, 24)
            actBtn(host, INSPECTOR_W - 64, y, 64, "Sleep", function()
                sel:Sleep(tonumber(sleepBox.text) or 1)
            end)
            y = y + 30
        end

        -- processors
        if t == "process" or t == "rootprocess" then
            actBtn(host, 0, y, COL1, "Start", function() safe(function(o) o.Start() end, sel) end)
            actBtn(host, COL1 + 6, y, COL2, "Stop", function() safe(function(o) o.Stop() end, sel) end)
            y = y + 28
            actBtn(host, 0, y, COL1, "boost(1)", function() sel:boost(1) end)
            actBtn(host, COL1 + 6, y, COL2, "Destroy", function() sel:Destroy() end)
            y = y + 28
            local maxBox = host:newTextBox("64", 0, y, INSPECTOR_W - 150, 24)
            actBtn(host, INSPECTOR_W - 144, y, 144, "setMaxThreads", function()
                sel:setMaxThreads(tonumber(maxBox.text) or 64)
            end)
            y = y + 30
            local delayBox = host:newTextBox("0", 0, y, INSPECTOR_W - 150, 24)
            actBtn(host, INSPECTOR_W - 144, y, 144, "setTaskDelay", function()
                sel:setTaskDelay(tonumber(delayBox.text) or 0)
            end)
            y = y + 30
        end

        -- services
        if t == "service" then
            actBtn(host, 0, y, COL1, "Start", function() sel.Start() end)
            actBtn(host, COL1 + 6, y, COL2, "Stop", function() sel.Stop() end)
            y = y + 28
            actBtn(host, 0, y, COL1, "Pause", function() sel:Pause() end)
            actBtn(host, COL1 + 6, y, COL2, "Resume", function() sel:Resume() end)
            y = y + 28
        end

        -- connections
        if t == "connector" then
            actBtn(host, 0, y, INSPECTOR_W, "Destroy connection", function()
                sel:Destroy()
            end)
            y = y + 28
        end

        -- reallocate to another processor
        local procBox = host:newTextBox("root", 0, y, INSPECTOR_W - 116, 24)
        actBtn(host, INSPECTOR_W - 110, y, 110, "Reallocate", function()
            local name = procBox.text
            for _, p in ipairs(multi:getProcessors()) do
                if objName(p) == name then
                    safe(function(o, pr) o:reallocate(pr) end, sel, p)
                    return
                end
            end
            if name == "root" then
                safe(function(o, pr) o:reallocate(pr) end, sel, multi)
            end
        end)
        y = y + 30

        host:setContentSize(INSPECTOR_W, math.max(y, 1))
    end
    tmUI.buildInspector()

    -- ── pipeline state ───────────────────────────────────────────────────────
    tmUI.dirty   = true
    tmUI.pending = nil
    tmUI.selected = nil

    local function isOpen()
        return tm:isActive()
    end

    -- collector: 1 Hz snapshot while the window is open
    tm.process:newThread("TM_collect", function()
        while true do
            thread.hold(isOpen)
            local groups = collectGroups()
            if sortKey then
                for _, g in ipairs(groups) do
                    sortGroupRows(g.rows, sortKey, sortAsc)
                end
            end
            -- filter
            local fname = filterNames[filterIdx]
            local needle = searchBox.filter
            if fname ~= "all" or needle ~= "" then
                for _, g in ipairs(groups) do
                    local keep = {}
                    for _, r in ipairs(g.rows) do
                        local okType = true
                        if fname == "threads"     then okType = (r.kind == "thread")
                        elseif fname == "actors"  then okType = (r.kind ~= "thread")
                        elseif fname == "processors" then okType = false
                        elseif fname == "services"   then okType = (r.kind == "service")
                        elseif fname == "connectors" then okType = (r.kind == "connector") end
                        if okType and needle ~= "" then
                            okType = (r.name or ""):lower():find(needle:lower(), 1, true) ~= nil
                        end
                        if okType then keep[#keep+1] = r end
                    end
                    g.rows = keep
                end
                -- "processors" keeps the group headers and empties their rows
                -- (the row filter above already cleared them).
            end
            tmUI.pending = groups
            tmUI.dirty = true
            thread.sleep(1)
        end
    end)

    searchBox:OnReturn(function(_, text)
        searchBox.filter = text or ""
        tmUI.dirty = true
    end)
    searchBox:OnReleasedOther(function()
        searchBox.filter = searchBox.text or ""
        tmUI.dirty = true
    end)

    -- load probe (idempotent; getLoad() is non-blocking)
    local schedulerProbe = require("gui.core.probe")
    schedulerProbe:install(multi)

    -- main-thread apply
    tm:OnUpdate(function()
        tm:topStack()
        if tmUI.dirty and tmUI.pending then
            tmUI.dirty = false
            local groups = tmUI.pending
            tmUI.pending = nil
            pool:apply(groups)
            local n = 0
            for _, g in ipairs(groups) do n = n + #g.rows end
            tm:setTitle("Task Manager  —  " .. n .. " objects")
        end

        local pct, lagMs = multi:getLoad()
        local _, _, barW = loadStrip:getAbsolutes()
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
ToggleTaskManager = gui:setHotKey({"lctrl", "`"}) +
                    gui:setHotKey({"rctrl", "`"})

ToggleTaskManager(function()
    if not taskManager then
        gui:showTaskManager()
    elseif taskManager:isActive() then
        taskManager:close()
    else
        taskManager:open()
    end
end)
