-- grid.lua
-- CSS Grid container/item support for the retained LÖVE GUI tree.
-- Source of truth: plans/grid-integration-plan.md (approved scope: the
-- CSS-Tricks complete-guide subset; non-goals: subgrid, standalone named
-- grid lines, masonry). Phase P1 = plan §7 steps 1-2: the property surface,
-- the string / Lua-array parsers (parsed ONCE at setGrid time, cached on
-- __grid / __gridPlacement per plan §2) and the scheduler seam stub.
-- Phase P2 = plan §7 steps 3-5: the real layoutGridRoot pipeline below —
-- seed -> placement -> track sizing (+fr) -> content distribution -> item
-- boxes (+alignment) -> shared flexbox write-back.
-- Phase P3 = plan §7 step 6: the cross-mode + text seam — Pass-B text-wrap
-- + auto-row re-solve, real grid.intrinsic (consumed by flexbox seedAxis /
-- propagateUp through the seed), sizeManaged grid roots (scroll parity), and
-- the nested-container descent (grid-in-grid recursive-in-pass; flex-in-grid
-- rides the shared depth-ordered root seam).
--
-- Dependency direction (plan §1): this module requires gui.core.measure at
-- load and gui.core.flexbox LAZILY inside function bodies (pcall +
-- nil-guard, cached) for the shared scheduler helpers (register / markDirty /
-- seedAxis / writeBack / fireGeometryEvents / inPass). flexbox in turn
-- lazy-requires this module inside runPass/init, so there is no require
-- cycle and deleting core/grid.lua disables grid while flex keeps working
-- (mirrors docs/flexbox.md's "removing flexbox.lua disables the feature").

local measure = require("gui.core.measure") -- used by min-content contributions

local max, min = math.max, math.min

local grid = {}

--------------------------------------------------------------------------------
-- Lazy flexbox handle (shared scheduler helpers, grid plan §1)
--------------------------------------------------------------------------------

local flexboxMod = false -- false = not attempted, nil = absent, table = loaded
local function FB()
    if flexboxMod == false then
        local ok, m = pcall(require, "gui.core.flexbox")
        flexboxMod = (ok and m) or nil
    end
    return flexboxMod
end

--------------------------------------------------------------------------------
-- Validation value sets (plan §2/§3) + helpers
--------------------------------------------------------------------------------

local ITEM_ALIGN = { ["start"] = true, ["end"] = true, ["center"] = true, ["stretch"] = true }
local CONTENT_ALIGN = {
    ["start"] = true, ["end"] = true, ["center"] = true,
    ["space-between"] = true, ["space-around"] = true, ["space-evenly"] = true,
}

local function typeName(e)
    return tostring(e.type)
end

local function trim(s)
    return s:match("^%s*(.-)%s*$")
end

-- Split a track-list string on whitespace that sits OUTSIDE parentheses, so
-- "repeat(2, minmax(100px, 1fr))" survives as one token (plan §3 grammar).
local function splitTopLevel(s, self, ctx)
    local out, depth, buf = {}, 0, {}
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "(" then
            depth = depth + 1
            buf[#buf + 1] = c
        elseif c == ")" then
            depth = depth - 1
            if depth < 0 then
                error("setGrid: unbalanced parentheses in " .. ctx ..
                      " on element type " .. typeName(self))
            end
            buf[#buf + 1] = c
        elseif (c == " " or c == "\t" or c == "\n") and depth == 0 then
            if #buf > 0 then
                out[#out + 1] = table.concat(buf)
                buf = {}
            end
        else
            buf[#buf + 1] = c
        end
    end
    if depth ~= 0 then
        error("setGrid: unbalanced parentheses in " .. ctx ..
              " on element type " .. typeName(self))
    end
    if #buf > 0 then out[#out + 1] = table.concat(buf) end
    return out
end

-- Split a function-argument string (inside repeat()/minmax()) on the
-- top-level comma only: "2, minmax(100px, 1fr)" -> {"2", "minmax(100px, 1fr)"}.
local function splitArgs(inner, self, ctx)
    local out, depth, buf = {}, 0, {}
    for i = 1, #inner do
        local c = inner:sub(i, i)
        if c == "(" then
            depth = depth + 1
            buf[#buf + 1] = c
        elseif c == ")" then
            depth = depth - 1
            buf[#buf + 1] = c
        elseif c == "," and depth == 0 then
            out[#out + 1] = trim(table.concat(buf))
            buf = {}
        else
            buf[#buf + 1] = c
        end
    end
    out[#out + 1] = trim(table.concat(buf))
    return out
end

--------------------------------------------------------------------------------
-- Track-list parser (plan §2 track spec + §3 grammar)
--   token: <n>fr | <n>px | bare <n> (= px) | auto | minmax(A, B)
--   repeat(<int>, <tokens>) expands at parse; nested repeat is rejected.
--   Parsed spec: {kind="px",v} | {kind="fr",v} | {kind="auto"}
--              | {kind="min-content"} | {kind="minmax",min=,max=}
--------------------------------------------------------------------------------

local FR_PAT = "^([%+%-%d%.]+)fr$"
local PX_PAT = "^([%+%-%d%.]+)px$"
local NUM_PAT = "^([%+%-%d%.]+)$"
local AREA_NAME_PAT = "^[%a_][%a%d_%-]*$"

local function parseTrackToken(tok, self, ctx)
    if tok == "auto" then return { kind = "auto" } end
    if tok == "min-content" then return { kind = "min-content" } end
    local v = tok:match(FR_PAT)
    if v then
        local n = tonumber(v)
        if n then return { kind = "fr", v = n } end
    end
    v = tok:match(PX_PAT)
    if v then
        local n = tonumber(v)
        if n then return { kind = "px", v = n } end
    end
    v = tok:match(NUM_PAT)
    if v then
        local n = tonumber(v)
        if n then return { kind = "px", v = n } end -- bare <n> = px (plan §3)
    end
    error("setGrid: invalid track token '" .. tok .. "' in " .. ctx ..
          " on element type " .. typeName(self))
end

local parseTrackEntry -- forward declaration: parseMinmax recurses through it

local function parseMinmax(tok, self, ctx)
    local inner = tok:match("^minmax%((.*)%)$")
    if not inner then
        error("setGrid: malformed minmax() in " .. ctx ..
              " on element type " .. typeName(self))
    end
    local args = splitArgs(inner, self, ctx)
    if #args ~= 2 or args[1] == "" or args[2] == "" then
        error("setGrid: minmax expects exactly 2 comma-separated arguments in " .. ctx ..
              " on element type " .. typeName(self))
    end
    local mn = parseTrackEntry(args[1], self, ctx)
    local mx = parseTrackEntry(args[2], self, ctx)
    -- min ∈ px|auto|min-content; max ∈ px|fr|auto|min-content (plan §2)
    if mn.kind == "fr" then
        error("setGrid: minmax min cannot be fr in " .. ctx ..
              " on element type " .. typeName(self))
    end
    return { kind = "minmax", min = mn, max = mx }
end

parseTrackEntry = function(tok, self, ctx)
    if tok:find("^minmax%(") then return parseMinmax(tok, self, ctx) end
    return parseTrackToken(tok, self, ctx)
end

local function parseTrackList(spec, self, ctx)
    local toks = {}
    if type(spec) == "string" then
        toks = splitTopLevel(spec, self, ctx)
    elseif type(spec) == "table" then
        -- Lua array form: { "1fr", "200px", "repeat(2, minmax(auto, 1fr))", "auto" }
        for i = 1, #spec do
            if type(spec[i]) ~= "string" then
                error("setGrid: " .. ctx .. " array entries must be strings on element type " ..
                      typeName(self))
            end
            for _, t in ipairs(splitTopLevel(spec[i], self, ctx)) do
                toks[#toks + 1] = t
            end
        end
    else
        error("setGrid: " .. ctx .. " must be a string or array on element type " ..
              typeName(self))
    end
    local out = {}
    for ti = 1, #toks do
        local tok = toks[ti]
        if tok:find("^repeat%(") then
            local inner = tok:match("^repeat%((.*)%)$")
            if not inner then
                error("setGrid: malformed repeat() in " .. ctx ..
                      " on element type " .. typeName(self))
            end
            local args = splitArgs(inner, self, ctx)
            if #args ~= 2 or args[1] == "" or args[2] == "" then
                error("setGrid: repeat expects exactly 2 comma-separated arguments in " .. ctx ..
                      " on element type " .. typeName(self))
            end
            local count = tonumber(args[1])
            if count == nil or count ~= math.floor(count) or count < 1 then
                error("setGrid: repeat count must be a positive integer in " .. ctx ..
                      " on element type " .. typeName(self))
            end
            local innerToks = splitTopLevel(args[2], self, ctx)
            if #innerToks == 0 then
                error("setGrid: repeat track list is empty in " .. ctx ..
                      " on element type " .. typeName(self))
            end
            for _, t in ipairs(innerToks) do
                if t:find("^repeat%(") then
                    error("setGrid: nested repeat() is not supported in " .. ctx ..
                          " on element type " .. typeName(self))
                end
            end
            for _ = 1, count do
                for _, t in ipairs(innerToks) do
                    out[#out + 1] = parseTrackEntry(t, self, ctx)
                end
            end
        else
            out[#out + 1] = parseTrackEntry(tok, self, ctx)
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- areas parser (plan §2: { [name] = {c1,r1,c2,r2} }, 1-based inclusive rects;
-- "." = empty cell; rows must have equal cell counts)
--------------------------------------------------------------------------------

local function parseAreas(rows, self)
    if type(rows) ~= "table" then
        error("setGrid: areas must be an array of row strings on element type " ..
              typeName(self))
    end
    local rects, width = {}, nil
    for r = 1, #rows do
        local row = rows[r]
        if type(row) ~= "string" then
            error("setGrid: areas row " .. r .. " must be a string on element type " ..
                  typeName(self))
        end
        local toks = {}
        for t in row:gmatch("%S+") do toks[#toks + 1] = t end
        if #toks == 0 then
            error("setGrid: areas row " .. r .. " is empty on element type " .. typeName(self))
        end
        if width == nil then
            width = #toks
        elseif #toks ~= width then
            error("setGrid: areas row " .. r .. " has " .. #toks ..
                  " cells, expected " .. width .. " on element type " .. typeName(self))
        end
        for c = 1, #toks do
            local name = toks[c]
            if name ~= "." then
                if not name:match(AREA_NAME_PAT) then
                    error("setGrid: invalid area name '" .. name .. "' in areas row " .. r ..
                          " on element type " .. typeName(self))
                end
                local rc = rects[name]
                if not rc then
                    rects[name] = { c1 = c, r1 = r, c2 = c, r2 = r }
                else
                    if c < rc.c1 then rc.c1 = c end
                    if c > rc.c2 then rc.c2 = c end
                    if r < rc.r1 then rc.r1 = r end
                    if r > rc.r2 then rc.r2 = r end
                end
            end
        end
    end
    return rects
end

--------------------------------------------------------------------------------
-- Placement parser (plan §3 grammar: <line> [ / <line|span n> ]; line = signed
-- int or area name; negative lines kept RAW — resolution is P2). Result:
-- {start=,end=,span=}; a bare name lands in start; "areaA / areaB" fills both.
--------------------------------------------------------------------------------

local function parseLineToken(s, self, key)
    local span = s:match("^span%s+(.+)$")
    if span then
        local n = tonumber(span)
        if n == nil or n ~= math.floor(n) or n < 1 then
            error("setGridPlacement: " .. key .. " span expects a positive integer on element type " ..
                  typeName(self))
        end
        return "span", n
    end
    local n = tonumber(s)
    if n ~= nil and n == math.floor(n) and n ~= 0 then
        return "line", n -- positive or negative, kept raw (P2 resolves)
    end
    if s:match(AREA_NAME_PAT) then
        return "area", s
    end
    error("setGridPlacement: invalid " .. key .. " placement token '" .. s ..
          "' on element type " .. typeName(self))
end

local function parsePlacement(spec, self, key)
    if type(spec) == "number" then
        -- YAML coerceNumericStrings turns bare line "2" into number 2 (plan §3)
        if spec ~= math.floor(spec) or spec == 0 then
            error("setGridPlacement: " .. key .. " number must be a non-zero integer on element type " ..
                  typeName(self))
        end
        return { start = spec }
    end
    if type(spec) ~= "string" then
        error("setGridPlacement: " .. key .. " must be a string or number on element type " ..
              typeName(self))
    end
    if spec:match("^%s*/") or spec:match("/%s*$") or spec:find("//") then
        error("setGridPlacement: " .. key .. " has an empty '/'-separated part on element type " ..
              typeName(self))
    end
    local parts = {}
    for seg in spec:gmatch("[^/]+") do parts[#parts + 1] = trim(seg) end
    if #parts == 0 or #parts > 2 then
        error("setGridPlacement: " .. key .. " expects at most one '/' on element type " ..
              typeName(self))
    end
    local out = {}
    if #parts == 1 then
        local kind, v = parseLineToken(parts[1], self, key)
        if kind == "span" then
            out.span = v
        else
            out.start = v -- line number or area name, raw
        end
    else
        local k1, v1 = parseLineToken(parts[1], self, key)
        local k2, v2 = parseLineToken(parts[2], self, key)
        if k1 == "span" then
            error("setGridPlacement: " .. key .. " span is only valid as a standalone or second part on element type " ..
                  typeName(self))
        end
        out.start = v1
        if k2 == "span" then
            out.span = v2
        else
            out["end"] = v2
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- gap normalization + place-* shorthand expansion (plan §2/§3)
--------------------------------------------------------------------------------

local function normalizeGap(v, self)
    if type(v) == "number" then
        v = v < 0 and 0 or v
        return v, v -- gap: colGap = rowGap
    elseif type(v) == "table" then
        local cg, rg = v.column or 0, v.row or 0
        if type(cg) ~= "number" or type(rg) ~= "number" then
            error("setGrid: gap.row/gap.column must be numbers on element type " ..
                  typeName(self))
        end
        return cg < 0 and 0 or cg, rg < 0 and 0 or rg
    end
    error("setGrid: gap must be number or table on element type " .. typeName(self))
end

-- place-* shorthand: "v h" -> align=v (vertical), justify=h (horizontal);
-- one value applies to both (CSS place-* semantics, plan §3). `src` names the
-- entry point so errors read like setFlex's ("setGridPlacement: ...").
local function parsePlacePair(v, self, key, valueSet, src)
    src = src or "setGrid"
    if type(v) ~= "string" then
        error(src .. ": " .. key .. " must be a string on element type " .. typeName(self))
    end
    local toks = {}
    for t in v:gmatch("%S+") do toks[#toks + 1] = t end
    if #toks == 1 then
        toks[2] = toks[1]
    elseif #toks ~= 2 then
        error(src .. ": " .. key .. " expects one or two values on element type " ..
              typeName(self))
    end
    if not valueSet[toks[1]] or not valueSet[toks[2]] then
        error(src .. ": invalid " .. key .. " value '" .. v .. "' on element type " ..
              typeName(self))
    end
    return toks[1], toks[2] -- align, justify
end

--------------------------------------------------------------------------------
-- Public element API (installed on gui by flexbox.init, grid plan §4 init row)
--------------------------------------------------------------------------------

function grid.apiSetGrid(self, opts)
    if opts == false then
        self.__grid = nil
        local fb = FB()
        if fb then fb.markDirty(self) end -- contract mirrors setFlex(false)
        return
    end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then
        error("setGrid: expected table or false, got " .. type(opts) ..
              " on element type " .. typeName(self))
    end
    if self.__flex then
        error("setGrid: element already has flex layout (setFlex(false) first) on element type " ..
              typeName(self))
    end
    -- Defaults per plan §2 (parsed template + line counts cached at setGrid
    -- time, never re-parsed per frame).
    local cfg = {
        columns = {},
        rows = {},
        areas = {},
        colGap = 0,
        rowGap = 0,
        autoFlow = "row",
        dense = false,
        justifyItems = "stretch",
        alignItems = "stretch",
        justifyContent = "start",
        alignContent = "start",
    }
    for k, v in pairs(opts) do
        if k == "columns" then
            cfg.columns = parseTrackList(v, self, "columns")
        elseif k == "rows" then
            cfg.rows = parseTrackList(v, self, "rows")
        elseif k == "areas" then
            cfg.areas = parseAreas(v, self)
        elseif k == "gap" then
            cfg.colGap, cfg.rowGap = normalizeGap(v, self)
        elseif k == "autoFlow" then
            if v ~= "row" and v ~= "column" then
                error("setGrid: invalid autoFlow '" .. tostring(v) ..
                      "' (expected row|column) on element type " .. typeName(self))
            end
            cfg.autoFlow = v
        elseif k == "dense" then
            if type(v) ~= "boolean" then
                error("setGrid: dense must be a boolean on element type " .. typeName(self))
            end
            cfg.dense = v
        elseif k == "justifyItems" then
            if not ITEM_ALIGN[v] then
                error("setGrid: invalid justifyItems '" .. tostring(v) ..
                      "' (expected start|end|center|stretch) on element type " .. typeName(self))
            end
            cfg.justifyItems = v
        elseif k == "alignItems" then
            if not ITEM_ALIGN[v] then
                error("setGrid: invalid alignItems '" .. tostring(v) ..
                      "' (expected start|end|center|stretch) on element type " .. typeName(self))
            end
            cfg.alignItems = v
        elseif k == "justifyContent" then
            if not CONTENT_ALIGN[v] then
                error("setGrid: invalid justifyContent '" .. tostring(v) ..
                      "' on element type " .. typeName(self))
            end
            cfg.justifyContent = v
        elseif k == "alignContent" then
            if not CONTENT_ALIGN[v] then
                error("setGrid: invalid alignContent '" .. tostring(v) ..
                      "' on element type " .. typeName(self))
            end
            cfg.alignContent = v
        elseif k == "placeItems" then
            -- shorthand applied after the longhands (wins on conflict, like a
            -- later CSS declaration)
            local a, j = parsePlacePair(v, self, k, ITEM_ALIGN)
            cfg.alignItems, cfg.justifyItems = a, j
        elseif k == "placeContent" then
            local a, j = parsePlacePair(v, self, k, CONTENT_ALIGN)
            cfg.alignContent, cfg.justifyContent = a, j
        elseif k == "placeSelf" then
            -- accepted at container parse time too (plan §2 comment: expanded
            -- to the pairs; per-item use belongs to setGridPlacement)
            local a, j = parsePlacePair(v, self, k, ITEM_ALIGN)
            cfg.alignSelf, cfg.justifySelf = a, j
        else
            error("setGrid: unknown option '" .. tostring(k) ..
                  "' on element type " .. typeName(self))
        end
    end
    self.__grid = cfg
    local fb = FB()
    if fb then
        fb.register(self)
        -- Dirty-marking event connections mirror apiSetFlex (flex plan §5.1
        -- row 5): gui's VisualEvents façaches filter `obj == self`
        -- (init.lua:1060-1078) and the handlers keep their own obj check;
        -- fb.inPass() covers the writing/firing guard window so the pass's
        -- own events never re-mark.
        if not self.__gridEvents then
            self.__gridEvents = true
            self:OnSizeChanged(function(obj)
                if obj == self and not fb.inPass() then
                    fb.markDirty(self)
                end
            end)
            self:OnPositionChanged(function(obj)
                if obj == self and not fb.inPass() then
                    fb.markDirty(self)
                end
            end)
        end
        fb.markDirty(self)
    end
end

function grid.apiSetGridPlacement(self, opts)
    if opts == false then
        -- back to auto-placement: mark up to the grid root (shared markDirty).
        -- Clears an escape-hatch float too (mirrors apiSetSizing{...}
        -- re-enabling management in flex): an explicit request to (re)join
        -- placement overrides the manual-geometry escape.
        self.__gridPlacement = nil
        self.__flexEscaped = nil
        local fb = FB()
        if fb then fb.markDirty(self) end
        return
    end
    if opts == nil then opts = {} end
    if type(opts) ~= "table" then
        error("setGridPlacement: expected table or false, got " .. type(opts) ..
              " on element type " .. typeName(self))
    end
    if self.__flex then
        error("setGridPlacement: element has flex layout (flex items are not grid items) on element type " ..
              typeName(self))
    end
    local cfg = {}
    for k, v in pairs(opts) do
        if k == "column" then
            cfg.column = parsePlacement(v, self, "column")
        elseif k == "row" then
            cfg.row = parsePlacement(v, self, "row")
        elseif k == "justifySelf" then
            if not ITEM_ALIGN[v] then
                error("setGridPlacement: invalid justifySelf '" .. tostring(v) ..
                      "' (expected start|end|center|stretch) on element type " .. typeName(self))
            end
            cfg.justifySelf = v
        elseif k == "alignSelf" then
            if not ITEM_ALIGN[v] then
                error("setGridPlacement: invalid alignSelf '" .. tostring(v) ..
                      "' (expected start|end|center|stretch) on element type " .. typeName(self))
            end
            cfg.alignSelf = v
        elseif k == "placeSelf" then
            local a, j = parsePlacePair(v, self, k, ITEM_ALIGN, "setGridPlacement")
            cfg.alignSelf, cfg.justifySelf = a, j
        else
            error("setGridPlacement: unknown option '" .. tostring(k) ..
                  "' on element type " .. typeName(self))
        end
    end
    self.__gridPlacement = cfg
    local fb = FB()
    if fb then fb.markDirty(self) end
end

--------------------------------------------------------------------------------
-- layoutGridRoot — full pipeline for one grid root (plan §5; P2 = plan §7
-- steps 3-5: track sizing + placement engine + alignment).
--
-- Order: seed items -> resolve placement (explicit positive-line / area /
-- span placements, then implicit-track growth from those, then negative
-- lines resolved against the extent so far, then auto-placement cursor
-- honoring autoFlow row|column + dense) -> track sizing (px / auto /
-- min-content / minmax bases, spanning-excess distribution, fr distribution)
-- -> content distribution (justify-content / align-content) -> item boxes
-- (__sizing modes, *-self vs *-items alignment, square/aspect bake) -> the
-- shared flexbox write-back + event tail.
--
-- Documented simplifications vs CSS (plan §5.2/§5.3 approved deviations):
--   * spanning items do not participate in the CSS iterative base-size
--     growth: their excess over the summed spanned bases is distributed
--     uniformly across the spanned auto/minmax tracks (spans over fr-only
--     tracks never grow them);
--   * negative-start items resolve against explicit + already-created
--     implicit tracks: they do NOT push implicit tracks at the FRONT;
--   * on overflow, fr tracks collapse to their lower bound (0, or the
--     minmax min) and the items overflow (CSS floors fr at its content base);
--   * minmax upper bounds other than fr are treated as growth limits
--     (auto/min-content -> max-content contribution; px -> hard clamp);
--   * no padding in the __grid model (plan §2);
--   * P3 (plan §5.7): the Pass-B analogue + auto-row re-solve re-solves the
--     ROW axis only — auto COLUMNS keep their max-content seed (documented:
--     no wrap re-solve on the column axis, autoFlow="column" included);
--   * grid.intrinsic = the root's last computed track sums, else a lightweight
--     first-frame compute (see below): grids relying on implicit tracks beyond
--     the template report their template-only size on the first frame and
--     converge one frame late (same documented class as the seed/propagation
--     contract, plan §5.7);
--   * cross-mode fit contribution feeds back by re-dirtying a fit flex
--     ancestor when a grid root's track sums change (one frame late); a flex
--     child inside a grid does NOT feed its size back into auto grid tracks —
--     the grid refreshes when dirtied through the shared markDirty seam;
--   * nested __grid-in-__grid IS descended by this pass (recursive
--     layoutGridRoot after the parent's write-back, flex's in-pass nested
--     descent analogue); __flex children of a grid are top-level roots handled
--     by the depth-ordered runPass (__flexFrame stamp), no code needed.
--------------------------------------------------------------------------------

local gbuf = {}      -- reusable subtree buffer (no per-frame allocation, flex plan §3.0)
local pitems = {}    -- placement items for the current pass (direct flow children)
local occ = {}       -- occ[row][col] = true: auto-placement occupancy (wiped per pass)
local colSpecs, colSizes, colPos = {}, {}, {}
local rowSpecs, rowSizes, rowPos = {}, {}, {}
local AUTO_TRACK = { kind = "auto" }
-- mirrors flexbox's DEFAULT_AXIS (fit, unclamped) for roots without
-- setSizing — module-level so the sizeManaged path allocates nothing (flex
-- plan §3.0 no-per-frame-allocation convention)
local DEFAULT_FIT_AXIS = { mode = "fit", min = 0, max = math.huge }

local function occupy(r1, r2, c1, c2)
    for r = r1, r2 do
        local row = occ[r]
        if not row then row = {}; occ[r] = row end
        for c = c1, c2 do row[c] = true end
    end
end

local function isFree(r1, r2, c1, c2)
    for r = r1, r2 do
        local row = occ[r]
        if row then
            for c = c1, c2 do
                if row[c] then return false end
            end
        end
    end
    return true
end

-- grid-local text predicate: elements created by newTextBase carry .text/.font
-- (init.lua:1152-1164); the type-mask check in flexbox's isTextElement is not
-- needed for grid items and keeps grid.lua free of the gui type masks.
local function isGridText(e)
    return e.text ~= nil and e.font ~= nil
end

-- grid-local min-content width (plan §5.2: widest single word; no measure.lua
-- change). Non-text items fall back to their seeded width.
local function minContentW(e)
    if not isGridText(e) then return e.__fw or 0 end
    local w = 0
    for word in tostring(e.text):gmatch("%S+") do
        local ww = e.font:getWidth(word)
        if ww > w then w = ww end
    end
    return w
end

-- Negative grid lines resolve against the FINAL track count (plan §5.3c):
-- line -k is the (k+1)-th line from the end, i.e. count + 2 - k... with v<0:
-- line = count + 2 + v (v=-1 -> the last line).
local function resolveLine(v, count)
    if v < 0 then return count + 2 + v end
    return v
end

-- Named-area line resolution (plan §5 step 1: placement names resolve to the
-- area's start/end lines; standalone named grid lines stay a non-goal).
local function areaLines(cfg, name, axis, self)
    local rc = cfg.areas[name]
    if not rc then
        error("setGridPlacement: unknown area name '" .. name ..
              "' in " .. axis .. " placement on element type " .. typeName(self))
    end
    if axis == "col" then return rc.c1, rc.c2 + 1 end
    return rc.r1, rc.r2 + 1
end

-- Copy one axis of a raw __gridPlacement onto the working item. Area names
-- expand to the area's lines (a bare name spans the whole area when no end /
-- span follows). Negative line numbers stay RAW here (phase C resolves them).
local function resolveAxisPlacement(item, cfg, axis, self)
    local p
    if item.pl then
        if axis == "col" then p = item.pl.column else p = item.pl.row end
    end
    local start, endL, span
    if p then
        start, endL, span = p.start, p["end"], p.span
        if type(start) == "string" then
            local s, e2 = areaLines(cfg, start, axis, self)
            start = s
            if endL == nil and span == nil then endL = e2 end
        end
        if type(endL) == "string" then
            local _, e2 = areaLines(cfg, endL, axis, self)
            endL = e2
        end
    end
    item[axis .. "_start"], item[axis .. "_end"], item[axis .. "_span"] = start, endL, span
    item["neg_" .. axis] = (type(start) == "number" and start < 0)
        or (type(endL) == "number" and endL < 0)
end

-- Track bases for one axis: contributions from items spanning exactly ONE
-- track (max-content for auto, widest word for min-content), minmax clamps,
-- then spanning-item excess spread uniformly over spanned auto/minmax tracks
-- (plan §5.2 simplification). Returns the base sizes; fr tracks get their
-- lower bound and are finalized by distributeFr.
local function sizeTracks(specs, sizes, count, items, nItems, axis)
    local maxC, minC = {}, {}
    for i = 1, nItems do
        local it = items[i]
        local a1 = axis == "col" and it.c1 or it.r1
        local a2 = axis == "col" and it.c2 or it.r2
        if a1 and a1 == a2 then
            local e = it.e
            local mc = axis == "col" and e.__fw or e.__fh
            if mc > (maxC[a1] or 0) then maxC[a1] = mc end
            local nc = axis == "col" and minContentW(e) or e.__fh
            if nc > (minC[a1] or 0) then minC[a1] = nc end
        end
    end

    for i = 1, count do
        local s = specs[i]
        if s.kind == "px" then
            sizes[i] = s.v
        elseif s.kind == "fr" then
            sizes[i] = 0 -- lower bound; fr share added by distributeFr
        elseif s.kind == "auto" then
            sizes[i] = maxC[i] or 0
        elseif s.kind == "min-content" then
            sizes[i] = minC[i] or 0
        else -- minmax
            local L = s.min.kind == "px" and s.min.v
                or (s.min.kind == "min-content" and (minC[i] or 0) or 0)
            if s.max.kind == "px" then
                local b = max(s.min.kind == "auto" and 0 or L, maxC[i] or 0)
                sizes[i] = min(b, s.max.v)
            elseif s.max.kind == "auto" or s.max.kind == "min-content" then
                -- growth limit = max-content contribution floored at min
                -- (min-content upper: widest-word contribution instead)
                if s.max.kind == "min-content" then
                    sizes[i] = max(L, minC[i] or 0)
                else
                    sizes[i] = max(L, maxC[i] or 0)
                end
            else -- max fr: lower bound now, share later
                sizes[i] = L
            end
        end
    end

    -- Spanning-item excess (plan §5.2): uniform top-up across spanned
    -- auto/minmax-family tracks; fr-only spans contribute nothing.
    for i = 1, nItems do
        local it = items[i]
        local a1 = axis == "col" and it.c1 or it.r1
        local a2 = axis == "col" and it.c2 or it.r2
        if a1 and a2 > a1 then
            local e = it.e
            local need = axis == "col" and e.__fw or e.__fh
            local summed, growable = 0, 0
            for t = a1, a2 do
                summed = summed + sizes[t]
                local k = specs[t].kind
                if k == "auto" or k == "min-content" or k == "minmax" then
                    growable = growable + 1
                end
            end
            local excess = need - summed
            if excess > 0 and growable > 0 then
                local add = excess / growable
                for t = a1, a2 do
                    local k = specs[t].kind
                    if k == "auto" or k == "min-content" or k == "minmax" then
                        sizes[t] = sizes[t] + add
                    end
                end
            end
        end
    end
end

-- fr distribution (plan §5.4): free = inner - Σ non-fr bases - Σ gaps;
-- fr track = max(lower, free * f / Σfr); free < 0 -> fr collapses to the
-- lower bound and items overflow (documented simplification). A minmax whose
-- MAX is fr participates with that weight, its base (the min) counted in the
-- non-fr sum.
local function frWeight(s)
    if s.kind == "fr" then return s.v end
    if s.kind == "minmax" and s.max.kind == "fr" then return s.max.v end
    return 0
end

local function distributeFr(specs, sizes, count, gap, inner)
    local sumFr, nonFr = 0, 0
    for i = 1, count do
        local w = frWeight(specs[i])
        if w > 0 then
            sumFr = sumFr + w
        else
            nonFr = nonFr + sizes[i]
        end
    end
    if sumFr <= 0 then return end
    local free = inner - nonFr - gap * max(count - 1, 0)
    if free < 0 then free = 0 end
    for i = 1, count do
        local w = frWeight(specs[i])
        if w > 0 then
            local share = free * w / sumFr
            if sizes[i] < share then sizes[i] = share end -- minmax lower clamp
        end
    end
end

-- Content distribution (plan §5.5): offset the whole track group inside the
-- content box. free <= 0 -> zero offsets (overflow).
local function distributeTracks(pos, sizes, count, gap, inner, origin, mode)
    local total = gap * max(count - 1, 0)
    for i = 1, count do total = total + sizes[i] end
    local extra = inner - total
    if extra < 0 then extra = 0 end
    local lead, between = 0, gap
    if mode == "center" then
        lead = extra / 2
    elseif mode == "end" then
        lead = extra
    elseif mode == "space-between" then
        if count > 1 then between = gap + extra / (count - 1) end
    elseif mode == "space-around" then
        if count > 0 then
            lead = extra / (2 * count)
            between = gap + extra / count
        end
    elseif mode == "space-evenly" then
        lead = extra / (count + 1)
        between = gap + extra / (count + 1)
    end
    local p = origin + lead
    for i = 1, count do
        pos[i] = p
        p = p + sizes[i] + between
    end
end

-- Item box along one axis (plan §5.6/§5.7 + §2 default-difference note):
-- with NO setSizing the item stretches to its grid area (CSS default);
-- setSizing opts into its mode — fit = natural size positioned per
-- justify-self/align-self (fallback *-items; "stretch" then behaves as
-- "start" for a fit item), grow = fills, percent = fraction of the area,
-- fixed = the authored value (min/max clamp applies to sized specs).
local function itemBoxAxis(areaPos, areaSize, e, sizeKey, selfVal)
    local sz = e.__sizing
    local spec = sz and sz[sizeKey]
    local pos, size
    if not spec then
        pos, size = areaPos, areaSize -- default stretch (plan §2)
    elseif spec.mode == "fixed" then
        size = spec.value or 0
    elseif spec.mode == "percent" then
        size = areaSize * (spec.value or 0)
    elseif spec.mode == "fit" then
        size = sizeKey == "width" and e.__fw or e.__fh
    else -- grow: fills the area
        pos, size = areaPos, areaSize
    end
    if spec then
        size = max(spec.min or 0, min(size, spec.max or math.huge))
    end
    if pos == nil then -- natural-size item: align inside the area
        if selfVal == "end" then
            pos = areaPos + areaSize - size
        elseif selfVal == "center" then
            pos = areaPos + (areaSize - size) / 2
        else
            pos = areaPos -- start (stretch on a fit item behaves as start)
        end
    end
    return pos, size
end

function grid.layoutGridRoot(root, rx, ry, rw, rh)
    local fb = FB()
    if not fb then return end -- flex scheduler absent: inert (should not happen)
    fb.stats.passes = fb.stats.passes + 1 -- grid roots count in stats (plan §5.9)
    root.__flexLaidOut = true

    -- Seed the root box (flex plan §3.1): dualDim-owned, read against parent.
    root.__fx, root.__fy, root.__fw, root.__fh = rx, ry, rw, rh

    local cfg = root.__grid

    -- ---- 1. Seed items (shared flex primitives) + gather placements -------
    for k in pairs(occ) do occ[k] = nil end
    local nItems = 0
    local nested = nil -- __grid children: descended recursively after write-back (P3)
    local children = root.children
    for ci = 1, #children do
        local child = children[ci]
        -- escape hatch: __flexEscaped children float out of placement (shared
        -- flag with flex; they keep their manual dualDim and stay descendants)
        if child.__flexEscaped ~= true then
            if not child.__flexManaged then
                child.__flexManaged = { size = true, pos = true }
            end
            child.__fw = fb.seedAxis(child, "width")
            child.__fh = fb.seedAxis(child, "height")
            -- square lock seeding mirrors layoutFlexRoot (flex plan §3.6
            -- idempotence: bake + resolver re-application become no-ops)
            if child.square == "w" and child.__fh < child.__fw then
                child.__fh = child.__fw
            elseif child.square == "h" and child.__fw < child.__fh then
                child.__fw = child.__fh
            end
            nItems = nItems + 1
            local item = pitems[nItems] or {}
            pitems[nItems] = item
            item.e = child
            item.pl = child.__gridPlacement
            item.c1, item.c2, item.r1, item.r2 = nil, nil, nil, nil
            resolveAxisPlacement(item, cfg, "col", child)
            resolveAxisPlacement(item, cfg, "row", child)
            if child.__grid then
                -- per-call local list: the recursion reuses the module buffers,
                -- so the child list must survive them being clobbered (P3)
                nested = nested or {}
                nested[#nested + 1] = child
            end
        end
    end
    for f = nItems + 1, #pitems do pitems[f] = nil end

    -- ---- 2. Placement resolution (plan §5.3 phases a-d) -------------------
    local colCount, rowCount = #cfg.columns, #cfg.rows
    -- grid-template-areas defines the explicit grid extent (CSS); areas rects
    -- are inclusive cell bounds, so the line count is c2/r2.
    for _, rc in pairs(cfg.areas) do
        if rc.c2 > colCount then colCount = rc.c2 end
        if rc.r2 > rowCount then rowCount = rc.r2 end
    end

    -- (a) explicit positive-line / area placements, per axis independently
    -- (an item may mix a positive column with a negative row: the positive
    -- axis resolves here, the negative one in phase (c)).
    for i = 1, nItems do
        local it = pitems[i]
        if it.col_start and not it.neg_col then
            it.c1 = it.col_start
            it.c2 = it.col_end and (it.col_end - 1)
                or (it.col_span and (it.c1 + it.col_span - 1) or it.c1)
            if it.c2 > colCount then colCount = it.c2 end -- (b) implicit at END
        end
        if it.row_start and not it.neg_row then
            it.r1 = it.row_start
            it.r2 = it.row_end and (it.row_end - 1)
                or (it.row_span and (it.r1 + it.row_span - 1) or it.r1)
            if it.r2 > rowCount then rowCount = it.r2 end
        end
        -- fully explicit items occupy cells immediately (overlap allowed)
        if it.c1 and it.r1 then occupy(it.r1, it.r2, it.c1, it.c2) end
    end

    -- (c) negative lines against the extent built so far (explicit + implicit
    -- from (a)/(b)); documented simplification: no FRONT implicit tracks.
    for i = 1, nItems do
        local it = pitems[i]
        if it.neg_col then
            local s = it.col_start and resolveLine(it.col_start, colCount)
            local e2 = it.col_end and resolveLine(it.col_end, colCount)
            if s and e2 then
                if s > e2 then s, e2 = e2, s end -- CSS normalizes start > end
                it.c1, it.c2 = s, e2 - 1
            elseif s then
                it.c1, it.c2 = s, s + (it.col_span or 1) - 1
            end
            if it.c2 and it.c2 > colCount then colCount = it.c2 end
        end
        if it.neg_row then
            local s = it.row_start and resolveLine(it.row_start, rowCount)
            local e2 = it.row_end and resolveLine(it.row_end, rowCount)
            if s and e2 then
                if s > e2 then s, e2 = e2, s end
                it.r1, it.r2 = s, e2 - 1
            elseif s then
                it.r1, it.r2 = s, s + (it.row_span or 1) - 1
            end
            if it.r2 and it.r2 > rowCount then rowCount = it.r2 end
        end
        if it.c1 and it.r1 then occupy(it.r1, it.r2, it.c1, it.c2) end
    end

    -- (d) auto-placement cursor honoring autoFlow row|column; dense rewinds
    -- the cursor to the first fitting gap for each auto item. Auto items must
    -- not overlap any occupied cell; overflow creates implicit tracks along
    -- the flow's growing axis.
    local rowFlow = cfg.autoFlow ~= "column"
    local curR, curC = 1, 1
    for i = 1, nItems do
        local it = pitems[i]
        if it.c1 == nil or it.r1 == nil then
            local cs = it.col_span or 1
            local rs = it.row_span or 1
            if it.c1 == nil and it.r1 == nil then
                -- fully auto
                if rowFlow then
                    if colCount == 0 then
                        -- no explicit columns: single implicit row, columns
                        -- grow (CSS none-template analogue)
                        it.c1, it.c2 = colCount + 1, colCount + cs
                        colCount = it.c2
                        it.r1, it.r2 = 1, rs
                        if it.r2 > rowCount then rowCount = it.r2 end
                    else
                        local r, c = (cfg.dense and 1 or curR), (cfg.dense and 1 or curC)
                        while true do
                            if c + cs - 1 > colCount then r, c = r + 1, 1 end
                            if r > rowCount then -- implicit auto row
                                it.r1, it.r2 = r, r + rs - 1
                                it.c1, it.c2 = c, c + cs - 1
                                if it.r2 > rowCount then rowCount = it.r2 end
                                break
                            end
                            if isFree(r, r + rs - 1, c, c + cs - 1) then
                                it.r1, it.r2 = r, r + rs - 1
                                it.c1, it.c2 = c, c + cs - 1
                                break
                            end
                            c = c + 1
                        end
                        curR, curC = r, c + cs
                        if curC > colCount then curR, curC = r + 1, 1 end
                    end
                else
                    if rowCount == 0 then
                        it.r1, it.r2 = rowCount + 1, rowCount + rs
                        rowCount = it.r2
                        it.c1, it.c2 = 1, cs
                        if it.c2 > colCount then colCount = it.c2 end
                    else
                        local c, r = (cfg.dense and 1 or curC), (cfg.dense and 1 or curR)
                        while true do
                            if r + rs - 1 > rowCount then c, r = c + 1, 1 end
                            if c > colCount then -- implicit auto column
                                it.c1, it.c2 = c, c + cs - 1
                                it.r1, it.r2 = r, r + rs - 1
                                if it.c2 > colCount then colCount = it.c2 end
                                break
                            end
                            if isFree(r, r + rs - 1, c, c + cs - 1) then
                                it.r1, it.r2 = r, r + rs - 1
                                it.c1, it.c2 = c, c + cs - 1
                                break
                            end
                            r = r + 1
                        end
                        curC, curR = c, r + rs
                        if curR > rowCount then curC, curR = c + 1, 1 end
                    end
                end
            elseif it.r1 == nil then
                -- column definite, row auto: advance the row cursor
                local r = 1
                while r <= rowCount and not isFree(r, r + rs - 1, it.c1, it.c2) do
                    r = r + 1
                end
                it.r1, it.r2 = r, r + rs - 1
                if it.r2 > rowCount then rowCount = it.r2 end
            else
                -- row definite, column auto: advance the column cursor
                local c = 1
                while c <= colCount and not isFree(it.r1, it.r2, c, c + cs - 1) do
                    c = c + 1
                end
                it.c1, it.c2 = c, c + cs - 1
                if it.c2 > colCount then colCount = it.c2 end
            end
            occupy(it.r1, it.r2, it.c1, it.c2)
        end
    end
    for f = nItems + 1, #pitems do pitems[f] = nil end

    -- ---- 3. Track sizing (px / auto / min-content / minmax + fr) ----------
    for i = 1, colCount do colSpecs[i] = cfg.columns[i] or AUTO_TRACK end
    for i = colCount + 1, #colSpecs do colSpecs[i] = nil end
    for i = 1, rowCount do rowSpecs[i] = cfg.rows[i] or AUTO_TRACK end
    for i = rowCount + 1, #rowSpecs do rowSpecs[i] = nil end

    sizeTracks(colSpecs, colSizes, colCount, pitems, nItems, "col")
    distributeFr(colSpecs, colSizes, colCount, cfg.colGap, rw)
    sizeTracks(rowSpecs, rowSizes, rowCount, pitems, nItems, "row")
    distributeFr(rowSpecs, rowSizes, rowCount, cfg.rowGap, rh)

    -- ---- 4. Content distribution: columns (rows re-distributed after the
    -- P3 wrap refinement below — wrapped heights change the row group size) --
    -- No padding in the plan §2 __grid model, so content box == root box.
    distributeTracks(colPos, colSizes, colCount, cfg.colGap, rw, root.__fx, cfg.justifyContent)

    -- ---- 5. Item X boxes (*-self overrides *-items) ------------------------
    local n = 1
    gbuf[1] = root
    gbuf[2] = nil
    for i = 1, nItems do
        local it = pitems[i]
        local e = it.e
        local pl = it.pl
        local jSelf = (pl and pl.justifySelf) or cfg.justifySelf or cfg.justifyItems
        local areaX = colPos[it.c1]
        local areaW = colPos[it.c2] + colSizes[it.c2] - areaX
        e.__fx, e.__fw = itemBoxAxis(areaX, areaW, e, "width", jSelf)
        n = n + 1
        gbuf[n] = e
        gbuf[n + 1] = nil
    end
    fb.stats.visited = fb.stats.visited + n

    -- ---- 5b. Pass-B analogue (plan §5.7, P3): wrapped text heights at the
    -- final X widths. measure.get + the shared fb.textMeasureOpts apply the
    -- exact printf inset rules, so measured lines == rendered lines (same as
    -- the flex pass). Documented: the column axis gets no wrap re-solve —
    -- auto columns keep the max-content seed from step 3.
    local textOpts = fb.textMeasureOpts
    for i = 1, nItems do
        local e = pitems[i].e
        if isGridText(e) then
            -- fit-height text only: an authored fixed height (e.g. a 36px
            -- button) must survive the wrap re-solve, same guard as flex
            -- Pass B (flexbox.lua).
            local sh = (e.__sizing and e.__sizing.height) or DEFAULT_FIT_AXIS
            if sh.mode == "fit" then
                e.__fh = measure.get(e.text, e.font, e.__fw, textOpts and textOpts(e) or nil).height
            end
        end
    end

    -- ---- 5c. Auto-row refinement (plan §5.7, P3): re-max auto/implicit rows
    -- from the wrapped heights of single-row items, then re-resolve row fr.
    -- sizeTracks recomputes from scratch, so fixed rows stay fixed and fr
    -- rows re-distribute against the refined non-fr sum.
    sizeTracks(rowSpecs, rowSizes, rowCount, pitems, nItems, "row")
    distributeFr(rowSpecs, rowSizes, rowCount, cfg.rowGap, root.__fh)

    -- Size-managed grid root (scroll content, flex plan §7 parity, P3): the
    -- pass owns the root SIZE — a fit-height box becomes Σ rows + gaps
    -- (clamped to min/max, exactly flex propagateUp's sizeManaged root rule)
    -- while the authored width stays dualDim-owned (writeBack never touches a
    -- __flexSizeManaged box's position slots). Re-solve fr against the grown
    -- box so fr rows distribute over the content height.
    if root.__flexSizeManaged then
        local sh = (root.__sizing and root.__sizing.height) or DEFAULT_FIT_AXIS
        if sh.mode == "fit" then
            local contentH = cfg.rowGap * max(rowCount - 1, 0)
            for i = 1, rowCount do contentH = contentH + rowSizes[i] end
            root.__fh = min(max(contentH, sh.min), sh.max)
            distributeFr(rowSpecs, rowSizes, rowCount, cfg.rowGap, root.__fh)
        end
    end

    distributeTracks(rowPos, rowSizes, rowCount, cfg.rowGap, root.__fh, root.__fy, cfg.alignContent)

    -- ---- 6. Item Y boxes + aspectRatio bake (flex Pass E analogue: aspect
    -- after both axes; text excluded, clay.h:2355) ---------------------------
    for i = 1, nItems do
        local it = pitems[i]
        local e = it.e
        local pl = it.pl
        local aSelf = (pl and pl.alignSelf) or cfg.alignSelf or cfg.alignItems
        local areaY = rowPos[it.r1]
        local areaH = rowPos[it.r2] + rowSizes[it.r2] - areaY
        e.__fy, e.__fh = itemBoxAxis(areaY, areaH, e, "height", aSelf)
        local ar = e.__sizing and e.__sizing.aspectRatio
        if ar and not isGridText(e) then
            e.__fh = e.__fw / ar
        end
    end

    -- square bake (mirrors flex Pass E tail) so the write-back invariant
    -- getAbsolutes() == __flexComputed holds through the resolver.
    for k = 2, n do
        local e = gbuf[k]
        if e.square == "w" then
            e.__fh = e.__fw
        elseif e.square == "h" then
            e.__fw = e.__fh
        end
    end

    -- Shared write-back + event policy from flexbox (grid plan §1: single-
    -- sourced so the invariant and event guards stay one implementation).
    fb.writeBack(gbuf, n, root)
    fb.fireGeometryEvents(gbuf, n, root)

    -- Cache the final track sums (P3): grid.intrinsic and flexbox's
    -- seedAxis/propagateUp contribution read exactly these values — one
    -- source for the cross-mode fit contribution (plan §4).
    local colSum, rowSum = cfg.colGap * max(colCount - 1, 0), cfg.rowGap * max(rowCount - 1, 0)
    for i = 1, colCount do colSum = colSum + colSizes[i] end
    for i = 1, rowCount do rowSum = rowSum + rowSizes[i] end
    local prev = root.__gridSums
    if not prev or prev.col ~= colSum or prev.row ~= rowSum then
        root.__gridSums = { col = colSum, row = rowSum }
        -- Cross-mode feedback (P3): ancestors seeded from the PREVIOUS sums
        -- earlier in this same runPass (depth order) — a fit flex parent's
        -- fit box, or a grid parent's auto track around this root. Dirty from
        -- the parent up (markDirty walks to the nearest layout root; from the
        -- root itself it would stop at a top-level grid and miss a fit flex
        -- parent). Converges one frame late — the documented seed/
        -- propagation contract (plan §5.7), self-limiting: the sums only
        -- change while the layout is still moving.
        fb.markDirty(root.parent or root)
    end

    -- Nested __grid descent (P3): a __grid child of a __grid parent is NOT a
    -- top-level root (isFlexRoot excludes same-mode nesting), so this pass
    -- lays it out itself — the analogue of flex descending nested __flex
    -- inside its own pass. Runs after the parent's write-back so the child
    -- seeds from the box just placed (and the module buffers are spent; the
    -- per-call `nested` list survives gbuf being clobbered by the recursion).
    -- __flex children need no descent here: they ARE top-level roots and the
    -- depth-ordered runPass seeds them from this pass's fresh absolutes
    -- (__flexFrame stamp).
    if nested then
        for i = 1, #nested do
            local ch = nested[i]
            grid.layoutGridRoot(ch, ch.__fx, ch.__fy, ch.__fw, ch.__fh)
        end
    end
end

--------------------------------------------------------------------------------
-- intrinsic — cross-mode intrinsic contribution (plan §4 seedAxis/propagateUp
-- rows, §5 step 2; P3). Returns the grid's computed content size along one
-- sizing axis ("width" | "height"): the track sums cached by the root's last
-- layout (the same source flexbox consumes through seedAxis, and therefore
-- propagateUp's fit sums), else a lightweight on-demand compute — explicit
-- template tracks + gaps, auto/minmax bases from direct-children max-content
-- contributions (explicit single-track placements, plus a sequential
-- auto-flow approximation for unplaced items). Multi-track spans and implicit
-- tracks beyond the template are not modeled lightweight, so those grids
-- report their template-only size on the FIRST frame and converge the next
-- frame once the root's own pass has cached the real sums (documented
-- one-frame-late contract). Column axis: auto COLUMNS use the max-content
-- seed — no wrap re-solve (documented P3 simplification).
--------------------------------------------------------------------------------

local function naturalAlong(e, axis)
    -- max-content along one sizing axis: mirrors flexbox.seedAxis (fixed ->
    -- authored value first, then the fit branch: text natural / image / video
    -- dims), plus recursion into nested grids (their own sums / lightweight
    -- value, so nested grids contribute their content size too).
    if e.__grid then return grid.intrinsic(e, axis) end
    local sp = e.__sizing and e.__sizing[axis]
    if sp and sp.mode == "fixed" then return sp.value or 0 end
    if isGridText(e) and e.font then
        if axis == "width" then return measure.natural(e.text, e.font).width end
        return e.font:getHeight()
    end
    if e.imageWidth or e.imageHeight then
        return (axis == "width" and e.imageWidth) or (axis == "height" and e.imageHeight) or 0
    end
    if e.videoWidth or e.videoHeigth then
        return (axis == "width" and e.videoWidth) or (axis == "height" and e.videoHeigth) or 0
    end
    return 0
end

local function intrinsicLightweight(e, axis)
    local cfg = e.__grid
    local specs = axis == "width" and cfg.columns or cfg.rows
    local count = #specs
    if count == 0 then return 0 end -- implicit-only: unknown before first layout
    local gap = axis == "width" and cfg.colGap or cfg.rowGap
    local maxC = {}
    local autoIdx = 0
    local children = e.children
    for ci = 1, #children do
        local ch = children[ci]
        if ch.__flexEscaped ~= true then
            local pl = ch.__gridPlacement
            local p = pl and (axis == "width" and pl.column or pl.row)
            local t
            if p and type(p.start) == "number" and p.start > 0 then
                local e2 = p["end"]
                if type(e2) == "number" and e2 > 0 then
                    if e2 - 1 == p.start then t = p.start end -- single track only
                else
                    local last = p.start + (p.span or 1) - 1
                    if last <= count then t = last end -- span/implicit: not modeled
                end
            end
            if t == nil then
                autoIdx = autoIdx + 1
                t = (autoIdx - 1) % count + 1 -- sequential auto-flow approximation
            end
            local v = naturalAlong(ch, axis)
            if v > (maxC[t] or 0) then maxC[t] = v end
        end
    end
    local total = gap * max(count - 1, 0)
    for i = 1, count do
        local s = specs[i]
        if s.kind == "px" then
            total = total + s.v
        elseif s.kind == "fr" then
            -- intrinsic of an fr track is its content base (0 without a
            -- definite parent box; the fr share only exists inside one)
        elseif s.kind == "auto" then
            total = total + (maxC[i] or 0)
        else
            -- min-content / minmax: contribution clamped between the bounds
            -- (the widest-word min refinement is the full pass's job, not
            -- the lightweight first-frame estimate)
            local L = s.kind == "minmax" and (s.min.kind == "px" and s.min.v or 0) or 0
            local v = max(L, maxC[i] or 0)
            if s.kind == "minmax" and s.max.kind == "px" then v = min(v, s.max.v) end
            total = total + v
        end
    end
    return total
end

function grid.intrinsic(e, axis)
    if not e.__grid then return 0 end
    local sums = e.__gridSums
    if sums then
        local v = sums[axis == "width" and "col" or "row"]
        if v ~= nil then return v end
    end
    return intrinsicLightweight(e, axis)
end

--------------------------------------------------------------------------------
-- init — called by flexbox.init after it wires gui.setGrid/setGridPlacement;
-- no installation happens here (the single late-injection point stays
-- init.lua:2580 -> flexbox.init, grid plan §4 init row). The hook exists so
-- a later phase can capture the scheduler reference.
--------------------------------------------------------------------------------

function grid.init(flexboxRef)
end

return grid
