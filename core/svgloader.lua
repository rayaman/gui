-- svgloader.lua — pure-Lua SVG *vector* renderer for the LÖVE GUI library.
--
-- Parses a supported SVG subset ONCE into vector geometry, then draws it LIVE
-- every frame at the element's current box size via love draw commands, so
-- quality is preserved at any scale (crisp under flex/dualDim resizes — no
-- rasterization, no size-keyed image cache).
--
-- Vector pipeline (validated against the reference PNG on LÖVE 11.5):
--   parse -> flatten curves (C/S/Q/T) to polylines -> love.math.triangulate
--   each closed contour -> combine into one love.graphics.stencil("invert")
--   parity pass (even-odd fill) -> setStencilTest + fill the bbox; strokes via
--   love.graphics.line. Everything is issued under a per-frame translate/scale
--   so it re-renders crisp at whatever size the box currently is.
--
-- NOTE: this build has NO love.math.newPath/Path/setFillMode (added in LÖVE
-- 11.4); the stencil-parity approach is used instead. Anti-aliasing comes from
-- window MSAA (t.window.msaa), not from this loader.
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
--   s.width, s.height                        -- intrinsic px
--   svg.getInfo(s)
--   svg.clearCache()
--
-- Supported subset: svg root (width/height px or unitless, viewBox); elements
-- path, rect, circle, ellipse, line, polyline, polygon, g (paint inheritance +
-- translate/scale transform); path commands M m L l H h V v Z z exact, C c S s
-- and Q q T t flattened to polylines; solid fills (#RGB, #RRGGBB, rgb(), named,
-- none), fill-opacity, fill-rule (evenodd parity; nonzero approximated as
-- even-odd), stroke + stroke-width + stroke-opacity; preserveAspectRatio
-- default xMidYMid meet-fit only.
--
-- NOT supported: gradients, patterns, masks, clip-paths (clip-rule read but
-- ignored), filters, group opacity, text/image/use/defs/symbol, SMIL, A/a arcs
-- (warned once), rx/ry, stroke-dasharray, line caps/joins, percent/em/pt units,
-- non-default preserveAspectRatio.
--
-- Requires love.math.triangulate (LÖVE 0.10+; present in the project's 11.x).

if not (love and love.math and love.math.triangulate) then
    error("svgloader requires love.math.triangulate (LÖVE 0.10+)")
end

local SVG = {}

local rad = math.rad
local min = math.min
local cos, sin = math.cos, math.sin

local SHAPE_TAGS = {
    path = true, rect = true, circle = true, ellipse = true,
    line = true, polyline = true, polygon = true,
}
local SKIP_TAGS = {
    defs = true, symbol = true, use = true, text = true, image = true,
    clipPath = true, mask = true, filter = true, pattern = true,
    linearGradient = true, radialGradient = true, stop = true, switch = true,
}
local INHERIT_ATTRS = { "fill", "stroke", "fill-rule", "fill-opacity",
                        "stroke-opacity", "stroke-width" }

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

local function numAttr(v)
    if v == nil then return nil end
    return tonumber(tostring(v):match("^%s*([%d%.]+)"))
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

local function parseTransform(s)
    local tx, ty, sx, sy = 0, 0, 1, 1
    if not s then return { tx = tx, ty = ty, sx = sx, sy = sy } end
    for fn, arg in tostring(s):gmatch("(%w+)%(([^)]*)%)") do
        local p = numbers(arg)
        if fn == "translate" then
            tx = tx + (p[1] or 0); ty = ty + (p[2] or 0)
        elseif fn == "scale" then
            sx = sx * (p[1] or 1); sy = sy * (p[2] or p[1] or 1)
        else
            print("svgloader: unsupported transform: " .. fn .. " (ignored)")
        end
    end
    return { tx = tx, ty = ty, sx = sx, sy = sy }
end

-- ---------------------------------------------------------------------------
-- Path data -> sequence of CONTOURS. Each contour is a flat list of absolute
-- user coords {x1,y1,x2,y2,...} plus a closed flag. Curves are flattened to
-- line segments (cubic/quadratic via adaptive subdivision). A/a unsupported.
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

local function execPathContours(d, warned)
    local toks = scanTokens(d or "")
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
            if not warned.arcs then
                warned.arcs = true
                print("svgloader: elliptical arcs (A/a) are not supported in v1 (skipped)")
            end
            ti = ti + 7
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
    local own = parseTransform(a.transform)
    local ptf = parent.tf
    eff.tf = {
        sx = own.sx * ptf.sx, sy = own.sy * ptf.sy,
        tx = own.tx * ptf.sx + ptf.tx, ty = own.ty * ptf.sy + ptf.ty,
    }
    return eff
end

-- transform + subtract viewBox origin so geometry lives in 0..vbW x 0..vbH
local function xformContour(cont, tf, vbX, vbY)
    local out = {}
    for k = 1, #cont do
        if k % 2 == 1 then out[k] = tf.tx + tf.sx * cont[k] - vbX
        else out[k] = tf.ty + tf.sy * cont[k] - vbY end
    end
    out.closed = cont.closed
    return out
end

local function addShape(doc, name, a, eff, warned)
    local contours
    if name == "path" then
        contours = execPathContours(a.d, warned)
    elseif name == "rect" then
        local x, y = numAttr(a.x) or 0, numAttr(a.y) or 0
        local w, h = numAttr(a.width) or 0, numAttr(a.height) or 0
        if a.rx and not warned.rx then
            warned.rx = true
            print("svgloader: rect rx/ry rounding is not supported in v1 (ignored)")
        end
        contours = { { x, y, x + w, y, x + w, y + h, x, y + h, closed = true } }
    elseif name == "circle" then
        contours = circleContours(numAttr(a.cx) or 0, numAttr(a.cy) or 0,
            numAttr(a.r) or 0, numAttr(a.r) or 0)
    elseif name == "ellipse" then
        contours = circleContours(numAttr(a.cx) or 0, numAttr(a.cy) or 0,
            numAttr(a.rx) or 0, numAttr(a.ry) or 0)
    elseif name == "line" then
        contours = { { numAttr(a.x1) or 0, numAttr(a.y1) or 0,
                       numAttr(a.x2) or 0, numAttr(a.y2) or 0, closed = false } }
    elseif name == "polyline" or name == "polygon" then
        contours = polyContour(numbers(a.points or ""), name == "polygon")
    else
        return
    end

    local hasFillable = false
    for _, c in ipairs(contours) do if c.closed and #c >= 6 then hasFillable = true end end
    local fill = parsePaint(eff.fill or "#000000")
    local stroke = parsePaint(eff.stroke or "none")
    if (not fill or not hasFillable) and not stroke then return end

    local xf = {}
    for _, c in ipairs(contours) do xf[#xf + 1] = xformContour(c, eff.tf, doc.vbX, doc.vbY) end

    doc.shapes[#doc.shapes + 1] = {
        kind = name, contours = xf,
        fill = (hasFillable and fill) or nil,
        fillAlpha = tonumber(eff["fill-opacity"]) or 1,
        fillRule = eff["fill-rule"] or "nonzero",
        stroke = stroke,
        strokeAlpha = tonumber(eff["stroke-opacity"]) or 1,
        strokeWidth = tonumber(eff["stroke-width"]) or 1,
        closed = (name ~= "line" and name ~= "polyline"),
    }
end

-- returns { vbX, vbY, vbW, vbH, width, height, shapes = { ... } }
function SVG.parse(text)
    text = text:gsub("<!%-%-.-%-%->", " ")
    text = text:gsub("<%?.-%?>", " ")
    text = text:gsub("<!DOCTYPE[^>]->", " ")

    local doc = { vbX = 0, vbY = 0, vbW = nil, vbH = nil, width = nil, height = nil, shapes = {} }
    local warned = {}
    local rootDone, skipDepth = false, 0
    local stack, inh = {}, nil

    for tag in text:gmatch("<[^>]->") do
        local closing = tag:sub(2, 2) == "/"
        local selfClose = tag:sub(-2, -1) == "/>"
        local name = tag:match("^</?([%w:_%-]+)")

        if skipDepth > 0 then
            if closing then skipDepth = skipDepth - 1
            elseif not selfClose then skipDepth = skipDepth + 1 end
        elseif not name then
            -- skip
        elseif closing then
            if name == "g" and #stack > 0 then inh = table.remove(stack) end
        elseif name == "svg" then
            if not rootDone then
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
                inh = {
                    fill = a.fill, stroke = a.stroke, ["fill-rule"] = a["fill-rule"],
                    ["fill-opacity"] = a["fill-opacity"], ["stroke-opacity"] = a["stroke-opacity"],
                    ["stroke-width"] = a["stroke-width"],
                    tf = { sx = 1, sy = 1, tx = 0, ty = 0 },
                }
            end
        elseif SKIP_TAGS[name] then
            if not warned[name] then
                warned[name] = true
                print("svgloader: <" .. name .. "> is not supported in v1 (skipped)")
            end
            if not selfClose then skipDepth = skipDepth + 1 end
        elseif name == "g" then
            local child = inheritFrom(inh or {}, parseAttrs(tag))
            if not selfClose then stack[#stack + 1] = inh; inh = child end
        elseif SHAPE_TAGS[name] then
            addShape(doc, name, parseAttrs(tag), inheritFrom(inh or {}, parseAttrs(tag)), warned)
        end
    end

    if not doc.vbW or doc.vbW <= 0 or not doc.vbH or doc.vbH <= 0 then
        error("svgloader: could not determine a usable viewBox/size for the document")
    end
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

-- Build a line-strip mesh (mode "strip") from an open or closed polyline.
local function lineMeshFrom(cont)
    local verts = {}
    local n = #cont / 2
    for i = 1, n do verts[#verts + 1] = { cont[2 * i - 1], cont[2 * i] } end
    if cont.closed and n > 1 then verts[#verts + 1] = verts[1] end
    return love.graphics.newMesh(verts, "strip")
end

function SVGmt:ensureBuilt()
    if self._built then return end
    for _, sh in ipairs(self.shapes) do
        if sh.fill then
            sh.fillMeshes = {}
            for _, c in ipairs(sh.contours) do
                if c.closed and #c >= 6 then sh.fillMeshes[#sh.fillMeshes + 1] = triMeshFrom(c) end
            end
        end
        if sh.stroke then
            sh.strokeMeshes = {}
            for _, c in ipairs(sh.contours) do
                if #c >= 4 then sh.strokeMeshes[#sh.strokeMeshes + 1] = lineMeshFrom(c) end
            end
        end
    end
    self._built = true
end

-- Draw at absolute window coords into box (x,y,w,h), meet-fit (preserveAspectRatio
-- default xMidYMid). opts = {rotation, scaleX, scaleY, alpha}. Flip/rotation
-- follow the image pipeline's sign conventions (init.lua drawtypes[1] pattern).
function SVGmt:draw(x, y, w, h, opts)
    if not w or w <= 0 or not h or h <= 0 then return end
    opts = opts or {}
    self:ensureBuilt()

    local s = min(w / self.vbW, h / self.vbH)
    if s <= 0 then return end
    local offX, offY = (w - self.vbW * s) / 2, (h - self.vbH * s) / 2
    local alpha = opts.alpha or 1
    if alpha <= 0 then return end
    local rot = rad(opts.rotation or 0)
    local sx, sy = opts.scaleX or 1, opts.scaleY or 1

    -- mirror the image pipeline's flip adjust-offsets
    local X, Y = x + offX, y + offY
    if sx < 0 then X = X + self.vbW * s end
    if sy < 0 then Y = Y + self.vbH * s end

    love.graphics.push()
    love.graphics.translate(X, Y)
    love.graphics.rotate(rot)
    love.graphics.scale(sx * s, sy * s)

    local prevLW = love.graphics.getLineWidth()
    for _, sh in ipairs(self.shapes) do
        if sh.fill and sh.fillMeshes then
            -- even-odd parity: one stencil pass over all contours with "invert"
            -- (each contour toggle flips covered pixels; nested hole -> parity 0).
            love.graphics.stencil(function()
                for _, m in ipairs(sh.fillMeshes) do love.graphics.draw(m) end
            end, "invert", 1)
            love.graphics.setStencilTest("notequal", 0)
            love.graphics.setColor(sh.fill[1], sh.fill[2], sh.fill[3], sh.fillAlpha * alpha)
            love.graphics.rectangle("fill", 0, 0, self.vbW, self.vbH)
            love.graphics.setStencilTest()
        end
        if sh.stroke and sh.strokeMeshes then
            love.graphics.setColor(sh.stroke[1], sh.stroke[2], sh.stroke[3], sh.strokeAlpha * alpha)
            love.graphics.setLineWidth(sh.strokeWidth) -- scales with the transform
            for _, m in ipairs(sh.strokeMeshes) do love.graphics.draw(m) end
        end
    end
    love.graphics.setLineWidth(prevLW)
    love.graphics.pop()
end

function SVGmt:getWidth() return self.width end
function SVGmt:getHeight() return self.height end

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
        vbW = doc.vbW, vbH = doc.vbH,
        width = doc.width or doc.vbW,
        height = doc.height or doc.vbH,
        shapes = doc.shapes,
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
SVG._execPathContours = execPathContours
SVG._parsePaint = parsePaint

return SVG
