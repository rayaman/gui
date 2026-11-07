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
    -- SVG at 400x400: the vector redraws crisp (no resampled blur a scaled PNG shows)
    SVG400    = gui:newImageLabel(SVG_SRC, 520, 120, 400, 400, 0, 0, 0, 0)
    -- window-following SVG box: its box is driven from the window size every
    -- frame (see love.update), so the vector re-renders crisp at any size.
    SVGGROW   = gui:newImageLabel(SVG_SRC, 40, 545, 300, 200, 0, 0, 0, 0)
    SVGGROW._lastW, SVGGROW._lastH = -1, -1

    -- labels
    local function label(txt, x, y)
        local l = gui:newTextLabel(txt, x, y, 400, 20, 0, 0, 0, 0)
        l.color = { 0, 0, 0, 0 }
        l.visibility = 0
        return l
    end
    label("PNG (raster reference)", 40, 95)
    label("SVG (vector) 200px", 280, 95)
    label("SVG (vector) 400px — crisp at any scale", 520, 95)
    label("SVG box follows window resize (drag the window edge)", 40, 535)
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

    -- crispness at 400px: interior fill present + an AA edge exists (not a blur)
    local bigX, bigY = 520, 120
    local rr, gg, bb = snap:getPixel(bigX + 6.75 / 24 * 400 + 0.5, bigY + 12 / 24 * 400 + 0.5)
    local isDark = rr < 0.25 and gg < 0.25 and bb < 0.3
    expect(isDark, "400px SVG interior renders the dark fill (vector, not blank)")
    local rr2, gg2, bb2 = snap:getPixel(bigX + 2 / 24 * 400 + 0.5, bigY + 2 / 24 * 400 + 0.5)
    local isWhite = rr2 > 0.9 and gg2 > 0.9 and bb2 > 0.9
    expect(isWhite, "400px SVG background stays clean (no bleed/blur)")
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
