-- gui_yaml.lua
-- Parses a YAML-like table (pre-parsed by a YAML lib) into GUI elements.
-- Usage: local yaml = require("tinyyaml")  (or lyaml, etc.)
--        local def = yaml.parse(yaml_string)
--        local root = gui_yaml.build(gui, def)

local gui_yaml = {}

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────

local function parseColor(v)
    if type(v) == "string" then
        return require("gui.core.color").new(v)
    elseif type(v) == "table" then
        -- {r, g, b} or {r, g, b, a} — values 0-255 or 0-1
        local r, g, b, a = v[1], v[2], v[3], v[4] or 255
        -- normalise if in 0-255 range
        if r > 1 or g > 1 or b > 1 then
            r, g, b = r/255, g/255, b/255
            if a > 1 then a = a/255 end
        end
        return {r, g, b, a}
    end
    return nil
end

local function parseDualDim(def)
    --[[
    YAML formats accepted:
      pos:  [x, y]          offset
      size: [w, h]          offset
      scale-pos:  [sx, sy]  scale (0-1)
      scale-size: [sw, sh]  scale (0-1)

    Or shorthand flat:
      x, y, w, h, sx, sy, sw, sh
    ]]
    local px = def.x or (def.pos and def.pos[1]) or 0
    local py = def.y or (def.pos and def.pos[2]) or 0
    local pw = def.w or def.width  or (def.size and def.size[1]) or 0
    local ph = def.h or def.height or (def.size and def.size[2]) or 0
    local sx = def.sx or (def["scale-pos"]  and def["scale-pos"][1])  or 0
    local sy = def.sy or (def["scale-pos"]  and def["scale-pos"][2])  or 0
    local sw = def.sw or (def["scale-size"] and def["scale-size"][1]) or 0
    local sh = def.sh or (def["scale-size"] and def["scale-size"][2]) or 0
    return px, py, pw, ph, sx, sy, sw, sh
end

local function applyShared(parent, obj, def)
    -- Color / border
    if def.color        then obj.color       = parseColor(def.color) end
    if def["border-color"] then obj.borderColor = parseColor(def["border-color"]) end
    if def["draw-border"] ~= nil then obj.drawBorder = def["draw-border"] end

    -- Visibility
    if def.visible    ~= nil then obj.visible    = def.visible    end
    if def.active     ~= nil then obj.active     = def.active     end
    if def.visibility ~= nil then obj.visibility = def.visibility end

    -- Rotation
    if def.rotation then obj.rotation = def.rotation end

    -- Tag
    if def.tag then obj:tag(def.tag) end

    -- Tags (multi)
    if def.tags then
        for _, t in ipairs(def.tags) do obj:setTag(t) end
    end

    -- Form factor
    if def.form then
        local f = def.form
        if f == "circle" then
            local x, y, w, h, sx, sy, sw = parseDualDim(def)
            local r = def.radius or (w / 2)
            obj:makeCircle(x, y, r, sx, sy, sw, def.segments)
        elseif f == "arc" then
            local x, y, w, h, sx, sy, sw = parseDualDim(def)
            local r = def.radius or (w / 2)
            obj:makeArc(
                def["arc-type"] or "open",
                x, y, r, sx, sy, sw,
                def["angle-start"] or 0,
                def["angle-end"]   or math.pi * 2,
                def.segments
            )
        end
    end

    -- Roundness
    if def.roundness then
        local r = def.roundness
        if type(r) == "table" then
            obj:setRoundness(r[1], r[2], r[3], r.side)
        elseif type(r) == "string" then
            -- "top" | "bottom" shorthand
            obj:setRoundness(5, 5, 30, r)
        else
            obj:setRoundness(r, r, 30)
        end
    end

    -- Centering
    if def["center-x"] then obj:centerX(def["center-x"]) end
    if def["center-y"] then obj:centerY(def["center-y"]) end

    -- Full frame shorthand
    if def["full-frame"] then obj:fullFrame() end

    -- Square lock
    if def.square then obj.square = def.square end

    -- Dragging
    if def.draggable then
        obj:enableDragging(
            type(def.draggable) == "number" and def.draggable or 1
        )
    end

    -- Hierarchy
    if def["respect-hierarchy"] ~= nil then
        obj:respectHierarchy(def["respect-hierarchy"])
    end

    -- Clip descendants
    if def["clip-descendants"] ~= nil then
        obj.clipDescendants = def["clip-descendants"]
    end

    -- Effects (function reference by name — looked up via _G or a registry)
    if def.effect then
        local fn = type(def.effect) == "function"
            and def.effect
            or  _G[def.effect]
        if fn then obj.effect = fn end
    end

    -- Shader (name → looked up in _G)
    if def.shader then
        obj.shader = type(def.shader) == "userdata"
            and def.shader
            or  _G[def.shader]
    end

    -- Position on stack
    if def.stack then
        if def.stack == "top"    then obj:topStack()    end
        if def.stack == "bottom" then obj:bottomStack() end
    end
end

local function applyEvents(obj, def, env)
    --[[
    Events in YAML can be:
      on-pressed: "myFunction"      -- looks up _G or env
      on-pressed: |
        print("hello")             -- raw Lua string, loaded as chunk
    ]]
    local function resolve(v)
        if type(v) == "function" then return v end
        if type(v) == "string" then
            -- Try global lookup first
            if _G[v] and type(_G[v]) == "function" then return _G[v] end
            -- Otherwise treat as Lua source
            if env then
                return env[v]
            end
        end
    end

    local map = {
        ["on-pressed"]          = "OnPressed",
        ["on-released"]         = "OnReleased",
        ["on-released-outer"]   = "OnReleasedOuter",
        ["on-pressed-outer"]    = "OnPressedOuter",
        ["on-enter"]            = "OnEnter",
        ["on-exit"]             = "OnExit",
        ["on-moved"]            = "OnMoved",
        ["on-drag-start"]       = "OnDragStart",
        ["on-dragging"]         = "OnDragging",
        ["on-drag-end"]         = "OnDragEnd",
        ["on-wheel"]            = "OnWheelMoved",
        ["on-size-changed"]     = "OnSizeChanged",
        ["on-position-changed"] = "OnPositionChanged",
        ["on-destroy"]          = "OnDestroy",
        ["on-load"]             = "OnLoad",
        ["on-return"]           = "OnReturn",  -- textbox only
    }

    for yaml_key, conn_key in pairs(map) do
        if def[yaml_key] and obj[conn_key] then
            local fn = resolve(def[yaml_key])
            if fn then obj[conn_key](fn) end
        end
    end

    -- on-update is special (not a connection)
    if def["on-update"] then
        local fn = resolve(def["on-update"])
        if fn then obj:OnUpdate(fn) end
    end

    -- Hotkeys
    if def.hotkeys then
        for _, hk in ipairs(def.hotkeys) do
            --  {keys: [lctrl, s], action: "mySaveFunction"}
            local fn = resolve(hk.action)
            if fn then obj:setHotKey(hk.keys)(fn) end
        end
    end
end

local function applyTextProps(obj, def)
    if def.text       then obj.text = tostring(def.text) end
    if def["text-color"] then obj.textColor = parseColor(def["text-color"]) end
    if def["text-visibility"] then obj.textVisibility = def["text-visibility"] end
    if def["text-scale"] then
        obj.textScaleX = def["text-scale"][1] or 1
        obj.textScaleY = def["text-scale"][2] or 1
    end
    if def["text-offset"] then
        obj.textOffsetX = def["text-offset"][1] or 0
        obj.textOffsetY = def["text-offset"][2] or 0
    end
    if def["text-shear"] then
        obj.textShearingFactorX = def["text-shear"][1] or 0
        obj.textShearingFactorY = def["text-shear"][2] or 0
    end

    -- Alignment
    local alignMap = {left = 1, center = 0, right = 2}
    if def.align then
        obj.align = alignMap[def.align] or 1
    end

    -- Font
    if def.font then
        local f = def.font
        if type(f) == "number" then
            obj:setFont(f)
        elseif type(f) == "string" then
            obj:setFont(f, def["font-size"])
        elseif type(f) == "table" then
            -- {file: "fonts/roboto.ttf", size: 18}
            obj:setFont(f.file or f[1], f.size or f[2])
        end
    end

    -- fit-font: true | {min: 8, max: 200, scale: 1}
    if def["fit-font"] then
        local ff = def["fit-font"]
        if ff == true then
            obj:fitFont()
        elseif type(ff) == "table" then
            obj:fitFont(ff.min, ff.max, ff.scale and {scale=ff.scale} or nil)
        end
    end

    -- center-font: true | offset
    if def["center-font"] then
        local cf = def["center-font"]
        obj:centerFont(type(cf) == "number" and cf or nil)
    end
end

local function applyImageProps(obj, def)
    -- source: "path/to/image.png"
    -- tile:   [x, y, w, h]   (optional sub-quad)
    if def.source then
        if def.tile then
            local t = def.tile
            obj:setImage(def.source, t[1], t[2], t[3], t[4])
        else
            obj:setImage(def.source)
        end
    end

    if def["scale-x"] then obj.scaleX = def["scale-x"] end
    if def["scale-y"] then obj.scaleY = def["scale-y"] end
    if def["image-color"] then obj.imageColor = parseColor(def["image-color"]) end
    if def["image-visibility"] then obj.imageVisibility = def["image-visibility"] end

    -- flip: "horizontal" | "vertical" | "both"
    if def.flip then
        local fl = def.flip
        if fl == "horizontal" or fl == "both" then obj:flip(false) end
        if fl == "vertical"   or fl == "both" then obj:flip(true)  end
    end

    -- gradient shorthand
    if def.gradient then
        local g = def.gradient
        -- {direction: "vertical", colors: [[r,g,b,a], ...]}
        local colors = {}
        for _, c in ipairs(g.colors) do
            colors[#colors+1] = parseColor(c)
        end
        obj:applyGradient(g.direction or "vertical", table.unpack(colors))
    end
end

local function applyVideoProps(obj, def)
    if def.source  then obj:setVideo(def.source)   end
    if def.volume  then obj:setVolume(def.volume)   end
    if def.autoplay and def.autoplay then obj:play() end
    if def["video-color"]      then obj.videoColor      = parseColor(def["video-color"])  end
    if def["video-visibility"] then obj.videoVisibility = def["video-visibility"]          end
end

-- ─────────────────────────────────────────────
-- Core builder
-- ─────────────────────────────────────────────

local builders  -- forward ref for recursion

builders = {
    ["frame"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newFrame(x,y,w,h,sx,sy,sw,sh)
    end,
    ["virtual-frame"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newVirtualFrame(x,y,w,h,sx,sy,sw,sh)
    end,
    ["visual-frame"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newVisualFrame(x,y,w,h,sx,sy,sw,sh)
    end,
    ["label"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newTextLabel(def.text or "", x,y,w,h,sx,sy,sw,sh)
    end,
    ["button"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newTextButton(def.text or "", x,y,w,h,sx,sy,sw,sh)
    end,
    ["textbox"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newTextBox(def.text or "", x,y,w,h,sx,sy,sw,sh)
    end,
    ["image"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newImageLabel(def.source, x,y,w,h,sx,sy,sw,sh)
    end,
    ["image-button"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newImageButton(def.source, x,y,w,h,sx,sy,sw,sh)
    end,
    ["video"] = function(parent, def)
        local x,y,w,h,sx,sy,sw,sh = parseDualDim(def)
        return parent:newVideo(def.source, x,y,w,h,sx,sy,sw,sh)
    end,
}

local TEXT_TYPES  = {label=true, button=true, textbox=true}
local IMAGE_TYPES = {image=true, ["image-button"]=true}
local VIDEO_TYPES = {video=true}

function gui_yaml.build(parent, def, env)
    --[[
    parent : gui element or gui root
    def    : parsed YAML table (one element)
    env    : optional Lua env table for event string resolution

    Returns the created object (or nil on unknown type).
    ]]
    local typ = def.type
    if not typ then
        error("gui_yaml: element missing 'type' field")
    end

    local builder = builders[typ]
    if not builder then
        error("gui_yaml: unknown element type '" .. tostring(typ) .. "'")
    end

    local obj = builder(parent, def)

    -- Apply shared properties
    applyShared(parent, obj, def)

    -- Apply type-specific properties
    if TEXT_TYPES[typ]  then applyTextProps(obj, def)  end
    if IMAGE_TYPES[typ] then applyImageProps(obj, def) end
    if VIDEO_TYPES[typ] then applyVideoProps(obj, def) end

    -- Events
    applyEvents(obj, def, env)

    -- Recurse into children
    if def.children then
        for _, child_def in ipairs(def.children) do
            gui_yaml.build(obj, child_def, env)
        end
    end

    return obj
end

function gui_yaml.buildMany(parent, defs, env)
    local results = {}
    for _, def in ipairs(defs) do
        results[#results+1] = gui_yaml.build(parent, def, env)
    end
    return results
end

-- Convenience: parse a YAML string and build in one call.
-- Requires a YAML library. Tries tinyyaml, then lyaml.
function gui_yaml.fromString(parent, yaml_str, env)
    local ok, yaml = pcall(require, "gui.yaml.tinyyaml")
    if not ok then
        ok, yaml = pcall(require, "lyaml")
        if not ok then
            error("gui_yaml.fromString: no YAML library found (tried tinyyaml, lyaml)")
        end
    end
    local def = yaml.parse(yaml_str)
    -- Support both single-element and list-of-elements at root
    if def.type then
        return gui_yaml.build(parent, def, env)
    else
        return gui_yaml.buildMany(parent, def, env)
    end
end

return gui_yaml