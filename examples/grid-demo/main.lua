-- main.lua — standalone LÖVE demo + test harness for core/grid.lua
-- (plans/grid-integration-plan.md §6/§7 Phases P4-P5).
--
-- Run:  love examples/grid-demo                 (interactive window, labeled scenarios + console PASS/FAIL)
--       love examples/grid-demo --grid-autotest  (runs checks, prints summary, quits)
--       love examples/grid-demo --grid-headless  (no window; layout+checks only)
--
-- Checks (plan §6 scenario matrix 1-10, hand-computed expected rects):
--   1. columns="1fr 2fr 100px" + gap — fr distribution + gap arithmetic exact
--   2. areas + area placement + "span 2" + explicit "1 / 3"-style lines + negatives
--   3. auto-placement overflow -> implicit auto rows; autoFlow="column"
--   4. dense=true out-of-order span-2 -> hole filled (vs non-dense twin)
--   5. minmax(50px,1fr) + auto track with text (intrinsic contribution)
--   6. alignment: justifyContent space-between, alignItems center,
--      justifySelf="end" override, placeSelf="center end", stretch default
--   7. YAML equivalence: grid:/grid-placement: keys == imperative twin
--   8. cross-mode: grid-in-flex (fit intrinsic), flex-in-grid, grid-in-grid
--   9. escape hatch: setDualDim floats a grid item; setGridPlacement(false) rejoins
--  10. idle gate: quiet frames visit 0 elements; per-draw invariantFails == 0
--  + text wrap in an auto row + sizeManaged scroll-fit parity (flex-demo §7 pattern)

-- ---------------------------------------------------------------------------
-- Boot: locate the gui library root (parent of examples/grid-demo) and mount
-- both `gui` and `multi` into the love.filesystem + package.path so the real
-- library can be required unmodified (identical preamble to flex-demo).
-- ---------------------------------------------------------------------------
local gameDir = love.filesystem.getRealDirectory("main.lua") or "."
local guiRoot = (gameDir .. "/../../.."):gsub("\\", "/")
local multiRoot = (guiRoot .. "/../../multi"):gsub("\\", "/")

local AUTO_TEST, HEADLESS = false, false

love.filesystem.mount(guiRoot, "gui")
love.filesystem.mount(multiRoot, "multi")
package.path = table.concat({
    guiRoot .. "/?.lua",
    guiRoot .. "/?/init.lua",
    multiRoot .. "/?.lua",
    multiRoot .. "/?/init.lua",
    package.path,
}, ";")

local multi    = require("multi")
local gui      = require("gui")
local flexbox  = require("gui.core.flexbox")
local measure  = require("gui.core.measure")
local gui_yaml = require("gui.yaml.builder")
local tinyyaml = require("gui.yaml.tinyyaml")
-- gui.addons.system (newScrollFrame) is required lazily in scrollSetup: it
-- requires `socket` at load time, so stub it with love.timer (only the task
-- manager clock uses it — newScrollFrame never does).
local ADDONS_OK, ADDONS_ERR = nil, nil
local function ensureAddons()
    if ADDONS_OK ~= nil then return ADDONS_OK end
    package.loaded["socket"] = package.loaded["socket"]
        or { gettime = love.timer.getTime }
    ADDONS_OK, ADDONS_ERR = pcall(require, "gui.addons.system")
    return ADDONS_OK
end
local verify = require("verify")

-- ---------------------------------------------------------------------------
-- Test bookkeeping
-- ---------------------------------------------------------------------------
local checks = { passed = 0, failed = 0 }

local function expectRect(name, elem, ex, ey, ew, eh)
    local x, y, w, h = elem:getAbsolutes()
    local ok = verify.rect(name, x, y, w, h, ex, ey, ew, eh)
    if ok then
        checks.passed = checks.passed + 1
        print("PASS [" .. name .. "]")
    else
        checks.failed = checks.failed + 1
    end
    return ok
end

local function expect(cond, name)
    if cond then
        checks.passed = checks.passed + 1
        print("PASS [" .. name .. "]")
    else
        checks.failed = checks.failed + 1
        print("FAIL [" .. name .. "]")
    end
end

-- ---------------------------------------------------------------------------
-- Scenario elements
-- ---------------------------------------------------------------------------
local G1, X1, X2, X3                    -- case 1: 1fr 2fr 100px + gap
local G2, H, S, M, F                    -- case 2: areas / span / explicit / negative
local G3, C1, C2, C3, C4, C5            -- case 3: auto-flow row overflow
local G3b, C6, C7, C8, C9, C10          -- case 3: autoFlow column
local G4, Q1, Q2, Q3                    -- case 4: dense, hole filled
local G4b, Q1b, Q2b, Q3b                -- case 4: non-dense twin (hole NOT filled)
local G5, A5, B5                        -- case 5: minmax(50px,1fr) + auto text
local G5b, A5b, B5b                     -- case 5: overflow -> fr collapses to min
local G6, Y1, Y2, Y3                    -- case 6: alignment matrix
local GR, GC1, GC2, GC3, GC4            -- case 7: imperative twin
local YR, YC1, YC2, YC3, YC4            -- case 7: YAML-built twin
local FX, GCX, FX1, GI1, GI2, GI3, GI4  -- case 8a: grid container as flex child
local GX2, FCX, F1, F2                  -- case 8b: flex container as grid child
local GO, GIN, GNA, GNB, GNC, GND       -- case 8c: grid-in-grid nesting
local G9, E1, E2, E3                    -- case 9: escape hatch / rejoin
local G10, WT                           -- text wrap in a 150px column
local SF, SCS1, SCS2                    -- scroll frame with fit-content grid
local lastVisited = 0
local idleDelta = nil

local LONG_TEXT = "The quick brown fox jumps over the lazy dog, repeatedly and " ..
                  "with a few extra words to force wrapping at narrow widths."

-- build() is split into per-scenario builders: a single function closing over
-- every scenario element would exceed Lua's 60-upvalue limit.
local function buildFrAndAreas()
    -- G1 (20,20,570,100): columns "1fr 2fr 100px" gap 10 ----------------------
    -- free = 570 - 100 - 20 = 450 -> 1fr=150, 2fr=300; x: 20, 180, 490
    G1 = gui:newFrame(20, 20, 570, 100, 0, 0, 0, 0)
    G1.color = { .25, .25, .35 }
    G1:setGrid{ columns = "1fr 2fr 100px", gap = 10 }
    for i = 1, 3 do
        local ch = G1:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
        ch.color = { .3 + i * .25, .3, .3 }
        ch:setSizing{ width = "grow", height = { mode = "fixed", value = 40 } }
        if i == 1 then X1 = ch elseif i == 2 then X2 = ch else X3 = ch end
    end

    -- G2 (20,160,600,200): areas header/side/main, cols 200/400, rows 60/140,
    -- gap 10. F (negative -1/-2, row 3 fixed 30) creates implicit row 3. -----
    G2 = gui:newFrame(20, 160, 600, 200, 0, 0, 0, 0)
    G2.color = { .25, .3, .25 }
    G2:setGrid{
        areas   = { "header header", "side main" },
        columns = "200px 400px",
        rows    = "60px 140px",
        gap     = 10,
    }
    H = G2:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    H.color = { .9, .4, .4 }
    H:setGridPlacement{ column = "header / header" }        -- area lines, row auto
    S = G2:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    S.color = { .4, .9, .4 }
    S:setGridPlacement{ column = "side", row = "span 2" }   -- implicit row 3
    M = G2:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    M.color = { .4, .4, .9 }
    M:setGridPlacement{ column = "2", row = "2" }           -- explicit line pair
    F = G2:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    F.color = { .9, .9, .3 }
    F:setGridPlacement{ column = "-1 / -2", row = "3" }     -- negative lines
    F:setSizing{ width = { mode = "fixed", value = 400 },
                 height = { mode = "fixed", value = 30 } }

end

local function buildFlowAndDense()
    -- G3 (20,420,400,120): 2 explicit cols, 5 items -> implicit auto rows ----
    G3 = gui:newFrame(20, 420, 400, 120, 0, 0, 0, 0)
    G3.color = { .3, .25, .25 }
    G3:setGrid{ columns = "100px 100px" }
    for i = 1, 5 do
        local ch = G3:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
        ch.color = { .5 + i * .08, .5, .2 }
        ch:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }
        if i == 1 then C1 = ch elseif i == 2 then C2 = ch elseif i == 3 then C3 = ch
        elseif i == 4 then C4 = ch else C5 = ch end
    end

    -- G3b (460,420,400,120): autoFlow column, 2 explicit rows -> implicit cols
    G3b = gui:newFrame(460, 420, 400, 120, 0, 0, 0, 0)
    G3b.color = { .3, .25, .25 }
    G3b:setGrid{ rows = "30px 30px", autoFlow = "column" }
    for i = 1, 5 do
        local ch = G3b:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
        ch.color = { .2, .5 + i * .08, .5 }
        ch:setSizing{ width = { mode = "fixed", value = 80 },
                      height = { mode = "fixed", value = 30 } }
        if i == 1 then C6 = ch elseif i == 2 then C7 = ch elseif i == 3 then C8 = ch
        elseif i == 4 then C9 = ch else C10 = ch end
    end

    -- G4 (20,580,400,120): dense — Q2 (span 2) overflows row 1, drops to row 2;
    -- Q3 rewinds the cursor and FILLS the hole at (1,2). cols 100px gap 10.
    G4 = gui:newFrame(20, 580, 400, 120, 0, 0, 0, 0)
    G4.color = { .2, .3, .3 }
    G4:setGrid{ columns = "100px 100px", rows = "30px 30px", gap = 10, dense = true }
    Q1 = G4:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q1.color = { .9, .5, .1 }
    Q1:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }
    Q2 = G4:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q2.color = { .1, .9, .5 }
    Q2:setGridPlacement{ column = "span 2" }
    Q2:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }
    Q3 = G4:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q3.color = { .5, .1, .9 }
    Q3:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }

    -- G4b (460,580,400,120): identical but dense=false -> Q3 lands on a new
    -- implicit row 3 instead of filling the hole at (1,2).
    G4b = gui:newFrame(460, 580, 400, 120, 0, 0, 0, 0)
    G4b.color = { .2, .3, .3 }
    G4b:setGrid{ columns = "100px 100px", rows = "30px 30px", gap = 10 }
    Q1b = G4b:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q1b.color = { .9, .5, .1 }
    Q1b:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }
    Q2b = G4b:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q2b.color = { .1, .9, .5 }
    Q2b:setGridPlacement{ column = "span 2" }
    Q2b:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }
    Q3b = G4b:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Q3b.color = { .5, .1, .9 }
    Q3b:setSizing{ width = "grow", height = { mode = "fixed", value = 30 } }

end

local function buildSizingAndAlign()
    -- G5 (20,740,400,100): minmax(50px,1fr) + auto column fed by text --------
    G5 = gui:newFrame(20, 740, 400, 100, 0, 0, 0, 0)
    G5.color = { .3, .3, .25 }
    G5:setGrid{ columns = "minmax(50px, 1fr) auto" }
    A5 = G5:newTextLabel("Hello world", 0, 0, 0, 0, 0, 0, 0, 0)
    B5 = G5:newTextLabel("Wide content", 0, 0, 0, 0, 0, 0, 0, 0)

    -- G5b (460,740,120,100): overflow — free < 0 -> fr collapses to the 50px min
    G5b = gui:newFrame(460, 740, 120, 100, 0, 0, 0, 0)
    G5b.color = { .35, .25, .25 }
    G5b:setGrid{ columns = "minmax(50px, 1fr) auto" }
    A5b = G5b:newTextLabel("Hi", 0, 0, 0, 0, 0, 0, 0, 0)
    B5b = G5b:newTextLabel("Very long content text", 0, 0, 0, 0, 0, 0, 0, 0)

    -- G6 (20,880,400,120): justifyContent space-between, alignItems center ---
    G6 = gui:newFrame(20, 880, 400, 120, 0, 0, 0, 0)
    G6.color = { .2, .3, .3 }
    G6:setGrid{ columns = "100px 100px 100px", rows = "120px",
                justifyContent = "space-between", alignItems = "center" }
    Y1 = G6:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    Y1.color = { .9, .3, .3 }
    Y1:setSizing{ width = "grow", height = { mode = "fixed", value = 40 } } -- stretch X
    Y2 = G6:newTextLabel("Mid", 0, 0, 0, 0, 0, 0, 0, 0)
    Y2:setGridPlacement{ placeSelf = "center end" }
    Y2:setSizing{ width = "fit", height = "fit" }
    Y3 = G6:newTextLabel("End", 0, 0, 0, 0, 0, 0, 0, 0)
    Y3:setGridPlacement{ justifySelf = "end" }
    Y3:setSizing{ width = "fit", height = { mode = "fixed", value = 40 } }

end

local function buildTwinsAndCrossMode()
    -- Case 7: imperative twin GR (20,1040,300,100) + YAML twin at +320 x -----
    GR = gui:newFrame(20, 1040, 300, 100, 0, 0, 0, 0)
    GR.color = { .25, .35, .25 }
    GR:setGrid{ columns = "1fr 1fr", rows = "40px 40px", gap = 10 }
    GC1 = GR:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GC1.color = { .8, .4, .2 }
    GC2 = GR:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GC2.color = { .2, .8, .4 }
    GC3 = GR:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GC3.color = { .4, .2, .8 }
    GC3:setGridPlacement{ column = 2, row = 2 }
    GC4 = GR:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GC4.color = { .8, .8, .3 }

    -- Case 8a: FX flex row; GCX grid child fit->intrinsic; FX1 fixed sibling
    FX = gui:newFrame(20, 1180, 400, 120, 0, 0, 0, 0)
    FX.color = { .3, .3, .3 }
    FX:setFlex{ direction = "row" }
    GCX = FX:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GCX.color = { .5, .3, .5 }
    GCX:setGrid{ columns = "100px 50px", rows = "30px 40px" }
    GCX:setSizing{ width = "fit", height = "fit" }
    for i = 1, 4 do
        local ch = GCX:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
        ch.color = { .8, .5 + i * .1, .2 }
        if i == 1 then GI1 = ch elseif i == 2 then GI2 = ch
        elseif i == 3 then GI3 = ch else GI4 = ch end
    end
    FX1 = FX:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    FX1.color = { .2, .6, .6 }
    FX1:setSizing{ width = { mode = "fixed", value = 100 },
                   height = { mode = "fixed", value = 120 } }

    -- Case 8b: GX2 grid; FCX flex child (top-level root) laid out by flex pass
    GX2 = gui:newFrame(460, 1180, 300, 120, 0, 0, 0, 0)
    GX2.color = { .3, .25, .35 }
    GX2:setGrid{ columns = "200px 100px", rows = "120px" }
    FCX = GX2:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    FCX.color = { .45, .45, .3 }
    FCX:setFlex{ direction = "row" }
    F1 = FCX:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    F1.color = { .9, .3, .5 }
    F1:setSizing{ width = { mode = "fixed", value = 80 },
                  height = { mode = "fixed", value = 40 } }
    F2 = FCX:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    F2.color = { .5, .3, .9 }
    F2:setSizing{ width = { mode = "fixed", value = 60 },
                  height = { mode = "fixed", value = 40 } }

    -- Case 8c: grid-in-grid (P3 recursion): GIN stretched into col 1 of GO
    GO = gui:newFrame(760, 1180, 300, 120, 0, 0, 0, 0)
    GO.color = { .35, .3, .25 }
    GO:setGrid{ columns = "200px 100px", rows = "120px" }
    GIN = GO:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    GIN.color = { .3, .5, .4 }
    GIN:setGrid{ columns = "100px 100px", rows = "60px 60px" }
    for i = 1, 4 do
        local ch = GIN:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
        ch.color = { .6 + i * .08, .3, .5 }
        if i == 1 then GNA = ch elseif i == 2 then GNB = ch
        elseif i == 3 then GNC = ch else GND = ch end
    end

end

local function buildEscapeAndWrap()
    -- Case 9: escape hatch grid (460,1040,200,100): E2 floats via setDualDim,
    -- rejoins with setGridPlacement(false) (phase5Setup / phase5bSetup).
    G9 = gui:newFrame(460, 1040, 200, 100, 0, 0, 0, 0)
    G9.color = { .3, .2, .3 }
    G9:setGrid{ columns = "100px 100px", rows = "50px 50px" }
    E1 = G9:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    E1.color = { .9, .4, .4 }
    E2 = G9:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    E2.color = { .4, .9, .4 }
    E3 = G9:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    E3.color = { .4, .4, .9 }

    -- Text wrap: long text in a 150px column wraps, auto row grows
    G10 = gui:newFrame(900, 1040, 150, 200, 0, 0, 0, 0)
    G10.color = { .25, .3, .3 }
    G10:setGrid{ columns = "150px" }
    WT = G10:newTextLabel(LONG_TEXT, 0, 0, 0, 0, 0, 0, 0, 0)
end

local function build()
    buildFrAndAreas()
    buildFlowAndDense()
    buildSizingAndAlign()
    buildTwinsAndCrossMode()
    buildEscapeAndWrap()
end

-- ---------------------------------------------------------------------------
-- Frame-2 checks: static scenario matrix (cases 1-6, 8, text wrap)
-- ---------------------------------------------------------------------------
local function staticChecks()
    print("== Case 1: fr distribution + gap ==")
    expectRect("G1.X1 1fr", X1, 20, 20, 150, 40)
    expectRect("G1.X2 2fr", X2, 180, 20, 300, 40)
    expectRect("G1.X3 100px", X3, 490, 20, 100, 40)

    print("== Case 2: areas / span / explicit lines / negative lines ==")
    -- rows: 60px @160, 140px @230, implicit auto row3 (F's 30px) @380
    expectRect("G2.H area header/header row1", H, 20, 160, 610, 60)
    expectRect("G2.S side span2 rows2-3", S, 20, 230, 200, 180)
    expectRect("G2.M explicit 2/2", M, 230, 230, 400, 140)
    -- F's negative lines resolve against the 2-column extent: line -1 = 3,
    -- line -2 = 2, normalized start>end -> cells 2..2 (col 2), row 3 implicit.
    expectRect("G2.F negative -1/-2 row3", F, 230, 380, 400, 30)

    print("== Case 3: auto-flow row overflow + column flow ==")
    expectRect("G3.C1", C1, 20, 420, 100, 30)
    expectRect("G3.C2", C2, 120, 420, 100, 30)
    expectRect("G3.C3 implicit row2", C3, 20, 450, 100, 30)
    expectRect("G3.C4 implicit row2", C4, 120, 450, 100, 30)
    expectRect("G3.C5 implicit row3", C5, 20, 480, 100, 30)
    expectRect("G3b.C6", C6, 460, 420, 80, 30)
    expectRect("G3b.C7", C7, 460, 450, 80, 30)
    expectRect("G3b.C8 implicit col2", C8, 540, 420, 80, 30)
    expectRect("G3b.C9 implicit col2", C9, 540, 450, 80, 30)
    expectRect("G3b.C10 implicit col3", C10, 620, 420, 80, 30)

    print("== Case 4: dense fills the hole; non-dense twin does not ==")
    expectRect("G4.Q1", Q1, 20, 580, 100, 30)
    expectRect("G4.Q2 span2 dropped to row2", Q2, 20, 620, 210, 30)
    expectRect("G4.Q3 dense fills hole (1,2)", Q3, 130, 580, 100, 30)
    expectRect("G4b.Q1", Q1b, 460, 580, 100, 30)
    expectRect("G4b.Q2 span2 row2", Q2b, 460, 620, 210, 30)
    expectRect("G4b.Q3 non-dense implicit row3", Q3b, 460, 660, 100, 30)

    print("== Case 5: minmax(50px,1fr) + auto text track ==")
    local wB = B5.font:getWidth("Wide content")
    local lh = A5.font:getHeight()
    -- fr free = inner - Σnon-fr (the auto track's contribution) - gaps;
    -- the minmax's own 50px lower bound is NOT double-subtracted.
    local col1 = math.max(50, 400 - wB)
    expect(wB > 50 and col1 > 50, "G5 auto track intrinsic exceeds the minmax min")
    expectRect("G5.A5 minmax(50px,1fr) grows to free", A5, 20, 740, col1, lh)
    expectRect("G5.B5 auto track == text natural width", B5, 20 + col1, 740, wB, lh)
    local wBb = B5b.font:getWidth("Very long content text")
    expect(wBb > 70, "G5b auto contribution makes fr free negative")
    expectRect("G5b.A5b fr collapses to 50px min", A5b, 460, 740, 50, lh)
    expectRect("G5b.B5b auto keeps natural width (overflow)", B5b, 510, 740, wBb, lh)

    print("== Case 6: content distribution + item alignment ==")
    -- space-between: extra = 400-300 = 100, between = 50 -> x: 20, 170, 320
    expectRect("G6.Y1 stretch default + alignItems center", Y1, 20, 920, 100, 40)
    local wMid = Y2.font:getWidth("Mid")
    expectRect("G6.Y2 placeSelf center end", Y2, 170 + 100 - wMid, 880 + (120 - lh) / 2, wMid, lh)
    local wEnd = Y3.font:getWidth("End")
    expectRect("G6.Y3 justifySelf end override", Y3, 320 + 100 - wEnd, 920, wEnd, 40)

    print("== Case 8: cross-mode + grid-in-grid ==")
    -- 8a: GCX fit -> grid.intrinsic = template sums (100+50, 30+40)
    expectRect("FX.GCX grid child fit intrinsic", GCX, 20, 1180, 150, 70)
    expectRect("FX.FX1 fixed sibling after grid child", FX1, 170, 1180, 100, 120)
    expectRect("GCX.GI1", GI1, 20, 1180, 100, 30)
    expectRect("GCX.GI2", GI2, 120, 1180, 50, 30)
    expectRect("GCX.GI3", GI3, 20, 1210, 100, 40)
    expectRect("GCX.GI4", GI4, 120, 1210, 50, 40)
    -- 8b: FCX stretched into grid col 1/row 1, then flex pass lays out its kids
    expectRect("GX2.FCX flex-in-grid stretched area", FCX, 460, 1180, 200, 120)
    expectRect("GX2.FCX.F1 flex flow first", F1, 460, 1180, 80, 40)
    expectRect("GX2.FCX.F2 flex flow second", F2, 540, 1180, 60, 40)
    -- 8c: grid-in-grid: GIN stretched to 200x120, inner tracks 100/60
    expectRect("GO.GIN inner grid stretched", GIN, 760, 1180, 200, 120)
    expectRect("GIN.GNA", GNA, 760, 1180, 100, 60)
    expectRect("GIN.GNB", GNB, 860, 1180, 100, 60)
    expectRect("GIN.GNC", GNC, 760, 1240, 100, 60)
    expectRect("GIN.GND", GND, 860, 1240, 100, 60)
    expect(GIN.__flexManaged ~= nil and GNA.__flexManaged ~= nil,
           "grid-in-grid children managed through the recursion")

    print("== Text wrap: auto row grows to the wrapped height ==")
    local _, wrapped = WT.font:getWrap(LONG_TEXT, 150)
    local nLines = #wrapped
    expect(nLines >= 2, "WT wraps to multiple lines at width 150")
    expectRect("G10.WT wrapped height feeds auto row", WT, 900, 1040, 150, nLines * lh)
end

-- ---------------------------------------------------------------------------
-- Case 7 setup/checks + scroll parity (flex-demo phase-6 pattern)
-- ---------------------------------------------------------------------------
local function phase7Setup()
    print("== Case 7: YAML grid:/grid-placement: keys ==")
    local def = tinyyaml.parse([[
type: frame
x: 340
y: 1040
w: 300
h: 100
grid: { columns: "1fr 1fr", rows: "40px 40px", gap: 10 }
children:
  - type: frame
  - type: frame
  - type: frame
    grid-placement: { column: 2, row: 2 }
  - type: frame
]])
    YR = gui_yaml.build(gui, def)
    -- Scroll frame whose content is a size-managed grid root (plan §7 step 6
    -- scroll-fit parity, mirrors flex-demo phase6Setup).
    if not ensureAddons() then
        print("  gui.addons.system unavailable — scroll scenario skipped: "
            .. tostring(ADDONS_ERR))
        return
    end
    SF = gui:newScrollFrame(1080, 1180, 100, 80, 0, 0, 0, 0)
    SF:setGrid{ columns = "100px", rows = "50px 50px", gap = { row = 4, column = 0 } }
    flexbox.sizeManaged(SF, true)
    SCS1 = SF:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    SCS1.color = { .5, .5, .2 }
    SCS1:setSizing{ width = "grow", height = { mode = "fixed", value = 50 } }
    SCS2 = SF:newFrame(0, 0, 0, 0, 0, 0, 0, 0)
    SCS2.color = { .2, .5, .5 }
    SCS2:setSizing{ width = "grow", height = { mode = "fixed", value = 50 } }
end

local function phase7Checks()
    -- YAML equivalence: the yaml-built twin reflows identically to the
    -- imperative GR (offset +320 x).
    expect(YR ~= nil and YR.__grid ~= nil, "YAML grid: key created a grid container")
    if YR and YR.__grid then
        local yc = YR.children
        local ic = GR.children
        local ok = true
        for i = 1, 4 do
            local ix, iy, iw, ih = ic[i]:getAbsolutes()
            ok = expectRect("YAML child " .. i .. " == imperative", yc[i],
                            ix + 320, iy, iw, ih) and ok
        end
        expect(#yc == 4 and yc[1].__flexManaged and yc[4].__flexManaged,
               "YAML grid children all grid-managed")
        -- coerceNumericStrings: bare numeric line 2 -> number; grammar strings no-op
        local gp = yc[3].__gridPlacement
        expect(gp and gp.column.start == 2 and gp.row.start == 2,
               "YAML bare numeric line coerced to number 2")
        expect(YR.__grid.columns[1].kind == "fr" and YR.__grid.columns[1].v == 1,
               'YAML "1fr" survived coercion as fr track')
        expect(YR.__grid.rows[1].kind == "px" and YR.__grid.rows[1].v == 40,
               'YAML "40px 40px" survived coercion as px tracks')
        expect(YR.__grid.colGap == 10 and YR.__grid.rowGap == 10,
               "YAML gap: 10 coerced number -> colGap/rowGap")
    end
    -- Scroll fit-content parity: content height = 50 + 4 + 50 = 104
    if not SF then
        expect(false, "scroll scenario requires gui.addons.system")
        return
    end
    local _, _, sw, sh = SF:getAbsolutes()
    expect(sh == 104, "grid scroll content fit-content height 104 (got " .. sh .. ")")
    expect(sw == 100, "grid scroll content keeps authored width 100 (got " .. sw .. ")")
    local msx, msy = SF:getMaxScroll()
    expect(msy == 24, "maxScrollY derived from grid fit content (got " .. msy .. ")")
    expect(msx == 0, "no horizontal scroll (content width == viewport width)")
    expectRect("scroll child 1 flow", SCS1, 1080, 1180, 100, 50)
    expectRect("scroll child 2 flow row2", SCS2, 1080, 1234, 100, 50)
    expect(SF.__flexSizeManaged == true, "grid content root size-managed")
    -- Trigger the scroll: applyScroll setDualDim on the size-managed grid root
    -- must NOT escape it; children re-anchor on the next pass (assert frame 6).
    SF:scrollTo(20)
end

-- ---------------------------------------------------------------------------
-- Case 9: escape hatch / rejoin (frame 4 setup -> frame 5 checks + rejoin
-- setup -> frame 6 checks)
-- ---------------------------------------------------------------------------
local function escapeSetup()
    print("== Case 9: escape hatch floats a grid item ==")
    E2:setDualDim(5, 5, 50, 20, 0, 0, 0, 0) -- manual write -> __flexEscaped
end

local function escapeChecks()
    expect(E2.__flexEscaped == true, "E2 flagged floating after manual write")
    expect(E2.__flexManaged == nil, "E2 unmanaged after escape")
    expectRect("E2 keeps manual rect", E2, 465, 1045, 50, 20)
    expectRect("E3 reflows into (1,2) ignoring floated sibling", E3, 560, 1040, 100, 50)
    -- rejoin: setGridPlacement(false) clears the escape and re-joins placement
    E2:setGridPlacement(false)
end

local function rejoinChecks()
    expect(E2.__flexEscaped ~= true, "E2 escape cleared by setGridPlacement(false)")
    expectRect("E2 rejoined at (1,2)", E2, 560, 1040, 100, 50)
    expectRect("E3 back to implicit row2 (2,1)", E3, 460, 1090, 100, 50)
    expect(E2.__flexManaged ~= nil, "E2 grid-managed again after rejoin")
end

local function scrollReanchorChecks()
    print("== Scroll re-anchor / no-escape ==")
    if not SF then return end
    local _, cy1 = SCS1:getAbsolutes()
    expect(cy1 == 1160, "scrolled child follows content offset (got " .. cy1 .. ")")
    expect(SCS1.__flexEscaped ~= true, "scroll position write does not escape grid children")
    expect(SF.__flexEscaped ~= true, "scroll position write does not escape the content root")
    expect(SCS2.__flexManaged ~= nil, "scroll children stay grid-managed after scroll")
end

-- ---------------------------------------------------------------------------
-- LÖVE callbacks
-- ---------------------------------------------------------------------------
local frame = 0
local invariantFails = 0
local summaryShown = false

function love.errhand(msgh, traceback, _)
    -- autotest/headless: surface the error on stdout and exit nonzero instead
    -- of hanging on the LÖVE error screen (os.exit flushes redirected stdout)
    if AUTO_TEST or HEADLESS then
        print("ERROR: " .. tostring(msgh))
        print(traceback or "")
        io.stdout:flush()
        os.exit(2)
    end
end

function love.load(args)
    for _, a in ipairs(args or {}) do
        if a == "--grid-autotest" then AUTO_TEST = true end
        if a == "--grid-headless" then HEADLESS = true end
    end
    build()
    print("grid-demo boot: autotest=" .. tostring(AUTO_TEST) ..
          " headless=" .. tostring(HEADLESS))
end

function love.update(dt)
    gui.update(dt)
    multi:uManager(dt) -- drives multi threads (resize, OnUpdate pump, draw handler thread)

    frame = frame + 1

    -- Idle-frame gate: layout work since the last frame must be exactly zero
    -- when nothing changed (dirty-flag fast path, grid plan §5.9/§6 case 10).
    idleDelta = flexbox.stats.visited - lastVisited
    lastVisited = flexbox.stats.visited

    if frame == 2 then
        staticChecks()
    elseif frame == 3 then
        phase7Setup()
    elseif frame == 4 then
        phase7Checks()
        escapeSetup()
    elseif frame == 5 then
        escapeChecks()
    elseif frame == 6 then
        rejoinChecks()
        scrollReanchorChecks()
    end

    if frame % 30 == 0 then
        print(string.format("frame %d grid stats: passes=%d elementsVisited=%d " ..
            "measure hits=%d misses=%d invariantFails=%d",
            frame, flexbox.stats.passes, flexbox.stats.visited,
            measure.stats.hits, measure.stats.misses, invariantFails))
    end

    -- Idle gate: frames 7+ do nothing, so the frame-8 draw pass (delta recorded
    -- at frame 8 update) must have visited zero elements. Summary at frame 8.
    if AUTO_TEST and frame == 8 and not summaryShown then
        summaryShown = true
        expect(idleDelta == 0, "idle frame visits 0 elements (dirty gate)")
        print(string.format("idle-frame stats: rootsScanned=%d visited=%d (delta %d)",
            flexbox.stats.rootsScanned, flexbox.stats.visited, idleDelta))
        print(string.format("== SUMMARY: %d passed, %d failed, invariantFails=%d ==",
            checks.passed, checks.failed, invariantFails))
        print(checks.failed == 0 and invariantFails == 0
            and "ALL CHECKS PASS" or "CHECKS FAILED")
        love.event.quit(checks.failed == 0 and invariantFails == 0 and 0 or 1)
    end
end

local LABELS = {
    { 20, 8,  "1: fr tracks + gap" },
    { 20, 148, "2: areas / span / explicit / negative lines" },
    { 20, 408, "3: auto-flow row overflow" },
    { 460, 408, "3b: autoFlow column" },
    { 20, 568, "4: dense=true (hole filled)" },
    { 460, 568, "4b: dense=false twin" },
    { 20, 728, "5: minmax(50px,1fr) + auto text" },
    { 460, 728, "5b: overflow -> fr floors at min" },
    { 20, 868, "6: space-between / center / end / placeSelf" },
    { 20, 1028, "7: imperative twin" },
    { 340, 1028, "7: YAML twin" },
    { 460, 1028, "9: escape hatch" },
    { 900, 1028, "wrap: auto row" },
    { 20, 1168, "8a: grid-in-flex (fit intrinsic)" },
    { 460, 1168, "8b: flex-in-grid" },
    { 760, 1168, "8c: grid-in-grid" },
    { 1080, 1168, "scroll fit" },
}

function love.draw()
    gui.draw()

    -- write-back invariant: the pass ran at draw_loop top and draw_handler has
    -- just re-cached every live element's absolutes parent-first — exactly the
    -- observation point the invariant is defined at (grid plan §6).
    local fails = verify.invariant(flexbox, gui)
    if fails > 0 then
        invariantFails = invariantFails + fails
        print("INVARIANT FAILURES this draw frame: " .. fails)
    end

    if HEADLESS then return end

    -- overlay: __flexComputed debug rects + scenario labels + status line
    love.graphics.setLineWidth(1)
    -- literal table (not a file-scope one) so it reads the current locals each
    -- frame — a file-scope table would capture nils before build() assigns them
    for _, e in ipairs({ X1, X2, X3, H, S, M, F, C1, C2, C3, C4, C5, C6, C7, C8, C9, C10,
                         Q1, Q2, Q3, Q1b, Q2b, Q3b, A5, B5, A5b, B5b, Y1, Y2, Y3,
                         GC1, GC2, GC3, GC4, GCX, GI1, GI2, GI3, GI4, FCX, F1, F2,
                         GIN, GNA, GNB, GNC, GND, E1, E2, E3, WT }) do
        local c = e.__flexComputed
        if c then
            local floating = e.__flexEscaped
            love.graphics.setColor(floating and { 1, .8, 0, .9 } or { 0, 1, 1, .6 })
            love.graphics.rectangle("line", c.x + .5, c.y + .5, c.w, c.h)
        end
    end
    love.graphics.setColor(.9, .9, .9, 1)
    for _, l in ipairs(LABELS) do
        love.graphics.print(l[3], l[1], l[2])
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format(
        "grid-demo  checks: %d pass / %d fail | invariantFails: %d | " ..
        "passes: %d visited: %d | frame: %d  (R=restart, Esc=quit)",
        checks.passed, checks.failed, invariantFails,
        flexbox.stats.passes, flexbox.stats.visited, frame), 8, 1270)
end

function love.keypressed(key)
    if key == "escape" then love.event.quit() end
    if key == "r" then
        for _, tree in ipairs({ gui, gui.virtual }) do
            for i = #tree.children, 1, -1 do tree.children[i]:destroy() end
        end
        checks = { passed = 0, failed = 0 }
        frame = 0
        invariantFails = 0
        build()
    end
end
