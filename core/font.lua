-- font.lua
-- font caching utility for Love2D
-- Usage: local font = require("font")
--        font.set("assets/fonts/my_font.ttf", 24)
--        font.set(nil, 16)  -- uses Love2D default font

local font = {}

-- Cache table: keys are "path:size" or "default:size"
local cache = {}

--- Returns a cache key for the given font path and size.
local function cacheKey(path, size)
    return (path or "default") .. ":" .. tostring(size)
end

--- Loads (or retrieves from cache) a font
-- @param path  string|nil  Path to a .ttf/.otf file, or nil for Love2D's default font.
-- @param size  number      Point size of the font (default: 12).
-- @return love.font        The font object that was set.
function font.set(path, size)
    if type(path) == "userdata" then path = nil end
    size = size or 12

    local key = cacheKey(path, size)

    if not cache[key] then
        if path then
            cache[key] = love.graphics.newFont(path, size)
        else
            cache[key] = love.graphics.newFont(size)
        end
    end

    return cache[key]
end

--- Returns a cached font without setting it as active.
-- Useful when you want to measure text or pass fonts around manually.
-- @param path  string|nil
-- @param size  number
-- @return love.font
function font.get(path, size)
    size = size or 12

    local key = cacheKey(path, size)

    if not cache[key] then
        if path then
            cache[key] = love.graphics.newFont(path, size)
        else
            cache[key] = love.graphics.newFont(size)
        end
    end

    return cache[key]
end

--- Removes a specific font from the cache, freeing its memory.
-- @param path  string|nil
-- @param size  number
function font.evict(path, size)
    size = size or 12
    cache[cacheKey(path, size)] = nil
end

--- Clears all cached fonts.
function font.clear()
    cache = {}
end

--- Returns the number of fonts currently cached (handy for debugging).
function font.size()
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    return count
end

return font
