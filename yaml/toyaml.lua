local function colorToYaml(c)
    if not c then return nil end
    -- Check if it's a color object with hex method, otherwise use raw values
    if type(c) == "table" then
        if c.toHex then return c:toHex() end
        -- Normalise to 0-255 for readability
        local r = c[1] or 0
        local g = c[2] or 0
        local b = c[3] or 0
        local a = c[4]
        if r <= 1 and g <= 1 and b <= 1 then
            r, g, b = math.floor(r*255), math.floor(g*255), math.floor(b*255)
            if a then a = math.floor(a*255) end
        end
        if a and a < 255 then
            return string.format("[%d, %d, %d, %d]", r, g, b, a)
        end
        return string.format("[%d, %d, %d]", r, g, b)
    end
    return nil
end

local function dualDimToYaml(obj)
    local dd = obj.dualDim
    local fields = {}
    local op = dd.offset.pos
    local os = dd.offset.size
    local sp = dd.scale.pos
    local ss = dd.scale.size

    if op.x ~= 0 then fields[#fields+1] = {"x", op.x} end
    if op.y ~= 0 then fields[#fields+1] = {"y", op.y} end
    if os.x ~= 0 then fields[#fields+1] = {"w", os.x} end
    if os.y ~= 0 then fields[#fields+1] = {"h", os.y} end
    if sp.x ~= 0 then fields[#fields+1] = {"sx", sp.x} end
    if sp.y ~= 0 then fields[#fields+1] = {"sy", sp.y} end
    if ss.x ~= 0 then fields[#fields+1] = {"sw", ss.x} end
    if ss.y ~= 0 then fields[#fields+1] = {"sh", ss.y} end
    return fields
end

local bit = require("bit")
local band = bit.band
local frame, image, text, box, video, button, anim = 0, 1, 2, 4, 8, 16, 32

local function resolveTypeName(typ)
    -- Match in specificity order (combined types first)
    if typ == text + box    then return "textbox"      end
    if typ == text + button then return "button"       end
    if typ == text + frame  then return "label"        end
    if typ == image + frame then return "image"        end
    -- image+button uses frame internally in this lib
    -- (newImageButton sets type = image+frame but adds cursor behaviour)
    -- We detect image buttons by checking for cursor handler presence;
    -- as a fallback we use "image" and the loader will still reconstruct it.
    if band(typ, video) == video then return "video"   end
    if band(typ, image) == image then return "image"   end
    if typ == frame             then return "frame"    end
    return "frame"  -- safe fallback
end

local alignNames = {[0]="center", [1]="left", [2]="right"}
local formNames  = {
    [1] = "rectangle",
    [2] = "circle",
    [3] = "arc",
}

-- YAML emitter — produces clean, human-readable YAML without a library dep.
local function emit(val, indent, visited)
    indent  = indent  or 0
    visited = visited or {}
    local pad = string.rep("  ", indent)
    local t   = type(val)

    if t == "boolean" then return tostring(val) end
    if t == "number"  then
        -- Avoid scientific notation for small floats
        if val == math.floor(val) then return string.format("%d", val) end
        return string.format("%.6g", val)
    end
    if t == "string" then
        -- Quote if contains special YAML chars or is empty
        if val == "" or val:match("^[%s#&*!|>'\"%[%]{},?:-]") or val:match("[\n\r]") then
            -- Escape inner quotes, wrap in double quotes
            return '"' .. val:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
        end
        return val
    end
    if t ~= "table" then return tostring(val) end

    -- Cycle guard
    if visited[val] then return '"<cycle>"' end
    visited[val] = true

    -- Detect plain array (sequential integer keys starting at 1)
    local isArray = true
    local maxN    = 0
    for k, _ in pairs(val) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
            isArray = false
            break
        end
        if k > maxN then maxN = k end
    end
    if isArray and maxN ~= #val then isArray = false end

    local lines = {}

    if isArray then
        -- Inline short numeric/string arrays on one line
        local allScalar = true
        for _, v in ipairs(val) do
            if type(v) == "table" then allScalar = false; break end
        end
        if allScalar and #val <= 6 then
            local parts = {}
            for _, v in ipairs(val) do parts[#parts+1] = emit(v, 0, visited) end
            visited[val] = nil
            return "[" .. table.concat(parts, ", ") .. "]"
        end
        for _, v in ipairs(val) do
            local rendered = emit(v, indent + 1, visited)
            if type(v) == "table" then
                lines[#lines+1] = pad .. "-\n" .. rendered
            else
                lines[#lines+1] = pad .. "- " .. rendered
            end
        end
    else
        for _, pair in ipairs(val) do
            local k, v = pair[1], pair[2]
            local rendered = emit(v, indent + 1, visited)
            if type(v) == "table" and #v > 0 and type(v[1]) == "table" then
                -- Nested block (list of pairs = mapping, or list of items)
                lines[#lines+1] = pad .. k .. ":\n" .. rendered
            elseif type(v) == "table" and type(v[1]) ~= "table" then
                -- Inline array
                lines[#lines+1] = pad .. k .. ": " .. rendered
            else
                lines[#lines+1] = pad .. k .. ": " .. rendered
            end
        end
    end

    visited[val] = nil
    return table.concat(lines, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main export function
-- ─────────────────────────────────────────────────────────────────────────────

local function guiToYaml(obj, opts)
    --[[
    opts = {
        indent         = 0,       -- starting indent level
        skipDefaults   = true,    -- omit fields that equal their default values
        includeChildren = true,   -- recurse into children
        eventNames     = {},      -- map of connection object -> string name
                                  -- e.g. {[obj.OnPressed] = "handlePress"}
    }
    --]]
    opts = opts or {}
    local skipDef   = opts.skipDefaults    ~= false  -- default true
    local inclChild = opts.includeChildren ~= false  -- default true
    local indent    = opts.indent          or 0
    local evNames   = opts.eventNames      or {}

    -- Ordered list of {key, value} pairs — order controls YAML output order
    local fields = {}
    local function add(k, v)
        if v == nil then return end
        if skipDef then
            -- Skip booleans that match common defaults
            if k == "visible"       and v == true  then return end
            if k == "active"        and v == true  then return end
            if k == "visibility"    and v == 1     then return end
            if k == "draw-border"   and v == true  then return end
            if k == "rotation"      and v == 0     then return end
            if k == "align"         and v == "left" then return end
            if k == "text-visibility" and v == 1   then return end
            if k == "image-visibility" and v == 1  then return end
            if k == "video-visibility" and v == 1  then return end
            if k == "scale-x"       and v == 1     then return end
            if k == "scale-y"       and v == 1     then return end
        end
        fields[#fields+1] = {k, v}
    end

    -- ── Type ──────────────────────────────────────────────────────────
    add("type", resolveTypeName(obj.type))

    -- ── Dual dimensions ───────────────────────────────────────────────
    for _, pair in ipairs(dualDimToYaml(obj)) do
        add(pair[1], pair[2])
    end

    -- ── Shared appearance ─────────────────────────────────────────────
    local col = colorToYaml(obj.color)
    if col and col ~= "[142, 141, 141]" then   -- skip library default grey
        add("color", col)
    end
    local bcol = colorToYaml(obj.borderColor)
    if bcol and bcol ~= "[0, 0, 0]" then
        add("border-color", bcol)
    end
    add("draw-border",  obj.drawBorder)
    add("visible",      obj.visible)
    add("active",       obj.active)
    if obj.visibility ~= 1 then add("visibility", obj.visibility) end
    if obj.rotation   ~= 0 then add("rotation",   obj.rotation)   end

    -- ── Tag / tags ────────────────────────────────────────────────────
    if obj.__tag then add("tag", obj.__tag) end
    if obj.tags  then
        local tagList = {}
        for t, _ in pairs(obj.tags) do tagList[#tagList+1] = t end
        if #tagList > 0 then add("tags", tagList) end
    end

    -- ── Form factor ───────────────────────────────────────────────────
    local ff = obj.formFactor or 1
    if ff ~= 1 then   -- skip default "rectangle"
        add("form", formNames[ff] or "rectangle")
        if obj.__radius   then add("radius",      obj.__radius)   end
        if obj.segments   then add("segments",    obj.segments)   end
        if ff == 3 then
            add("arc-type",     obj.arcType or "open")
            add("angle-start",  obj.__angleS)
            add("angle-end",    obj.__angleE)
        end
    end

    -- ── Roundness ─────────────────────────────────────────────────────
    if obj.roundness then
        local r = obj.roundness
        if r == true then
            -- generic — emit the rx/ry/segments triple
            add("roundness", {obj.__rx or 5, obj.__ry or 5, obj.__segments or 30})
        elseif type(r) == "string" then
            add("roundness", r)         -- "top" or "bottom"
        end
    end

    -- ── Behaviour flags ───────────────────────────────────────────────
    if obj.clipDescendants then add("clip-descendants", true) end
    if obj.square          then add("square", obj.square)     end

    -- ── Text-type fields ──────────────────────────────────────────────
    if band(obj.type, text) == text then
        if obj.text and obj.text ~= "" then add("text", obj.text) end

        local al = alignNames[obj.align]
        add("align", al)

        local tc = colorToYaml(obj.textColor)
        if tc and tc ~= "[0, 0, 0]" then add("text-color", tc) end
        if obj.textVisibility ~= 1  then add("text-visibility", obj.textVisibility) end

        if obj.textScaleX ~= 1 or obj.textScaleY ~= 1 then
            add("text-scale", {obj.textScaleX, obj.textScaleY})
        end
        if obj.textOffsetX ~= 0 or obj.textOffsetY ~= 0 then
            add("text-offset", {obj.textOffsetX, obj.textOffsetY})
        end
        if obj.textShearingFactorX ~= 0 or obj.textShearingFactorY ~= 0 then
            add("text-shear", {obj.textShearingFactorX, obj.textShearingFactorY})
        end

        -- Font: emit as {file, size} when a file path is known
        if obj.font then
            if obj.fontFile then
                add("font", {{"file", obj.fontFile}, {"size", obj.font:getHeight()}})
            else
                add("font", obj.font:getHeight())
            end
        end
    end

    -- ── Image-type fields ─────────────────────────────────────────────
    if band(obj.type, image) == image and band(obj.type, video) ~= video then
        -- Source path is stored via getSource()
        local src = obj:getSource and obj:getSource()
        if src then add("source", src) end

        if obj.scaleX ~= 1  then add("scale-x", obj.scaleX) end
        if obj.scaleY ~= 1  then add("scale-y", obj.scaleY) end

        local ic = colorToYaml(obj.imageColor)
        if ic and ic ~= "[255, 255, 255]" then add("image-color", ic) end
        if obj.imageVisibility and obj.imageVisibility ~= 1 then
            add("image-visibility", obj.imageVisibility)
        end
    end

    -- ── Video-type fields ─────────────────────────────────────────────
    if band(obj.type, video) == video then
        local src = obj:getSource and obj:getSource()
        if src then add("source", src) end

        local vc = colorToYaml(obj.videoColor)
        if vc and vc ~= "[255, 255, 255]" then add("video-color", vc) end
        if obj.videoVisibility and obj.videoVisibility ~= 1 then
            add("video-visibility", obj.videoVisibility)
        end
        if obj.audiosource then
            add("volume", obj.audiosource:getVolume())
        end
        if obj.playing then add("autoplay", true) end
    end

    -- ── Events ────────────────────────────────────────────────────────
    -- We can only serialise events when the caller supplies a name map.
    -- Otherwise we silently skip them (can't decompile closures).
    local connMap = {
        ["on-pressed"]          = obj.OnPressed,
        ["on-released"]         = obj.OnReleased,
        ["on-released-outer"]   = obj.OnReleasedOuter,
        ["on-pressed-outer"]    = obj.OnPressedOuter,
        ["on-enter"]            = obj.OnEnter,
        ["on-exit"]             = obj.OnExit,
        ["on-moved"]            = obj.OnMoved,
        ["on-drag-start"]       = obj.OnDragStart,
        ["on-dragging"]         = obj.OnDragging,
        ["on-drag-end"]         = obj.OnDragEnd,
        ["on-wheel"]            = obj.OnWheelMoved,
        ["on-size-changed"]     = obj.OnSizeChanged,
        ["on-position-changed"] = obj.OnPositionChanged,
        ["on-destroy"]          = obj.OnDestroy,
        ["on-load"]             = obj.OnLoad,
        ["on-return"]           = obj.OnReturn,
    }
    for yamlKey, conn in pairs(connMap) do
        if conn and evNames[conn] then
            add(yamlKey, evNames[conn])
        end
    end

    -- ── Children ──────────────────────────────────────────────────────
    if inclChild and obj.children and #obj.children > 0 then
        local childDefs = {}
        for _, child in ipairs(obj.children) do
            -- Recurse, collect as ordered-pair tables for the emitter
            local childFields = guiToYaml(child, {
                skipDefaults    = opts.skipDefaults,
                includeChildren = opts.includeChildren,
                eventNames      = opts.eventNames,
                _returnRaw      = true,   -- internal: return fields table, not string
            })
            childDefs[#childDefs+1] = childFields
        end
        fields[#fields+1] = {"children", childDefs}
    end

    -- Internal mode: return the raw ordered-pair table for parent to embed
    if opts._returnRaw then return fields end

    return emit(fields, indent)
end

return guiToYaml