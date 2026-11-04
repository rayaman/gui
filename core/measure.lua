-- measure.lua
-- Cached text measurement service for the flex layout pass (docs/flexbox-integration-plan.md §1/§3.3).
-- Mirrors Clay's MeasureTextCached (reference/clay/clay.h:1639-1719) adapted to LÖVE fonts.
--
-- The measurement replicates exactly what love.graphics.printf will render:
--   * the printf draw path (init.lua:2130-2151) wraps at w*mul where mul is 2 for
--     circle/arc form factors, and offsets the print box by adjust + textOffsetX;
--   * therefore the effective wrap width is w*mul inset by adjust/textOffsetX;
--   * line breaking uses font:getWrap, the very same routine LÖVE's printf uses
--     internally, so measured line count == visibly rendered line count.
--
-- Cache is a plain Lua table keyed fontRef .. "\0" .. text .. "\0" .. floor(effWidth),
-- with a generation counter; measure.beginPass() bumps the generation and sweeps
-- entries that were not touched in the previous pass (analogue of Clay's generation
-- eviction, clay.h:1664-1667). measure.invalidate(font) drops everything for a font
-- (call on font change / FontUpdated).

local floor, max = math.floor, math.max

local measure = {}

local cache = {}
local cacheCount = 0
local gen = 0
local SWEEP_AT = 4096 -- cache size that triggers a generation sweep

measure.stats = { hits = 0, misses = 0 }

--- Bump the measurement generation. Call once per layout pass so stale entries
--- become sweepable. Cheap: only the sweep itself walks the cache.
function measure.beginPass()
    gen = gen + 1
    if cacheCount > SWEEP_AT then
        local kept = 0
        for k, entry in pairs(cache) do
            if entry.gen < gen - 1 then
                cache[k] = nil
            else
                kept = kept + 1
            end
        end
        cacheCount = kept
    end
    return gen
end

--- Drop every cached measurement for a font (font object changed / evicted).
function measure.invalidate(font)
    local prefix = tostring(font) .. "\0"
    local kept = 0
    for k in pairs(cache) do
        if k:sub(1, #prefix) ~= prefix then
            cache[k] = nil
        else
            kept = kept + 1
        end
    end
    cacheCount = kept
end

--- Clear the whole cache.
function measure.clear()
    cache = {}
    cacheCount = 0
end

--- Measure a string as love.graphics.printf would render it.
-- @param text   string
-- @param font   love.font
-- @param width  number  the element box width (already resolved by the flex pass)
-- @param opts   optional { mul = 1|2, adjust = 0, textOffsetX = 0 } — the same
--               inset rules the printf draw path applies (init.lua:2131-2134, 2146).
--               Pass mul = 2 for circle/arc form factors.
-- @return { width = widest rendered line, height = lines * font:getHeight(), lines = n }
function measure.get(text, font, width, opts)
    opts = opts or {}
    local mul = opts.mul or 1
    local eff = width * mul
    if opts.adjust or opts.textOffsetX then
        eff = eff - (opts.adjust or 0) - (opts.textOffsetX or 0)
    end
    if eff < 0 then eff = 0 end

    -- Infinity-safe: natural-width measurement (no wrap) uses a huge box.
    local keyW
    if eff >= 1e8 then
        keyW = "inf"
        eff = 1e8
    else
        keyW = floor(eff) -- plan §1: cache keyed on floor(wrapW)
    end

    local key = tostring(font) .. "\0" .. text .. "\0" .. keyW
    local entry = cache[key]
    if entry then
        entry.gen = gen
        measure.stats.hits = measure.stats.hits + 1
        return entry
    end
    measure.stats.misses = measure.stats.misses + 1

    local lines
    if eff < 1 then
        -- Degenerate box: LÖVE would split every glyph; treat as one unwrapped line
        -- so fit-sizing never explodes on zero-width containers (Phase 2 guard).
        lines = { text }
    else
        -- Wrap at the exact effective width (what printf uses); the floor is only
        -- the cache key granularity per the plan (§1).
        local _, wrapped = font:getWrap(text, eff)
        lines = wrapped
        if #lines == 0 then lines = { "" } end
    end

    local widest = 0
    for i = 1, #lines do
        local lw = font:getWidth(lines[i])
        if lw > widest then widest = lw end
    end
    local lineHeight = font:getHeight()

    entry = {
        width  = widest,
        height = lineHeight * #lines, -- clay.h:2635: height = lineHeight * #lines
        lines  = #lines,
        gen    = gen,
    }
    cache[key] = entry
    cacheCount = cacheCount + 1
    return entry
end

--- Convenience: natural (unwrapped) single-pass measurement.
function measure.natural(text, font, opts)
    return measure.get(text, font, 1e9, opts)
end

return measure
