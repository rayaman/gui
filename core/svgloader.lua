-- svgloader.lua — pure-Lua SVG *vector* renderer for the LÖVE GUI library.
--
-- Parses a supported SVG subset ONCE into vector geometry, then draws it LIVE
-- every frame at the element's current box size via love draw commands, so
-- quality is preserved at any scale (crisp under flex/dualDim resizes — no
-- rasterization, no size-keyed image cache).
--
-- Vector pipeline (validated against the reference PNG on LÖVE 11.5):
--   parse -> flatten curves (C/S/Q/T/A) to polylines -> love.math.triangulate
--   each closed contour -> per shape, one baseline stencil "replace 0" pass +
--   ONE contour-writing stencil pass (evenodd="invert", nonzero uniform
--   ="increment") -> setStencilTest + fill the bbox (or draw a gradient/mask
--   textured mesh under it); strokes via line-strip meshes (dashes tessellated
--   at build). Everything is issued under a per-frame translate/scale so it
--   re-renders crisp at whatever size the box currently is.
--
-- NOTE: this build has NO love.math.newPath/Path/setFillMode (those are LÖVE
-- 12.0 APIs; verified absent in this stripped 11.5 build — see
-- plans/svgloader-plan.md §H.1 probe), nor love.graphics.setLineCap, nor canvas
-- stencil attachments; the stencil-parity approach is used instead. Stencil
-- WRITES are suppressed while a stencil test is active: do all stencil passes
-- first, then set the test. Anti-aliasing comes from window MSAA (t.window.msaa),
-- not from this loader.
--
-- Mirrors core/gifloader.lua's module shape (load() -> duck-typed object with
-- getWidth/getHeight), but there is no Updater/thread/kill: SVGs are static
-- vectors. The library hookup lives in init.lua's setImage: an `.svg` source
-- installs a `post` hook that re-reads getAbsolutes() each frame and calls
-- s:draw(x, y, w, h, {...}).
--
-- Direct use:
--   local svg = require("gui.core.svgloader")
--   local s = svg.load("bookmark-svg.svg")   -- parsed + cached per filepath
--   s:draw(x, y, w, h)                       -- absolute window space, meet-fit
--   s:draw(x, y, w, h, {rotation = 45, scaleX = -1, scaleY = 1, alpha = 0.5})
--   s:draw(x, y, w, h, {tint = "#ff0000"})   -- draw-time recolor (see :setSVGColor)
--   s:setSVGColor(colorTable)                -- persistent tint (nil restores)
--   s.width, s.height                        -- intrinsic px
--   svg.getInfo(s)
--   svg.clearCache()
--
-- Supported subset: svg root (width/height px or unitless, viewBox); elements
-- path, rect (incl. rx/ry), circle, ellipse, line, polyline, polygon, g (paint
-- inheritance + translate/scale/rotate/matrix/skew transform); path commands
-- M m L l H h V v Z z exact, C c S s and Q q T t flattened to polylines,
-- A a elliptical arcs (cubic-segment approximation); units px/unitless/pt/pc/
-- mm/cm/in/em/%; solid fills (#RGB, #RRGGBB, rgb(), named, none), fill-opacity,
-- fill-rule BOTH modes (evenodd parity "invert" pass; nonzero via a single
-- signed-area "increment" pass when all contours share an orientation, else
-- even-odd approximation + warn); stroke + stroke-width + stroke-opacity +
-- stroke-dasharray/dashoffset (tessellated to strip spans) + stroke-linejoin +
-- butt/square stroke-linecap (round cap/join approximated via line style);
-- group opacity folded into fill/stroke alpha; defs/use/symbol (href, x/y,
-- viewBox scaling, depth-capped); preserveAspectRatio xMin|xMid|xMax +
-- YMin|YMid|YMax + meet|slice + none.
--
-- clip-path (geometric Sutherland-Hodgman vs CONVEX regions; multiple children
-- intersect; concave regions skipped+warned) and masks (pure-Lua luminance
-- rasterization, sRGB weights; mask strokes/gradients inside masks unsupported;
-- gradient+mask on one shape -> gradient wins).
--
-- NOT supported: patterns, filters, SMIL, text/image; true round line
-- caps/joins (this build has no setLineCap and setLineJoin lacks "round").
--
-- Requires love.math.triangulate (LÖVE 0.10+; present in the project's 11.x).

if not (love and love.math and love.math.triangulate) then
    error("svgloader requires love.math.triangulate (LÖVE 0.10+)")
end

local SVG = {}

local rad = math.rad
local min, max = math.min, math.max
local cos, sin, tan = math.cos, math.sin, math.tan
local PI = math.pi
local TAU = 2 * math.pi

local SHAPE_TAGS = {
    path = true, rect = true, circle = true, ellipse = true,
    line = true, polyline = true, polygon = true,
}
-- Container tags build tree nodes (children nest under them); `use`, `stop` and
-- shape tags are leaves. DEFS_ONLY containers register into doc.defs by id and
-- are never drawn in document order. WARN_UNSUPPORTED warns once, then ignores.
local CONTAINER = {
    g = true, svg = true, defs = true, symbol = true,
    clipPath = true, mask = true, linearGradient = true, radialGradient = true,
    pattern = true, filter = true, switch = true,
}
local DEFS_ONLY = {
    defs = true, symbol = true, clipPath = true, mask = true,
    linearGradient = true, radialGradient = true, pattern = true, filter = true,
}
local WARN_UNSUPPORTED = { text = true, image = true }
-- Style attributes that inherit from ancestors (plan §H.2). `opacity` is folded
-- numerically (multiplied) in flatten, so it is handled separately.
local INHERIT_ATTRS = { "fill", "stroke", "fill-rule", "fill-opacity",
                        "stroke-opacity", "stroke-width", "stroke-linecap",
                        "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset",
                        "clip-path", "mask" }

local NAMED_COLORS = {
    black = { 0, 0, 0 },       white = { 1, 1, 1 },
    silver = { .75, .75, .75 }, gray = { .5, .5, .5 },  grey = { .5, .5, .5 },
    red = { 1, 0, 0 },         maroon = { .5, 0, 0 },
    purple = { .5, 0, .5 },    fuchsia = { 1, 0, 1 },
    green = { 0, .5, 0 },      lime = { 0, 1, 0 },
    olive = { .5, .5, 0 },     yellow = { 1, 1, 0 },
    navy = { 0, 0, .5 },       blue = { 0, 0, 1 },
    teal = { 0, .5, .5 },      aqua = { 0, 1, 1 },
    orange = { 1, .65, 0 },    transparent = nil,
}

-- ---------------------------------------------------------------------------
-- Token scanner: numbers/commands from viewBox, points, path d, transform args.
-- Handles implicit sign separators ("L5-3"), exponents, leading dots.
-- ---------------------------------------------------------------------------
local function scanTokens(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" or c == "," then
            i = i + 1
        elseif c:match("[A-Za-z]") then
            out[#out + 1] = c
            i = i + 1
        else
            local j = i
            if s:sub(j, j) == "+" or s:sub(j, j) == "-" then j = j + 1 end
            local digits = false
            while s:sub(j, j):match("%d") do j = j + 1 digits = true end
            if s:sub(j, j) == "." then
                j = j + 1
                while s:sub(j, j):match("%d") do j = j + 1 digits = true end
            end
            if digits and s:sub(j, j):match("[eE]") then
                local k = j + 1
                if s:sub(k, k) == "+" or s:sub(k, k) == "-" then k = k + 1 end
                if s:sub(k, k):match("%d") then
                    j = k
                    while s:sub(j, j):match("%d") do j = j + 1 end
                end
            end
            local num = tonumber(s:sub(i, j - 1))
            if num ~= nil then out[#out + 1] = num end
            i = math.max(j, i + 1)
        end
    end
    return out
end

local function numbers(s)
    local t = {}
    for _, v in ipairs(scanTokens(s or "")) do
        if type(v) == "number" then t[#t + 1] = v end
    end
    return t
end

-- Flag-aware path-data scanner. Inside A/a commands the 4th/5th params of each
-- 7-tuple are single-digit flags: "A4 4 0 01 8 8" must split into 0,1 where a
-- plain number scan would glue them into one number (1).
local function scanPathTokens(s)
    local out = {}
    local i, n = 1, #s
    local cmd, slot = nil, 0
    while i <= n do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" or c == "," then
            i = i + 1
        elseif c:match("[A-Za-z]") then
            out[#out + 1] = c
            cmd, slot = c, 0
            i = i + 1
        else
            slot = slot + 1
            local ss = (slot - 1) % 7 + 1  -- 1-based slot within the 7-tuple
            if (cmd == "A" or cmd == "a") and (ss == 4 or ss == 5) then
                local d = tonumber(c)
                if d ~= nil then out[#out + 1] = d end
                i = i + 1
            else
                local j = i
                if s:sub(j, j) == "+" or s:sub(j, j) == "-" then j = j + 1 end
                local digits = false
                while s:sub(j, j):match("%d") do j = j + 1 digits = true end
                if s:sub(j, j) == "." then
                    j = j + 1
                    while s:sub(j, j):match("%d") do j = j + 1 digits = true end
                end
                if digits and s:sub(j, j):match("[eE]") then
                    local k = j + 1
                    if s:sub(k, k) == "+" or s:sub(k, k) == "-" then k = k + 1 end
                    if s:sub(k, k):match("%d") then
                        j = k
                        while s:sub(j, j):match("%d") do j = j + 1 end
                    end
                end
                local v = tonumber(s:sub(i, j - 1))
                if v ~= nil then out[#out + 1] = v end
                i = math.max(j, i + 1)
            end
        end
    end
    return out
end

-- Unit-aware number: px/unitless pass through; pt/pc/mm/cm/in convert at
-- 96 dpi; em uses the root font-size (16 default); % resolves against the
-- caller-supplied viewport basis (nil -> treated as unitless).
local ROOT_FONT_SIZE = 16
local function numAttr(v, basis)
    if v == nil then return nil end
    local s = tostring(v)
    local n, unit = s:match("^%s*([%-+%.%d]+)%s*([a-zA-Z%%]*)%s*$")
    local num = tonumber(n)
    if num == nil then return nil end
    if unit == "" or unit == "px" then return num end
    if unit == "%" then return basis and num * basis / 100 or num end
    if unit == "pt" then return num * 4 / 3 end
    if unit == "pc" then return num * 16 end
    if unit == "mm" then return num * 96 / 25.4 end
    if unit == "cm" then return num * 96 / 2.54 end
    if unit == "in" then return num * 96 end
    if unit == "em" then return num * ROOT_FONT_SIZE end
    print("svgloader: unknown unit '" .. unit .. "' in '" .. s .. "' (treated as px)")
    return num
end

-- ---------------------------------------------------------------------------
-- Paint parsing
-- ---------------------------------------------------------------------------
local function parsePaint(s)
    if s == nil then return nil end
    s = tostring(s):lower():match("^%s*(.-)%s*$")
    if s == "" or s == "none" or s == "transparent" then return nil end
    if s:sub(1, 1) == "#" then
        local h = s:sub(2)
        if #h == 3 then
            return { tonumber(h:sub(1, 1), 16) * 17 / 255,
                     tonumber(h:sub(2, 2), 16) * 17 / 255,
                     tonumber(h:sub(3, 3), 16) * 17 / 255 }
        elseif #h == 6 or #h == 8 then
            return { tonumber(h:sub(1, 2), 16) / 255,
                     tonumber(h:sub(3, 4), 16) / 255,
                     tonumber(h:sub(5, 6), 16) / 255 }
        end
        print("svgloader: unsupported color form: " .. s)
        return { 0, 0, 0 }
    end
    if s:match("^rgba?%(") then
        local inner = s:match("%(([^)]*)%)")
        local parts = numbers(inner)
        if #parts >= 3 then
            local function comp(v) return v <= 1 and v or v / 255 end
            return { comp(parts[1]), comp(parts[2]), comp(parts[3]) }
        end
        print("svgloader: unsupported rgb() color: " .. s)
        return { 0, 0, 0 }
    end
    local named = NAMED_COLORS[s]
    if named then return { named[1], named[2], named[3] } end
    print("svgloader: unknown color: " .. s)
    return { 0, 0, 0 }
end

-- Affine 2x3 matrices {a,b,c,d,e,f}: x' = a*x + c*y + e, y' = b*x + d*y + f.
-- Replaces the v1 axis-aligned {sx,sy,tx,ty} model (plan §H.3) so rotate /
-- matrix / skewX / skewY compose like SVG's transform list.
local function matMul(m1, m2)
    return {
        a = m1.a * m2.a + m1.c * m2.b,
        b = m1.b * m2.a + m1.d * m2.b,
        c = m1.a * m2.c + m1.c * m2.d,
        d = m1.b * m2.c + m1.d * m2.d,
        e = m1.a * m2.e + m1.c * m2.f + m1.e,
        f = m1.b * m2.e + m1.d * m2.f + m1.f,
    }
end

local function parseTransform(s)
    local m = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }
    if not s then return m end
    for fn, arg in tostring(s):gmatch("(%w+)%(([^)]*)%)") do
        local p = numbers(arg)
        local om
        if fn == "translate" then
            om = { a = 1, b = 0, c = 0, d = 1, e = p[1] or 0, f = p[2] or 0 }
        elseif fn == "scale" then
            local sx = p[1] or 1
            om = { a = sx, b = 0, c = 0, d = p[2] or sx, e = 0, f = 0 }
        elseif fn == "rotate" then
            local ang = rad(p[1] or 0)
            local ca, sa = cos(ang), sin(ang)
            om = { a = ca, b = sa, c = -sa, d = ca, e = 0, f = 0 }
            if p[2] and p[3] then
                om = matMul({ a = 1, b = 0, c = 0, d = 1, e = p[2], f = p[3] },
                    matMul(om, { a = 1, b = 0, c = 0, d = 1, e = -p[2], f = -p[3] }))
            end
        elseif fn == "skewX" then
            om = { a = 1, b = tan(rad(p[1] or 0)), c = 0, d = 1, e = 0, f = 0 }
        elseif fn == "skewY" then
            om = { a = 1, b = 0, c = tan(rad(p[1] or 0)), d = 1, e = 0, f = 0 }
        elseif fn == "matrix" then
            om = { a = p[1] or 1, b = p[2] or 0, c = p[3] or 0,
                   d = p[4] or 1, e = p[5] or 0, f = p[6] or 0 }
        else
            print("svgloader: unsupported transform: " .. fn .. " (ignored)")
        end
        if om then m = matMul(m, om) end
    end
    return m
end

-- ---------------------------------------------------------------------------
-- Path data -> sequence of CONTOURS. Each contour is a flat list of absolute
-- user coords {x1,y1,x2,y2,...} plus a closed flag. Curves are flattened to
-- line segments (cubic/quadratic via subdivision; arcs -> cubic segments).
-- ---------------------------------------------------------------------------
local function flattenCubic(x0, y0, x1, y1, x2, y2, x3, y3, out)
    -- fixed-step subdivision (16) — simple, good enough for icon geometry
    local STEPS = 16
    for i = 1, STEPS do
        local t = i / STEPS
        local mt = 1 - t
        local a = mt * mt * mt
        local b = 3 * mt * mt * t
        local c = 3 * mt * t * t
        local d = t * t * t
        out[#out + 1] = a * x0 + b * x1 + c * x2 + d * x3
        out[#out + 1] = a * y0 + b * y1 + c * y2 + d * y3
    end
end

-- Elliptical arc -> cubic segments (SVG spec F.6.5 endpoint->center + F.6.6
-- cubic approximation), appended flattened into `out`.
local function arcToCubics(x1, y1, rx, ry, phiDeg, laf, sf, x2, y2, out)
    if x1 == x2 and y1 == y2 then return end
    rx, ry = math.abs(rx or 0), math.abs(ry or 0)
    if rx == 0 or ry == 0 then
        out[#out + 1] = x2; out[#out + 1] = y2
        return
    end
    local phi = rad(phiDeg or 0)
    local cphi, sphi = cos(phi), sin(phi)
    local dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    local x1p = cphi * dx + sphi * dy
    local y1p = -sphi * dx + cphi * dy
    local lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 then  -- F.6.5 radii out-of-range correction
        local k = math.sqrt(lambda)
        rx, ry = rx * k, ry * k
    end
    local rx2, ry2 = rx * rx, ry * ry
    local num = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
    if num < 0 then num = 0 end
    local den = rx2 * y1p * y1p + ry2 * x1p * x1p
    if den <= 0 then out[#out + 1] = x2; out[#out + 1] = y2; return end
    local co = (laf ~= sf) and 1 or -1
    local sq = co * math.sqrt(num / den)
    local cxp = sq * rx * y1p / ry
    local cyp = -sq * ry * x1p / rx
    local cx = cphi * cxp - sphi * cyp + (x1 + x2) / 2
    local cy = sphi * cxp + cphi * cyp + (y1 + y2) / 2
    local function ang(ux, uy, vx, vy)
        local d = ux * vx + uy * vy
        local l = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
        if l == 0 then return 0 end
        local a = math.acos(max(-1, min(1, d / l)))
        if ux * vy - uy * vx < 0 then a = -a end
        return a
    end
    local ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    local vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    local th = ang(1, 0, ux, uy)
    local dth = ang(ux, uy, vx, vy)
    if sf then
        if dth < 0 then dth = dth + TAU end
    else
        if dth > 0 then dth = dth - TAU end
    end
    local n = max(1, math.ceil(math.abs(dth) / (PI / 2)))
    local delta = dth / n
    local t = 4 / 3 * tan(delta / 4)
    for i = 1, n do
        local a0 = th + (i - 1) * delta
        local a1 = th + i * delta
        local c0, s0, c1, s1 = cos(a0), sin(a0), cos(a1), sin(a1)
        local ex0 = cx + rx * c0 * cphi - ry * s0 * sphi
        local ey0 = cy + rx * c0 * sphi + ry * s0 * cphi
        local ex1 = cx + rx * c1 * cphi - ry * s1 * sphi
        local ey1 = cy + rx * c1 * sphi + ry * s1 * cphi
        local d0x = -rx * s0 * cphi - ry * c0 * sphi
        local d0y = -rx * s0 * sphi + ry * c0 * cphi
        local d1x = -rx * s1 * cphi - ry * c1 * sphi
        local d1y = -rx * s1 * sphi + ry * c1 * cphi
        flattenCubic(ex0, ey0, ex0 + t * d0x, ey0 + t * d0y,
                     ex1 - t * d1x, ey1 - t * d1y, ex1, ey1, out)
    end
end

local function execPathContours(d, warned)
    local toks = scanPathTokens(d or "")
    local contours = {}
    local cur = nil
    local ti = 1
    local x, y = 0, 0
    local subX, subY = 0, 0
    local c2x, c2y, qx, qy
    local prev

    local function ensure()
        if not cur then cur = {}; contours[#contours + 1] = cur end
    end
    local function pt(px, py) ensure(); cur[#cur + 1] = px; cur[#cur + 1] = py end
    local function num(v) return type(v) == "number" end
    local function nextNum() return num(toks[ti]) end

    while ti <= #toks do
        local tok = toks[ti]
        local cmd
        if type(tok) == "string" then cmd = tok; ti = ti + 1
        elseif prev then cmd = (prev == "M") and "L" or (prev == "m" and "l" or prev)
        else ti = ti + 1 end
        if not cmd then break end

        if cmd == "Z" or cmd == "z" then
            if cur then cur.closed = true end
            x, y = subX, subY
            cur = nil
            prev = "Z"
        elseif cmd == "M" or cmd == "m" then
            if not (nextNum() and num(toks[ti + 1])) then break end
            local a, b = toks[ti], toks[ti + 1]; ti = ti + 2
            if cmd == "M" then x, y = a, b else x, y = x + a, y + b end
            subX, subY = x, y
            cur = nil
            pt(x, y)
            prev = cmd
        elseif cmd == "L" or cmd == "l" then
            if not (nextNum() and num(toks[ti + 1])) then break end
            local a, b = toks[ti], toks[ti + 1]; ti = ti + 2
            if cmd == "L" then x, y = a, b else x, y = x + a, y + b end
            pt(x, y); prev = cmd
        elseif cmd == "H" or cmd == "h" then
            if not nextNum() then break end
            if cmd == "H" then x = toks[ti] else x = x + toks[ti] end
            ti = ti + 1
            pt(x, y); prev = cmd
        elseif cmd == "V" or cmd == "v" then
            if not nextNum() then break end
            if cmd == "V" then y = toks[ti] else y = y + toks[ti] end
            ti = ti + 1
            pt(x, y); prev = cmd
        elseif cmd == "C" or cmd == "c" then
            if not num(toks[ti + 5]) then break end
            local x1, y1, x2, y2, ex, ey = toks[ti], toks[ti + 1], toks[ti + 2],
                                           toks[ti + 3], toks[ti + 4], toks[ti + 5]
            ti = ti + 6
            if cmd == "c" then
                x1, y1 = x + x1, y + y1; x2, y2 = x + x2, y + y2; ex, ey = x + ex, y + ey
            end
            ensure()
            flattenCubic(x, y, x1, y1, x2, y2, ex, ey, cur)
            c2x, c2y = x2, y2
            x, y = ex, ey
            prev = cmd
        elseif cmd == "S" or cmd == "s" then
            if not num(toks[ti + 3]) then break end
            local x2, y2, ex, ey = toks[ti], toks[ti + 1], toks[ti + 2], toks[ti + 3]
            ti = ti + 4
            if cmd == "s" then x2, y2 = x + x2, y + y2; ex, ey = x + ex, y + ey end
            local x1, y1
            if prev == "C" or prev == "c" or prev == "S" or prev == "s" then
                x1, y1 = 2 * x - c2x, 2 * y - c2y
            elseif prev == "Q" or prev == "q" or prev == "T" or prev == "t" then
                x1, y1 = 2 * x - qx, 2 * y - qy
            else x1, y1 = x, y end
            ensure()
            flattenCubic(x, y, x1, y1, x2, y2, ex, ey, cur)
            c2x, c2y = x2, y2
            x, y = ex, ey
            prev = cmd
        elseif cmd == "Q" or cmd == "q" then
            if not num(toks[ti + 3]) then break end
            local cx, cy, ex, ey = toks[ti], toks[ti + 1], toks[ti + 2], toks[ti + 3]
            ti = ti + 4
            if cmd == "q" then cx, cy = x + cx, y + cy; ex, ey = x + ex, y + ey end
            -- exact degree elevation quadratic->cubic, then flatten
            ensure()
            flattenCubic(x, y, x + 2 / 3 * (cx - x), y + 2 / 3 * (cy - y),
                ex + 2 / 3 * (cx - ex), ey + 2 / 3 * (cy - ey), ex, ey, cur)
            qx, qy = cx, cy
            x, y = ex, ey
            prev = cmd
        elseif cmd == "T" or cmd == "t" then
            if not (nextNum() and num(toks[ti + 1])) then break end
            local ex, ey = toks[ti], toks[ti + 1]; ti = ti + 2
            if cmd == "t" then ex, ey = x + ex, y + ey end
            local cx, cy
            if prev == "Q" or prev == "q" or prev == "T" or prev == "t" then
                cx, cy = 2 * x - qx, 2 * y - qy
            else cx, cy = x, y end
            ensure()
            flattenCubic(x, y, x + 2 / 3 * (cx - x), y + 2 / 3 * (cy - y),
                ex + 2 / 3 * (cx - ex), ey + 2 / 3 * (cy - ey), ex, ey, cur)
            qx, qy = cx, cy
            x, y = ex, ey
            prev = cmd
        elseif cmd == "A" or cmd == "a" then
            if not num(toks[ti + 6]) then break end
            local rx, ry, rot = toks[ti], toks[ti + 1], toks[ti + 2]
            local laf, sf2 = toks[ti + 3], toks[ti + 4]
            local ex, ey = toks[ti + 5], toks[ti + 6]
            ti = ti + 7
            if cmd == "a" then ex, ey = x + ex, y + ey end
            ensure()
            arcToCubics(x, y, rx, ry, rot, laf ~= 0, sf2 ~= 0, ex, ey, cur)
            x, y = ex, ey
            prev = cmd
        else
            print("svgloader: unknown path command: " .. cmd)
            ti = ti + 1
        end
    end
    -- trim degenerate contours
    local kept = {}
    for _, c in ipairs(contours) do
        if #c >= 4 then kept[#kept + 1] = c end
    end
    return kept
end

-- ---------------------------------------------------------------------------
-- Primitive shapes -> contour lists (flat abs coords + closed flag)
-- ---------------------------------------------------------------------------
local KAPPA = 0.5522847498307936

local function circleContours(cx, cy, rx, ry)
    local ox, oy = rx * KAPPA, ry * KAPPA
    local c = {}
    local function push(px, py) c[#c + 1] = px; c[#c + 1] = py end
    push(cx + rx, cy)
    -- four cubic quarters, flattened via 16-step each
    local function quarter(x0, y0, x1, y1, x2, y2, x3, y3)
        for i = 1, 16 do
            local t = i / 16; local mt = 1 - t
            local a, b, cc, dd = mt * mt * mt, 3 * mt * mt * t, 3 * mt * t * t, t * t * t
            push(a * x0 + b * x1 + cc * x2 + dd * x3, a * y0 + b * y1 + cc * y2 + dd * y3)
        end
    end
    quarter(cx + rx, cy, cx + rx, cy + oy, cx + ox, cy + ry, cx, cy + ry)
    quarter(cx, cy + ry, cx - ox, cy + ry, cx - rx, cy + oy, cx - rx, cy)
    quarter(cx - rx, cy, cx - rx, cy - oy, cx - ox, cy - ry, cx, cy - ry)
    quarter(cx, cy - ry, cx + ox, cy - ry, cx + rx, cy - oy, cx + rx, cy)
    c.closed = true
    return { c }
end

local function polyContour(points, closed)
    local c = {}
    for _, v in ipairs(points) do c[#c + 1] = v end
    c.closed = closed
    return { c }
end

-- Rounded rect: four straight edges joined by quarter cubics (same KAPPA
-- machinery as circleContours). rx/ry clamped to half the side (SVG spec).
local function roundRectContours(x, y, w, h, rx, ry)
    if (rx or 0) <= 0 or (ry or 0) <= 0 or w <= 0 or h <= 0 then
        return { { x, y, x + w, y, x + w, y + h, x, y + h, closed = true } }
    end
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    local ox, oy = rx * KAPPA, ry * KAPPA
    local c = {}
    local function push(px, py) c[#c + 1] = px; c[#c + 1] = py end
    local function quarter(x0, y0, x1, y1, x2, y2, x3, y3)
        for i = 1, 16 do
            local t = i / 16; local mt = 1 - t
            local a, b, cc, dd = mt * mt * mt, 3 * mt * mt * t, 3 * mt * t * t, t * t * t
            push(a * x0 + b * x1 + cc * x2 + dd * x3, a * y0 + b * y1 + cc * y2 + dd * y3)
        end
    end
    push(x + rx, y)
    push(x + w - rx, y)
    quarter(x + w - rx, y, x + w - rx + ox, y, x + w, y + ry - oy, x + w, y + ry)
    push(x + w, y + h - ry)
    quarter(x + w, y + h - ry, x + w, y + h - ry + oy, x + w - rx + ox, y + h, x + w - rx, y + h)
    push(x + rx, y + h)
    quarter(x + rx, y + h, x + rx - ox, y + h, x, y + h - ry + oy, x, y + h - ry)
    push(x, y + ry)
    quarter(x, y + ry, x, y + ry - oy, x + rx - ox, y, x + rx, y)
    c.closed = true
    return { c }
end

-- Shoelace signed area of a closed contour (flat abs coords). Sign = winding
-- direction; used to pick stencil increment vs decrement per contour so
-- fill-rule="nonzero" counts crossings with sign instead of parity.
local function contourSignedArea(cont)
    local n = #cont / 2
    if n < 3 then return 0 end
    local a = 0
    for i = 1, n do
        local j = i % n + 1
        a = a + (cont[2 * i - 1] * cont[2 * j] - cont[2 * j - 1] * cont[2 * i])
    end
    return a / 2
end

-- ---------------------------------------------------------------------------
-- Document parse
-- ---------------------------------------------------------------------------
local function parseAttrs(tag)
    local t = {}
    for name, val in tag:gmatch('([%w_:%-]+)=["\']([^"\']*)["\']') do t[name] = val end
    return t
end

local function inheritFrom(parent, a)
    local eff = {}
    for _, k in ipairs(INHERIT_ATTRS) do
        eff[k] = (a[k] ~= nil) and a[k] or parent[k]
    end
    -- parent ∘ own: the element's own transform applies first, then ancestors'
    eff.tf = matMul(parent.tf, parseTransform(a.transform))
    return eff
end

-- transform + subtract viewBox origin so geometry lives in 0..vbW x 0..vbH
local function xformContour(cont, tf, vbX, vbY)
    local out = {}
    for k = 1, #cont, 2 do
        local x, y = cont[k], cont[k + 1]
        out[k] = tf.a * x + tf.c * y + tf.e - vbX
        out[k + 1] = tf.b * x + tf.d * y + tf.f - vbY
    end
    out.closed = cont.closed
    return out
end

-- ---------------------------------------------------------------------------
-- clip-path (plan §H.1 probe revision): GEOMETRIC clipping at build time —
-- this build cannot nest stencil passes (writes reset per stencil() call and
-- are suppressed under an active test). Sutherland-Hodgman against CONVEX
-- clip regions; multiple children INTERSECT (documented approximation of the
-- spec union); concave children warn once and the clip is skipped.
-- ---------------------------------------------------------------------------
local shapeContours   -- forward decl: defined after the clip/mask helpers

local function isConvexPoly(cont)
    local n = #cont / 2
    if n < 3 then return false end
    local sign = 0
    for i = 1, n do
        local j = i % n + 1
        local k = j % n + 1
        local ax, ay = cont[2*i-1], cont[2*i]
        local bx, by = cont[2*j-1], cont[2*j]
        local cx2, cy2 = cont[2*k-1], cont[2*k]
        local cr = (bx-ax)*(cy2-ay) - (by-ay)*(cx2-ax)
        if math.abs(cr) > 1e-9 then
            local s = cr > 0 and 1 or -1
            if sign == 0 then sign = s elseif s ~= sign then return false end
        end
    end
    return true
end

local function clipToConvex(sub, clip)
    local out = {}
    local n = #sub / 2
    for i = 1, n do out[#out+1] = sub[2*i-1]; out[#out+1] = sub[2*i] end
    local m = #clip / 2
    local sgn = contourSignedArea(clip) >= 0 and 1 or -1
    for i = 1, m do
        if #out < 6 then break end
        local ax, ay = clip[2*i-1], clip[2*i]
        local j = i % m + 1
        local bx, by = clip[2*j-1], clip[2*j]
        local ex, ey = bx - ax, by - ay
        local inp = out
        out = {}
        local pn = #inp / 2
        local function inter(px, py, qx, qy)
            local dx, dy = qx - px, qy - py
            local den = dx*ey - dy*ex
            if math.abs(den) < 1e-12 then return px, py end
            local t = ((ax-px)*ey - (ay-py)*ex) / den
            return px + dx*t, py + dy*t
        end
        for k = 1, pn do
            local px, py = inp[2*k-1], inp[2*k]
            local kk = k % pn + 1
            local qx, qy = inp[2*kk-1], inp[2*kk]
            local pc = sgn * (ex*(py-ay) - ey*(px-ax))
            local qc = sgn * (ex*(qy-ay) - ey*(qx-ax))
            if pc >= 0 then
                out[#out+1] = px; out[#out+1] = py
                if qc < 0 then
                    local ix, iy = inter(px, py, qx, qy)
                    out[#out+1] = ix; out[#out+1] = iy
                end
            elseif qc >= 0 then
                local ix, iy = inter(px, py, qx, qy)
                out[#out+1] = ix; out[#out+1] = iy
            end
        end
    end
    return out
end

local function applyClipPath(doc, ref, xf, warned)
    local id = tostring(ref):match("^%s*url%(#([%w_%-]+)%)%s*$")
    local node = id and doc.defs and doc.defs[id]
    if not node or node.name ~= "clipPath" then
        if id and not warned["clip:" .. id] then
            warned["clip:" .. id] = true
            print("svgloader: clip-path url(#" .. id .. ") references no clipPath (ignored)")
        end
        return xf
    end
    local tfBase = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }
    if node.attrs.clipPathUnits == "objectBoundingBox" then
        local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
        for _, c in ipairs(xf) do
            for i = 1, #c, 2 do
                bx0 = min(bx0, c[i]); bx1 = max(bx1, c[i])
                by0 = min(by0, c[i+1]); by1 = max(by1, c[i+1])
            end
        end
        if bx1 > bx0 and by1 > by0 then
            tfBase = { a = bx1-bx0, b = 0, c = 0, d = by1-by0, e = bx0, f = by0 }
        end
    end
    local polys
    for _, ch in ipairs(node.children) do
        if SHAPE_TAGS[ch.name] then
            local conts = shapeContours(ch.name, ch.attrs, doc, warned)
            if conts then
                local tf = matMul(tfBase, parseTransform(ch.attrs.transform))
                for _, c in ipairs(conts) do
                    if c.closed and #c >= 6 then
                        local xc = xformContour(c, tf, doc.vbX, doc.vbY)
                        if not isConvexPoly(xc) then
                            if not warned["clipConvex"] then
                                warned["clipConvex"] = true
                                print("svgloader: concave clip-path child unsupported (clip skipped)")
                            end
                            return xf
                        end
                        polys = polys or {}
                        polys[#polys + 1] = xc
                    end
                end
            end
        end
    end
    if not polys then return xf end
    local out = {}
    for _, c in ipairs(xf) do
        if c.closed and #c >= 6 then
            for _, p in ipairs(polys) do c = clipToConvex(c, p) end
            if #c >= 6 then c.closed = true; out[#out + 1] = c end
        else
            out[#out + 1] = c
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- mask (plan §H.1 probe revision): pure-Lua ImageData rasterization (this
-- build has no canvas stencils). Luminance -> alpha (sRGB weights; linearRGB
-- is the spec default — documented deviation). WHITE RGB is baked into the
-- raster (luminance rides pixel alpha); the shape's fill color — or the
-- active draw-time tint — rides the vertex color at draw time, so a masked
-- fill draws as a colored textured quad under the normal shape stencil,
-- same code path as gradient meshes, no shader needed. maskUnits
-- (objectBoundingBox default w/ SVG region defaults,
-- userSpaceOnUse) and maskContentUnits (userSpaceOnUse default,
-- objectBoundingBox) supported. Mask strokes and gradient fills inside masks:
-- unsupported (warn once). mask + gradient on one shape: gradient wins.
-- ---------------------------------------------------------------------------
local MASK_RES = 96

local function pointInPoly(px, py, cont)
    local n = #cont / 2
    local inside = false
    for i = 1, n do
        local j = i % n + 1
        local xi, yi = cont[2*i-1], cont[2*i]
        local xj, yj = cont[2*j-1], cont[2*j]
        if (yi > py) ~= (yj > py)
            and px < (xj - xi) * (py - yi) / (yj - yi) + xi then
            inside = not inside
        end
    end
    return inside
end

local function collectMaskShapes(doc, node, tf, style, out, warned, depth)
    if depth > 8 then return end
    for _, ch in ipairs(node.children) do
        if SHAPE_TAGS[ch.name] then
            local eff = {}
            for _, k in ipairs(INHERIT_ATTRS) do
                eff[k] = (ch.attrs[k] ~= nil) and ch.attrs[k] or style[k]
            end
            local ctf = matMul(tf, parseTransform(ch.attrs.transform))
            local conts = shapeContours(ch.name, ch.attrs, doc, warned)
            if conts then
                local xf = {}
                for _, c in ipairs(conts) do
                    if c.closed and #c >= 6 then
                        xf[#xf + 1] = xformContour(c, ctf, doc.vbX, doc.vbY)
                    end
                end
                out[#out + 1] = {
                    contours = xf,
                    fill = parsePaint(eff.fill or "#000000") or { 0, 0, 0 },
                    alpha = (tonumber(eff["fill-opacity"]) or 1)
                          * (tonumber(ch.attrs.opacity) or 1),
                }
            end
        elseif ch.name == "g" then
            local eff = {}
            for _, k in ipairs(INHERIT_ATTRS) do
                eff[k] = (ch.attrs[k] ~= nil) and ch.attrs[k] or style[k]
            end
            eff.opacity = (tonumber(style.opacity) or 1)
                        * (tonumber(ch.attrs.opacity) or 1)
            collectMaskShapes(doc, ch,
                matMul(tf, parseTransform(ch.attrs.transform)), eff, out, warned, depth + 1)
        elseif not warned["maskChild:" .. ch.name] then
            warned["maskChild:" .. ch.name] = true
            print("svgloader: <" .. ch.name .. "> inside <mask> not supported (skipped)")
        end
    end
end

local function buildMaskMesh(sh, node, doc)
    local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(sh.contours) do
        for i = 1, #c, 2 do
            bx0 = min(bx0, c[i]); bx1 = max(bx1, c[i])
            by0 = min(by0, c[i+1]); by1 = max(by1, c[i+1])
        end
    end
    if bx1 <= bx0 or by1 <= by0 then return nil end
    local bw, bh = bx1 - bx0, by1 - by0

    local mx, my, mw, mh
    if (node.attrs.maskUnits or "objectBoundingBox") == "objectBoundingBox" then
        local function f(v, d)
            if v == nil then return d end
            local n = tonumber(tostring(v):match("^%s*([%-+%.%d]+)"))
            if n == nil then return d end
            if tostring(v):find("%%") then n = n / 100 end
            return n
        end
        mx = bx0 + f(node.attrs.x, -0.1) * bw
        my = by0 + f(node.attrs.y, -0.1) * bh
        mw = f(node.attrs.width, 1.2) * bw
        mh = f(node.attrs.height, 1.2) * bh
    else
        mx = (numAttr(node.attrs.x, doc.vbW) or 0) - doc.vbX
        my = (numAttr(node.attrs.y, doc.vbH) or 0) - doc.vbY
        mw = numAttr(node.attrs.width, doc.vbW) or doc.vbW
        mh = numAttr(node.attrs.height, doc.vbH) or doc.vbH
    end
    if mw <= 0 or mh <= 0 then return nil end

    local warned = {}
    local shapes = {}
    local tfBase = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }
    if node.attrs.maskContentUnits == "objectBoundingBox" then
        tfBase = { a = bw, b = 0, c = 0, d = bh, e = bx0, f = by0 }
    end
    collectMaskShapes(doc, node, tfBase, {}, shapes, warned, 0)
    if #shapes == 0 then return nil end

    local img = love.image.newImageData(MASK_RES, MASK_RES)
    -- White RGB baked in: the final color (shape fill or setSVGColor tint) is
    -- applied as the vertex color in SVGmt:draw's maskMesh branch.
    local R, G, B = 1, 1, 1
    for py = 0, MASK_RES - 1 do
        local uy = my + mh * (py + 0.5) / MASK_RES
        for px = 0, MASK_RES - 1 do
            local ux = mx + mw * (px + 0.5) / MASK_RES
            local dr, dg, db, da = 0, 0, 0, 0
            for _, ms in ipairs(shapes) do
                local cov = false
                for _, c in ipairs(ms.contours) do
                    if pointInPoly(ux, uy, c) then cov = true; break end
                end
                if cov then
                    local a = ms.alpha
                    dr = ms.fill[1] * a + dr * (1 - a)
                    dg = ms.fill[2] * a + dg * (1 - a)
                    db = ms.fill[3] * a + db * (1 - a)
                    da = a + da * (1 - a)
                end
            end
            local lum = 0.3 * dr + 0.59 * dg + 0.11 * db
            img:setPixel(px, py, R, G, B, max(0, min(1, lum * da)) * sh.fillAlpha)
        end
    end
    local tex = love.graphics.newImage(img)
    tex:setWrap("clamp", "clamp")
    tex:setFilter("linear", "linear")
    local verts = {
        { mx, my, 0, 0 }, { mx + mw, my, 1, 0 }, { mx + mw, my + mh, 1, 1 },
        { mx, my, 0, 0 }, { mx + mw, my + mh, 1, 1 }, { mx, my + mh, 0, 1 },
    }
    local mesh = love.graphics.newMesh(verts, "triangles")
    mesh:setTexture(tex)
    return mesh
end

-- Build the raw (pre-transform) contour list for one shape element.
function shapeContours(name, a, doc, warned)
    if name == "path" then
        return execPathContours(a.d, warned)
    elseif name == "rect" then
        local x = numAttr(a.x, doc.vbW) or 0
        local y = numAttr(a.y, doc.vbH) or 0
        local w = numAttr(a.width, doc.vbW) or 0
        local h = numAttr(a.height, doc.vbH) or 0
        local rx = numAttr(a.rx, doc.vbW)
        local ry = numAttr(a.ry, doc.vbH)
        if rx == nil and ry ~= nil then rx = ry
        elseif ry == nil and rx ~= nil then ry = rx end
        return roundRectContours(x, y, w, h, rx or 0, ry or 0)
    elseif name == "circle" then
        local rbase = math.sqrt((doc.vbW * doc.vbW + doc.vbH * doc.vbH) / 2)
        return circleContours(numAttr(a.cx, doc.vbW) or 0, numAttr(a.cy, doc.vbH) or 0,
            numAttr(a.r, rbase) or 0, numAttr(a.r, rbase) or 0)
    elseif name == "ellipse" then
        return circleContours(numAttr(a.cx, doc.vbW) or 0, numAttr(a.cy, doc.vbH) or 0,
            numAttr(a.rx, doc.vbW) or 0, numAttr(a.ry, doc.vbH) or 0)
    elseif name == "line" then
        return { { numAttr(a.x1, doc.vbW) or 0, numAttr(a.y1, doc.vbH) or 0,
                   numAttr(a.x2, doc.vbW) or 0, numAttr(a.y2, doc.vbH) or 0, closed = false } }
    elseif name == "polyline" or name == "polygon" then
        return polyContour(numbers(a.points or ""), name == "polygon")
    end
    return nil
end

local function addShape(doc, name, a, eff, warned)
    local contours = shapeContours(name, a, doc, warned)
    if not contours then return end

    local hasFillable = false
    for _, c in ipairs(contours) do if c.closed and #c >= 6 then hasFillable = true end end
    -- fill may be a paint-server reference: url(#id) -> gradient (plan §H.6).
    -- Unknown/missing id -> fill none (SVG spec) + warn once.
    local gradId
    if type(eff.fill) == "string" then
        gradId = eff.fill:match("^%s*url%(#([%w_%-]+)%)%s*$")
    end
    local fill
    if gradId then
        local node = doc.defs and doc.defs[gradId]
        if node and (node.name == "linearGradient" or node.name == "radialGradient") then
            fill = { 1, 1, 1 }   -- placeholder; ensureBuilt builds gradMesh
        else
            if not warned["grad:" .. gradId] then
                warned["grad:" .. gradId] = true
                print("svgloader: fill url(#" .. gradId .. ") references no gradient (fill none)")
            end
            gradId = nil
        end
    else
        fill = parsePaint(eff.fill or "#000000")
    end
    local stroke = parsePaint(eff.stroke or "none")
    if (not fill or not hasFillable) and not stroke then return end

    local xf = {}
    for _, c in ipairs(contours) do xf[#xf + 1] = xformContour(c, eff.tf, doc.vbX, doc.vbY) end

    -- clip-path: geometric Sutherland-Hodgman clipping (helpers above);
    -- mask: id validated here, rasterized lazily in ensureBuilt.
    if eff["clip-path"] then
        xf = applyClipPath(doc, eff["clip-path"], xf, warned)
    end
    local maskId
    if eff["mask"] then
        maskId = tostring(eff["mask"]):match("^%s*url%(#([%w_%-]+)%)%s*$")
        if maskId and not (doc.defs and doc.defs[maskId]
                           and doc.defs[maskId].name == "mask") then
            if not warned["mask:" .. maskId] then
                warned["mask:" .. maskId] = true
                print("svgloader: mask url(#" .. maskId .. ") references no mask (ignored)")
            end
            maskId = nil
        end
    end

    local gop = tonumber(eff.opacity) or 1   -- inherited group opacity folded in
    doc.shapes[#doc.shapes + 1] = {
        kind = name, contours = xf,
        fill = (hasFillable and fill) or nil,
        fillAlpha = (tonumber(eff["fill-opacity"]) or 1) * gop,
        fillRule = eff["fill-rule"] or "nonzero",
        stroke = stroke,
        strokeAlpha = (tonumber(eff["stroke-opacity"]) or 1) * gop,
        strokeWidth = tonumber(eff["stroke-width"]) or 1,
        closed = (name ~= "line" and name ~= "polyline"),
        clipPath = eff["clip-path"], mask = eff["mask"], maskId = maskId,
        dasharray = eff["stroke-dasharray"], dashoffset = tonumber(eff["stroke-dashoffset"]),
        linecap = eff["stroke-linecap"], linejoin = eff["stroke-linejoin"],
        grad = gradId,
    }
end

-- returns { vbX, vbY, vbW, vbH, width, height, par, shapes = { ... }, defs = {id=node} }
-- Two-phase (plan §H.2): (1) build an element tree, registering every id-bearing
-- node into doc.defs; (2) flatten body containers in document order, inheriting
-- style + transform, expanding use/symbol references (depth-capped), and
-- compiling shapes. This resolves forward references (defs after use, url(#id))
-- that the streaming v1 parser could not. `addShape`/doc.shapes are unchanged.
function SVG.parse(text)
    text = text:gsub("<!%-%-.-%-%->", " ")
    text = text:gsub("<%?.-%?>", " ")
    text = text:gsub("<!DOCTYPE[^>]->", " ")

    local doc = { vbX = 0, vbY = 0, vbW = nil, vbH = nil, width = nil, height = nil,
                  par = nil, shapes = {}, defs = {} }
    local warned = {}

    -- ---- phase 1: tree build + defs registry ---------------------------
    local root, rootDone = nil, false
    local stack, cur = {}, nil

    for tag in text:gmatch("<[^>]->") do
        local closing = tag:sub(2, 2) == "/"
        local selfClose = tag:sub(-2, -1) == "/>"
        local name = tag:match("^</?([%w:_%-]+)")

        if not name then
            -- skip
        elseif name == "svg" and not closing and not rootDone then
            rootDone = true
            local a = parseAttrs(tag)
            local vb = numbers(a.viewBox or "")
            if #vb >= 4 then
                doc.vbX, doc.vbY, doc.vbW, doc.vbH = vb[1], vb[2], vb[3], vb[4]
            else
                doc.vbW = numAttr(a.width) or 300
                doc.vbH = numAttr(a.height) or 150
            end
            doc.width = numAttr(a.width) or doc.vbW
            doc.height = numAttr(a.height) or doc.vbH
            doc.par = a.preserveAspectRatio
            if not doc.par or doc.par == "defer" then doc.par = "xMidYMid meet" end
            if doc.par == "none" then doc.par = "none meet" end
            root = { name = "svg", attrs = a, children = {} }
            if a.id then doc.defs[a.id] = root end
            cur = root
            if not selfClose then stack[#stack + 1] = root end
        elseif closing then
            if #stack > 0 then
                stack[#stack] = nil          -- lenient: pop regardless of name
                cur = stack[#stack] or root
            end
        elseif root then
            local node = { name = name, attrs = parseAttrs(tag), children = {} }
            if node.attrs.id then doc.defs[node.attrs.id] = node end
            if cur then cur.children[#cur.children + 1] = node end
            if CONTAINER[name] and not selfClose then
                stack[#stack + 1] = node
                cur = node
            end
        end
    end

    if not doc.vbW or doc.vbW <= 0 or not doc.vbH or doc.vbH <= 0 then
        error("svgloader: could not determine a usable viewBox/size for the document")
    end
    if not doc.par then doc.par = "xMidYMid meet" end
    if not root then return doc end

    -- ---- phase 2: flatten body + compile shapes ------------------------
    local IDENTITY = { a = 1, b = 0, c = 0, d = 1, e = 0, f = 0 }

    local function symbolMap(sym, useAttrs, tf)
        local vb = numbers(sym.attrs.viewBox or "")
        if #vb < 4 then return tf end
        local sw = numAttr(useAttrs.width, doc.vbW) or numAttr(sym.attrs.width, doc.vbW) or doc.vbW
        local sh = numAttr(useAttrs.height, doc.vbH) or numAttr(sym.attrs.height, doc.vbH) or doc.vbH
        local sx, sy = sw / vb[3], sh / vb[4]
        return matMul(tf, { a = sx, b = 0, c = 0, d = sy, e = -vb[1] * sx, f = -vb[2] * sy })
    end

    local function flatten(node, style, tf, depth)
        if depth > 8 or DEFS_ONLY[node.name] then return end
        if WARN_UNSUPPORTED[node.name] then
            if not warned[node.name] then
                warned[node.name] = true
                print("svgloader: <" .. node.name .. "> is not supported (skipped)")
            end
            return
        end
        local a = node.attrs
        if node.name == "use" then
            local href = a["xlink:href"] or a.href or ""
            local id = href:match("#?([%w_%-]+)$")
            local ref = id and doc.defs[id]
            if ref and ref ~= node then
                -- use's own transform, then its x/y translate, then (symbol) its
                -- viewBox mapping; use presentation attrs inherit into the ref.
                local ux = numAttr(a.x, doc.vbW) or 0
                local uy = numAttr(a.y, doc.vbH) or 0
                local uTf = matMul(matMul(tf, parseTransform(a.transform)),
                    { a = 1, b = 0, c = 0, d = 1, e = ux, f = uy })
                local ustyle = {}
                for _, k in ipairs(INHERIT_ATTRS) do
                    ustyle[k] = (a[k] ~= nil) and a[k] or style[k]
                end
                ustyle.opacity = (tonumber(style.opacity) or 1) * (tonumber(a.opacity) or 1)
                if ref.name == "symbol" then
                    uTf = symbolMap(ref, a, uTf)
                    for _, ch in ipairs(ref.children) do flatten(ch, ustyle, uTf, depth + 1) end
                else
                    flatten(ref, ustyle, uTf, depth + 1)
                end
            elseif id and not warned["use:" .. id] then
                warned["use:" .. id] = true
                print("svgloader: <use> references unknown id '" .. id .. "' (skipped)")
            end
            return
        end
        local eff = {}
        for _, k in ipairs(INHERIT_ATTRS) do
            eff[k] = (a[k] ~= nil) and a[k] or style[k]
        end
        eff.opacity = (tonumber(style.opacity) or 1) * (tonumber(a.opacity) or 1)
        local nodeTf = matMul(tf, parseTransform(a.transform))
        if SHAPE_TAGS[node.name] then
            eff.tf = nodeTf
            addShape(doc, node.name, a, eff, warned)
        else
            for _, ch in ipairs(node.children) do flatten(ch, eff, nodeTf, depth + 1) end
        end
    end

    local rootStyle = {}
    for _, k in ipairs(INHERIT_ATTRS) do rootStyle[k] = root.attrs[k] end
    rootStyle.opacity = tonumber(root.attrs.opacity) or 1
    flatten(root, rootStyle, IDENTITY, 0)
    return doc
end

-- ---------------------------------------------------------------------------
-- SVG object (duck-typed like GifLoader's return; static, no Updater)
-- ---------------------------------------------------------------------------
local SVGmt = {}
SVGmt.__index = SVGmt

-- Build a triangulated "triangles" mesh from a closed contour's flat coords.
-- Falls back to a centroid fan if love.math.triangulate rejects the polygon.
local function triMeshFrom(cont)
    local pts = {}
    for i = 1, #cont do pts[i] = cont[i] end
    local tris = nil
    local ok, r = pcall(love.math.triangulate, unpack(pts))
    if ok and r and #r > 0 then tris = r end
    local verts = {}
    if tris then
        for _, t in ipairs(tris) do
            verts[#verts + 1] = { t[1], t[2] }
            verts[#verts + 1] = { t[3], t[4] }
            verts[#verts + 1] = { t[5], t[6] }
        end
    else
        -- centroid fan fallback
        local n = #pts / 2
        local cx, cy = 0, 0
        for i = 1, n do cx = cx + pts[2 * i - 1]; cy = cy + pts[2 * i] end
        cx, cy = cx / n, cy / n
        for i = 1, n do
            local j = i % n + 1
            verts[#verts + 1] = { cx, cy }
            verts[#verts + 1] = { pts[2 * i - 1], pts[2 * i] }
            verts[#verts + 1] = { pts[2 * j - 1], pts[2 * j] }
        end
    end
    return love.graphics.newMesh(verts, "triangles")
end

-- ---------------------------------------------------------------------------
-- Gradients (plan §H.6): stops -> 256x1 sampler texture (linear AND radial use
-- the same 1D ramp; radial samples by distance), then a UV-mapped mesh over the
-- shape bbox. This build has no canvas stencils, so no canvas needed here —
-- ImageData textures sample fine under the stencil TEST (read-only).
-- Documented limits: gradientTransform ignored; radial fx/fy focal point treated
-- as the center.
-- ---------------------------------------------------------------------------
local function parseStops(node)
    local stops = {}
    for _, ch in ipairs(node.children) do
        if ch.name == "stop" then
            local off = tonumber((tostring(ch.attrs.offset or "0")):match("^%s*([%d%.]+)")) or 0
            if tostring(ch.attrs.offset or ""):find("%%") then off = off / 100 end
            local col = parsePaint(ch.attrs["stop-color"] or "#000000") or { 0, 0, 0 }
            local a = tonumber(ch.attrs["stop-opacity"]) or 1
            stops[#stops + 1] = { off = max(0, min(1, off)), r = col[1], g = col[2], b = col[3], a = max(0, min(1, a)) }
        end
    end
    table.sort(stops, function(p, q) return p.off < q.off end)
    return stops
end

local function rampImage(stops)
    if #stops == 0 then return nil end
    if #stops == 1 then stops = { stops[1], stops[1] } end
    local W = 256
    local img = love.image.newImageData(W, 1)
    for x = 0, W - 1 do
        local t = x / (W - 1)
        local i = 1
        while i < #stops and stops[i + 1].off < t do i = i + 1 end
        local s0, s1 = stops[i], stops[min(i + 1, #stops)]
        local span = s1.off - s0.off
        local k = span > 0 and (t - s0.off) / span or 0
        k = max(0, min(1, k))
        img:setPixel(x, 0,
            s0.r + (s1.r - s0.r) * k,
            s0.g + (s1.g - s0.g) * k,
            s0.b + (s1.b - s0.b) * k,
            s0.a + (s1.a - s0.a) * k)
    end
    return img
end

-- Build the textured fill mesh for shape sh (returns mesh or nil).
local function buildGradientMesh(sh, node, vbW, vbH)
    local stops = parseStops(node)
    if #stops == 0 then return nil end
    local img = rampImage(stops)
    if not img then return nil end
    local spread = node.attrs.spreadMethod
    local texWrap = (spread == "repeat" and "repeat")
                 or (spread == "reflect" and "mirroredrepeat") or "clamp"

    -- shape bbox (geometry already in 0..vb space)
    local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
    for _, c in ipairs(sh.contours) do
        for i = 1, #c, 2 do
            bx0 = min(bx0, c[i]); bx1 = max(bx1, c[i])
            by0 = min(by0, c[i + 1]); by1 = max(by1, c[i + 1])
        end
    end
    if bx1 <= bx0 or by1 <= by0 then return nil end
    local bw, bh = bx1 - bx0, by1 - by0

    local objBB = (node.attrs.gradientUnits or "objectBoundingBox") ~= "userSpaceOnUse"
    -- Resolve a gradient coord to user space: % -> fraction of base; plain
    -- number -> fraction of base when objectBoundingBox, absolute units when
    -- userSpaceOnUse (SVG spec F.5). d = default fraction.
    local function gv(v, d, base)
        if v == nil then return d * base end
        local n = tonumber(tostring(v):match("^%s*([%-+%.%d]+)"))
        if n == nil then return d * base end
        if tostring(v):find("%%") then n = n / 100 end
        if objBB then return n * base end
        return n
    end
    local bx, by = objBB and bx0 or 0, objBB and by0 or 0

    local verts
    if node.name == "linearGradient" then
        local x1 = gv(node.attrs.x1, 0, bw) + bx
        local y1 = gv(node.attrs.y1, 0, bh) + by
        local x2 = gv(node.attrs.x2, 1, bw) + bx
        local y2 = gv(node.attrs.y2, 0, bh) + by
        local dx, dy = x2 - x1, y2 - y1
        local len2 = dx * dx + dy * dy
        if len2 <= 0 then len2 = 1 end
        local function uAt(x, y) return ((x - x1) * dx + (y - y1) * dy) / len2 end
        verts = {}
        local corners = { { bx0, by0 }, { bx1, by0 }, { bx1, by1 },
                          { bx0, by0 }, { bx1, by1 }, { bx0, by1 } }
        for _, p in ipairs(corners) do
            verts[#verts + 1] = { p[1], p[2], uAt(p[1], p[2]), 0.5 }
        end
    else
        -- radial: sample by normalized distance from center (focal point
        -- ignored, documented limit). Flat triangle list (duplicated verts) —
        -- this build has no Mesh:setTriangles.
        local cx = gv(node.attrs.cx, 0.5, bw) + bx
        local cy = gv(node.attrs.cy, 0.5, bh) + by
        local rbase = math.sqrt(bw * bw + bh * bh) / math.sqrt(2)
        local r = gv(node.attrs.r, 0.5, rbase)
        if r <= 0 then return nil end
        local N = 16
        local function uv(px, py)
            local dx, dy = px - cx, py - cy
            return math.sqrt(dx * dx + dy * dy) / r
        end
        local function grid(gx, gy)
            local px = bx0 + bw * gx / N
            local py = by0 + bh * gy / N
            return px, py, uv(px, py)
        end
        verts = {}
        for gy = 0, N - 1 do
            for gx = 0, N - 1 do
                local ax, ay, au = grid(gx, gy)
                local bx2, by2, bu = grid(gx + 1, gy)
                local cx2, cy2, cu = grid(gx + 1, gy + 1)
                local dx2, dy2, du = grid(gx, gy + 1)
                verts[#verts + 1] = { ax, ay, au, 0.5 }
                verts[#verts + 1] = { bx2, by2, bu, 0.5 }
                verts[#verts + 1] = { cx2, cy2, cu, 0.5 }
                verts[#verts + 1] = { ax, ay, au, 0.5 }
                verts[#verts + 1] = { cx2, cy2, cu, 0.5 }
                verts[#verts + 1] = { dx2, dy2, du, 0.5 }
            end
        end
    end

    local mesh = love.graphics.newMesh(verts, "triangles")
    -- rampImage returns ImageData (unit-testable); meshes need a texture
    local tex = love.graphics.newImage(img)
    tex:setWrap(texWrap, "clamp")
    tex:setFilter("linear", "linear")
    mesh:setTexture(tex)
    return mesh, img
end

-- Build a line-strip mesh (mode "strip") from an open or closed polyline.
local function lineMeshFrom(cont)
    local verts = {}
    local n = #cont / 2
    for i = 1, n do verts[#verts + 1] = { cont[2 * i - 1], cont[2 * i] } end
    if cont.closed and n > 1 then verts[#verts + 1] = verts[1] end
    return love.graphics.newMesh(verts, "strip")
end

-- Walk a polyline by arc length emitting alternating ON spans per dasharray
-- (SVG dash model: odd length doubled, non-negative, zero => solid). Returns a
-- list of flat abs-coord polylines, one per dash. Pure geometry -> unit-testable.
local function dashTessellate(points, dasharray, offset, closed)
    local d = {}
    for _, v in ipairs(dasharray or {}) do d[#d + 1] = max(0, tonumber(v) or 0) end
    if #d == 0 then return { points } end
    if #d % 2 == 1 then for i = 1, #d do d[#d + 1] = d[i] end end
    local period = 0
    for _, v in ipairs(d) do period = period + v end
    if period <= 0 then return { points } end

    local n = #points / 2
    if n < 2 then return {} end
    local segLen, pathLen = {}, 0
    for i = 1, n - 1 do
        local dx = points[2 * (i + 1) - 1] - points[2 * i - 1]
        local dy = points[2 * (i + 1)] - points[2 * i]
        segLen[i] = math.sqrt(dx * dx + dy * dy); pathLen = pathLen + segLen[i]
    end
    if closed then
        local dx = points[1] - points[2 * n - 1]
        local dy = points[2] - points[2 * n]
        segLen[n] = math.sqrt(dx * dx + dy * dy); pathLen = pathLen + segLen[n]
    end
    if pathLen <= 0 then return {} end

    local function pointAt(dist)
        local acc = 0
        for i = 1, #segLen do
            if acc + segLen[i] >= dist or i == #segLen then
                local t = segLen[i] > 0 and (dist - acc) / segLen[i] or 0
                local ax, ay, bx, by
                if i < n then ax, ay = points[2 * i - 1], points[2 * i]
                            bx, by = points[2 * (i + 1) - 1], points[2 * (i + 1)]
                else ax, ay = points[2 * n - 1], points[2 * n]
                            bx, by = points[1], points[2] end
                return ax + (bx - ax) * t, ay + (by - ay) * t
            end
            acc = acc + segLen[i]
        end
        return points[1], points[2]
    end

    offset = (offset or 0) % period
    local out, curSpan = {}, nil
    local di, dRemaining, on, dist = 1, d[1] + offset, true, 0
    -- consume the offset as a leading (possibly partial) run
    if offset > 0 then
        dRemaining = d[1] - offset
        if dRemaining <= 0 then
            local carry = -dRemaining
            di = 1
            while carry >= d[di % #d + 1] do carry = carry - d[di % #d + 1]; di = di % #d + 1 end
            di = di % #d + 1
            dRemaining = d[di] - carry
        end
        on = (di % 2 == 1)
    end
    while dist < pathLen do
        local runEnd = min(dist + max(dRemaining, 1e-9), pathLen)
        if on then
            local sx, sy = pointAt(dist)
            local ex, ey = pointAt(runEnd)
            if not curSpan then curSpan = { sx, sy } end
            curSpan[#curSpan + 1] = ex; curSpan[#curSpan + 1] = ey
        end
        dRemaining = dRemaining - (runEnd - dist)
        dist = runEnd
        if dRemaining <= 1e-9 then
            if curSpan and #curSpan >= 4 then out[#out + 1] = curSpan end
            curSpan = nil
            di = di % #d + 1
            on = (di % 2 == 1)
            dRemaining = d[di]
        end
    end
    if curSpan and #curSpan >= 4 then out[#out + 1] = curSpan end
    if #out == 0 then return {} end
    return out
end

-- butt/square caps on OPEN polylines (closed -> unchanged). square extends each
-- end by width/2; round is handled at draw via line style (no setLineCap here).
local function applyCaps(span, closed, width, cap)
    if closed or cap == "butt" or cap == nil or (width or 0) <= 0 then return span end
    local n = #span / 2
    if n < 2 then return span end
    local ext = (cap == "round") and width / 2 or width / 2
    local function unit(ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local l = math.sqrt(dx * dx + dy * dy)
        if l == 0 then return 0, 0 end
        return dx / l, dy / l
    end
    local ux0, uy0 = unit(span[3], span[4], span[1], span[2])         -- backwards at start
    local xe, ye = span[#span - 1], span[#span]
    local xpe, ype = span[#span - 3], span[#span - 2]
    local ux1, uy1 = unit(xpe, ype, xe, ye)                            -- forwards at end
    local out = { span[1] + ux0 * ext, span[2] + uy0 * ext }
    for i = 1, #span do out[#out + 1] = span[i] end
    out[#out + 1] = xe + ux1 * ext; out[#out + 1] = ye + uy1 * ext
    return out
end

function SVGmt:ensureBuilt()
    if self._built then return end
    for _, sh in ipairs(self.shapes) do
        if sh.fill then
            sh.fillMeshes = {}
            for _, c in ipairs(sh.contours) do
                if c.closed and #c >= 6 then sh.fillMeshes[#sh.fillMeshes + 1] = triMeshFrom(c) end
            end
            -- Choose the single stencil op for this shape (this build resets the
            -- stencil buffer at the start of EVERY stencil() call — accumulation
            -- across calls is impossible; see plan §H.1 probe).
            --   evenodd        -> "invert" (parity)
            --   nonzero uniform-> "increment" (union: winding != 0 exactly)
            --   nonzero mixed  -> "invert" approximation + warn once
            sh.fillOp = "invert"
            if sh.fillRule == "nonzero" then
                local pos, neg = 0, 0
                for _, c in ipairs(sh.contours) do
                    if c.closed and #c >= 6 then
                        local a = contourSignedArea(c)
                        if a > 1e-9 then pos = pos + 1 elseif a < -1e-9 then neg = neg + 1 end
                    end
                end
                if pos > 0 and neg > 0 then
                    if not self._mixedFillWarned then
                        self._mixedFillWarned = true
                        print("svgloader: fill-rule=nonzero with mixed contour orientations approximated as even-odd (see plan §H.4)")
                    end
                    sh.fillOp = "invert"
                else
                    sh.fillOp = "increment"
                end
            end
        end
        if sh.fill and sh.grad and self.defs and self.defs[sh.grad] then
            sh.gradMesh = buildGradientMesh(sh, self.defs[sh.grad], self.vbW, self.vbH)
        elseif sh.fill and sh.maskId and self.defs and self.defs[sh.maskId] then
            sh.maskMesh = buildMaskMesh(sh, self.defs[sh.maskId], self)
        end
        if sh.stroke then
            sh.strokeMeshes = {}
            local da = sh.dasharray and numbers(sh.dasharray) or nil
            local capped = (sh.linecap == "square" or sh.linecap == "round")
            for _, c in ipairs(sh.contours) do
                if #c >= 4 then
                    if da then
                        for _, span in ipairs(dashTessellate(c, da, sh.dashoffset, c.closed)) do
                            span = applyCaps(span, false, sh.strokeWidth, sh.linecap)
                            if #span >= 4 then sh.strokeMeshes[#sh.strokeMeshes + 1] = lineMeshFrom(span) end
                        end
                    else
                        local cc = capped and applyCaps(c, c.closed, sh.strokeWidth, sh.linecap) or c
                        sh.strokeMeshes[#sh.strokeMeshes + 1] = lineMeshFrom(cc)
                    end
                end
            end
        end
    end
    self._built = true
end

-- Draw at absolute window coords into box (x,y,w,h) honoring
-- preserveAspectRatio (default xMidYMid meet). opts = {rotation, scaleX,
-- scaleY, alpha}. Flip/rotation follow the image pipeline's sign conventions
-- (init.lua drawtypes[1] pattern).
function SVGmt:draw(x, y, w, h, opts)
    if not w or w <= 0 or not h or h <= 0 then return end
    opts = opts or {}
    self:ensureBuilt()

    local par = self.par or "xMidYMid meet"
    local align = par:match("^(%a+)") or "xMidYMid"
    local slice = par:match("slice") ~= nil
    local sX, sY
    if align == "none" then
        sX, sY = w / self.vbW, h / self.vbH
    else
        local s = slice and max(w / self.vbW, h / self.vbH)
                       or min(w / self.vbW, h / self.vbH)
        sX, sY = s, s
    end
    if sX <= 0 or sY <= 0 then return end
    local offX = align:find("^xMin") and 0
        or (align:find("^xMax") and (w - self.vbW * sX)
        or (w - self.vbW * sX) / 2)
    local offY = align:find("YMin$") and 0
        or (align:find("YMax$") and (h - self.vbH * sY)
        or (h - self.vbH * sY) / 2)
    local alpha = opts.alpha or 1
    if alpha <= 0 then return end
    local rot = rad(opts.rotation or 0)
    local sx, sy = opts.scaleX or 1, opts.scaleY or 1

    -- Draw-time recolor (opts.tint or the persistent self.tint from
    -- setSVGColor): replaces every fill AND stroke RGB with the tint while
    -- keeping per-shape fill/stroke alpha; the tint's own alpha [4]
    -- multiplies in. Strings are parsed as SVG paints, so gui library color
    -- tables, "#rrggbb", "rgb()" and named colors all work. Geometry and
    -- meshes are untouched — the change shows next frame with no rebuild.
    local tint = opts.tint or self.tint
    if type(tint) == "string" then tint = parsePaint(tint) end
    local tintA = tint and (tint[4] or 1) or 1

    -- mirror the image pipeline's flip adjust-offsets
    local X, Y = x + offX, y + offY
    if sx < 0 then X = X + self.vbW * sX end
    if sy < 0 then Y = Y + self.vbH * sY end

    love.graphics.push()
    love.graphics.translate(X, Y)
    love.graphics.rotate(rot)
    love.graphics.scale(sx * sX, sy * sY)

    local prevLW = love.graphics.getLineWidth()
    local prevStyle = love.graphics.getLineStyle and love.graphics.getLineStyle() or nil
    for _, sh in ipairs(self.shapes) do
        if sh.fill and sh.fillMeshes then
            -- Exactly ONE contour-writing stencil call per shape (the buffer is
            -- reset per call in this build; last call wins). The preceding
            -- replace-0 pass establishes a clean baseline under either stencil
            -- model. All writes precede the test: writes are suppressed while a
            -- stencil test is active.
            love.graphics.stencil(function()
                love.graphics.rectangle("fill", 0, 0, self.vbW, self.vbH)
            end, "replace", 0)
            love.graphics.stencil(function()
                for _, m in ipairs(sh.fillMeshes) do love.graphics.draw(m) end
            end, sh.fillOp or "invert", 1)
            love.graphics.setStencilTest("notequal", 0)
            if sh.gradMesh then
                -- the ramp texture holds the gradient; the vertex color is
                -- white unless a tint recolors the whole ramp
                if tint then
                    love.graphics.setColor(tint[1], tint[2], tint[3], sh.fillAlpha * alpha * tintA)
                else
                    love.graphics.setColor(1, 1, 1, sh.fillAlpha * alpha)
                end
                love.graphics.draw(sh.gradMesh)
            elseif sh.maskMesh then
                -- mask raster bakes white RGB + luminance-alpha (see
                -- buildMaskMesh); fill color (or tint) rides the vertex color
                local mc = tint or sh.fill
                love.graphics.setColor(mc[1], mc[2], mc[3], alpha * tintA)
                love.graphics.draw(sh.maskMesh)
            else
                local fc = tint or sh.fill
                love.graphics.setColor(fc[1], fc[2], fc[3], sh.fillAlpha * alpha * tintA)
                love.graphics.rectangle("fill", 0, 0, self.vbW, self.vbH)
            end
            love.graphics.setStencilTest()
        end
        if sh.stroke and sh.strokeMeshes then
            local sc = tint or sh.stroke
            love.graphics.setColor(sc[1], sc[2], sc[3], sh.strokeAlpha * alpha * tintA)
            love.graphics.setLineWidth(sh.strokeWidth) -- scales with the transform
            local join = sh.linejoin
            if join == "round" then
                love.graphics.setLineStyle("smooth")
            elseif join == "bevel" then
                pcall(love.graphics.setLineJoin, "bevel"); love.graphics.setLineStyle("rough")
            elseif join == "miter" then
                pcall(love.graphics.setLineJoin, "miter"); love.graphics.setLineStyle("rough")
            end
            if sh.linecap == "round" then love.graphics.setLineStyle("smooth") end
            for _, m in ipairs(sh.strokeMeshes) do love.graphics.draw(m) end
        end
    end
    love.graphics.setLineWidth(prevLW)
    if prevStyle then pcall(love.graphics.setLineStyle, prevStyle) end
    love.graphics.pop()
end

function SVGmt:getWidth() return self.width end
function SVGmt:getHeight() return self.height end

-- Persistent draw-time recolor: every fill AND stroke draws with c's RGB;
-- c[4] (gui library colors carry it) multiplies into fill/stroke alpha, so
-- fill-opacity / stroke-opacity / group opacity survive. Accepts a gui
-- library color table, an SVG paint string ("#rrggbb", "rgb()", named), or
-- r,g,b[,a] floats; nil restores the SVG's own parsed colors. Purely a draw
-- concern — no re-parse, no mesh rebuild, effective next frame.
-- NOTE: load() caches per filepath, so this recolors EVERY element sharing
-- the file. For per-instance color prefer the element-level setSVGColor in
-- init.lua, which passes opts.tint through the post hook instead.
function SVGmt:setSVGColor(c, g, b, a)
    if c == nil then
        self.tint = nil
    elseif type(c) == "string" then
        local t = parsePaint(c)
        self.tint = t and { t[1], t[2], t[3], a } or nil
    elseif type(c) == "table" then
        self.tint = { c[1], c[2], c[3], a or c[4] }
    else
        self.tint = { c, g or 0, b or 0, a }
    end
    return self
end

-- ---------------------------------------------------------------------------
-- Public API + filepath-keyed parse cache (geometry/meshes are size-independent)
-- ---------------------------------------------------------------------------
local cache = {}

function SVG.load(filepath)
    local cached = cache[filepath]
    if cached then return cached end

    -- love.filesystem first (mounted archives), then plain io as a fallback so
    -- the loader also works with bare OS filesystem paths.
    local text = love.filesystem.read(filepath)
    if not text then
        local fh = io.open(filepath, "rb")
        if fh then text = fh:read("*a"); fh:close() end
    end
    if not text then
        error("Could not read SVG file: " .. filepath)
    end
    local doc = SVG.parse(text)

    local obj = setmetatable({
        sourcePath = filepath,
        vbX = doc.vbX, vbY = doc.vbY,
        vbW = doc.vbW, vbH = doc.vbH,
        width = doc.width or doc.vbW,
        height = doc.height or doc.vbH,
        par = doc.par,
        shapes = doc.shapes,
        defs = doc.defs,
        _built = false,
    }, SVGmt)
    cache[filepath] = obj
    return obj
end

function SVG.getInfo(s)
    local strokes = false
    for _, sh in ipairs(s.shapes) do if sh.stroke then strokes = true break end end
    return {
        sourcePath = s.sourcePath,
        viewBox = { 0, 0, s.vbW, s.vbH },
        width = s.width, height = s.height,
        shapeCount = #s.shapes, hasStrokes = strokes,
    }
end

function SVG.clearCache()
    cache = {}
end

-- Exposed for the autotest (unit checks without file I/O).
SVG._scanTokens = scanTokens
SVG._scanPathTokens = scanPathTokens
SVG._execPathContours = execPathContours
SVG._arcToCubics = arcToCubics
SVG._parsePaint = parsePaint
SVG._contourSignedArea = contourSignedArea
SVG._numAttr = numAttr
SVG._parseTransform = parseTransform
SVG._roundRectContours = roundRectContours
SVG._dashTessellate = dashTessellate
SVG._applyCaps = applyCaps
SVG._parseStops = parseStops
SVG._rampImage = rampImage
SVG._isConvexPoly = isConvexPoly
SVG._clipToConvex = clipToConvex
SVG._pointInPoly = pointInPoly

return SVG
