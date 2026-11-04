-- flexbox.lua
-- Scoped port of Clay v0.14's layout algorithm into the retained LÖVE GUI tree.
-- Source of truth: docs/flexbox-integration-plan.md (Phases 1-6: Pass A/D sizing,
-- Pass B text wrap, Pass C upward fit-content propagation, Pass E aspect/square,
-- Pass F positions, dualDim write-back, escape hatch / floating children,
-- dirty-flag scheduling §5, event connections, virtual-tree pass, scroll
-- fit-content integration §7).
--
-- Pipeline order per flex root (clay.h:2573-2700 + plan Appendix A):
--   seed -> Pass A (X) -> Pass B (text wrap) -> aspect(h) -> Pass C (propagate
--   heights up) -> Pass D (Y) -> aspect(w) -> Pass F (positions) -> square bake
--   -> write-back. Pass C completes before any write-back (plan §3.4).
--
-- Clay references:
--   sizing BFS      reference/clay/clay.h:2281-2513  (Clay__SizeContainersAlongAxis)
--   final layout    reference/clay/clay.h:3095-3183  (Pass F position DFS portion)
--   sizing config   reference/clay/clay.h:299-360
--   floating config reference/clay/clay.h:484-514 (reduced to escape-hatch semantics)
--
-- The engine never touches draw_handler/canPress/__clip: it rewrites *dualDim
-- values* so the existing parent-first resolver reproduces the computed pixels
-- (plan §0 linchpin + §6 write-back math).

local measure = require("gui.core.measure")

local ok_bit, bit = pcall(require, "bit")
local function pureBand(a, b)
    -- pure-Lua fallback for environments without the bit library (gui type masks are small)
    local r, m = 0, 1
    a, b = math.floor(a), math.floor(b)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = (a - a % 2) / 2, (b - b % 2) / 2, m * 2
    end
    return r
end
local band = ok_bit and bit.band or pureBand

local max, min, abs, huge = math.max, math.min, math.abs, math.huge

local flexbox = {}

-- Clay's epsilon / FloatEqual (clay.h:2265-2270)
local EPS = 0.01
local function floatEqual(a, b)
    local d = a - b
    return d < EPS and d > -EPS
end

-- stats: `passes` = layoutFlexRoot calls, `visited` = elements laid out
-- (sum of subtree sizes; 0 on idle frames — the Phase 5 perf gate),
-- `rootsScanned` = flex roots examined by runPass (O(roots) steady-state cost).
flexbox.stats = { passes = 0, visited = 0, rootsScanned = 0 }

-- All elements that ever had setFlex, weak-keyed so destroyed elements drop out.
local allFlex = setmetatable({}, { __mode = "k" })

local writing = false    -- set while the pass writes dualDim (plan §5.3)
local firing = false     -- set while the pass fires its own OnSize/PositionChanged
local running = false    -- set inside runPass (plan §5.3)
local deferred = false   -- re-entrant runPass request: re-run after the current one
local guiRef  = nil      -- injected via flexbox.init(gui, ...)
local passGen = 0        -- bumped per runPass; stamped on laid-out elements so
                         -- floating flex roots seed from this frame's fresh
                         -- parent absolutes instead of the stale draw cache

-- Module-level reusable buffers (plan §3.0 — no per-frame allocation)
local elemsBuf = {}     -- pre-order list of the current subtree (parents before children)
local textBuf = {}      -- text leaves collected during seeding (Pass B input, clay.h:2349-2350)
local rootsBuf = {}     -- this runPass's flex roots of one tree, depth-ordered
local rb = {}           -- resizable child buffer, per container
local textOptsBuf = {}  -- scratch {mul,adjust,textOffsetX} reused per Pass B lookup

--------------------------------------------------------------------------------
-- Predicates / helpers
--------------------------------------------------------------------------------

local function isTextElement(e)
    return e.text ~= nil and band(e.type or 0, 2) ~= 0
end

-- A child of a flex container is "floating" (escape hatch / setSizing(false)):
-- excluded from sizing sums and cursor advancement but still a normal descendant.
local function isFloating(e)
    return e.__flexEscaped == true
end

-- Root condition (plan §3.0 + §4, generalized for grid per grid plan §0/§1):
-- a __flex or __grid element whose parent does not carry the SAME layout mode
-- (that parent's pass owns the child's subtree), or a *floating* element
-- (Clay treats floaters as separate tree roots). Cross-mode nesting falls out
-- naturally: a __grid child of a __flex parent (and a __flex child of a
-- __grid parent, which is already true today) is its own root, because the
-- parent's algorithm cannot lay out the child's subtree. Flex-only trees
-- observe byte-identical behavior (p.__grid is nil there).
local function isFlexRoot(e)
    if not (e.__flex or e.__grid) then return false end
    local p = e.parent
    if p == nil or isFloating(e) then return true end
    if e.__flex then return p.__flex == nil end
    return p.__grid == nil
end

local function belongsTo(e, tree)
    local p = e.parent
    local steps = 0
    while p and steps < 1000 do
        if p == tree then return true end
        p = p.parent
        steps = steps + 1
    end
    return e == tree
end

-- Defensive twin of getAbsolutes (init.lua:371-391) tolerating nil parent cache
-- fields on the very first frame before draw_handler has populated them.
-- The parent values may be overridden with the pass's own freshly computed
-- absolutes (plan §6: "nested flex children use values the pass itself computed
-- AND baked into the parent's dualDim").
local function absolutesWith(e, px, py, pw, ph)
    local dd = e.dualDim
    px, py, pw, ph = px or 0, py or 0, pw or 0, ph or 0
    local x = (pw * dd.scaleX) + dd.offsetX + px
    local y = (ph * dd.scaleY) + dd.offsetY + py
    local w = (pw * dd.scaleW) + dd.offsetW
    local h = (ph * dd.scaleH) + dd.offsetH
    if e.square == "w" then
        h = w
    elseif e.square == "h" then
        w = h
    end
    return x, y, w, h
end

local function safeAbsolutes(e)
    local p = e.parent
    -- The parent draw cache (init.lua:2225-2228) is rawset only by
    -- draw_handler. An element created in the same frame as this flex root
    -- (e.g. newScrollFrame's viewport) has NO stamped cache — but plain
    -- p.x reads inherit gui's boot values through the element metatable
    -- (0,0,window_w,window_h), silently mis-seeding the root. rawget
    -- distinguishes "never stamped" from "stale", and an unstamped parent is
    -- resolved on the fly: draw_handler stamps it (parent-first, same frame)
    -- with exactly those values, so the invariant still holds by construction.
    local px, py, pw, ph = rawget(p, "x"), rawget(p, "y"), rawget(p, "w"), rawget(p, "h")
    if px == nil or py == nil or pw == nil or ph == nil then
        px, py, pw, ph = p:getAbsolutes()
    end
    return absolutesWith(e, px, py, pw, ph)
end

-- Effective sizing for a managed child (default: both axes fit — Clay's
-- CLAY__SIZING_TYPE_FIT default, clay.h:302).
local DEFAULT_AXIS = { mode = "fit", min = 0, max = huge }
local DEFAULT_SIZING = { width = DEFAULT_AXIS, height = DEFAULT_AXIS }
local function sizingOf(e)
    return e.__sizing or DEFAULT_SIZING
end

-- The printf draw path (init.lua:2141-2160) wraps at w*mul (mul=2 for
-- circle/arc) inset by adjust + textOffsetX; measure.get applies the same
-- rules so measured lines == rendered lines (plan §9 risk row).
local function textMeasureOpts(e)
    textOptsBuf.mul = (e.formFactor == 2 or e.formFactor == 3) and 2 or 1 -- FORM_CIRCLE/FORM_ARC
    textOptsBuf.adjust = e.adjust
    textOptsBuf.textOffsetX = e.textOffsetX
    return textOptsBuf
end

-- Map layout axis ("x"/"y") onto the sizing table keys ("width"/"height", plan §2.1)
local function axisSizing(e, axis)
    return sizingOf(e)[axis == "x" and "width" or "height"]
end

-- Shared with the grid module: the printf inset rules (mul/adjust/textOffsetX)
-- so the grid's Pass-B analogue measures exactly what draw renders (grid plan
-- §5.7; same opts the flex Pass B uses, plan §3.3).
flexbox.textMeasureOpts = textMeasureOpts

-- Lazy, nil-guarded grid module handle (grid plan §1 dependency direction):
-- flexbox never requires grid at load time, so there is no require cycle and
-- deleting core/grid.lua leaves __grid elements inert while flex keeps
-- working — the same pattern init.lua:7 uses for flexbox itself. Declared
-- before seedAxis/propagateUp, which consume grid.intrinsic (P3).
local gridModCache = false
local function gridMod()
    if gridModCache == false then
        local ok, m = pcall(require, "gui.core.grid")
        gridModCache = (ok and m) or nil
    end
    return gridModCache
end

--------------------------------------------------------------------------------
-- Dirty marking (plan §5.1)
--------------------------------------------------------------------------------

function flexbox.markDirty(elem)
    local e = elem
    local steps = 0
    while e and steps < 1000 do
        if e.__flex or e.__grid then
            e.__flexDirty = true
            -- nearest layout (flex or grid) root reached: the pass is
            -- per-root, stop climbing
            if isFlexRoot(e) then break end
        end
        e = e.parent
        steps = steps + 1
    end
end

--------------------------------------------------------------------------------
-- Leaf seeding (plan §3.2 "leaf initial sizes")
--------------------------------------------------------------------------------

-- axis here is the sizing key: "width" | "height"
local function seedAxis(e, axis)
    local s = sizingOf(e)[axis]
    if s.mode == "fixed" then
        return s.value or 0
    end
    -- fit / grow / percent all start at the fit minimum (clay.h:2322-2327)
    if e.__grid then
        -- cross-mode intrinsic contribution (grid plan §4 seedAxis row, P3):
        -- a __grid child seeds from the grid module's computed content size
        -- (last layout's track sums, else a lightweight first-frame compute);
        -- absent core/grid.lua -> 0 fallback, the documented inert behavior.
        local g = gridMod()
        return (g and g.intrinsic(e, axis)) or 0
    end
    if isTextElement(e) and e.font then
        if axis == "width" then
            return measure.natural(e.text, e.font).width
        else
            return e.font:getHeight() -- one line; wrap resolved in Pass B (Phase 3)
        end
    end
    if e.imageWidth or e.imageHeight then
        return (axis == "width" and e.imageWidth) or (axis == "height" and e.imageHeight) or 0
    end
    if e.videoWidth or e.videoHeigth then
        return (axis == "width" and e.videoWidth) or (axis == "height" and e.videoHeigth) or 0
    end
    return 0 -- empty frame (plan §3.2)
end

-- Shared with the grid module: grid roots seed their items with the same
-- flex item primitives (grid plan §7 step 2; grid lazy-requires flexbox).
flexbox.seedAxis = seedAxis

--------------------------------------------------------------------------------
-- Pass A / Pass D — sizeContainersAlongAxis (port of clay.h:2281-2513)
--------------------------------------------------------------------------------

local function sizeAlongAxis(parent, axis)
    local f = parent.__flex
    local onAxis = (axis == "x") == (f.direction == "row")
    local pad = f.padding
    local parentPad = (axis == "x") and (pad.l + pad.r) or (pad.t + pad.b)
    local parentSize = (axis == "x") and parent.__fw or parent.__fh
    local gap = f.gap

    local innerContentSize = 0
    local totalPadGaps = parentPad
    local growCount = 0
    local rbLen = 0
    local first = true

    local children = parent.children
    for ci = 1, #children do
        local child = children[ci]
        if not isFloating(child) then
            local s = axisSizing(child, axis)
            local csize = (axis == "x") and child.__fw or child.__fh

            -- resizable: not percent, not fixed (clay.h:2364-2370)
            if s.mode ~= "percent" and s.mode ~= "fixed" then
                rbLen = rbLen + 1
                rb[rbLen] = child
            end

            if onAxis then
                innerContentSize = innerContentSize + (s.mode == "percent" and 0 or csize)
                if s.mode == "grow" then growCount = growCount + 1 end
                if not first then
                    innerContentSize = innerContentSize + gap
                    totalPadGaps = totalPadGaps + gap
                end
            else
                if csize > innerContentSize then innerContentSize = csize end -- clay.h:2382
            end
            first = false
        end
    end

    -- percent expansion (clay.h:2387-2400)
    for ci = 1, #children do
        local child = children[ci]
        if not isFloating(child) then
            local s = axisSizing(child, axis)
            if s.mode == "percent" then
                local v = (parentSize - totalPadGaps) * (s.value or 0)
                if axis == "x" then child.__fw = v else child.__fh = v end
                if onAxis then innerContentSize = innerContentSize + v end
            end
        end
    end

    if onAxis then
        local free = parentSize - parentPad - innerContentSize
        if free < 0 then
            -- Overflow: clipped containers skip compression (clay.h:2407-2409;
            -- our clip analogue is clipDescendants, plan §7).
            if not parent.clipDescendants then
                -- Shrink largest toward second-largest (clay.h:2411-2445)
                while free < -EPS and rbLen > 0 do
                    local largest, secondLargest = 0, 0
                    local add = free
                    for ri = 1, rbLen do
                        local c = rb[ri]
                        local cs = (axis == "x") and c.__fw or c.__fh
                        if not floatEqual(cs, largest) then
                            if cs > largest then
                                secondLargest = largest
                                largest = cs
                            end
                            if cs < largest then
                                if cs > secondLargest then secondLargest = cs end
                                add = secondLargest - largest
                            end
                        end
                    end
                    local div = free / rbLen
                    if add < div then add = div end -- MAX(add, free/len); both negative
                    local ri = 1
                    while ri <= rbLen do
                        local c = rb[ri]
                        local s = axisSizing(c, axis)
                        if axis == "x" then
                            if floatEqual(c.__fw, largest) then
                                local prev = c.__fw
                                c.__fw = c.__fw + add
                                if c.__fw <= s.min then
                                    c.__fw = s.min
                                    rb[ri] = rb[rbLen]; rb[rbLen] = nil; rbLen = rbLen - 1; ri = ri - 1
                                end
                                free = free - (c.__fw - prev)
                            end
                        else
                            if floatEqual(c.__fh, largest) then
                                local prev = c.__fh
                                c.__fh = c.__fh + add
                                if c.__fh <= s.min then
                                    c.__fh = s.min
                                    rb[ri] = rb[rbLen]; rb[rbLen] = nil; rbLen = rbLen - 1; ri = ri - 1
                                end
                                free = free - (c.__fh - prev)
                            end
                        end
                        ri = ri + 1
                    end
                end
            end
        elseif free > 0 and growCount > 0 then
            -- keep only grow children in the buffer (clay.h:2448-2454)
            local ri = 1
            while ri <= rbLen do
                local c = rb[ri]
                if axisSizing(c, axis).mode ~= "grow" then
                    rb[ri] = rb[rbLen]; rb[rbLen] = nil; rbLen = rbLen - 1
                else
                    ri = ri + 1
                end
            end
            -- Grow smallest toward second-smallest, capped at max (clay.h:2455-2490)
            while free > EPS and rbLen > 0 do
                local smallest, secondSmallest = huge, huge
                local add = free
                for ri2 = 1, rbLen do
                    local c = rb[ri2]
                    local cs = (axis == "x") and c.__fw or c.__fh
                    if not floatEqual(cs, smallest) then
                        if cs < smallest then
                            secondSmallest = smallest
                            smallest = cs
                        end
                        if cs > smallest then
                            if cs < secondSmallest then secondSmallest = cs end
                            add = secondSmallest - smallest
                        end
                    end
                end
                local div = free / rbLen
                if add > div then add = div end
                local ri2 = 1
                while ri2 <= rbLen do
                    local c = rb[ri2]
                    local s = axisSizing(c, axis)
                    if axis == "x" then
                        if floatEqual(c.__fw, smallest) then
                            local prev = c.__fw
                            c.__fw = c.__fw + add
                            if c.__fw >= s.max then
                                c.__fw = s.max
                                rb[ri2] = rb[rbLen]; rb[rbLen] = nil; rbLen = rbLen - 1; ri2 = ri2 - 1
                            end
                            free = free - (c.__fw - prev)
                        end
                    else
                        if floatEqual(c.__fh, smallest) then
                            local prev = c.__fh
                            c.__fh = c.__fh + add
                            if c.__fh >= s.max then
                                c.__fh = s.max
                                rb[ri2] = rb[rbLen]; rb[rbLen] = nil; rbLen = rbLen - 1; ri2 = ri2 - 1
                            end
                            free = free - (c.__fh - prev)
                        end
                    end
                    ri2 = ri2 + 1
                end
            end
        end
    else
        -- Off-axis stretch/clamp (clay.h:2492-2509)
        for ri = 1, rbLen do
            local c = rb[ri]
            local s = axisSizing(c, axis)
            local maxSize = parentSize - parentPad
            if parent.clipDescendants and innerContentSize > maxSize then
                maxSize = innerContentSize -- clay.h:2501-2504 (scroll analogue)
            end
            if s.mode == "grow" then
                local v = maxSize < s.max and maxSize or s.max
                if axis == "x" then c.__fw = v else c.__fh = v end
            end
            if axis == "x" then
                c.__fw = max(s.min, min(c.__fw, maxSize))
            else
                c.__fh = max(s.min, min(c.__fh, maxSize))
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Pass F — position assignment (port of clay.h:3095-3183, minus zIndex/scroll)
--------------------------------------------------------------------------------

local function assignPositions(parent)
    local f = parent.__flex
    local pad = f.padding
    local row = f.direction == "row"
    local gap = f.gap

    -- On-axis alignment lead-in (clay.h:3097-3131)
    local contentSize = 0
    local flowCount = 0
    local children = parent.children
    for ci = 1, #children do
        local child = children[ci]
        if not isFloating(child) then
            flowCount = flowCount + 1
            local cs = row and child.__fw or child.__fh
            contentSize = contentSize + cs
        end
    end
    contentSize = contentSize + gap * max(flowCount - 1, 0)
    local onSize = row and parent.__fw or parent.__fh
    local padOn = row and (pad.l + pad.r) or (pad.t + pad.b)
    local alignOn = row and f.alignX or f.alignY
    local extra = onSize - padOn - contentSize
    if alignOn == "center" then
        extra = extra / 2
    elseif alignOn == "end" then
        -- full extra
    else
        extra = 0
    end
    if extra < 0 then extra = 0 end

    local cursor = (row and pad.l or pad.t) + extra

    for ci = 1, #children do
        local child = children[ci]
        if not isFloating(child) then
            if row then
                child.__fx = parent.__fx + cursor
                -- cross-axis (y) alignment per child, clay.h:3143-3150
                local white = parent.__fh - pad.t - pad.b - child.__fh
                local cross = pad.t
                if f.alignY == "center" then
                    cross = cross + white / 2
                elseif f.alignY == "end" then
                    cross = cross + white
                end
                child.__fy = parent.__fy + cross
                cursor = cursor + child.__fw + gap
            else
                child.__fy = parent.__fy + cursor
                -- cross-axis (x) alignment per child, clay.h:3151-3159
                local white = parent.__fw - pad.l - pad.r - child.__fw
                local cross = pad.l
                if f.alignX == "center" then
                    cross = cross + white / 2
                elseif f.alignX == "end" then
                    cross = cross + white
                end
                child.__fx = parent.__fx + cross
                cursor = cursor + child.__fh + gap
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Pass C — upward fit-content propagation (plan §3.4, retained-port extension)
--
-- Clay knows a container's fit *width* at immediate-mode close time
-- (clay.h:1886-1941) before SizeContainersAlongAxis ever runs, and propagates
-- fit *heights* only after text wrap (clay.h:2646-2691). In the retained tree
-- neither is known up front, so the port sweeps both in two places:
--   C0 (after seeding, before Pass A): both axes — makes fit containers hug
--      their children so Pass A/D on-axis sums see real sizes.
--   C1 (after Pass B): heights only — wrap changed text heights (widths are
--      untouched by Pass B).
-- elemsBuf is pre-order (parents before children), so reverse iteration is
-- post-order: children finalize before their parent reads them. The flex root
-- itself is never propagated (its box is dualDim-owned, plan §3.1) — EXCEPT
-- size-managed scroll roots (§7), where the pass owns the box size and the
-- host owns the position. Containers with an aspectRatio are skipped
-- (clay.h:2638-2643/2696-2700 own those axes; clay.h:2642 also caps their max).
-- min/max clamp mirrors clay.h:2679/2689. Floating children are excluded from
-- every sum (plan §4).
--------------------------------------------------------------------------------

local function propagateUp(e, heightsOnly)
    if not e.__flex then return end
    if e.__sizing and e.__sizing.aspectRatio then return end
    local f = e.__flex
    local pad = f.padding
    local row = f.direction == "row"
    local gap = f.gap
    local children = e.children

    -- Grid-child contribution (grid plan §4 propagateUp row, P3): a __grid
    -- flow child contributes the grid's last computed track sums — the same
    -- source grid.intrinsic feeds seedAxis, so the fit sums and the seeded
    -- fit minimum can never disagree. Absent grid module (or un-laid grid):
    -- fall back to the seeded __f* values (0 until the grid pass runs).
    local function along(ch, axis)
        if ch.__grid then
            local g = gridMod()
            if g then return g.intrinsic(ch, axis) end
        end
        return axis == "width" and (ch.__fw or 0) or (ch.__fh or 0)
    end

    if not heightsOnly and axisSizing(e, "x").mode == "fit" then
        local sw = axisSizing(e, "x")
        local content, flowCount = 0, 0
        for ci = 1, #children do
            local ch = children[ci]
            if not isFloating(ch) then
                flowCount = flowCount + 1
                if row then content = content + along(ch, "width")
                else content = max(content, along(ch, "width")) end
            end
        end
        if row then content = content + gap * max(flowCount - 1, 0) end
        content = content + pad.l + pad.r
        e.__fw = min(max(content, sw.min), sw.max)
    end

    if axisSizing(e, "y").mode == "fit" then
        local sh = axisSizing(e, "y")
        local contentH, flowCount = 0, 0
        for ci = 1, #children do
            local ch = children[ci]
            if not isFloating(ch) then
                flowCount = flowCount + 1
                if row then contentH = max(contentH, along(ch, "height") + pad.t + pad.b)
                else contentH = contentH + along(ch, "height") end
            end
        end
        if row then
            -- clay.h:2674-2680 loops children; no children -> height untouched
            if flowCount > 0 then
                e.__fh = min(max(contentH, sh.min), sh.max)
            end
        else
            contentH = contentH + pad.t + pad.b + gap * max(flowCount - 1, 0)
            e.__fh = min(max(contentH, sh.min), sh.max)
        end
    end
end

--------------------------------------------------------------------------------
-- Shared write-back + event tail (grid plan §1/§4): extracted verbatim from
-- layoutFlexRoot so grid roots reuse the exact same math and guards — the
-- write-back invariant (getAbsolutes() == __flexComputed), the __flexFrame
-- pass stamp and the event policy stay single-sourced. grid.lua calls these
-- via the lazy flexbox require (buf is the module-local subtree buffer of the
-- calling pass; parents must precede children, buf[1] is the root).
--------------------------------------------------------------------------------

-- Write-back (flex plan §6): offsetX = cx - px etc, scales zeroed.
-- Size-managed roots (flex plan §7): position slots untouched — the host
-- (scroll frame's setDualDim(-scrollX,-scrollY)) owns them; the pass owns size.
local function writeBack(buf, n, root)
    writing = true
    for k = 2, n do
        local e = buf[k]
        local p = e.parent
        if e.__flexSizeManaged then
            e:rawSetDualDim(nil, nil, e.__fw, e.__fh, nil, nil, 0, 0)
        else
            e:rawSetDualDim(
                e.__fx - p.__fx,
                e.__fy - p.__fy,
                e.__fw,
                e.__fh,
                0, 0, 0, 0)
        end
    end
    -- Size-managed ROOT box: the pass owns its offsetW/offsetH (fit height,
    -- authored width), never its offset*X/Y position slots (the scroll frame
    -- owns those, flex plan §7).
    if root.__flexSizeManaged then
        root:rawSetDualDim(nil, nil, root.__fw, root.__fh, nil, nil, 0, 0)
    end
    writing = false
    -- Stamp frame so floating layout roots under this subtree seed from fresh
    -- absolutes in the same runPass (their own dualDim is manual/unowned).
    for k = 1, n do
        buf[k].__flexFrame = passGen
    end
end

-- Event policy (flex plan §2.3 item 4): fire only on actual deltas.
-- `firing` guards our own OnSizeChanged/OnPositionChanged connections
-- (flex plan §5.1 row 5: write-back-fired events must not re-mark dirty);
-- user handlers and the escape hatch (onManualGeometry) still run.
local function fireGeometryEvents(buf, n, root)
    firing = true
    for k = 2, n do
        local e = buf[k]
        local comp = e.__flexComputed
        local cx, cy, cw, ch = e.__fx, e.__fy, e.__fw, e.__fh
        if not comp or comp.w ~= cw or comp.h ~= ch then
            e.OnSizeChanged:Fire(e, e.dualDim.offsetX, e.dualDim.offsetY,
                                 cw, ch, 0, 0, 0, 0)
        end
        if not comp or comp.x ~= cx or comp.y ~= cy then
            local dx = comp and (cx - comp.x) or cx
            local dy = comp and (cy - comp.y) or cy
            e.OnPositionChanged:Fire(e, dx, dy)
        end
        e.__flexComputed = { x = cx, y = cy, w = cw, h = ch }
    end
    -- Size-managed root: its own box (offsetH) changed via raw write-back, so
    -- the host (newScrollFrame's content:OnSizeChanged -> updateScrollbars)
    -- must hear about it. Fire once per actual size delta (flex plan §7).
    if root.__flexSizeManaged then
        local prev = root.__flexRootComputed
        if not prev or prev.w ~= root.__fw or prev.h ~= root.__fh then
            root.OnSizeChanged:Fire(root, root.dualDim.offsetX, root.dualDim.offsetY,
                                    root.__fw, root.__fh, 0, 0, 0, 0)
        end
        root.__flexRootComputed = { w = root.__fw, h = root.__fh }
    end
    firing = false
end

flexbox.writeBack = writeBack
flexbox.fireGeometryEvents = fireGeometryEvents

--------------------------------------------------------------------------------
-- layoutFlexRoot — full pipeline for one root subtree (plan §3, §6)
--------------------------------------------------------------------------------

local function layoutFlexRoot(root, rx, ry, rw, rh)
    flexbox.stats.passes = flexbox.stats.passes + 1
    root.__flexLaidOut = true

    -- Seed the root box (plan §3.1): dualDim-owned, read against parent cache.
    root.__fx, root.__fy, root.__fw, root.__fh = rx, ry, rw, rh

    -- Build the pre-order subtree list + seed managed children (parents before
    -- children so nested containers have final sizes when their turn comes).
    local n = 1
    local tn = 0
    elemsBuf[1] = root
    elemsBuf[2] = nil
    local i = 1
    while i <= n do
        local parent = elemsBuf[i]
        -- Plan §2.4: the pass never descends into a non-flex container's children
        -- (a flex child of a non-flex intermediate is its own root, §3.0).
        if parent.__flex then
            local children = parent.children
            for ci = 1, #children do
                local child = children[ci]
                if isFloating(child) and child.__flex then
                    -- floating flex container: re-lay it out against this
                    -- frame's fresh parent absolutes later in the same runPass
                    -- (depth order, plan §4).
                    child.__flexDirty = true
                end
                if not isFloating(child) then
                    -- (Re-)enable management for flow children (plan §2.1)
                    if not child.__flexManaged then
                        child.__flexManaged = { size = true, pos = true }
                    end
                    child.__fw = seedAxis(child, "width")
                    child.__fh = seedAxis(child, "height")
                    -- square lock (init.lua:389-393): seed the dependent axis
                    -- from the controlling one so Pass C's propagation and
                    -- Pass A/D's on-axis sums are consistent with the final
                    -- post-position bake — the bake and the resolver's
                    -- re-application both become no-ops (idempotence, §3.6).
                    if child.square == "w" and child.__fh < child.__fw then
                        child.__fh = child.__fw
                    elseif child.square == "h" and child.__fw < child.__fh then
                        child.__fw = child.__fh
                    end
                    n = n + 1
                    elemsBuf[n] = child
                    elemsBuf[n + 1] = nil
                    if isTextElement(child) and child.font then
                        tn = tn + 1
                        textBuf[tn] = child
                    end
                end
            end
        end
        i = i + 1
    end
    flexbox.stats.visited = flexbox.stats.visited + n

    -- Pass C0: fit-content both axes, bottom-up, before any axis sizing so
    -- Pass A/D on-axis sums see real fit-container widths/heights (see above).
    for k = n, 2, -1 do
        propagateUp(elemsBuf[k], false)
    end
    -- Size-managed roots (scroll content, plan §7): the pass owns the box
    -- SIZE, so propagate fit content up into the root — heights only: the
    -- authored width stays dualDim-owned (newScrollFrame sizes content to the
    -- viewport width; fit-width would collapse cross-axis stretch children).
    if root.__flexSizeManaged then
        propagateUp(root, true)
    end

    -- Pass A: size along X (BFS/pre-order: parents first)
    for k = 1, n do
        local e = elemsBuf[k]
        if e.__flex then sizeAlongAxis(e, "x") end
    end

    -- Pass B: text wrap heights at the final X width (port of clay.h:2583-2636
    -- via core/measure.lua; plan §3.3). Height becomes lineHeight * #lines,
    -- exactly what love.graphics.printf will render at that box width. The
    -- width Pass A produced is kept (shrink results preserved, plan §3.3
    -- "child.__w = max(child.__w_min, w)"); fit text already seeded at its
    -- natural width so it hugs the text without further shrinking.
    for ti = 1, tn do
        local e = textBuf[ti]
        local m = measure.get(e.text, e.font, e.__fw, textMeasureOpts(e))
        e.__fh = m.height
    end

    -- aspect after X (clay.h:2638-2643; text elements are excluded, clay.h:2355)
    for k = 1, n do
        local e = elemsBuf[k]
        local ar = e.__sizing and e.__sizing.aspectRatio
        if ar and not isTextElement(e) then e.__fh = e.__fw / ar end
    end

    -- Pass C1: upward height propagation after wrap (port of clay.h:2646-2691,
    -- plan §3.4). Reverse pre-order == children before parents, so every fit
    -- container's height is final before Pass D reads it and long before the
    -- write-back — the parent-first draw cache never observes a half-state.
    -- Widths do not change in Pass B, so only heights are re-swept here.
    for k = n, 2, -1 do
        propagateUp(elemsBuf[k], true)
    end
    if root.__flexSizeManaged then
        propagateUp(root, true)
    end

    -- Pass D: size along Y
    for k = 1, n do
        local e = elemsBuf[k]
        if e.__flex then sizeAlongAxis(e, "y") end
    end
    -- aspect after Y (clay.h:2696-2700)
    for k = 1, n do
        local e = elemsBuf[k]
        local ar = e.__sizing and e.__sizing.aspectRatio
        if ar and not isTextElement(e) then e.__fw = e.__fh * ar end
    end

    -- Pass F: positions (pre-order: parent's __fx/__fy set before children read it)
    for k = 1, n do
        local e = elemsBuf[k]
        if e.__flex then assignPositions(e) end
    end

    -- Pass E tail: square lock baked so the resolver re-application (init.lua:385)
    -- is a no-op — write-back idempotence invariant (plan §3.6, §5.4).
    for k = 2, n do
        local e = elemsBuf[k]
        if e.square == "w" then
            e.__fh = e.__fw
        elseif e.square == "h" then
            e.__fw = e.__fh
        end
    end

    -- Write-back + event policy: shared helpers (grid plan §1 extraction) —
    -- identical order/guards as before the refactor: writing window,
    -- __flexFrame stamp, then the firing window.
    writeBack(elemsBuf, n, root)
    fireGeometryEvents(elemsBuf, n, root)
end

--------------------------------------------------------------------------------
-- runPass — entry from draw_loop / virtual refresh thread (plan §5.2)
--
-- Dirty-flag scheduling (plan §5.1 + Phase 5): a flex root re-lays out only
-- when marked dirty (setFlex/setSizing, child add/remove/reparent, manual
-- geometry, event connections) OR when its own resolved absolutes changed
-- (seed re-check: covers setDualDim/move/size on the root, scroll position
-- writes, and any parent scale change). The parent-watch (p.x/y/w/h cache)
-- is retained ONLY for size-managed roots — the eventless resize/letterbox
-- thread mutates gui.x/y/w/h fields directly (init.lua:2532-2563), and for
-- regular roots that mutation is already caught by the seed re-check, so
-- steady-state idle frames visit exactly zero elements (stats.visited gate).
--------------------------------------------------------------------------------

-- Depth of an element from the tree root (parent-chain length). Used to
-- process flex roots ancestors-before-descendants within one runPass: a
-- floating __flex element (its own root, §4) resolves against its flex parent,
-- so the parent's subtree must be written back first or the write-back math
-- mixes this-frame and last-frame parent values (invariant break). Same
-- applies to cross-mode roots (grid-in-flex / flex-in-grid, grid plan P3):
-- the seed re-check reads the parent's fresh __fx/__fy written earlier in the
-- same pass, so the parent root MUST precede the child root.
-- NOTE: gui.parent == gui and gui.virtual.parent == gui.virtual (init.lua:
-- 2499-2502) are self-parent sentinels, so the walk terminates on a
-- self-parent — without that guard every element caps at the step limit and
-- ALL roots tie at depth 1000, degrading the sort to weak-table iteration
-- order (cross-mode children then seed from stale parent values).
local function rootDepth(e)
    local d, p, steps = 0, e.parent, 0
    while p and p ~= p.parent and steps < 1000 do
        d = d + 1
        p = p.parent
        steps = steps + 1
    end
    return d
end

function flexbox.runPass(tree)
    -- Re-entrancy guard (plan §5.3): if a fired event handler calls back into
    -- runPass mid-pass (e.g. a user OnSizeChanged that forces a layout), do
    -- NOT recurse — request a deferred re-run after the current pass finishes.
    if running then
        deferred = true
        return
    end
    running = true
    passGen = passGen + 1
    measure.beginPass()

    -- Collect this tree's flex roots, then layout in increasing
    -- depth (insertion sort; root counts are small).
    local rn = 0
    for e in pairs(allFlex) do
        if (e.__flex or e.__grid) and isFlexRoot(e) and belongsTo(e, tree) then
            rn = rn + 1
            rootsBuf[rn] = e
            rootsBuf[rn].__flexDepth = rootDepth(e)
        end
    end
    flexbox.stats.rootsScanned = flexbox.stats.rootsScanned + rn
    for i = 2, rn do
        local key, kd = rootsBuf[i], rootsBuf[i].__flexDepth
        local j = i - 1
        while j >= 1 and rootsBuf[j].__flexDepth > kd do
            rootsBuf[j + 1] = rootsBuf[j]
            j = j - 1
        end
        rootsBuf[j + 1] = key
    end
    for ri = 1, rn do
        local e = rootsBuf[ri]
        rootsBuf[ri] = nil
        local p = e.parent
        -- Seed against this frame's fresh parent absolutes when the parent was
        -- laid out earlier in this same runPass (depth order guarantees that);
        -- otherwise against the parent's cached draw fields (plan §3.1).
        local ax, ay, aw, ah
        if p.__flexFrame == passGen then
            ax, ay, aw, ah = absolutesWith(e, p.__fx, p.__fy, p.__fw, p.__fh)
        else
            ax, ay, aw, ah = safeAbsolutes(e)
        end
        -- Dirty gate: reseed only on explicit marks or when the root's own
        -- resolved absolutes changed (seed re-check, cheap float compares).
        local reseed = e.__flexDirty
            or e.__flexAX ~= ax or e.__flexAY ~= ay
            or e.__flexAW ~= aw or e.__flexAH ~= ah
        -- Parent-watch safety net (plan §5.1 last row, letterbox/resize thread
        -- init.lua:2532-2563 mutates fields directly, fires nothing): only
        -- needed for size-managed roots, whose fit size depends on the parent
        -- box; regular roots' seed re-check already covers parent changes.
        if not reseed and e.__flexSizeManaged then
            reseed = e.__flexPX ~= p.x or e.__flexPY ~= p.y
                  or e.__flexPW ~= p.w or e.__flexPH ~= p.h
        end
        if reseed then
            e.__flexDirty = nil
            e.__flexAX, e.__flexAY, e.__flexAW, e.__flexAH = ax, ay, aw, ah
        end
        e.__flexPX, e.__flexPY, e.__flexPW, e.__flexPH = p.x, p.y, p.w, p.h
        if reseed or not e.__flexLaidOut then
            if e.__grid then
                -- Grid root: dispatch to the grid module (lazy require,
                -- nil-guarded — a missing core/grid.lua leaves __grid-only
                -- elements inert: no crash, no layout; grid plan §1/§4).
                -- __flex/__grid are mutually exclusive (apiSetFlex and
                -- apiSetGrid reject the other mode), so this is unambiguous.
                local g = gridMod()
                if g then g.layoutGridRoot(e, ax, ay, aw, ah) end
            else
                layoutFlexRoot(e, ax, ay, aw, ah)
            end
            if e.__flexSizeManaged then
                -- The pass just rewrote the root's own offsetW/offsetH (fit
                -- content): record the post-write resolved size so the seed
                -- re-check does not see a phantom change and reseed forever.
                e.__flexAW, e.__flexAH = e.__fw, e.__fh
            end
        end
    end
    running = false
    if deferred then
        deferred = false
        flexbox.runPass(tree)
    end
end

--------------------------------------------------------------------------------
-- init.lua hook: escape hatch (plan §2.3)
--------------------------------------------------------------------------------

function flexbox.onManualGeometry(elem)
    if writing then return end -- the pass's own write-back
    local p = elem.parent
    if p and (p.__flex or p.__grid) and not elem.__flexEscaped then
        elem.__flexEscaped = true
        elem.__flexManaged = nil
        elem.__flexComputed = nil
        flexbox.markDirty(p)
    end
    -- A manual write to a flex element's OWN box (setDualDim/move/size on a
    -- container): its children must reflow against the new geometry — the
    -- element keeps __flex (floating __flex containers lay out their own
    -- children normally, plan §4). This is also how newScrollFrame's
    -- applyScroll (content:setDualDim(-scrollX,-scrollY), addons/system.lua:234)
    -- re-anchors a size-managed content root's children on scroll: the content
    -- is a flex ROOT (parent = viewport, not flex) so it never escapes.
    if elem.__flex or elem.__grid then
        flexbox.markDirty(elem)
    end
end

-- init.lua hook: newBase child insertion (plan §1 item 3)
function flexbox.onChildAdded(parent, child)
    if parent and (parent.__flex or parent.__grid) then
        flexbox.markDirty(parent)
    end
end

-- init.lua hook: destroy()/setParent() removal (plan §1 item 3)
function flexbox.onChildRemoved(elem)
    local p = elem.parent
    if p and (p.__flex or p.__grid) then
        flexbox.markDirty(p)
    end
end

-- init.lua hook: setParent() insertion (plan §1 item 3, new parent dirty)
function flexbox.onParentSet(elem)
    if elem.parent and (elem.parent.__flex or elem.parent.__grid) then
        flexbox.markDirty(elem.parent)
    end
end

--------------------------------------------------------------------------------
-- Scroll fit-content helper (plan §7, Phase 6)
--
-- Marks a flex ROOT whose box SIZE is pass-owned while its POSITION stays
-- host-owned (newScrollFrame content: setDualDim(-scrollX,-scrollY) keeps
-- working; the pass only writes offsetW/offsetH). Call after setFlex.
-- Mode-agnostic: a __grid root may be size-managed too (grid plan §4).
--------------------------------------------------------------------------------

function flexbox.sizeManaged(elem, on)
    elem.__flexSizeManaged = (on ~= false) and true or nil
    if on ~= false then allFlex[elem] = true end
    flexbox.markDirty(elem)
end

-- Test/diagnostic accessor: true while a layout pass is executing (the
-- `running` re-entrancy window, plan §5.3).
function flexbox.isRunning()
    return running
end

-- Shared scheduler helpers for the grid module (grid plan §1): grid
-- containers register into the same weak root registry, and grid's dirty-
-- marking event connections observe the same writing/firing guard window
-- that apiSetFlex installs (flex plan §5.1 row 5).
function flexbox.register(elem)
    allFlex[elem] = true
end

function flexbox.inPass()
    return writing or firing
end

--------------------------------------------------------------------------------
-- Public element API (installed on gui by flexbox.init)
--------------------------------------------------------------------------------

local ALIGN_VALUES = { ["start"] = true, ["center"] = true, ["end"] = true }
local MODES = { fit = true, grow = true, percent = true, fixed = true }

local function typeName(e)
    return tostring(e.type)
end

function flexbox.apiSetFlex(self, opts)
    if opts == false then
        self.__flex = nil
        flexbox.markDirty(self)
        return
    end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then
        error("setFlex: expected table or false, got " .. type(opts) ..
              " on element type " .. typeName(self))
    end
    if self.__grid then
        error("setFlex: element already has grid layout (setGrid(false) first) on element type " ..
              typeName(self))
    end
    local cfg = {
        direction = "row",
        gap = 0,
        padding = { l = 0, r = 0, t = 0, b = 0 },
        alignX = "start",
        alignY = "start",
    }
    for k, v in pairs(opts) do
        if k == "direction" then
            if v ~= "row" and v ~= "column" then
                error("setFlex: invalid direction '" .. tostring(v) ..
                      "' on element type " .. typeName(self))
            end
            cfg.direction = v
        elseif k == "gap" then
            if type(v) ~= "number" then
                error("setFlex: gap must be a number on element type " .. typeName(self))
            end
            cfg.gap = v < 0 and 0 or v -- Clay uses uint16_t (clay.h:355)
        elseif k == "padding" then
            if type(v) == "number" then
                v = v < 0 and 0 or v
                cfg.padding = { l = v, r = v, t = v, b = v }
            elseif type(v) == "table" then
                local l = v.l or v.left or 0
                local r = v.r or v.right or 0
                local t = v.t or v.top or 0
                local b = v.b or v.bottom or 0
                if type(l) ~= "number" or type(r) ~= "number"
                    or type(t) ~= "number" or type(b) ~= "number" then
                    error("setFlex: padding components must be numbers on element type " ..
                          typeName(self))
                end
                cfg.padding = {
                    l = l < 0 and 0 or l, r = r < 0 and 0 or r,
                    t = t < 0 and 0 or t, b = b < 0 and 0 or b,
                }
            else
                error("setFlex: padding must be number or table on element type " ..
                      typeName(self))
            end
        elseif k == "alignX" or k == "alignY" then
            if not ALIGN_VALUES[v] then
                error("setFlex: invalid " .. k .. " '" .. tostring(v) ..
                      "' (expected start|center|end) on element type " .. typeName(self))
            end
            cfg[k] = v
        else
            error("setFlex: unknown option '" .. tostring(k) ..
                  "' on element type " .. typeName(self))
        end
    end
    self.__flex = cfg
    allFlex[self] = true
    self.__flexDirty = true
    -- Plan §5.1 row 5: event connections installed on flex roots so an
    -- evented geometry change on the root itself (setDualDim/move/size)
    -- marks it dirty. NOTE: gui's VisualEvents wrappers do NOT filter by
    -- obj == self (init.lua:1060-1075 — the Do fires for every element's
    -- event), so the handler must check obj itself. The `firing` guard
    -- keeps the pass's own delta events from re-marking (re-entrancy,
    -- plan §5.3); `writing` guards the write-back window. Connections are
    -- registered via addConnection, auto-unconnected on destroy
    -- (init.lua:735-739). The runPass seed re-check + parent-watch stay as
    -- the safety net for the eventless resize/letterbox path.
    if not self.__flexEvents then
        self.__flexEvents = true
        self:OnSizeChanged(function(obj)
            if obj == self and not (firing or writing) then
                flexbox.markDirty(self)
            end
        end)
        self:OnPositionChanged(function(obj)
            if obj == self and not (firing or writing) then
                flexbox.markDirty(self)
            end
        end)
    end
    flexbox.markDirty(self)
end

local function parseAxisSpec(spec, self, key)
    -- shorthand: "grow"|"fit"|"percent"|"fixed" | number (fixed) | table
    if spec == nil then
        return { mode = "fit", min = 0, max = huge }
    end
    if type(spec) == "string" then
        if not MODES[spec] then
            error("setSizing: invalid " .. key .. " mode '" .. tostring(spec) ..
                  "' on element type " .. typeName(self))
        end
        return { mode = spec, min = 0, max = huge }
    end
    if type(spec) == "number" then
        return { mode = "fixed", value = spec, min = 0, max = huge }
    end
    if type(spec) == "table" then
        local mode = spec.mode or "fit"
        if not MODES[mode] then
            error("setSizing: invalid " .. key .. " mode '" .. tostring(mode) ..
                  "' on element type " .. typeName(self))
        end
        local value = spec.value
        if mode == "fixed" and value == nil then
            mode = "fit" -- plan §2.4: fixed with nil value -> fit
        end
        if mode == "percent" then
            if type(value) ~= "number" or value < 0 or value > 1 then
                error("setSizing: " .. key .. " percent expects 0-1 range (clay.h:305)" ..
                      " on element type " .. typeName(self))
            end
        end
        local mn = spec.min or 0
        local mx = spec.max or huge
        if type(mn) ~= "number" or type(mx) ~= "number" then
            error("setSizing: " .. key .. " min/max must be numbers on element type " ..
                  typeName(self))
        end
        if mn > mx then
            error("setSizing: " .. key .. " min > max on element type " .. typeName(self))
        end
        return { mode = mode, value = value, min = mn, max = mx }
    end
    error("setSizing: invalid " .. key .. " spec on element type " .. typeName(self))
end

function flexbox.apiSetSizing(self, opts)
    if opts == false then
        -- permanent escape: excluded from flow (plan §2.2 / §4)
        self.__sizing = nil
        self.__flexManaged = nil
        self.__flexEscaped = true
        self.__flexComputed = nil
        flexbox.markDirty(self.parent)
        return
    end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then
        error("setSizing: expected table or false, got " .. type(opts) ..
              " on element type " .. typeName(self))
    end
    for k in pairs(opts) do
        if k ~= "width" and k ~= "height" and k ~= "aspectRatio" then
            error("setSizing: unknown option '" .. tostring(k) ..
                  "' on element type " .. typeName(self))
        end
    end
    local ar = opts.aspectRatio
    if ar ~= nil and (type(ar) ~= "number" or ar <= 0) then
        error("setSizing: aspectRatio must be a positive number on element type " ..
              typeName(self))
    end
    self.__sizing = {
        width  = parseAxisSpec(opts.width, self, "width"),
        height = parseAxisSpec(opts.height, self, "height"),
        aspectRatio = ar,
    }
    -- re-enables management if it was escaped (plan §2.2)
    self.__flexEscaped = nil
    flexbox.markDirty(self.parent)
end

--------------------------------------------------------------------------------
-- Debug verifier (plan §6 invariant + §8 acceptance)
--------------------------------------------------------------------------------

function flexbox.debugVerifySubtree(tree, epsilon)
    epsilon = epsilon or 1e-9
    local fails = 0
    for e in pairs(allFlex) do
        if (e.__flex or e.__grid) and isFlexRoot(e) and belongsTo(e, tree) then
            local buf = { e }
            for k = 1, #buf do
                local parent = buf[k]
                if parent.__flex or parent.__grid then
                    for _, c in ipairs(parent.children) do
                        if not isFloating(c) then
                            buf[#buf + 1] = c
                            local comp = c.__flexComputed
                            if comp then
                                local ok, x, y, w, h = pcall(c.getAbsolutes, c)
                                if ok and x then
                                    if abs(x - comp.x) > epsilon or abs(y - comp.y) > epsilon
                                        or abs(w - comp.w) > epsilon or abs(h - comp.h) > epsilon then
                                        fails = fails + 1
                                        print(string.format(
                                            "FLEX VERIFY FAIL [%s] computed(%.4f,%.4f,%.4f,%.4f) " ..
                                            "resolves(%.4f,%.4f,%.4f,%.4f)",
                                            tostring(c.label or c.type),
                                            comp.x, comp.y, comp.w, comp.h, x, y, w, h))
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return fails
end

--------------------------------------------------------------------------------
-- Late injection (shader-module pattern, plan §1 item 5 / init.lua:2558-2562)
--------------------------------------------------------------------------------

function flexbox.init(gui, updater, drawer)
    guiRef = gui
    gui.setFlex   = flexbox.apiSetFlex
    gui.setSizing = flexbox.apiSetSizing
    -- grid late injection (grid plan §4 init row): same single injection
    -- point (init.lua:2580), lazy pcall require + nil-guard so a missing
    -- core/grid.lua leaves the grid API uninstalled and flex fully working.
    local g = gridMod()
    if g then
        gui.setGrid          = g.apiSetGrid
        gui.setGridPlacement = g.apiSetGridPlacement
        g.init(flexbox)
    end
end

return flexbox
