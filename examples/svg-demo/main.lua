-- main.lua — standalone LÖVE demo + autotest for core/svgloader.lua.
--
-- Run:  love examples/svg-demo                (interactive window: PNG vs SVG,
--                                             200px + 400px + window-following boxes)
--       love examples/svg-demo --svg-autotest (parse/cache/geometry checks + a
--                                             window-capture pixel diff vs the
--                                             reference PNG, prints summary, quits)
--
-- The point of the vector loader: the SVG is drawn LIVE every frame at the
-- element's current box size, so it stays crisp at 200px, 400px, and while the
-- window resizes — the 400px render is shape-identical to the 200px render,
-- unlike a scaled-up raster.

-- ---------------------------------------------------------------------------
-- Boot: same shape as examples/flex-demo. guiRoot here = the PROJECT root
-- (three levels up: svg-demo -> examples -> gui -> project), so
-- require("gui") / require("gui.core.*") / require("multi") resolve through
-- guiRoot/?/init.lua. The `gui` mount points at the gui library dir so love
-- paths like gui/bookmark-svg.svg work when mounts succeed; if they don't,
-- fixtures fall back to absolute OS paths (the loader has an io fallback and
-- love.image accepts absolute paths natively).
-- ---------------------------------------------------------------------------
local gameDir = love.filesystem.getRealDirectory("main.lua") or "."
local guiRoot = (gameDir .. "/../../.."):gsub("\\", "/")     -- project root (flex-demo's pattern)
local guiDir  = (gameDir .. "/../.."):gsub("\\", "/")        -- the gui library root

local AUTO_TEST = false

love.filesystem.mount(guiDir, "gui")
love.filesystem.mount(guiRoot .. "/multi", "multi")
package.path = table.concat({
    guiRoot .. "/?.lua",
    guiRoot .. "/?/init.lua",
    package.path,
}, ";")

local multi = require("multi")
local gui   = require("gui")
local svg   = require("gui.core.svgloader")
local verify = require("verify")

-- Fixtures: love.image/love.filesystem only accept PhysFS love paths. Prefer
-- the mounted `gui/` paths (getInfo is the reliable check); if the mount
-- didn't take (Windows can refuse it while another love process holds the
-- dir), stage copies into the save directory via io + love.filesystem.write
-- and use those love-relative paths instead. Everything downstream then uses
-- plain love paths, which every loader accepts.
local function stageFixtures()
    if love.filesystem.getInfo("gui/bookmark-svg.png")
       and love.filesystem.getInfo("gui/bookmark-svg.svg") then
        return "gui/bookmark-svg.svg", "gui/bookmark-svg.png"
    end
    love.filesystem.createDirectory("fixtures")
    for _, name in ipairs({ "bookmark-svg.svg", "bookmark-svg.png" }) do
        local fh = assert(io.open(guiDir .. "/" .. name, "rb"), "cannot read " .. name)
        local bytes = fh:read("*a"); fh:close()
        assert(love.filesystem.write("fixtures/" .. name, bytes), "cannot stage " .. name)
    end
    return "fixtures/bookmark-svg.svg", "fixtures/bookmark-svg.png"
end

local SVG_SRC, PNG_SRC = stageFixtures()
print("fixture paths: svg=" .. SVG_SRC .. " png=" .. PNG_SRC)

-- fill-rule fixtures: two same-direction (clockwise) overlapping squares.
-- nonzero -> the overlap stays filled; evenodd -> the overlap is a hole.
-- This is the discriminating regression for the winding stencil passes.
local RULE_NZ_SVG, RULE_EVEN_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local d = "M0 0H10V10H0ZM4 4H14V14H4Z"
    local defs = {
        ["rule-nonzero.svg"] = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">' ..
            '<path fill-rule="nonzero" fill="#1F2328" d="' .. d .. '"/></svg>',
        ["rule-evenodd.svg"] = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">' ..
            '<path fill-rule="evenodd" fill="#1F2328" d="' .. d .. '"/></svg>',
    }
    for name, body in pairs(defs) do
        assert(love.filesystem.write("fixtures/" .. name, body), "cannot stage " .. name)
    end
    -- pin names explicitly: pairs() order is not deterministic
    return "fixtures/rule-nonzero.svg", "fixtures/rule-evenodd.svg"
end)()

-- Phase 2 geometry fixture: rounded rect (rx=10), rotate(45) rect, and a
-- sweep-1 semicircular arc closed into a half-disk. viewBox 0..100.
local GEO_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local body = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' ..
        '<rect x="10" y="10" width="40" height="40" rx="10" fill="#1F2328"/>' ..
        '<rect x="50" y="10" width="20" height="20" transform="rotate(45 60 20)" fill="#1F2328"/>' ..
        '<path d="M10 80 A40 40 0 0 1 90 80 Z" fill="#1F2328"/></svg>'
    assert(love.filesystem.write("fixtures/tier1-geo.svg", body), "cannot stage tier1-geo.svg")
    return "fixtures/tier1-geo.svg"
end)()

-- Phase 5 gradient fixture: left half linear black->white (objectBoundingBox),
-- right half radial black->white centered on its left edge. viewBox 0..100.
local GRAD_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local body = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' ..
        '<defs>' ..
        '<linearGradient id="lr" x1="0" y1="0" x2="1" y2="0">' ..
        '<stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>' ..
        '</linearGradient>' ..
        '<radialGradient id="rd" cx="0" cy="0.5" r="0.5">' ..
        '<stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>' ..
        '</radialGradient>' ..
        '</defs>' ..
        '<rect x="0" y="0" width="50" height="100" fill="url(#lr)"/>' ..
        '<rect x="50" y="0" width="50" height="100" fill="url(#rd)"/></svg>'
    assert(love.filesystem.write("fixtures/grad.svg", body), "cannot stage grad.svg")
    return "fixtures/grad.svg"
end)()

-- Phase 6 fixtures: a rect clipped by a circle clipPath; a rect masked by two
-- white stripes (luminance mask). viewBox 0..100.
local CLIP_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local body = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' ..
        '<defs><clipPath id="disc"><circle cx="50" cy="50" r="30"/></clipPath></defs>' ..
        '<rect x="10" y="10" width="80" height="80" fill="#1F2328" clip-path="url(#disc)"/></svg>'
    assert(love.filesystem.write("fixtures/clip.svg", body), "cannot stage clip.svg")
    return "fixtures/clip.svg"
end)()
local MASK_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local body = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' ..
        '<defs><mask id="stripes"><rect x="10" y="0" width="20" height="100" fill="#ffffff"/>' ..
        '<rect x="70" y="0" width="20" height="100" fill="#ffffff"/></mask></defs>' ..
        '<rect x="0" y="0" width="100" height="100" fill="#1F2328" mask="url(#stripes)"/></svg>'
    assert(love.filesystem.write("fixtures/mask.svg", body), "cannot stage mask.svg")
    return "fixtures/mask.svg"
end)()

-- Phase 3 tree fixture: defs/g + use (forward ref, xlate), symbol + use (scale),
-- and a group-opacity fold. viewBox 0..100.
local TREE_SVG = (function()
    love.filesystem.createDirectory("fixtures")
    local body = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">' ..
        '<defs>' ..
        '<g id="tile"><rect x="0" y="0" width="8" height="8" fill="#1F2328"/>' ..
        '<rect x="12" y="0" width="8" height="8" fill="#1F2328"/></g>' ..
        '<symbol id="sym" viewBox="0 0 10 10"><rect x="0" y="0" width="10" height="10" fill="#1F2328"/></symbol>' ..
        '</defs>' ..
        '<g opacity="0.5"><rect x="40" y="0" width="10" height="10" fill="#1F2328"/></g>' ..
        '<use href="#tile" x="0" y="20"/>' ..
        '<use href="#tile" x="30" y="20"/>' ..
        '<use href="#sym" x="0" y="40" width="40" height="40"/></svg>'
    assert(love.filesystem.write("fixtures/tier1-tree.svg", body), "cannot stage tier1-tree.svg")
    return "fixtures/tier1-tree.svg"
end)()
local _, _, winFlags = love.window.getMode()
print("window msaa=" .. tostring(winFlags.msaa) .. " (vector AA source)")

-- ---------------------------------------------------------------------------
-- Test bookkeeping
-- ---------------------------------------------------------------------------
local checks = { passed = 0, failed = 0 }
local function expect(cond, name)
    if cond then
        checks.passed = checks.passed + 1
        print("PASS [" .. name .. "]")
    else
        checks.failed = checks.failed + 1
        print("FAIL [" .. name .. "]")
    end
    return cond
end

-- ---------------------------------------------------------------------------
-- Layout elements
-- ---------------------------------------------------------------------------
local PNG_LABEL, SVG200, SVG400, SVGGROW
local frame = 0

local function build()
    -- reference PNG (raster) vs SVG (vector) at identical 200x200 boxes
    PNG_LABEL = gui:newImageLabel(PNG_SRC, 40, 120, 200, 200, 0, 0, 0, 0)
    SVG200    = gui:newImageLabel(SVG_SRC, 280, 120, 200, 200, 0, 0, 0, 0)
    -- SVG at 300x300: the vector redraws crisp (no resampled blur a scaled PNG shows)
    SVG400    = gui:newImageLabel(SVG_SRC, 520, 120, 300, 300, 0, 0, 0, 0)
    -- Phase 5 gradient fixture (linear | radial ramps)
    GRAD      = gui:newImageLabel(GRAD_SVG, 830, 120, 160, 160, 0, 0, 0, 0)
    -- window-following SVG box: its box is driven from the window size every
    -- frame (see love.update), so the vector re-renders crisp at any size.
    SVGGROW   = gui:newImageLabel(SVG_SRC, 40, 545, 300, 200, 0, 0, 0, 0)
    SVGGROW._lastW, SVGGROW._lastH = -1, -1

    -- fill-rule discrimination pair: identical geometry, different fill-rule.
    RULENONZ  = gui:newImageLabel(RULE_NZ_SVG,   490, 545, 110, 110, 0, 0, 0, 0)
    RULEEVEN  = gui:newImageLabel(RULE_EVEN_SVG, 610, 545, 110, 110, 0, 0, 0, 0)

    -- Phase 2 geometry fixture box (rounded rect + rotate + arc)
    GEO = gui:newImageLabel(GEO_SVG, 370, 545, 110, 110, 0, 0, 0, 0)

    -- Phase 3 tree fixture box (defs/use/symbol/group-opacity)
    TREE = gui:newImageLabel(TREE_SVG, 250, 545, 110, 110, 0, 0, 0, 0)

    -- Phase 6 boxes: clip-path disc + luminance mask stripes
    CLIP = gui:newImageLabel(CLIP_SVG, 730, 545, 110, 110, 0, 0, 0, 0)
    MASK = gui:newImageLabel(MASK_SVG, 850, 545, 110, 110, 0, 0, 0, 0)

    -- labels
    local function label(txt, x, y)
        local l = gui:newTextLabel(txt, x, y, 400, 20, 0, 0, 0, 0)
        l.color = { 0, 0, 0, 0 }
        l.visibility = 0
        return l
    end
    label("PNG (raster reference)", 40, 95)
    label("SVG (vector) 200px", 280, 95)
    label("SVG (vector) 300px — crisp at any scale", 520, 95)
    label("SVG box follows window resize (drag the window edge)", 40, 535)
    label("nonzero", 490, 528)
    label("evenodd", 610, 528)
    label("rx + rotate + arc", 370, 528)
    label("use + symbol", 250, 528)
    label("clip-path disc", 730, 528)
    label("luminance mask", 850, 528)
    label("linear | radial gradient", 830, 95)
end

-- ---------------------------------------------------------------------------
-- Static (non-rendering) checks: parse structure, cache, geometry, colors.
-- ---------------------------------------------------------------------------
local function staticChecks()
    local s = svg.load(SVG_SRC)

    -- cache identity
    expect(s == svg.load(SVG_SRC), "svg.load returns cached table (identity)")

    -- root/viewBox
    local info = svg.getInfo(s)
    expect(s.vbW == 24 and s.vbH == 24, "viewBox parsed to 24x24")
    expect(info.width == 800 and info.height == 800, "root width/height px parsed")
    expect(info.shapeCount == 1, "exactly one shape element")
    expect(info.hasStrokes == false, "fixture has no strokes")

    -- fill parsed to #1F2328
    local sh = s.shapes[1]
    local f = sh.fill
    local okFill = f and math.abs(f[1] - 31/255) < 1e-3
        and math.abs(f[2] - 35/255) < 1e-3 and math.abs(f[3] - 40/255) < 1e-3
    expect(okFill, "fill color parsed to #1F2328")
    expect(sh.fillRule == "evenodd", "fill-rule evenodd captured")

    -- path data -> two closed contours (outer + punched hole)
    local contours = svg._execPathContours(
        "M18 4H6V20H8.06066L12 16.0607L15.9393 20H18V4Z" ..
        "M7.5 18.4393V5.5H16.5V18.4393L12 13.9393L7.5 18.4393Z", {})
    expect(#contours == 2, "path d yields 2 contours (outer + hole)")
    expect(contours[1].closed and contours[2].closed, "both contours closed")
    expect(contours[1][1] == 18 and contours[1][2] == 4, "outer contour starts at (18,4)")

    -- curve flattening sanity: a C command yields a closed contour with >4 pts
    local c2 = svg._execPathContours("M0 0 C 10 0 10 10 0 10 Z", {})
    expect(#c2 == 1 and #c2[1] > 4, "C command flattened to a polyline contour")

    -- paint parser unit checks
    local p = svg._parsePaint("#0f0")
    expect(p and p[1] == 0 and p[2] == 1 and p[3] == 0, "parsePaint #0f0 -> green")
    local p2 = svg._parsePaint("rgb(255,0,0)")
    expect(p2 and p2[1] == 1 and p2[2] == 0, "parsePaint rgb(255,0,0) -> red")
    expect(svg._parsePaint("none") == nil, "parsePaint none -> nil")

    -- signed area (winding orientation) unit checks
    local cw = svg._contourSignedArea({ 0, 0, 10, 0, 10, 10, 0, 10 })
    local ccw = svg._contourSignedArea({ 0, 0, 0, 10, 10, 10, 10, 0 })
    expect(cw > 0 and math.abs(cw - 100) < 1e-9, "signedArea CW square -> +100")
    expect(math.abs(ccw + 100) < 1e-9, "signedArea CCW square -> -100")

    -- fill-rule fixtures parse with their rules recorded
    local snz = svg.load(RULE_NZ_SVG)
    local sev = svg.load(RULE_EVEN_SVG)
    expect(snz.shapes[1].fillRule == "nonzero", "rule fixture: fill-rule nonzero captured")
    expect(sev.shapes[1].fillRule == "evenodd", "rule fixture: fill-rule evenodd captured")
    expect(#snz.shapes[1].contours == 2, "rule fixture: two contours")

    -- Phase 2 units: flag-aware path scanner ("01" splits into 0,1 inside A)
    local ft = svg._scanPathTokens("A4 4 0 01 8 8")
    expect(ft[1] == "A" and ft[2] == 4 and ft[3] == 4 and ft[4] == 0
        and ft[5] == 0 and ft[6] == 1 and ft[7] == 8 and ft[8] == 8,
        "scanPathTokens splits A flags '01' into 0,1")

    -- arcs: semicircle bulges ~r from the chord, endpoints exact
    local arc = svg._execPathContours("M10 80 A40 40 0 0 1 90 80 Z", {})
    local okArc = #arc == 1 and arc[1].closed and arc[1][1] == 10 and arc[1][2] == 80
    local minY, topX = 80, nil
    for i = 1, #arc[1], 2 do
        if arc[1][i + 1] < minY then minY = arc[1][i + 1]; topX = arc[1][i] end
    end
    expect(okArc, "arc contour closed, starts at (10,80)")
    expect(math.abs(minY - 40) < 1 and math.abs((topX or 0) - 50) < 1,
        "sweep-1 semicircle bulges to y=40 at x=50")
    -- endpoint equality: A with equal start/end is a no-op (no NaN points)
    local arc0 = svg._execPathContours("M5 5 A10 10 0 0 1 5 5 L9 9", {})
    local okNaN = true
    for _, v in ipairs(arc0[1]) do if v ~= v then okNaN = false end end
    expect(okNaN, "zero-length arc adds no NaNs")

    -- rounded rect: starts at (x+rx, y), many points, stays in bounds
    local rr = svg._roundRectContours(0, 0, 10, 10, 2, 2)[1]
    local okRR = rr.closed and rr[1] == 2 and rr[2] == 0 and #rr > 40
    for i = 1, #rr, 2 do
        if rr[i] < -1e-9 or rr[i] > 10 + 1e-9 or rr[i + 1] < -1e-9 or rr[i + 1] > 10 + 1e-9 then
            okRR = false
        end
    end
    expect(okRR, "roundRect: starts (2,0), >20 pts, within 0..10")

    -- transforms: rotate(90) matrix, matrix(...) with translate, composition order
    local rotm = svg._parseTransform("rotate(90)")
    expect(math.abs(rotm.a) < 1e-9 and math.abs(rotm.b - 1) < 1e-9
        and math.abs(rotm.c + 1) < 1e-9 and math.abs(rotm.d) < 1e-9,
        "parseTransform rotate(90) -> [0 1 -1 0]")
    local comp = svg._parseTransform("translate(10,0) scale(2)")
    local px2 = comp.a * 1 + comp.c * 1 + comp.e   -- point (1,1)
    local py2 = comp.b * 1 + comp.d * 1 + comp.f
    expect(math.abs(px2 - 12) < 1e-9 and math.abs(py2 - 2) < 1e-9,
        "transform list: scale applies before translate (SVG order)")

    -- units
    expect(math.abs(svg._numAttr("10pt") - 40 / 3) < 1e-9, "numAttr 10pt -> 13.33px")
    expect(math.abs(svg._numAttr("1in") - 96) < 1e-9, "numAttr 1in -> 96px")
    expect(math.abs(svg._numAttr("2em") - 32) < 1e-9, "numAttr 2em -> 32px")
    expect(math.abs(svg._numAttr("50%", 200) - 100) < 1e-9, "numAttr 50% of 200 -> 100")
    expect(svg._numAttr("12") == 12 and svg._numAttr("12px") == 12, "numAttr px/unitless")

    -- Phase 3: two-phase tree parse — defs registry, use/symbol expansion,
    -- group-opacity fold. Uses SVG.parse directly (defs not on the cached obj).
    local tree = svg.load(TREE_SVG)
    expect(#tree.shapes == 6, "tree fixture: 6 shapes (1 g + 2 use-tile + 2 use-tile + 1 use-sym)")
    expect(tree.shapes[1].fillAlpha == 0.5, "tree fixture: group opacity folded into fillAlpha")
    -- the symbol use (shape 6) is scaled 40/10 = 4x: its contour spans ~40 wide
    local sym = tree.shapes[6]
    local minX, maxX = math.huge, -math.huge
    for _, c in ipairs(sym.contours) do
        for i = 1, #c, 2 do if c[i] < minX then minX = c[i] end; if c[i] > maxX then maxX = c[i] end end
    end
    expect(math.abs((maxX - minX) - 40) < 1e-6, "tree fixture: symbol use scaled to 40 wide")
    -- the second use of #tile (shapes 4-5) is translated x+30
    local t2 = tree.shapes[4]
    local t2min = math.huge
    for i = 1, #t2.contours[1], 2 do if t2.contours[1][i] < t2min then t2min = t2.contours[1][i] end end
    expect(math.abs(t2min - 30) < 1e-6, "tree fixture: use x-translation applied")
    -- defs registry populated (parse-level)
    local d = svg.parse('<svg viewBox="0 0 10 10"><defs><g id="q"><rect x="0" y="0" width="1" height="1"/></g></defs><use href="#q"/></svg>')
    expect(d.defs and d.defs.q and d.defs.q.name == "g", "parse: defs registry holds forward-referenced id")
    expect(#d.shapes == 1, "parse: forward use expands to the def's shape")
    -- unknown use id -> no shape (warned once)
    local d2 = svg.parse('<svg viewBox="0 0 10 10"><use href="#nope"/></svg>')
    expect(#d2.shapes == 0, "parse: unknown use id yields no shape")

    -- Phase 4: dash tessellation on a length-10 straight polyline
    local line = { 0, 0, 10, 0 }
    local spans = svg._dashTessellate(line, { 2, 2 }, 0, false)
    expect(#spans == 3 and math.abs(spans[1][3] - 2) < 1e-6
        and math.abs(spans[2][1] - 4) < 1e-6 and math.abs(spans[3][1] - 8) < 1e-6,
        "dash {2,2} over len10 -> 3 spans starting x=0,4,8")
    local off = svg._dashTessellate(line, { 2, 2 }, 1, false)
    expect(#off >= 3 and math.abs(off[1][1]) < 1e-6 and math.abs(off[1][3] - 1) < 1e-6,
        "dash {2,2} offset1 -> first span trimmed to len1")
    local odd = svg._dashTessellate(line, { 3 }, 0, false)  -- odd -> doubled {3,3}
    local oddOn = 0
    for _, s in ipairs(odd) do oddOn = oddOn + (s[3] - s[1]) end
    expect(math.abs(oddOn - 6) < 1e-6, "dash {3} doubles to {3,3}: 6 on of 10")
    expect(#svg._dashTessellate(line, { 0, 0 }, 0, false) == 1, "dash {0,0} -> solid passthrough")
    local cap = svg._applyCaps({ 0, 0, 4, 0 }, false, 2, "square")
    expect(math.abs(cap[1] + 1) < 1e-6 and math.abs(cap[#cap - 1] - 5) < 1e-6,
        "square cap extends open span by w/2 at both ends")
    expect(#svg._applyCaps({ 0, 0, 4, 0 }, true, 2, "square") == 4,
        "square cap is a no-op on a closed span")
    -- dashed fixture compiles to multiple stroke meshes
    local dashDoc = svg.parse('<svg viewBox="0 0 100 20"><line x1="0" y1="10" x2="100" y2="10" ' ..
        'stroke="#1F2328" stroke-width="2" stroke-dasharray="5 5"/></svg>')
    expect(#dashDoc.shapes == 1 and dashDoc.shapes[1].dasharray == "5 5",
        "dashed fixture: dasharray captured on the shape")

    -- Phase 5: gradient parse-level checks
    local grad = svg.load(GRAD_SVG)
    expect(grad.shapes[1].grad == "lr" and grad.shapes[2].grad == "rd",
        "gradient fixture: url(#id) refs captured")
    expect(grad.defs.lr.name == "linearGradient" and grad.defs.rd.name == "radialGradient",
        "gradient fixture: gradient defs registered")
    local stops = svg._parseStops(grad.defs.lr)
    expect(#stops == 2 and stops[1].off == 0 and stops[2].off == 1
        and stops[1].r == 0 and stops[2].r == 1,
        "parseStops: two stops, offsets 0/1, black->white")
    local ramp = svg._rampImage(stops)
    expect(ramp and ramp:getWidth() == 256
        and math.abs(ramp:getPixel(0, 0)) < 1e-6
        and math.abs(ramp:getPixel(255, 0) - 1) < 1e-6,
        "rampImage: 256px ramp, endpoints exact")
    local badDoc = svg.parse('<svg viewBox="0 0 10 10"><rect x="0" y="0" width="5" height="5" fill="url(#ghost)"/></svg>')
    expect(#badDoc.shapes == 0, "gradient: unknown url(#id) -> no shape (fill none)")

    -- Phase 6: clip-path unit tests (Sutherland-Hodgman)
    expect(svg._isConvexPoly({ 0, 0, 10, 0, 10, 10, 0, 10 }) == true, "isConvexPoly: square")
    expect(svg._isConvexPoly({ 0, 0, 10, 0, 10, 5, 5, 5, 5, 10, 0, 10 }) == false,
        "isConvexPoly: L-shape concave")
    local clipped = svg._clipToConvex({ 0, 0, 10, 0, 10, 10, 0, 10 }, { 5, 5, 15, 5, 15, 15, 5, 15 })
    local areaOK = math.abs(math.abs(svg._contourSignedArea(clipped)) - 25) < 1e-6
    expect(#clipped == 8 and areaOK, "clipToConvex: square∩offset-square -> area 25")
    local gone = svg._clipToConvex({ 0, 0, 4, 0, 4, 4, 0, 4 }, { 10, 10, 20, 10, 20, 20, 10, 20 })
    expect(#gone < 6, "clipToConvex: disjoint -> empty")
    expect(svg._pointInPoly(1, 1, { 0, 0, 10, 0, 10, 10, 0, 10 }) == true
        and svg._pointInPoly(11, 5, { 0, 0, 10, 0, 10, 10, 0, 10 }) == false,
        "pointInPoly: inside/outside")

    -- clip fixture: circle clip (convex 64-gon) over rect
    local clipDoc = svg.load(CLIP_SVG)
    expect(#clipDoc.shapes == 1 and clipDoc.shapes[1].clipPath == "url(#disc)",
        "clip fixture: clip-path captured")
    local cc = clipDoc.shapes[1].contours[1]
    expect(math.abs(math.abs(svg._contourSignedArea(cc)) - math.pi * 30 * 30) < 60,
        "clip fixture: clipped contour is ~disc area (pi*30^2, tol 60)")

    -- mask fixture: stripes rasterize; masked shape gets maskId
    local maskDoc = svg.load(MASK_SVG)
    expect(#maskDoc.shapes == 1 and maskDoc.shapes[1].maskId == "stripes",
        "mask fixture: maskId captured on shape")
    expect(maskDoc.defs.stripes.name == "mask", "mask fixture: mask registered in defs")
end

-- ---------------------------------------------------------------------------
-- Window-capture pixel diff: SVG(200) box vs PNG(200) box. Both are square
-- boxes with the same square artwork meet-fit identically, so pixels at the
-- same box-relative offsets must match within anti-alias tolerance (the vector
-- edges are MSAA'd; the PNG edges are browser-AA'd — same shape, slightly
-- different AA character).
-- ---------------------------------------------------------------------------
local snap, snapRequested, snapProcessed = nil, false, false

-- Classify a pixel against the known scene colors: white-ish page, dark fill,
-- or AA-blend. (The window clear color is 0.92 gray; the bookmark fill and
-- transparent-PNG-over-gray composite are near #1F2328.)
local function classify(r, g, b)
    local function near(v, t) return math.abs(v - t) < 0.09 end
    if near(r, 1) and near(g, 1) and near(b, 1) then return "white" end
    if near(r, 31/255) and near(g, 35/255) and near(b, 40/255) then return "fill" end
    return "aa"
end

local function pixelDiff()
    local SW, SH = 200, 200
    local svgX, svgY = 280, 120   -- SVG200 box origin
    local pngX, pngY = 40, 120    -- PNG_LABEL box origin
    local sum, maxd, edges, edgeSum, disagree = 0, 0, 0, 0, 0
    for yy = 0, SW - 1 do
        for xx = 0, SW - 1 do
            local r1, g1, b1 = snap:getPixel(svgX + xx + 0.5, svgY + yy + 0.5)
            local r2, g2, b2 = snap:getPixel(pngX + xx + 0.5, pngY + yy + 0.5)
            local d = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
            sum = sum + d
            if d > maxd then maxd = d end
            local c1, c2 = classify(r1, g1, b1), classify(r2, g2, b2)
            if c1 == "aa" or c2 == "aa" then
                edges = edges + 1
                edgeSum = edgeSum + d
            end
            -- shape disagreement: one side solid white, the other solid fill
            if (c1 == "white" and c2 == "fill") or (c1 == "fill" and c2 == "white") then
                disagree = disagree + 1
            end
        end
    end
    local mean = sum / (SW * SW)
    print(string.format(
        "pixel-diff SVG-vs-PNG: mean=%.4f (%.2f/255/ch) max=%.3f edgePixels=%d edgeMean=%.4f disagreements=%d",
        mean, mean / 3 * 255, maxd, edges, edgeSum / math.max(1, edges), disagree))
    -- the two renders must look alike: interiors/backgrounds agree, only the
    -- AA band may differ (vector MSAA vs the PNG's own anti-aliasing)
    -- The AA band mean is tolerant by design: the vector edges are MSAA'd at
    -- native resolution while the reference PNG (256px) is linear-downsampled
    -- to 200px, so the soft-edge bands differ in character even though the
    -- SHAPE agrees everywhere (see disagreements==0 + shape probes).
    expect(mean <= 0.05, "pixel-diff mean within AA tolerance (<=0.05 summed)")
    expect(edges > 100, "AA edge band present on both renders")
    expect(edgeSum / math.max(1, edges) <= 0.7, "AA edge band mean diff within tolerance (<=0.7 summed)")
    expect(disagree == 0, "zero shape disagreements (white-vs-fill mismatches)")

    -- shape identity via a few probe points (viewBox 0..24 -> box px)
    local function probe(name, vx, vy)
        local px, py = svgX + vx / 24 * SW + 0.5, svgY + vy / 24 * SW + 0.5
        local r1, g1, b1 = snap:getPixel(px, py)
        local r2, g2, b2 = snap:getPixel(pngX + vx / 24 * SW + 0.5, pngY + vy / 24 * SW + 0.5)
        local d = math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2)
        expect(d <= 0.15, "shape probe " .. name .. " matches (d=" .. string.format("%.3f", d) .. ")")
    end
    probe("frame-band", 6.75, 12)   -- frame material (dark)
    probe("hole", 12, 8)            -- punched hole (white bg)
    probe("outside", 2, 2)          -- outside shape (white bg)
    probe("notch", 12, 18.5)        -- bottom V notch (white bg)

    -- crispness at 300px: interior fill present + an AA edge exists (not a blur)
    local bigX, bigY = 520, 120
    local rr, gg, bb = snap:getPixel(bigX + 6.75 / 24 * 300 + 0.5, bigY + 12 / 24 * 300 + 0.5)
    local isDark = rr < 0.25 and gg < 0.25 and bb < 0.3
    expect(isDark, "300px SVG interior renders the dark fill (vector, not blank)")
    local rr2, gg2, bb2 = snap:getPixel(bigX + 2 / 24 * 300 + 0.5, bigY + 2 / 24 * 300 + 0.5)
    local isWhite = rr2 > 0.9 and gg2 > 0.9 and bb2 > 0.9
    expect(isWhite, "300px SVG background stays clean (no bleed/blur)")

    -- Phase 5 gradient render probes (box 830,120,160x160; viewBox 0..100 -> 1.6x)
    local function gradProbe(tag, vx, vy, test)
        local px, py = 830 + vx / 100 * 160 + 0.5, 120 + vy / 100 * 160 + 0.5
        local r = snap:getPixel(px, py)
        expect(test(r), string.format("grad %s (%g,%g) r=%.2f", tag, vx, vy, r))
    end
    gradProbe("linear-left",   1, 50, function(r) return r < 0.15 end)
    gradProbe("linear-right", 49, 50, function(r) return r > 0.85 end)
    gradProbe("linear-mid",   25, 50, function(r) return r > 0.35 and r < 0.65 end)
    gradProbe("radial-center", 50, 50, function(r) return r < 0.15 end)
    gradProbe("radial-edge",  88, 50, function(r) return r > 0.8 end)
    gradProbe("radial-clamp", 99, 99, function(r) return r > 0.8 end)

    -- fill-rule discrimination: same geometry, opposite overlap treatment.
    -- viewBox 0..20 -> 160px box. (7,7) is inside BOTH squares; (2,2) and
    -- (12,12) are inside exactly one.
    local function ruleProbe(tag, boxX, boxY, vx, vy, wantFill)
        local px, py = boxX + vx / 20 * 110 + 0.5, boxY + vy / 20 * 110 + 0.5
        local r, g, b = snap:getPixel(px, py)
        local filled = r < 0.5 and g < 0.5 and b < 0.5
        expect(filled == wantFill, string.format(
            "fill-rule %s probe (%g,%g) -> %s", tag, vx, vy, wantFill and "fill" or "bg"))
    end
    ruleProbe("nonzero", 490, 545, 7, 7, true)    -- overlap: filled
    ruleProbe("nonzero", 490, 545, 2, 2, true)    -- single square
    ruleProbe("nonzero", 490, 545, 12, 12, true)  -- single square
    ruleProbe("evenodd", 610, 545, 7, 7, false)   -- overlap: punched
    ruleProbe("evenodd", 610, 545, 2, 2, true)    -- single square
    ruleProbe("evenodd", 610, 545, 12, 12, true)  -- single square

    -- Phase 2 geometry fixture probes (viewBox 0..100 -> 110px box at 370,545)
    local function geoProbe(tag, vx, vy, wantFill)
        local px, py = 370 + vx / 100 * 110 + 0.5, 545 + vy / 100 * 110 + 0.5
        local r, g, b = snap:getPixel(px, py)
        local filled = r < 0.5 and g < 0.5 and b < 0.5
        expect(filled == wantFill, string.format(
            "geo %s probe (%g,%g) -> %s", tag, vx, vy, wantFill and "fill" or "bg"))
    end
    geoProbe("rx-corner", 10.5, 10.5, false)  -- outside the r=10 corner arc
    geoProbe("rx-inside", 20, 20, true)
    geoProbe("rot-center", 60, 20, true)      -- rotated square center
    geoProbe("rot-corner", 50, 10, false)     -- pre-rotation corner now empty
    geoProbe("rot-diamond", 60, 32, true)     -- diamond reaches y=34.1
    geoProbe("arc-disk", 50, 42, true)        -- inside semicircle disk
    geoProbe("arc-below", 50, 95, false)      -- below the flat edge

    -- Phase 6 render probes (110px boxes at 730/850,545; viewBox 0..100)
    local function cmProbe(tag, boxX, vx, vy, wantFill)
        local px, py = boxX + vx / 100 * 110 + 0.5, 545 + vy / 100 * 110 + 0.5
        local r, g, b = snap:getPixel(px, py)
        local filled = r < 0.5 and g < 0.5 and b < 0.5
        expect(filled == wantFill, string.format(
            "%s probe (%g,%g) -> %s", tag, vx, vy, wantFill and "fill" or "bg"))
    end
    cmProbe("clip", 730, 50, 50, true)     -- disc center
    cmProbe("clip", 730, 50, 30, true)     -- inside disc (r=20)
    cmProbe("clip", 730, 15, 15, false)    -- rect corner outside disc
    cmProbe("clip", 730, 50, 90, false)    -- below disc
    cmProbe("mask", 850, 20, 50, true)     -- white stripe 1
    cmProbe("mask", 850, 50, 50, false)    -- black gap between stripes
    cmProbe("mask", 850, 80, 50, true)     -- white stripe 2
    cmProbe("mask", 850, 5, 50, false)     -- black before stripe 1
end

local function showSummary()
    print(string.format("== SUMMARY: %d passed, %d failed ==", checks.passed, checks.failed))
    print(checks.failed == 0 and "ALL CHECKS PASS" or "CHECKS FAILED")
    love.event.quit(checks.failed == 0 and 0 or 1)
end

-- ---------------------------------------------------------------------------
-- LÖVE callbacks
-- ---------------------------------------------------------------------------
function love.load(args)
    for _, a in ipairs(args or {}) do
        if a == "--svg-autotest" then AUTO_TEST = true end
    end
    build()
    print("svg-demo boot: autotest=" .. tostring(AUTO_TEST))
    if not AUTO_TEST then staticChecks() end
end

function love.update(dt)
    -- Drive the window-following box from the live window size. Because the
    -- svgloader `post` re-reads getAbsolutes() every frame, the SVG redraws
    -- crisp at whatever size the box currently is (the whole point).
    -- Scripted resize ping-pong: every ~2s the follow box flips between 160px
    -- and 420px. The svgloader post re-reads getAbsolutes() each frame, so the
    -- vector re-renders crisp at each size (the core scale-tracking proof).
    if not AUTO_TEST and SVGGROW then
        local sz = (math.floor(frame / 120) % 2 == 0) and 130 or 215
        if sz ~= SVGGROW._lastW then
            SVGGROW:setDualDim(nil, nil, sz, sz)
            SVGGROW._lastW = sz
        end
    end
    gui.update(dt)
    multi:uManager(dt)
    frame = frame + 1

    if AUTO_TEST then
        if frame == 2 then staticChecks() end
        -- request the capture after a draw frame has presented the scene
        if frame >= 3 and not snapRequested then
            love.graphics.captureScreenshot(function(img) snap = img end)
            snapRequested = true
        end
        if snap and not snapProcessed then
            snapProcessed = true
            pixelDiff()
            showSummary()
        end
    end
end

function love.draw()
    love.graphics.clear(0.92, 0.92, 0.92, 1)
    gui.draw()

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print(string.format(
        "svg-demo  checks: %d pass / %d fail | frame: %d  (R=restart, Esc=quit)",
        checks.passed, checks.failed, frame), 8, 770)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "r" then
        for _, tree in ipairs({ gui, gui.virtual }) do
            for i = #tree.children, 1, -1 do tree.children[i]:destroy() end
        end
        checks = { passed = 0, failed = 0 }
        frame = 0
        build()
    end
end
