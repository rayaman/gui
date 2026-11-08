-- main.lua — standalone LÖVE demo + autotest for gui:newListFrame
-- (addons/extensions.lua).
--
-- Run:  love examples/list-demo                 (interactive: three live lists,
--                                               Add/Remove/Clear buttons, full
--                                               hover/press/selection motion)
--       love examples/list-demo --list-autotest (scripted checks on stdout,
--                                               PASS/FAIL summary, quits)
--
-- Autotest coverage: layout math, selection events, the invisible-text
-- regression (unselected rows must render nothing), remove/insert/removeValue
-- with reflow + selection reassignment, off-screen select -> smooth scroll,
-- simulated clicks (press feedback, double-click, right-click, click-away),
-- keyboard nav (instant, no tween), Delete key, empty placeholder, rapid
-- add/remove interruption, and worst-case data (300 rows, long unbreakable
-- text, one-letter and empty labels).

-- ---------------------------------------------------------------------------
-- Boot (same pattern as examples/flex-demo)
-- ---------------------------------------------------------------------------
local gameDir = love.filesystem.getRealDirectory("main.lua") or "."
local guiRoot = (gameDir .. "/../../.."):gsub("\\", "/")
local multiRoot = (guiRoot .. "/../../multi"):gsub("\\", "/")

local AUTO_TEST = false

love.filesystem.mount(guiRoot, "gui")
love.filesystem.mount(multiRoot, "multi")
package.path = table.concat({
    gameDir .. "/?.lua",
    guiRoot .. "/?.lua",
    guiRoot .. "/?/init.lua",
    multiRoot .. "/?.lua",
    multiRoot .. "/?/init.lua",
    package.path,
}, ";")

local multi = require("multi")
local gui   = require("gui")
-- addons/system requires `socket` at load time (task-manager clock only);
-- stub it like the other demos do.
package.loaded["socket"] = package.loaded["socket"] or { gettime = love.timer.getTime }
require("gui.addons")
local verify = require("verify")

-- ---------------------------------------------------------------------------
-- Test bookkeeping
-- ---------------------------------------------------------------------------
local checks = { passed = 0, failed = 0 }

local function check(name, cond)
    if cond then
        checks.passed = checks.passed + 1
        print("PASS [" .. name .. "]")
    else
        checks.failed = checks.failed + 1
        print("FAIL [" .. name .. "]")
    end
    return cond
end

local function rowRect(name, row, ex, ey, ew, eh)
    local x, y, w, h = row:getAbsolutes()
    local ok = verify.rectApprox(name, x, y, w, h, ex, ey, ew, eh)
    return check(name, ok)
end

-- ---------------------------------------------------------------------------
-- Scene
-- ---------------------------------------------------------------------------
local ROWH, GAP = 28, 2
local list, listB, listC          -- test list / striped demo / no-anim demo
local log, dbl, rmb = {}, nil, nil
local frame = 0

local function baseItems()
    return {
        { text = "Alpha",   value = 1 },
        { text = "Bravo",   value = 2 },
        { text = "Charlie", value = 3 },
        { text = "Delta",   value = 4 },
    }
end

local function build()
    local bg = gui:newFrame(0, 0, 0, 0, 0, 0, 1, 1)
    bg.color = { .11, .12, .15, 1 }
    bg.drawBorder = false

    local title = gui:newTextLabel("newListFrame — selection, motion, removal",
                                   20, 16, 500, 26, 0, 0, 0, 0)
    title.align = gui.ALIGN_LEFT
    title.textColor = { .92, .93, .96, 1 }
    title:scaleFont(.8)
    title.drawBorder = false

    -- primary test list
    list = gui:newListFrame(20, 60, 320, 300, 0, 0, 0, 0, {
        rowHeight = ROWH, gap = GAP,
        items     = baseItems(),
        keyboard  = true,
        emptyText = "Nothing here yet",
        align     = gui.ALIGN_LEFT,
        onChange = function(i, v) log[#log + 1] = { i = i, v = v } end,
        onDoubleClicked = function(i, v) dbl = { i = i, v = v } end,
        onRightClick    = function(i, v) rmb = { i = i, v = v } end,
    })

    -- striped demo list (visual only)
    local itemsB = {}
    for i = 1, 8 do itemsB[i] = "Striped row " .. i end
    listB = gui:newListFrame(360, 60, 250, 240, 0, 0, 0, 0, {
        items = itemsB, striped = true, rowHeight = ROWH, gap = GAP,
        keyboard = true,
    })

    -- instant variant (animate = false)
    listC = gui:newListFrame(360, 320, 250, 140, 0, 0, 0, 0, {
        items = { "No", "Animation", "Here" }, animate = false,
        rowHeight = ROWH, gap = GAP,
    })

    -- interactive controls
    local function button(label, x, y, fn)
        local b = gui:newTextButton(label, x, y, 100, 30, 0, 0, 0, 0)
        b:OnReleased(fn)
        return b
    end
    local n = 0
    button("Add",    20,  372, function() n = n + 1; list:add("Added " .. n, 100 + n) end)
    button("Remove", 130, 372, function()
        local i = list:getSelected()
        list:remove(i or list:getItemCount())
    end)
    button("Clear",  240, 372, function() list:clear() end)
    button("Refill", 20,  410, function() list:setItems(baseItems()) end)
    button("Insert", 130, 410, function() list:insert(2, "Inserted", 999) end)
    button("Select 40", 240, 410, function()
        local items = {}
        for i = 1, 40 do items[i] = "Item " .. i end
        list:setItems(items)
        list:select(40)
    end)

    local hint = gui:newTextLabel(
        "hover / press / select the rows · ↑↓ PgUp PgDn Home End Del (click a list first to focus it) · double-click and right-click log to console",
        20, 460, 860, 40, 0, 0, 0, 0)
    hint.textColor = { .55, .58, .64, 1 }
    hint.align = gui.ALIGN_LEFT
    hint:scaleFont(.45)
    hint.drawBorder = false
end

-- ---------------------------------------------------------------------------
-- Simulated input helpers (go through the real love.event queue so the whole
-- input pipeline — canPress, hierarchy gating, scissor clip — is exercised)
-- ---------------------------------------------------------------------------
local function moveTo(x, y)
    love.mouse.setPosition(x, y)
    love.event.push("mousemoved", x, y, 0, 0, false)
end
local function click(x, y, button)
    button = button or 1
    love.event.push("mousepressed", x, y, button, false, {})
    love.event.push("mousereleased", x, y, button, false, {})
end
local function pressKey(k) love.event.push("keypressed", k, 0, false) end

local function rowCenter(box, i)
    local row = box:getRow(i)
    if not row then return 0, 0 end
    local x, y, w, h = row:getAbsolutes()
    return x + w / 2, y + h / 2
end

-- ---------------------------------------------------------------------------
-- Scripted autotest: a tiny sequencer, one step per frame. waitSettle steps
-- poll box:isSettling() so layout/geometry checks always run on settled state.
-- ---------------------------------------------------------------------------
local seq, si = {}, 1

local function step(name, fn) seq[#seq + 1] = { name = name, fn = fn } end
-- Wall-clock settle: tweens advance on real dt, but autotest frames can run
-- far faster (or slower, unfocused cap) than realtime, so a frame budget
-- tears down mid-flight. Wait on actual settling; the deadline is computed
-- LAZILY when the step first runs (buildSeq queues everything at load time).
local function waitSettle(box, maxSeconds)
    seq[#seq + 1] = { name = "settle", wait = box, maxSeconds = maxSeconds or 4 }
end
local function frames(n)
    for _ = 1, n do seq[#seq + 1] = { name = "frame", tick = true } end
end

local function buildSeq()
    step("initial count == 4", function()
        check("initial count", list:getItemCount() == 4)
    end)
    waitSettle(list)
    step("initial layout + autoMeasure extent", function()
        rowRect("row1 pos", list:getRow(1), 20, 60 + GAP, 320, ROWH)
        rowRect("row4 pos", list:getRow(4), 20, 60 + GAP + 3 * (ROWH + GAP), 320, ROWH)
        local _, _, _, ch = list:getAbsolutes()
        check("content extent grows for scroll", math.abs(ch - (GAP + 4 * (ROWH + GAP) - GAP)) < 1)
    end)

    -- the invisible-text regression: unselected rows must paint nothing
    step("unselected rows transparent", function()
        local ok = true
        for i = 1, 4 do
            if list:getRow(i).visibility ~= 0 then ok = false end
        end
        check("unselected row fill alpha == 0", ok)
    end)

    step("select(2) fires onChange + paints nav", function()
        list:select(2)
        local i, v = list:getSelected()
        check("getSelected after select", i == 2 and v == 2)
        check("onChange logged (2,2)", log[#log] and log[#log].i == 2 and log[#log].v == 2)
        check("selected row fill target 1", list:getRow(2).__fillTo == 1)
    end)
    waitSettle(list)
    step("selected row settled opaque", function()
        check("selected row visibility == 1", list:getRow(2).visibility == 1)
        check("unselected still transparent", list:getRow(1).visibility == 0)
    end)

    -- removal: count drops immediately, selection reassigns, geometry reflows
    step("remove selected row", function()
        local removed = list:remove(2)
        check("remove returns value", removed == 2)
        check("count after remove", list:getItemCount() == 3)
        check("live indices skip ghosts", select(1, list:getItem(2)) == "Charlie")
        local i, v = list:getSelected()
        check("selection reassigned", i == 2 and v == 3)
        check("remove reselect fired", log[#log] and log[#log].i == 2 and log[#log].v == 3)
    end)
    waitSettle(list)
    step("reflow after remove", function()
        rowRect("reflow row1", list:getRow(1), 20, 60 + GAP, 320, ROWH)
        rowRect("reflow row2", list:getRow(2), 20, 60 + GAP + (ROWH + GAP), 320, ROWH)
        rowRect("reflow row3", list:getRow(3), 20, 60 + GAP + 2 * (ROWH + GAP), 320, ROWH)
    end)

    step("insert at live index 2", function()
        list:insert(2, "Echo", 42)
        check("count after insert", list:getItemCount() == 4)
        check("inserted at 2", select(1, list:getItem(2)) == "Echo")
        check("indexOf value", list:indexOf(42) == 2)
    end)
    waitSettle(list)
    step("removeValue", function()
        local i = list:removeValue(42)
        check("removeValue index", i == 2)
        check("count after removeValue", list:getItemCount() == 3)
        check("indexOf gone", list:indexOf(42) == nil)
    end)
    waitSettle(list)

    -- off-screen selection smooth-scrolls the viewport
    step("40 items, select off-screen", function()
        local items = {}
        for i = 1, 40 do items[i] = "Item " .. i end
        list:setItems(items)
        list:select(40)
    end)
    waitSettle(list, 6)
    step("scroll followed selection", function()
        local _, sy = list:getScrollPos()
        check("viewport scrolled", sy > 100)
        local x, y, w, h = list:getRow(40):getAbsolutes()
        local _, vy, _, vh = list.parent:getAbsolutes()
        check("row 40 inside viewport", y + h <= vy + vh + 1 and y >= vy - 1)
    end)

    -- programmatic scroll + scrollToShow (no OS-cursor dependency)
    step("scrollBy + scrollToShow(5)", function()
        list:scrollBy(120)
        local _, sy0 = list:getScrollPos()
        check("scrollBy applied", math.abs(sy0) >= 1)
        list:scrollToShow(5)
    end)
    waitSettle(list, 4)
    step("scrollToShow landed row 5", function()
        local _, vy, _, vh = list.parent:getAbsolutes()
        local _, ry, _, rh = list:getRow(5):getAbsolutes()
        check("row 5 fully visible", ry >= vy - 1 and ry + rh <= vy + vh + 1)
    end)

    -- simulated click: selection + press-feedback cleanup. Rows clipped by the
    -- viewport can't receive clicks (canPress intersects the scissor), so
    -- scroll home first and target a visible row.
    step("click selects row 3", function()
        list:scrollToTop()
        local cx, cy = rowCenter(list, 3)
        moveTo(cx, cy)
        click(cx, cy)
    end)
    frames(2)
    step("click results", function()
        local i = list:getSelected()
        check("click selected 3", i == 3)
        check("press state cleared", list:getRow(3).__down == false or list:getRow(3).__down == nil)
    end)

    step("double-click hook", function()
        dbl = nil
        local cx, cy = rowCenter(list, 3)
        moveTo(cx, cy)
        click(cx, cy)
        click(cx, cy)          -- same frame: within the 0.35 s window
    end)
    frames(2)
    step("double-click fired", function()
        -- items were plain strings, so value == the text itself
        check("onDoubleClicked", dbl ~= nil and dbl.i == 3 and dbl.v == "Item 3")
    end)

    step("right-click hook (no selection change)", function()
        rmb = nil
        local cx, cy = rowCenter(list, 5)
        moveTo(cx, cy)
        click(cx, cy, 2)
    end)
    frames(2)
    step("right-click results", function()
        check("onRightClick", rmb ~= nil and rmb.i == 5)
        check("right-click kept selection", list:getSelected() == 3)
    end)

    -- keyboard nav: instant, no settle needed; focus via public setter
    step("keyboard down x2 (instant)", function()
        list:setFocused(true)
        pressKey("down")
        pressKey("down")
    end)
    frames(2)
    step("keyboard results", function()
        local i = list:getSelected()
        check("down advanced selection to 5", i == 5)
        check("keyboard selection instant (snapped opaque)",
              list:getRow(i).__fill == 1 and list:getRow(i).visibility == 1)
    end)

    step("Delete key removes selected", function()
        pressKey("delete")
    end)
    frames(2)
    step("delete results", function()
        check("Delete removed a row", list:getItemCount() == 39)
        check("selection moved to row 5 (was 6)", select(1, list:getItem(5)) == "Item 6")
    end)

    -- empty-state placeholder
    step("clear -> placeholder fades in", function()
        list:clear()
    end)
    waitSettle(list, 6)
    step("placeholder visible, list empty", function()
        check("isEmpty", list:isEmpty())
        local lbl = list:getEmptyLabel()
        check("empty label exists", lbl ~= nil)
        check("placeholder opaque", lbl and lbl.textVisibility > .95)
    end)
    step("add clears placeholder", function()
        list:add("Fresh", 7)
    end)
    waitSettle(list, 6)
    step("placeholder hidden again", function()
        check("placeholder faded out", list:getEmptyLabel().textVisibility < .05)
        check("one live row", list:getItemCount() == 1)
    end)

    -- rapid interruption: adds, removes and a clear inside a few frames must
    -- not corrupt the array or leave ghosts (transitions retarget mid-flight)
    step("rapid churn", function()
        for i = 1, 5 do list:add("Churn " .. i, i) end
        list:remove(2)
        list:remove(4)
        list:insert(1, "First")
        list:clear()
        list:setItems(baseItems())
    end)
    waitSettle(list, 12)
    step("churn settled consistently", function()
        check("count after churn", list:getItemCount() == 4)
        rowRect("churn row1", list:getRow(1), 20, 60 + GAP, 320, ROWH)
        rowRect("churn row4", list:getRow(4), 20, 60 + GAP + 3 * (ROWH + GAP), 320, ROWH)
    end)

    -- worst case: 300 rows, long unbreakable text, empty and one-char labels
    step("worst-case data", function()
        local items = { "", "A",
            "An extremely long label that will never fit this row: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
        for i = 1, 300 do items[#items + 1] = { text = "Row " .. i, value = i } end
        list:setItems(items)
    end)
    waitSettle(list, 10)
    step("worst-case counts and extent", function()
        check("303 rows", list:getItemCount() == 303)
        local _, _, _, ch = list:getAbsolutes()
        check("extent ~ 303 rows", ch > 303 * (ROWH + GAP) - GAP)
        list:scrollToBottom()
    end)
    waitSettle(list, 6)
    step("worst-case bottom row reachable", function()
        local r = list:getRow(303)
        check("bottom row exists", r ~= nil)
        local _, _, w, h = r:getAbsolutes()   -- must not error
        check("bottom row has size", w > 0 and h > 0)
    end)

    -- animate=false: state lands immediately, no tween. Unselected rows stay
    -- transparent by design (only selection/hover/stripe paint).
    step("no-anim list lands instantly", function()
        listC:add("Now")
        local r4 = listC:getRow(4)
        local _, ry = r4:getAbsolutes()
        local _, vy = listC.parent:getAbsolutes()
        check("instant geometry", math.abs(ry - (vy + GAP + 3 * (ROWH + GAP))) < 1)
        check("instant text", r4.__label.textVisibility == 1)
        check("unselected fill still 0", r4.visibility == 0)
        listC:select(4, false)
        check("instant selection paint", listC:getRow(4).visibility == 1)
    end)

    -- click-away defocuses keyboard (press outside the list)
    step("click-away defocus", function()
        list:setFocused(true)
        moveTo(700, 620)     -- empty background area
        click(700, 620)
    end)
    frames(2)
    step("focus cleared after outside press", function()
        check("list defocused", list:isFocused() == false)
    end)
end

-- ---------------------------------------------------------------------------
-- Sequencer driver
-- ---------------------------------------------------------------------------
local summaryShown = false

local function drive()
    local s = seq[si]
    if not s then return true end
    if s.wait then
        if not s.deadline then s.deadline = love.timer.getTime() + s.maxSeconds end
        if not s.wait:isSettling() or love.timer.getTime() > s.deadline then si = si + 1 end
        return false
    end
    if s.tick then si = si + 1 return false end
    local ok, err = pcall(s.fn)
    if not ok then
        checks.failed = checks.failed + 1
        print("FAIL [" .. s.name .. "] ERROR: " .. tostring(err))
    end
    si = si + 1
    return false
end

-- ---------------------------------------------------------------------------
-- Love callbacks
-- ---------------------------------------------------------------------------
function love.load(args)
    for _, a in ipairs(args or {}) do
        if a == "--list-autotest" then AUTO_TEST = true end
    end
    build()
    if AUTO_TEST then buildSeq() end
    print("list-demo boot: autotest=" .. tostring(AUTO_TEST))
end

function love.update(dt)
    gui.update(dt)
    multi:uManager(dt)

    frame = frame + 1
    if AUTO_TEST and not summaryShown then
        if frame >= 3 then
            if drive() then
                summaryShown = true
                print(string.format("SUMMARY: %d passed, %d failed", checks.passed, checks.failed))
                io.stdout:flush()
                os.exit(checks.failed == 0 and 0 or 1)
            end
        end
    end
end

function love.draw()
    gui.draw()
end

function love.errhand(msgh, traceback, _)
    if AUTO_TEST then
        print("ERROR: " .. tostring(msgh))
        print((traceback or ""):sub(1, 2000))
        io.stdout:flush()
        os.exit(2)
    end
    return nil -- default error screen in interactive mode
end
