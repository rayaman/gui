local font = require("gui.core.font")
local utf8 = require("utf8")
local multi, thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local color = require("gui.core.color")
local gif   = require("gui.core.gifloader")
local gui = {}
local updater = multi:newProcessor("UpdateManager", true)
local drawer = multi:newProcessor("DrawManager", true)
local core_conns = multi:newProcessor("gui.events", true)

local bit = require("bit")
local band, bor = bit.band, bit.bor
local cursor_hand = love.mouse.getSystemCursor("hand")
local clips = {}
local max, min, abs, rad, floor, ceil = math.max, math.min, math.abs, math.rad,
                                        math.floor, math.ceil
local frame, image, text, box, video, button, anim = 0, 1, 2, 4, 8, 16, 32
local global_drag
local object_focus = gui

local white = color.new("#ffffff")
local black = color.new("#000000")
local highlighter_blue = color.new("#30C5FF")
local DEFAULT_COLOR = {.6, .6, .6}

local CONNECTOR_TYPE = multi.registerType("connector", "connections")

-- Types
gui.TYPE_FRAME      = frame
gui.TYPE_IMAGE      = image
gui.TYPE_TEXT       = text
gui.TYPE_BOX        = box
gui.TYPE_VIDEO      = video
gui.TYPE_BUTTON     = button
gui.TYPE_ANIM       = anim

-- Form Factor
gui.FORM_RECTANGLE = 1
gui.FORM_CIRCLE = 2
gui.FORM_ARC = 3

-- Variables

gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

gui.ALIGN_CENTER = 0
gui.ALIGN_LEFT = 1
gui.ALIGN_RIGHT = 2
gui.ALIGN_JUSTIFY = 3

-- Connections
gui.Events = {} -- We are using fastmode for all connection objects.
gui.Events.OnQuit = core_conns:newConnection()
gui.Events.OnDirectoryDropped = core_conns:newConnection()
gui.Events.OnDisplayRotated = core_conns:newConnection()
gui.Events.OnFilesDropped = core_conns:newConnection()
gui.Events.OnFocus = core_conns:newConnection()
gui.Events.OnMouseFocus = core_conns:newConnection()
gui.Events.OnResized = core_conns:newConnection()
gui.Events.OnVisible = core_conns:newConnection()
gui.Events.OnKeyPressed = core_conns:newConnection()
gui.Events.OnKeyReleased = core_conns:newConnection()
gui.Events.OnTextEdited = core_conns:newConnection()
gui.Events.OnTextInputed = core_conns:newConnection()
gui.Events.OnMouseMoved = core_conns:newConnection()
gui.Events.OnMousePressed = core_conns:newConnection()
gui.Events.OnMouseReleased = core_conns:newConnection()
gui.Events.OnWheelMoved = core_conns:newConnection()
gui.Events.OnTouchMoved = core_conns:newConnection()
gui.Events.OnTouchPressed = core_conns:newConnection()
gui.Events.OnTouchReleased = core_conns:newConnection()

-- Joysticks and gamepads
gui.Events.OnGamepadPressed = core_conns:newConnection()
gui.Events.OnGamepadReleased = core_conns:newConnection()
gui.Events.OnGamepadAxis = core_conns:newConnection()
gui.Events.OnJoystickAdded = core_conns:newConnection()
gui.Events.OnJoystickHat = core_conns:newConnection()
gui.Events.OnJoystickPressed = core_conns:newConnection()
gui.Events.OnJoystickReleased = core_conns:newConnection()
gui.Events.OnJoystickRemoved = core_conns:newConnection()

-- Internal Connections
gui.Events.OnCreated = core_conns:newConnection()
gui.Events.OnObjectFocusChanged = core_conns:newConnection()

gui.Events.OnUpdate = core_conns:newConnection()

-- Virtual gui init
gui.virtual = {}

-- Hooks

local function Hook(funcname, func)
    if love[funcname] then
        local cache = love[funcname]
        love[funcname] = function(...)
            cache(...)
            func({}, ...)
        end
    else
        love[funcname] = function(...) func({}, ...) end
    end
end

-- Incase you define one of these methods, we need to process this after that
updater:newTask(function()
    -- System
    Hook("quit", gui.Events.OnQuit.Fire)
    Hook("directorydropped", gui.Events.OnDirectoryDropped.Fire)
    Hook("displayrotated", gui.Events.OnDisplayRotated.Fire)
    Hook("filedropped", gui.Events.OnFilesDropped.Fire)
    Hook("focus", gui.Events.OnFocus.Fire)
    Hook("resize", updater:newFunction(function(...)
        thread.skip(2)
        gui.Events.OnResized.Fire(...)
    end))
    Hook("visible", gui.Events.OnVisible.Fire)

    -- Mouse
    Hook("mousefocus", gui.Events.OnMouseFocus.Fire)
    Hook("keypressed", gui.Events.OnKeyPressed.Fire)
    Hook("keyreleased", gui.Events.OnKeyReleased.Fire)
    Hook("mousemoved", gui.Events.OnMouseMoved.Fire)
    Hook("mousepressed", gui.Events.OnMousePressed.Fire)
    Hook("mousereleased", gui.Events.OnMouseReleased.Fire)
    Hook("wheelmoved", gui.Events.OnWheelMoved.Fire)

    -- Keyboard
    Hook("textedited", gui.Events.OnTextEdited.Fire)
    Hook("textinput", gui.Events.OnTextInputed.Fire)

    -- Touchscreen
    Hook("touchmoved", gui.Events.OnTouchMoved.Fire)
    Hook("touchpressed", gui.Events.OnTouchPressed.Fire)
    Hook("touchreleased", gui.Events.OnTouchReleased.Fire)

    -- Joystick/Gamepad
    Hook("gamepadpressed", gui.Events.OnGamepadPressed.Fire)
    Hook("gamepadaxis", gui.Events.OnGamepadAxis.Fire)
    Hook("gamepadreleased", gui.Events.OnGamepadReleased.Fire)
    Hook("joystickpressed", gui.Events.OnJoystickPressed.Fire)
    Hook("joystickreleased", gui.Events.OnJoystickReleased.Fire)
    Hook("joystickhat", gui.Events.OnJoystickHat.Fire)
    Hook("joystickremoved", gui.Events.OnJoystickRemoved.Fire)
    Hook("joystickadded", gui.Events.OnJoystickAdded.Fire)
end)


-- Hotkeys

local has_hotkey = false
local hot_keys = {}

-- Wait for keys to release to reset
local unPress = updater:newFunction(function(keys)
    local check = function()
        for key = 1, #keys["Keys"] do
            if not love.keyboard.isDown(keys["Keys"][key]) then
                keys.isBusy = false
                return true
            end
        end
    end
    thread.hold(check)
end)

updater:newThread("GUI Hotkey Manager", function()
    local check = function() return has_hotkey end
    while true do
        thread.hold(check)
        for i = 1, #hot_keys do
            local good = true
            for key = 1, #hot_keys[i]["Keys"] do
                if not love.keyboard.isDown(hot_keys[i]["Keys"][key]) then
                    good = false
                    break
                end
            end
            if good and not hot_keys[i].isBusy then
                hot_keys[i]["Connection"]:Fire(hot_keys[i]["Ref"])
                hot_keys[i].isBusy = true
                unPress(hot_keys[i])
            end
        end
        thread.sleep(.001)
    end
end)

function gui:setHotKey(keys, conn)
    has_hotkey = true
    local conn = conn or updater:newConnection()
    table.insert(hot_keys,
                 {Ref = self, Connection = conn, Keys = {unpack(keys)}})
    return conn
end

-- Default HotKeys
gui.HotKeys = {}

-- Connections can be added together to create an OR logic to them, they can be multiplied together to create an AND logic to them
gui.HotKeys.OnSelectAll = 	gui:setHotKey({"lctrl", "a"}) +
                        	gui:setHotKey({"rctrl", "a"})

gui.HotKeys.OnCopy = 		gui:setHotKey({"lctrl", "c"}) +
                         	gui:setHotKey({"rctrl", "c"})

gui.HotKeys.OnPaste =		gui:setHotKey({"lctrl", "v"}) +
                        	gui:setHotKey({"rctrl", "v"})

gui.HotKeys.OnCut =			gui:setHotKey({"lctrl", "x"}) +
                    		gui:setHotKey({"rctrl", "x"})

gui.HotKeys.OnUndo =		gui:setHotKey({"lctrl", "z"}) +
                    		gui:setHotKey({"rctrl", "z"})

gui.HotKeys.OnRedo =		gui:setHotKey({"lctrl", "y"}) +
							gui:setHotKey({"rctrl", "y"}) +
							gui:setHotKey({"lctrl", "lshift", "z"}) +
							gui:setHotKey({"rctrl", "lshift", "z"}) +
							gui:setHotKey({"lctrl", "rshift", "z"}) +
							gui:setHotKey({"rctrl", "rshift", "z"})

-- Utils

function gui:addConnection(conn)
    self.connections = self.connections or {}
    table.insert(self.connections, conn)
    return conn
end

function gui:noOf(sx,sy,sw,sh)
    if type(self) == "number" then -- gui.noOf
        return nil,nil,nil,nil,self,sx,sy,sw
    else
        return nil,nil,nil,nil,sx,sy,sw,sh
    end
end

--[[
C_ prefix = connect function to a connection
I_ prefix = invoke function args should be wrapped in a table
]]

local function handleFunction(object,field,value)
    if type(value) ~= "table" then return end
    object[field](object,unpack(value))
end

function gui.apply(apply, ...)
    for field, value in pairs(apply) do
        for _, object in pairs({...}) do
            local cmd = field:sub(1,2)
            local handle = field:sub(3,-1)
            local tp = type(object[field])
            if cmd == "C_" then
                object[field](object,value)
            elseif cmd == "I_" then
                handleFunction(object,handle,value)
            elseif tp == "table" and object[field].Type == CONNECTOR_TYPE then
                object[field](object,value)
            elseif tp == "function" then
                handleFunction(object,field,value)
            else
                object[field] = value
            end
        end
    end
end

gui.newFunction = updater.newFunction

function gui:getProcessor() return updater end

function gui:getObjectFocus() return object_focus end

function gui:hasType(t) return band(self.type, t) == t end

function gui:move(x, y)
    self.dualDim.offset.pos.x = self.dualDim.offset.pos.x + x
    self.dualDim.offset.pos.y = self.dualDim.offset.pos.y + y
    self.OnPositionChanged:Fire(self, x, y)
end

function gui:size(x,y)
    self.dualDim.offset.size.x = self.dualDim.offset.size.x + x
    self.dualDim.offset.size.y = self.dualDim.offset.size.y + y
    self.OnSizeChanged:Fire(self, x, y)
end

function gui:moveInBounds(dx, dy)
    local x, y, w, h = self:getAbsolutes()
    local x1, y1, w1, h1 = self.parent:getAbsolutes()
    if (x + dx >= x1 or dx > 0) and (x + w + dx <= x1 + w1 or dx < 0) and
        (y + dy >= y1 or dy > 0) and (y + h + dy <= y1 + h1 or dy < 0) then
        self:move(dx, dy)
    end
end

local function intersecpt(x1, y1, x2, y2, x3, y3, x4, y4)

    local x5 = max(x1, x3)
    local y5 = max(y1, y3)
    local x6 = min(x2, x4)
    local y6 = min(y2, y4)

    -- no intersection
    if x5 > x6 or y5 > y6 then
        return 0, 0, 0, 0 -- Return a no
    end

    local x7 = x5
    local y7 = y6
    local x8 = x6
    local y8 = y5

    return x7, y7, abs(x7 - x8), abs(y7 - y8)
end

local function toCoordPoints(x, y, w, h) return x, y, x + w, y + h end

function gui:intersecpt(x, y, w, h)
    local x1, y1, x2, y2 = toCoordPoints(self:getAbsolutes())
    local x3, y3, x4, y4 = toCoordPoints(x, y, w, h)

    return intersecpt(x1, y1, x2, y2, x3, y3, x4, y4)
end

function gui:isDescendantOf(obj)
    local parent = self.parent
    while parent ~= gui and parent ~= nil do
        if parent == obj then return true end
        parent = parent.parent
    end
    return false
end

function gui:getChildren() return self.children end

function gui:offsetToScale()
    local children = self:getAllChildren()
    for i = 1, #children do
        local child = children[i]
        local x, y = child:getAbsolutes()
        local _, __, w, h = child.parent:getAbsolutes()
        local _, __, w, h = child:getAbsolutes()
        local _, __, pw, ph = child.parent:getAbsolutes()
    end
end

function gui:getAbsolutes(transform) -- returns x, y, w, h
    local x, y, w, h
    local dd = self.dualDim
    if transform then
        x, y, w, h = transform((self.parent.w * dd.scaleX) + dd.offsetX + self.parent.x),
                     transform((self.parent.h * dd.scaleY) + dd.offsetY + self.parent.y),
                     transform((self.parent.w * dd.scaleW) + dd.offsetW),
                     transform((self.parent.h * dd.scaleH) + dd.offsetH)
    else
        x, y, w, h = (self.parent.w * dd.scaleX) + dd.offsetX + self.parent.x,
                     (self.parent.h * dd.scaleY) + dd.offsetY + self.parent.y,
                     (self.parent.w * dd.scaleW) + dd.offsetW,
                     (self.parent.h * dd.scaleH) + dd.offsetH
    end
    if self.square == "w" then
        h = w
    elseif self.square == "h" then
        w = h
    end
    return x, y, w, h
end

function gui:getAllChildren(vis)
    local children = self:getChildren()
    local allChildren = {}
    for i, child in ipairs(children) do
        if not (vis) and child.visible == true then
            allChildren[#allChildren + 1] = child
            local grandChildren = child:getAllChildren()
            for j, grandChild in ipairs(grandChildren) do
                allChildren[#allChildren + 1] = grandChild
            end
        end
    end
    return allChildren
end

function gui:newThread(func)
    return updater:newThread("ThreadHandler<" .. self.type .. ">", func, self, thread)
end

function gui:setDualDim(x, y, w, h, sx, sy, sw, sh)
    self:rawSetDualDim(x, y, w, h, sx, sy, sw, sh)
    self.OnSizeChanged:Fire(self, x, y, w, h, sx, sy, sw, sh)
end

function gui:rawSetDualDim(x, y, w, h, sx, sy, sw, sh)
    local dd = self.dualDim
    self.dualDim = self:newDualDim(
        x or dd.offsetX,
        y or dd.offsetY,
        w or dd.offsetW,
        h or dd.offsetH,
        sx or dd.scaleX,
        sy or dd.scaleY,
        sw or dd.scaleW,
        sh or dd.scaleH)
end

local image_cache = {}
function gui:getTile(i, x, y, w, h) -- returns imagedata
	local tw, wh
	if i == nil then return end
	if type(i) == "string" then i = image_cache[i] or i end
    if type(i) == "string" then
        i = love.image.newImageData(i)
		image_cache[i] = i
    elseif type(i) == "userdata" then
        -- do nothing
    elseif self:hasType(image) then
        i, x, y, w, h = self.image, i, x, y, w
    else
        error("getTile invalid args!!! Usage: ImageElement:getTile(x,y,w,h) or gui:getTile(imagedata,x,y,w,h)")
    end
    return i, love.graphics.newQuad(x, y, w, h, i:getWidth(), i:getHeight())
end

function gui:topStack()
    local siblings = self.parent.children
    for i = 1, #siblings do
        if siblings[i] == self then
            table.remove(siblings, i)
            break
        end
    end
    siblings[#siblings + 1] = self
end

function gui:bottomStack()
    local siblings = self.parent.children
    for i = 1, #siblings do
        if siblings[i] == self then
            table.remove(siblings, i)
            break
        end
    end
    table.insert(siblings, 1, self)
end

function gui:canPress(mx, my)
    if not self.visible then return false end
    local x, y, w, h
    local clip = self.__clip
    if clip and clip[1] then
        x, y, w, h = self:intersecpt(clip[2], clip[3], clip[4], clip[5])
    else
        x, y, w, h = self:getAbsolutes()
    end
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function gui:isBeingCovered(mx, my, respect)
    -- if not respect then return false end
    local children = gui:getAllChildren()
    for i = #children, 1, -1 do
        if children[i] == self or not respect then
            return false
        elseif children[i]:canPress(mx, my) and not (children[i] == self) and not (children[i].ignore) then
            return true
        end
    end
    return false
end

function gui:getLocalCords(mx, my)
    x, y, w, h = self:getAbsolutes()
    return mx - x, my - y
end

function gui:setParent(parent)
    local temp = self.parent:getChildren()
    for i = 1, #temp do
        if temp[i] == self then
            table.remove(self.parent.children, i)
            break
        end
    end
    if parent then
        table.insert(parent.children, self)
        self.parent = parent
    end
end

local function processDo(ref,self) ref.Do[1](self) end

function gui:clone(opt)
    --[[
		{
			copyTo: Who to set the parent to
			connections: Do we copy connections? (true/false)
		}
	]]

    local temp
    local u = self:getUniques()
    if self.type == frame then
        temp = gui:newFrame(self:getDualDim())
    elseif self.type == text + box then
        temp = gui:newTextBox(self.text, self:getDualDim())
    elseif self.type == text + button then
        temp = gui:newTextButton(self.text, self:getDualDim())
    elseif self.type == text then
        temp = gui:newTextLabel(self.text, self:getDualDim())
    elseif self.type == image + button then
        temp = gui:newImageButton(u.Do[2], self:getDualDim())
    elseif self.type == image then
        temp = gui:newImageLabel(u.Do[2], self:getDualDim())
    else -- We are dealing with a complex object
        temp = processDo(u,self)
    end

    for i, v in pairs(u) do temp[i] = v end

    local conn
    if opt then
        temp:setParent(opt.copyTo or gui.virtual)
        if opt.connections then
            conn = true
            for i, v in pairs(self) do
                if type(v) == "table" and v.Type == "connector" then
                    -- We want to copy the connection functions from the original object and bind them to the new one
                    if not temp[i] then
                        -- Incase we are dealing with a custom object, create a connection if the custom objects unique declearation didn't
                        temp[i] = updater:newConnection()
                    end
                    temp[i]:Bind(v:getConnections())
                end
            end
        end
    end

    -- This recursively clones and sets the parent to the temp
    for i, v in pairs(self:getChildren()) do
        v:clone({copyTo = temp, connections = conn})
    end

    return temp
end

function gui:isActive()
    return self.active and not self:isDescendantOf(gui.virtual)
end

function gui:isOnScreen()
    return not self:isOffScreen()
end

-- Base get uniques
function gui:getUniques(tab)
    local base = {
        active = self.active,
        visible = self.visible,
        visibility = self.visibility,
        color = self.color,
        borderColor = self.borderColor,
        drawBorder = self.drawborder,
        rotation = self.rotation,
        shader = self.shader
    }

    if tab then for i, v in pairs(tab) do base[i] = tab[i] end end
    return base
end

function gui:setTag(tag)
    self.tags = self.tags or {}
    self.tags[tag] = true
end

function gui:removeTag(tag)
    if self.tags then self.tags[tag] = nil end
end

function gui:hasTag(tag)
    return self.tags and self.tags[tag]
end

function gui:ancestorHasTag(tag)
    local parent = self.parent
    while parent ~= gui and parent ~= nil do
        if parent:hasTag(tag) then return true end
        parent = parent.parent
    end
end

function gui:parentHasTag(tag)
    local parent = self.parent
    while parent do
        if parent.tags and parent.tags[tag] then return true end
        parent = parent.parent
        if parent == gui.virtual or parent == gui then return false end
    end
    return false
end

local function testVisual(c)
    return not(c:hasTag("visual") or c:parentHasTag("visual")) 
end

local extensions = {}

function gui.registerExtension(template)
    table.insert(extensions, template)
end

function gui:extend(c)
    for i,v in pairs(extensions) do
        for key, value in pairs(v) do
            c[key] = value
        end
    end
end

function gui:setColor(key,col)
    if col[4] then
        self.visibility = col[4]
    end
    self[key] = col
end

function gui:isOffScreen()
    local x, y, w, h = self:getAbsolutes()
    return  y + h < 0 or y > gui.h or x + w < 0 or x > gui.w
end

function gui:setRoundness(rx, ry, seg, side)
    self.roundness = side or true
    self.__rx, self.__ry, self.__segments = rx or 5, ry or 5, seg or 30
end

function gui:setRoundnessDirection(hori, vert)
    self.__rhori = hori
    self.__rvert = vert
end

function gui:makeCircle(x, y, r, sx, sy, sr, segments)
    self.formFactor = gui.FORM_CIRCLE
    self.segments = segments
    self.__radius = r
    self:setDualDim(x, y, 2*r, 2*r, sx, sy, sr)
    return self
end

function gui:makeArc(tp, x, y, r, sx, sy, sr, angle1, angle2, segments)
    self.arcType = tp
    self:setDualDim(x, y, 2*r, 2*r, sx, sy, sr)
    self.__angleS = angle1
    self.__angleE = angle2
    self.__radius = r
    self.segments = segments
    self.formFactor = gui.FORM_ARC
    return self
end

function gui:destroy()
    -- Find and remove self from parent's children list
    local children = self.parent and self.parent.children
    if not children then return end

    local foundIdx
    for i, v in ipairs(children) do
        if v == self then
            foundIdx = i
            break
        end
    end
    if not foundIdx then return end

    -- Fire OnDestroy before teardown so listeners still work during the callback
    self.OnDestroy:Fire(self)

    -- Recursively destroy all children first
    for _, child in pairs(self.children) do
        if type(child.destroy) == "function" then
            child:destroy()
        end
    end
    self.children = {}

    -- Disconnect the global connections
    if self.connections then
        for _,conn in pairs(self.connections) do
            conn:Unconnect()
        end
    end

    -- Destroy all connection objects on self (OnPressed, OnReleased, etc.)
    for key, value in pairs(self) do
        if type(value) == "table" and
        value.Type == CONNECTOR_TYPE then
            value:Destroy()
        end
    end

    -- Remove from parent
    table.remove(children, foundIdx)
    self.parent = nil
end

function gui:fullFrame()
    self:setDualDim(0,0,0,0,0,0,1,1)
    return self
end

function gui:removeChildren()
    for _, child in pairs(self.children) do
        if type(child.destroy) == "function" then
            child:destroy()  -- recursive, disconnects gui.Events listeners
        end
    end
    self.children = {}
end
-- shader stuff
function gui:setShader(shader, env)
    if type(shader) == "string" then
        self.shader = love.graphics.newShader(shader)
    elseif type(shader) == "table" then
        self.shader = shader.source
        for i,v in pairs(shader or {}) do
            if i ~= "source" and i ~= "usage" then
                if self[i] then
                    if type(v) == "function" then
                        local data = v(self)
                        self.shader:send(i, data)
                    else
                        self.shader:send(i, self[i])
                    end
                elseif env[i] then
                    if type(v) == "function" then
                        local data = v(env)
                        self.shader:send(i, data)
                    else
                        self.shader:send(i, env[i])
                    end
                else
                    error(i .. " is a required argument!\n\n".. shader.usage())
                end
            end
        end
    else
        self.shader = shader  -- already a compiled love Shader object
    end
    return self
end

function gui:clearShader()
    self.shader = nil
end

function gui:setShaderUniform(name, ...)
    if not self.shader then return end
    if self.shader:hasUniform(name) then
        self.shader:send(name, ...)
    end
end

function gui:shaderTime(b)
    if not b and self.st then
        self.st:Unconnect()
        self.st = false
        return
    end
    if self.st then return end
    self.__shaderTime = 0
    self.st = self:OnUpdate(function(self, dt)
        if not self.shader then return end
        self.__shaderTime = self.__shaderTime + dt
        if self.shader:hasUniform("time") then
            self.shader:send("time", self.__shaderTime)
        end
    end)
end

function gui:testHierarchy(x, y)
    if self.hierarchy then
        return not (global_drag or self:isBeingCovered(x, y, true))
    end
    return true
end

function gui:respectHierarchy(bool) 
    self.hierarchy = bool 
end

function gui:enableDragging(but)
    if not but then
        self.draggable = false
        return
    end
    self.dragbutton = but or self.dragbutton
    self.draggable = true
end

function gui.centerthread(self)
    if self.centerX or self.centerY then
        local x, y, w, h = self:getAbsolutes()
        if self.centerX then
            self:rawSetDualDim(-w / 2, nil, nil, nil, .5)
        end
        if self.centerY then
            self:rawSetDualDim(nil, -h / 2, nil, nil, nil, .5)
        end
    end
end

function gui:centerX(bool)
    self.centerX = bool
    if self.centering then return end
    self.centering = true
    self:OnSizeChanged(self.centerthread)
    self:OnPositionChanged(self.centerthread)
    updater:newLoop(function()
        self:centerthread()
    end)
end


function gui:centerY(bool)
    self.centerY = bool
    if self.centering then return end
    self.centering = true
    self:OnSizeChanged(self.centerthread)
    self:OnPositionChanged(self.centerthread)
    updater:newLoop(self.centerthread)
end

---- Connection Handler
--[[
-- BasicEvents
OnLoad      = updater:newConnection()
OnDestroy   = updater:newConnection()

-- HierarchyEvents
OnPressed   = testVisual .. (testHierarchy .. updater:newConnection())
OnReleased  = testVisual .. (testHierarchy .. updater:newConnection())
OnEnter     = testVisual .. (testHierarchy .. updater:newConnection())
OnMoved     = testVisual .. (testHierarchy .. updater:newConnection())

-- VisualEvents
OnExit              = testVisual .. updater:newConnection()
OnPressedOuter      = testVisual .. updater:newConnection()
OnReleasedOuter     = testVisual .. updater:newConnection()
OnReleasedOther     = testVisual .. updater:newConnection()
OnDragStart         = testVisual .. updater:newConnection()
OnDragging          = testVisual .. updater:newConnection()
OnDragEnd           = testVisual .. updater:newConnection()
OnSizeChanged       = testVisual .. updater:newConnection()
OnPositionChanged   = testVisual .. updater:newConnection()
OnLeftStickUp       = testVisual .. updater:newConnection()
OnLeftStickDown     = testVisual .. updater:newConnection()
OnLeftStickLeft     = testVisual .. updater:newConnection()
OnLeftStickRight    = testVisual .. updater:newConnection()
OnRightStickUp      = testVisual .. updater:newConnection()
OnRightStickDown    = testVisual .. updater:newConnection()
OnRightStickLeft    = testVisual .. updater:newConnection()
OnRightStickRight   = testVisual .. updater:newConnection()
OnFontUpdated       = testVisual .. updater:newConnection()
OnReturn            = testVisual .. updater:newConnection()


OnWheelMoved = testVisual .. (defaultCheck / gui.Events.OnWheelMoved)

OnCreated   = self:isDescendantOf(c) .. updater:newConnection()
]]

local HierarchyEvents = {"Enter", "Moved", "Pressed", "Released"}

local VisualEvents = {"Exit", "PressedOuter", "ReleasedOuter", "ReleasedOther", "DragStart", 
                      "Dragging", "DragEnd", "SizeChanged", "PositionChanged", "LeftStickUp", 
                      "LeftStickDown", "LeftStickLeft", "LeftStickRight", "RightStickUp", 
                      "RightStickDown", "RightStickLeft", "RightStickRight","FontUpdated"}

local BasicEvents = {"Load", "Destroy", "VideoFinished"}

local initEvents = function(self, evnt_type)
    if self.__eventsInit then return end
    self.__eventsInit = true
    local ref1 = gui.Events.OnMouseMoved(function(x, y, dx, dy, istouch)
        if not self:isActive() then return end
        if self:canPress(x, y) or self.dragging then
            self.OnMoved:Fire(self, x, y, dx, dy, istouch)
            if self.entered == false then
                self.OnEnter:Fire(self, x, y)
                self.entered = true
            end
            if self.dragging then
                self.OnDragging:Fire(self, dx, dy, x, y, istouch)
            end
        elseif self.entered then
            self.entered = false
            self.OnExit:Fire(self, x, y)
        end
    end)

    local ref2 = gui.Events.OnMouseReleased(function(x, y, button, istouch, presses)
        self.pressed = false -- we need to handle dragging stopped even if an element is not active
        if self.dragging and button == self.dragbutton then
            self.dragging = false
            global_drag = false
            self.OnDragEnd:Fire(self, x, y, istouch, presses)
        end
        if not self:isActive() then return end
        if self:canPress(x, y) then
            self.OnReleased:Fire(self, x, y, button, istouch, presses)
        elseif self.pressed then
            self.OnReleasedOuter:Fire(self, x, y, button, istouch, presses)
        else
            self.OnReleasedOther:Fire(self, x, y, button, istouch, presses)
        end
    end)

    local ref3 = gui.Events.OnMousePressed(function(x, y, button, istouch, presses)
        if not self:isActive() then return end
        if self:canPress(x, y) or self.dragging then
            self.OnPressed:Fire(self, x, y, button, istouch)
            self.pressed = true

            -- Only change and trigger the event if it is a different object
            if self ~= object_focus then
                gui.Events.OnObjectFocusChanged:Fire(object_focus, self)
                object_focus = self
            end

            if self.draggable and button == self.dragbutton and not self:isBeingCovered(x, y, self.hierarchy) and
                not global_drag then
                self.dragging = true
                global_drag = true
                self.OnDragStart:Fire(self, x, y, button, istouch)
            end
        else
            self.OnPressedOuter:Fire(self, x, y, button, istouch, presses)
        end
    end)

    self:addConnection(ref1)
    self:addConnection(ref2)
    self:addConnection(ref3)
end


function gui:defaultCheck(...)
    if not self:isActive() then return false end
    local x, y = love.mouse.getPosition()
    if self:canPress(x, y) then
        return self, ...
    end
    return false
end

function gui:OnWheelMoved(func)
    initEvents(self)
    self:addConnection(gui.Events.OnWheelMoved(function(obj, ...)
        if obj == self and testVisual(obj) and obj:defaultCheck(x, y) then
            func(obj, ...)
        end
    end))
end

function gui:OnCreated(func)
    self:addConnection(gui.Events.OnCreated(function(obj)
        if obj == self and self.parent:isDescendantOf(self) then
            func(obj)
        end
    end))
end

function gui:OnUpdate(func)
    self:addConnection(gui.Events.OnUpdate(function()
        func(self, love.timer.getDelta())
    end))
end

for _,v in pairs(BasicEvents) do
    gui["_On".. v] = updater:newConnection()
    -- gui["_On".. v](function(...)
    --     local count = #gui["_On".. v]:getConnections()
    --     if count > 1 then
    --         print("Invoking: ".. v .. "Connections: ".. count, ...)
    --     end
    -- end)
    local mt = {
        __call = function(_, self, func)
            initEvents(self, v)
            self:addConnection(gui["_On" .. v](function(obj)
                if obj == self then
                    func(obj)
                end
            end))
        end,
        __index = gui["_On".. v]
    }
    gui["On".. v] = {}
    setmetatable(gui["On".. v], mt)
end

for _,v in pairs(HierarchyEvents) do
    gui["_On".. v] = updater:newConnection()
    -- gui["_On".. v](function(...)
    --     local count = #gui["_On".. v]:getConnections()
    --     if count > 1 then
    --         print("Invoking: ".. v .. "Connections: ".. count, ...)
    --     end
    -- end)
    local mt = {
        __call = function(_, self, func)
            initEvents(self,v)
            self:addConnection(gui["_On".. v](function(obj, x, y, ...)
                if obj == self and testVisual(obj) and obj:testHierarchy(x, y) then
                    func(obj, x, y, ...)
                end
            end))
        end,
        __index = gui["_On".. v]
    }
    gui["On".. v] = {}
    setmetatable(gui["On".. v], mt)
end

for _,v in pairs(VisualEvents) do
    gui["_On".. v] = updater:newConnection()
    -- gui["_On".. v](function(...)
    --     local count = #gui["_On".. v]:getConnections()
    --     if count > 1 then
    --         print("Invoking: ".. v .. "Connections: ".. count, ...)
    --     end
    -- end)
    local mt = {
        __call = function(_, self, func)
            initEvents(self,v)
            self:addConnection(gui["_On".. v](function(obj, ...)
                if testVisual(obj) then
                    func(obj, ...)
                end
            end))
        end,
        __index = gui["_On".. v]
    }
    gui["On".. v] = {}
    setmetatable(gui["On".. v], mt)
end

-- Base Library
function gui:newBase(typ, x, y, w, h, sx, sy, sw, sh, virtual)
    local c = {}
    c.dragbutton = 2
    setmetatable(c, gui)
    c.focus = false
    c.active = true
    c.type = typ
    c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
    c.children = {}
    c.visible = true
    c.visibility = 1
    c.color = DEFAULT_COLOR
    c.borderColor = black
    c.drawBorder = true
    c.rotation = 0
    c.formFactor = gui.FORM_RECTANGLE
    c.dragging = false
    c.entered = false
    c.pressed = false

    -- Add to the parents children table
    if virtual then
        c.parent = gui.virtual
        table.insert(gui.virtual.children, c)
    else
        c.parent = self
        table.insert(self.children, c)
    end

    local a = 0

    if typ == frame then
        gui.Events.OnCreated:Fire(c) -- Trigger frame types instantly
    end

    gui:extend(c, typ)

    return c
end

function gui:newDualDim(x, y, w, h, sx, sy, sw, sh)
    return {
        offsetX = x or 0, offsetY = y or 0,
        offsetW = w or 0, offsetH = h or 0,
        scaleX  = sx or 0, scaleY  = sy or 0,
        scaleW  = sw or 0, scaleH  = sh or 0,
    }
end

function gui:getDualDim()
    local dd = self.dualDim
    return dd.offsetX, dd.offsetY, dd.offsetW, dd.offsetH,
           dd.scaleX, dd.scaleY, dd.scaleW, dd.scaleH
end

-- Frames
function gui:newFrame(x, y, w, h, sx, sy, sw, sh)
    return self:newBase(frame, x, y, w, h, sx, sy, sw, sh)
end

function gui:newVirtualFrame(x, y, w, h, sx, sy, sw, sh)
    return self:newBase(frame, x, y, w, h, sx, sy, sw, sh, true)
end

function gui:newVisualFrame(x, y, w, h, sx, sy, sw, sh)
    local visual = self:newBase(frame, x, y, w, h, sx, sy, sw, sh)
    visual:setTag("visual")
    return visual
end

-- Texts
function gui:newTextBase(typ, txt, x, y, w, h, sx, sy, sw, sh)
    local c = self:newBase(text + typ, x, y, w, h, sx, sy, sw, sh)
    c.text = txt
    c.align = gui.ALIGN_LEFT
    c.adjust = 0
    c.textScaleX = 1
    c.textScaleY = 1
    c.textOffsetX = 0
    c.textOffsetY = 0
    c.textShearingFactorX = 0
    c.textShearingFactorY = 0
    c.textVisibility = 1
    c.font = love.graphics.newFont(12)
    c.textColor = black
    c.OnFontUpdated = updater:newConnection(false, testVisual)

    function c:calculateFontOffset(font, adjust)
        local adjust = adjust or 20
        local x, y, width, height = self:getAbsolutes()
        local top = height + adjust
        local bottom = 0
        local canvas = love.graphics.newCanvas(width, height + adjust)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, .5, false, false)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setFont(font)
        love.graphics.printf(self.text, 0, adjust / 2, width, "left",
                             self.rotation, self.textScaleX, self.textScaleY, 0,
                             0, self.textShearingFactorX,
                             self.textShearingFactorY)
        love.graphics.setCanvas()
        local data = canvas:newImageData()
        local f_top, f_bot = false, false
        for yy = 0, height - 1 do
            for xx = 0, width - 1 do
                local r, g, b, a = data:getPixel(xx, yy)
                if r ~= 0 or g ~= 0 or b ~= 0 then
                    if yy < top and not f_top then
                        top = yy
                        f_top = true
                        break
                    end
                end
            end
        end
        for yy = height - 1, 0, -1 do
            for xx = 0, width - 1 do
                local r, g, b, a = data:getPixel(xx, yy)
                if r ~= 0 or g ~= 0 or b ~= 0 then
                    if yy > bottom and not f_bot then
                        bottom = yy
                        f_bot = false
                        break
                    end
                end
            end
        end
        return top - adjust, bottom - adjust
    end

    local cache = {}
    function c:setFont(font, size)
        local index = tostring(font) .. tostring(size)
        if cache[index] then
            self.font = cache[index]
            return
        end
        if type(font) == "number" then
            self.font = love.graphics.newFont(font)
        elseif type(font) == "string" then
            self.fontFile = font
            self.font = love.graphics.newFont(font, size)
        else
            self.font = font
        end
        cache[index] = font
        self.OnFontUpdated:Fire(self)
    end

    -- something x > 0 
    function c:scaleFont(scale)
        if scale <= 0 then
            error("scale cannot be <= 0")
        end
        self.textScale = scale
    end

    function c:fitFont(minSize, maxSize, opt)
        local _,_,w,h = self:getAbsolutes()
        local sw, sh = love.graphics.getDimensions()
        local index = self.text .. tostring(w) .. tostring(h) .. tostring(sw) .. tostring(sh)
        if cache[index] then
            self:setFont(cache[index][1])
            return unpack(cache[index])
        end
        if opt == nil then
            opt = {scale=1}
        end
        local font
        local x, y, boxWidth, boxHeight = self:getAbsolutes()

        if self.fontFile then
            if self.fontFile:match("ttf") then
                font = function(n)
                    return love.graphics.newFont(self.fontFile, n, "normal")
                end
            else
                font = function(n)
                    return love.graphics.newFont(self.fontFile, n)
                end
            end
        else
            font = function(n) return love.graphics.setNewFont(n) end
        end

        minSize = minSize or 8
        maxSize = maxSize or 200
        
        local bestSize = minSize
        local bestFont
        
        local low = minSize
        local high = maxSize
        local text = self.text
        local mid
        while low <= high do
            mid = math.floor((low + high) / 2)
            local testFont = font(mid)
            local width = testFont:getWidth(text)
            local height = testFont:getHeight()
            
            if width <= boxWidth and height <= boxHeight then
                -- Font fits, try larger
                bestSize = mid
                bestFont = testFont
                low = mid + 1
            else
                -- Font too big, try smaller
                high = mid - 1
            end
        end
        if type(opt) == "table" and opt.scale ~= 0 then
            bestFont = font(mid*opt.scale)
        else
            bestFont = font(mid - 1)
        end
        self:setFont(bestFont)
        cache[index] = {bestFont, bestSize}
        return bestFont, bestSize
    end

    function c:centerFont(b)
        self.centerText = not b
    end

    function c:getUniques()
        return gui.getUniques(c, {
            text = c.text,
            align = c.align,
            textScaleX = c.textScaleX,
            textScaleY = c.textScaleY,
            textOffsetX = c.textOffsetX,
            textOffsetY = c.textOffsetY,
            textShearingFactorX = c.textShearingFactorX,
            textShearingFactorY = c.textShearingFactorY,
            textVisibility = c.textVisibility,
            font = c.font,
            textColor = c.textColor
        })
    end

    return c
end

function gui:newTextArea(initialText, x, y, w, h, sx, sy, sw, sh)
    -- Outer viewport (clips content)
    local viewport = self:newFrame(x, y, w or 0, h or 0, sx, sy, sw, sh)
    viewport.clipDescendants = true
    viewport.color = color.new("#f9f9f9")
    viewport:setRoundness(3, 3)

    -- Inner content frame (scrolled by offsetting its y)
    local content = viewport:newFrame(2, 2, -4, -4, 0, 0, 1, 0)
    content.drawBorder = false
    content.color      = {0, 0, 0, 0}
    content.visibility = 0

    -- Cursor line rendering happens via a separate frame
    local cursorBar = viewport:newFrame(0, 0, 1, 0)
    cursorBar.color      = color.new("#222222")
    cursorBar.drawBorder = false
    cursorBar.ignore     = true
    cursorBar.visibility = 0

    local lines    = {}
    local lineObjs = {}   -- TextLabel per line
    local LINE_H   = 18
    local scrollY  = 0
    local cursorLine = 1
    local cursorCol  = 0
    local blinkOn    = true
    local blinkTimer = 0
    local BLINK_RATE = 0.5
    local focused    = false

    viewport.OnChanged = updater:newConnection()
    viewport.readOnly  = false

    -- Split a string into lines
    local function splitLines(s)
        local result = {}
        local pos = 1
        while true do
            local nl = s:find("\n", pos, true)
            if nl then
                result[#result + 1] = s:sub(pos, nl - 1)
                pos = nl + 1
            else
                result[#result + 1] = s:sub(pos)
                break
            end
        end
        return result
    end

    -- Join lines back to a single string
    local function joinLines()
        return table.concat(lines, "\n")
    end

    -- Rebuild all line label objects
    local function rebuildLabels()
        for _, obj in ipairs(lineObjs) do
            obj:destroy()
        end
        lineObjs = {}

        for i, lineText in ipairs(lines) do
            local lbl = content:newTextLabel(lineText, 0, (i-1)*LINE_H, 0, LINE_H, 0, 0, 1)
            lbl.drawBorder = false
            lbl.color      = {0, 0, 0, 0}
            lbl.visibility = 0
            lbl.textColor  = color.new("#222222")
            lbl.align      = gui.ALIGN_LEFT
            lbl.ignore     = true
            lbl:setFont(13)
            lineObjs[i] = lbl
        end

        -- Resize content frame to fit all lines
        local totalH = #lines * LINE_H + 4
        content:setDualDim(nil, nil, nil, totalH)
    end

    -- Apply vertical scroll so the cursor stays visible
    local function applyScroll()
        local _, _, _, vh = viewport:getAbsolutes()
        local contentH = #lines * LINE_H + 4
        local maxScroll = math.max(0, contentH - vh)
        scrollY = math.max(0, math.min(scrollY, maxScroll))
        content:rawSetDualDim(2, 2 - scrollY)
    end

    local function ensureCursorVisible()
        local _, _, _, vh = viewport:getAbsolutes()
        local cursorY = (cursorLine - 1) * LINE_H
        if cursorY < scrollY then
            scrollY = cursorY
        elseif cursorY + LINE_H > scrollY + vh then
            scrollY = cursorY + LINE_H - vh
        end
        applyScroll()
    end

    -- Update the cursor bar position
    local function updateCursor()
        if not focused then
            cursorBar.visibility = 0
            return
        end
        local ax, ay = viewport:getAbsolutes()
        local lineText = lines[cursorLine] or ""
        local font = love.graphics.newFont(13)
        local cx = 2 + font:getWidth(lineText:sub(1, cursorCol))
        local cy = 2 + (cursorLine - 1) * LINE_H - scrollY
        cursorBar:rawSetDualDim(cx, cy, 1, LINE_H)
        cursorBar.visibility = blinkOn and 1 or 0
    end

    local function setText(s)
        lines = splitLines(s or "")
        if #lines == 0 then lines = {""} end
        rebuildLabels()
        cursorLine = math.min(cursorLine, #lines)
        cursorCol  = math.min(cursorCol, #lines[cursorLine])
        applyScroll()
        updateCursor()
    end

    function viewport:getText()
        return joinLines()
    end

    function viewport:setText(s)
        setText(s)
        self.OnChanged:Fire(self, joinLines())
    end

    function viewport:appendLine(s)
        lines[#lines + 1] = s
        rebuildLabels()
        applyScroll()
    end

    function viewport:scrollToBottom()
        scrollY = math.huge
        applyScroll()
    end

    -- Insert text at cursor
    local function insertText(s)
        if viewport.readOnly then return end
        local line = lines[cursorLine] or ""
        -- Handle newlines in inserted text
        if s == "\n" then
            local before = line:sub(1, cursorCol)
            local after  = line:sub(cursorCol + 1)
            lines[cursorLine] = before
            table.insert(lines, cursorLine + 1, after)
            cursorLine = cursorLine + 1
            cursorCol  = 0
        else
            lines[cursorLine] = line:sub(1, cursorCol) .. s .. line:sub(cursorCol + 1)
            cursorCol = cursorCol + #s
        end
        rebuildLabels()
        ensureCursorVisible()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    local function deleteBack()
        if viewport.readOnly then return end
        if cursorCol > 0 then
            local line = lines[cursorLine]
            lines[cursorLine] = line:sub(1, cursorCol - 1) .. line:sub(cursorCol + 1)
            cursorCol = cursorCol - 1
        elseif cursorLine > 1 then
            -- merge with previous line
            local prevLine = lines[cursorLine - 1]
            cursorCol = #prevLine
            lines[cursorLine - 1] = prevLine .. lines[cursorLine]
            table.remove(lines, cursorLine)
            cursorLine = cursorLine - 1
        end
        rebuildLabels()
        ensureCursorVisible()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    local function deleteForward()
        if viewport.readOnly then return end
        local line = lines[cursorLine]
        if cursorCol < #line then
            lines[cursorLine] = line:sub(1, cursorCol) .. line:sub(cursorCol + 2)
        elseif cursorLine < #lines then
            lines[cursorLine] = line .. lines[cursorLine + 1]
            table.remove(lines, cursorLine + 1)
        end
        rebuildLabels()
        updateCursor()
        viewport.OnChanged:Fire(viewport, joinLines())
    end

    -- Mouse click to position cursor
    viewport:OnPressed(function(self, mx, my)
        focused = true
        local _, vy = viewport:getAbsolutes()
        local relY = my - vy + scrollY - 2
        cursorLine = math.max(1, math.min(#lines, math.floor(relY / LINE_H) + 1))
        local lineText = lines[cursorLine] or ""
        local font     = love.graphics.newFont(13)
        local _, vx    = viewport:getAbsolutes()
        local relX     = mx - vx - 2
        -- binary-search for cursor column
        local col = 0
        for i = 1, #lineText do
            local w = font:getWidth(lineText:sub(1, i))
            if w > relX then break end
            col = i
        end
        cursorCol = col
        updateCursor()
    end)

    viewport:OnPressedOuter(function()
        focused = false
        updateCursor()
    end)

    -- Keyboard input (only when focused)
    local _textInputRef = gui.Events.OnTextInputed(function(t)
        if not focused then return end
        insertText(t)
    end)

    local _keyPressRef = gui.Events.OnKeyPressed(function(key)
        if not focused then return end
        if key == "return" or key == "kpenter" then
            insertText("\n")
        elseif key == "backspace" then
            deleteBack()
        elseif key == "delete" then
            deleteForward()
        elseif key == "up" then
            cursorLine = math.max(1, cursorLine - 1)
            cursorCol  = math.min(cursorCol, #(lines[cursorLine] or ""))
            ensureCursorVisible(); updateCursor()
        elseif key == "down" then
            cursorLine = math.min(#lines, cursorLine + 1)
            cursorCol  = math.min(cursorCol, #(lines[cursorLine] or ""))
            ensureCursorVisible(); updateCursor()
        elseif key == "left" then
            if cursorCol > 0 then
                cursorCol = cursorCol - 1
            elseif cursorLine > 1 then
                cursorLine = cursorLine - 1
                cursorCol  = #lines[cursorLine]
            end
            ensureCursorVisible(); updateCursor()
        elseif key == "right" then
            local lineLen = #(lines[cursorLine] or "")
            if cursorCol < lineLen then
                cursorCol = cursorCol + 1
            elseif cursorLine < #lines then
                cursorLine = cursorLine + 1
                cursorCol  = 0
            end
            ensureCursorVisible(); updateCursor()
        elseif key == "home" then
            cursorCol = 0; updateCursor()
        elseif key == "end" then
            cursorCol = #(lines[cursorLine] or ""); updateCursor()
        end
    end)

    viewport.OnDestroy(function()
        gui.Events.OnTextInputed:Unconnect(_textInputRef)
        gui.Events.OnKeyPressed:Unconnect(_keyPressRef)
    end)

    -- Scroll wheel
    viewport:OnWheelMoved(function(_, dy)
        scrollY = scrollY - dy * 30
        applyScroll()
        updateCursor()
    end)

    -- Cursor blink
    viewport:OnUpdate(function(self, dt)
        blinkTimer = blinkTimer + dt
        if blinkTimer >= BLINK_RATE then
            blinkTimer = 0
            blinkOn = not blinkOn
            if focused then
                cursorBar.visibility = blinkOn and 1 or 0
            end
        end
    end)

    setText(initialText or "")
    return viewport
end

function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
    local c = self:newTextBase(button, txt, x, y, w, h, sx, sy, sw, sh)
    c:respectHierarchy(true)
    gui.Events.OnCreated:Fire(c)
    return c
end

function gui:newTextLabel(txt, x, y, w, h, sx, sy, sw, sh)
    local c = self:newTextBase(frame, txt, x, y, w, h, sx, sy, sw, sh)
    gui.Events.OnCreated:Fire(c)
    return c
end

-- local val used when drawing

local function getTextPosition(text, self, mx, my, exact)
    -- Initialize variables
    local pos = 0
    local font = love.graphics.getFont()
    local width = 0
    local height = font:getHeight()
    -- Loop through each character in the string
    for i = 1, #text do

        local _w = font:getWidth(text:sub(i, i))
        local x, y, w, h = math.floor(width + self.adjust + self.textOffsetX),
                           0, _w, height

        width = width + _w

        if not (mx > x + w or mx < x or my > y + h or my < y) then
            if not (exact) and
                (_w -
                    (width - (mx - math.floor(self.adjust + self.textOffsetX))) <
                    _w / 2 and i >= 1) then
                return i - 1
            else
                return i
            end
        elseif i == #text and mx > x + w then
            return #text
        end
    end
    return pos
end

local cur = love.mouse.getCursor()
function gui:newTextBox(txt, x, y, w, h, sx, sy, sw, sh)
    local c = self:newTextBase(box, txt, x, y, w, h, sx, sy, sw, sh)
    c:respectHierarchy(true)
    c.doSelection = false
    c.OnReturn = updater:newConnection(false, testVisual)
    c.cur_pos = 0
    c.selection = {0, 0}
    c.blink = true

    function c:getUniques()
        return gui.getUniques(c, {
            doSelection = c.doSelection,
            cur_pos = c.cur_pos,
            adjust = c.adjust
        })
    end

    function c:HasSelection()
        return c.selection[1] ~= 0 and c.selection[2] ~= 0
    end

    function c:GetSelection()
        local start, stop = c.selection[1], c.selection[2]
        if start > stop then start, stop = stop, start end
        return start, stop
    end

    function c:GetSelectedText()
        if not c:HasSelection() then return "" end
        local sta, sto = c.selection[1], c.selection[2]
        if sta > sto then sta, sto = sto, sta end
        return c.text:sub(sta, sto)
    end

    function c:ClearSelection()
        c.doSelection = false
        c.selection = {0, 0}
    end

    c:OnEnter(function()
        love.mouse.setCursor(love.mouse.getSystemCursor("ibeam"))
    end)

    c:OnExit(function() love.mouse.setCursor(cur) end)

    c:OnPressed(function(c, x, y, dx, dy, istouch)
        object_focus.bar_show = true
        c.cur_pos = getTextPosition(c.text, c, c:getLocalCords(x, y))
        c.selection[1] = c.cur_pos
        c.doSelection = true
    end)

    c:OnMoved(function(c, x, y)
        if c.doSelection then
            local xx, yy = c:getLocalCords(x, y)
            c.selection[2] = getTextPosition(c.text, c, xx, yy, true)
        end
    end)

    -- Connect to both events
    local unselect = function(c)
        c.doSelection = false
    end
    c:OnReleased(unselect)
    c:OnReleasedOuter(unselect)

    -- ReleasedOther is different than ReleasedOuter (Other/Outer)
    local doselection = function()
        c.doSelection = false
        c.selection = {0, 0}
    end
    c:OnReleasedOther(doselection)
    c:OnPressedOuter(doselection)

    c:OnPressedOuter(function() c.bar_show = false end)
    gui.Events.OnCreated:Fire(c)
    return c
end

local function textBoxThread()
    updater:newThread("Textbox Handler", function()
        local check = function() return object_focus:hasType(box) and object_focus.blink end
        while true do
            -- Do nothing if we aren't dealing with a textbox
            thread.hold(check)
            local ref = object_focus
            ref.bar_show = true
            thread.sleep(.5)
            ref.bar_show = false
            thread.sleep(.5)
        end
    end).OnError(textBoxThread)
end
textBoxThread()

local function insert(obj, n_text)
    if obj:HasSelection() then
        local start, stop = obj:GetSelection()
        obj.text = obj.text:sub(1, start - 1) .. n_text ..
                       obj.text:sub(stop + 1, -1)
        obj:ClearSelection()
        obj.cur_pos = start
        if #n_text > 1 then obj.cur_pos = start + #n_text end
    else
        obj.text = obj.text:sub(1, obj.cur_pos) .. n_text ..
                       obj.text:sub(obj.cur_pos + 1, -1)
        obj.cur_pos = obj.cur_pos + 1
        if #n_text > 1 then obj.cur_pos = obj.cur_pos + #n_text end
    end
end

local function delete(obj, cmd)
    if obj:HasSelection() then
        local start, stop = obj:GetSelection()
        obj.text = obj.text:sub(1, start - 1) .. obj.text:sub(stop + 1, -1)
        obj:ClearSelection()
        obj.cur_pos = start - 1
    else
        if cmd == "delete" then
            obj.text = obj.text:sub(1, obj.cur_pos) ..
                           obj.text:sub(obj.cur_pos + 2, -1)
        else
            obj.text = obj.text:sub(1, obj.cur_pos - 1) ..
                           obj.text:sub(obj.cur_pos + 1, -1)
            object_focus.cur_pos = object_focus.cur_pos - 1
            if object_focus.cur_pos == 0 then
                object_focus.cur_pos = 1
            end
        end
    end
end

gui.HotKeys.OnSelectAll(function()
    if object_focus:hasType(box) then
        object_focus.selection = {1, #object_focus.text}
    end
end)

gui.Events.OnTextInputed(function(text)
    if object_focus:hasType(box) then insert(object_focus, text) end
end)

gui.HotKeys.OnCopy(function()
    if object_focus:hasType(box) then
        love.system.setClipboardText(object_focus:GetSelectedText())
    end
end)

gui.HotKeys.OnPaste(function()
    if object_focus:hasType(box) then
        insert(object_focus, love.system.getClipboardText())
    end
end)

gui.HotKeys.OnCut(function()
    if object_focus:hasType(box) and object_focus:HasSelection() then
        love.system.setClipboardText(object_focus:GetSelectedText())
        delete(object_focus, "backspace")
    end
end)

gui.Events.OnKeyPressed(function(key, scancode, isrepeat)
    -- Don't process if we aren't dealing with a textbox
    if not object_focus:hasType(box) then return end
    if key == "left" then
        object_focus.cur_pos = object_focus.cur_pos - 1
        object_focus.bar_show = true
    elseif key == "right" then
        object_focus.cur_pos = object_focus.cur_pos + 1
        object_focus.bar_show = true
    elseif key == "return" then
        object_focus.OnReturn:Fire(object_focus, object_focus.text)
    elseif key == "backspace" then
        delete(object_focus, "backspace")
    elseif key == "delete" then
        delete(object_focus, "delete")
    end
end)

-- Images

local load_image = THREAD:newFunction(function(path)
    require("love.image")
    return love.image.newImageData(path)
end)

local load_images = THREAD:newFunction(function(paths)
    require("love.image")
    local images = #paths
    for i = 1, #paths do
        _G.THREAD.pushStatus(i, images, love.image.newImageData(paths[i]))
    end
end)

-- Loads a resource and adds it to the cache
gui.cacheImage = updater:newFunction(function(self, path_or_paths)
    if type(path_or_paths) == "string" then
        -- runs thread to load image then cache it for faster loading
        load_image(path_or_paths):OnReturn(function(img)
            image_cache[path_or_paths] = img
        end)
    -- table of paths
    elseif type(path_or_paths) == "table" then
        local handler = load_images(path_or_paths)
        handler.OnStatus(function(part, whole, img)
            image_cache[path_or_paths[part]] = img
            thread.pushStatus(part, whole, image_cache[path_or_paths[part]])
        end)
    end
end)

function gui:applyGradient(direction, ...)
    local colors = {...}
    if direction == "horizontal" then
        direction = true
    elseif direction == "vertical" then
        direction = false
    else
        error("Invalid direction '" .. tostring(direction) .. "' for gradient.  Horizontal or vertical expected.")
    end
    local result = love.image.newImageData(direction and 1 or #colors, direction and #colors or 1)
    for i, color in ipairs(colors) do
        local x, y
        if direction then
            x, y = 0, i - 1
        else
            x, y = i - 1, 0
        end
        result:setPixel(x, y, color[1], color[2], color[3], color[4] or 255)
    end

    local img = love.graphics.newImage(result)
    img:setFilter('linear', 'linear')
    local x, y, w, h = self:getAbsolutes()
    self.imageColor = white
    self.imageVisibility = 1
    self.image = img
    self.image:setWrap("repeat", "repeat")
    self.imageHeight = img:getHeight()
    self.imageWidth = img:getWidth()
    self.quad = love.graphics.newQuad(0, 0, self.imageWidth, self.imageHeight, self.imageWidth, self.imageHeight)
    
    if not (band(self.type, image) == image) then
        self.type = self.type + image
    end
end

function gui:newImageBase(typ, x, y, w, h, sx, sy, sw, sh)
    local c = self:newBase(image + typ, x, y, w, h, sx, sy, sw, sh)
    c.color = white
    c.visibility = 0
    c.scaleX = 1
    c.scaleY = 1

    local IMAGE

    function c:getUniques()
        return gui.getUniques(c, {
            -- Recreating the image object using set image is the way to go
            DO = {[[setImage]], c.image or IMAGE}
        })
    end

    function c:flip(vert)
        if vert then
            c.scaleY = c.scaleY * -1
        else
            c.scaleX = c.scaleX * -1
        end
    end

    function c:getSource()
        return IMAGE
    end

    local img

    c.setImage = function(self, i, x, y, w, h)
        if i == nil then return end

        if type(i) == "string" and i:match(".gif") then
            img = gif.load(i)

            gif.Updater(img, drawer)
            c:OnDestroy(function()
                img.kill = true -- trigger the gif thread to terminate
            end)

            IMAGE = i
            c.__isGif = true
        elseif type(i) == "string" then
            img = love.image.newImageData(i)
            img = love.graphics.newImage(img)
            IMAGE = i
        end
        
        if type(i) == "string" then i = image_cache[i] or i end

        if i and x then
            c.imageHeight = h
            c.imageWidth = w

            if type(i) == "string" and not c.__isGif then
                image_cache[i] = img
                i = image_cache[i]
            end

            c.image = i
            if not c.__isGif then
                c.image:setWrap("repeat", "repeat")
            end
            c.imageColor = white
            c.quad = love.graphics.newQuad(x, y, w, h, c.image:getWidth(), c.image:getHeight())
            c.imageVisibility = 1

            return
        end
        
        if type(i) == "userdata" and i:type() == "Image" then
            img = i
        end

        local x, y, w, h = c:getAbsolutes()
        c.imageColor = white
        c.imageVisibility = 1
        c.image = img
        if not self.__isGif then 
            c.image:setWrap("repeat", "repeat")
        end
        c.imageHeight = img:getHeight()
        c.imageWidth = img:getWidth()
        c.quad = love.graphics.newQuad(0, 0, c.imageWidth, c.imageHeight, c.imageWidth, c.imageHeight)
    end
    return c
end

function gui:newImageLabel(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(frame, x, y, w, h, sx, sy, sw, sh)
    c:setImage(source)
    gui.Events.OnCreated:Fire(c)
    return c
end

function gui:newImageButton(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(frame, x, y, w, h, sx, sy, sw, sh)
    c:respectHierarchy(true)
    c:setImage(source)
    gui.Events.OnCreated:Fire(c)
    return c
end

-- Video
function gui:newVideo(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(video, x,  y, w, h, sx, sy, sw, sh)
    c.playing = false

    function c:setVideo(v)
        if type(v) == "string" then
            c.video = love.graphics.newVideo(v)
        elseif v then
            c.video = v
        end
        c.audiosource = c.video:getSource()
        if c.audiosource then c.audioLength = c.audiosource:getDuration() end
        c.videoHeigth = c.video:getHeight()
        c.videoWidth = c.video:getWidth()
        c.quad = love.graphics.newQuad(0, 0, w, h, c.videoWidth, c.videoHeigth)
    end

    function c:getDuration()
        return c.audioLength
    end

    function c:getVideo() return self.video end

    if type(source) == "string" then c:setVideo(source) end

    function c:play()
        c.playing = true
        c.video:play()
    end

    function c:setVolume(vol)
        if self.audiosource then self.audiosource:setVolume(vol) end
    end

    function c:pause() c.video:pause() end

    function c:stop()
        c.playing = false
        c.video:pause()
        c.video:rewind()
    end

    function c:rewind() c.video:rewind() end

    function c:seek(n) c.video:seek(n) end

    function c:tell() return c.video:tell() end

    function c:isPlaying() return c.video:isPlaying() end

    updater:newThread("Video Handler",function()

        local testCompletion = function() -- More intensive test
            if c.video:tell() == 0 then
                c.OnVideoFinished:Fire(c)
                return true
            end
        end

        local isplaying = function() -- Less intensive test
            return c.video:isPlaying()
        end

        while true do thread.chain(isplaying, testCompletion) end

    end)

    c.videoVisibility = 1
    c.videoColor = white
    gui.Events.OnCreated:Fire(c)
    return c
end

-- Draw Function

-- local label, image, text, button, box, video, animation (spritesheet)
local drawtypes = {
    [0] = function() end,
    [1] = function(child, x, y, w, h)
        if child.image then
            love.graphics.setColor(child.imageColor[1], child.imageColor[2], child.imageColor[3], child.imageVisibility)
            if child.__isGif then
                if child.scaleX < 0 or child.scaleY < 0 then
                    local sx, sy = child.scaleX, child.scaleY
                    local adjustX, adjustY = child.scaleX * w, child.scaleY * h
                    if sx < 0 and sy < 0 then
                        love.graphics.draw(child.image.frames[child.image.currentFrame], child.quad, x - adjustX, y - adjustY, rad(child.rotation), (w / child.imageWidth) * child.scaleX, (h / child.imageHeight) * child.scaleY)
                    elseif sx < 0 then
                        love.graphics.draw(child.image.frames[child.image.currentFrame], child.quad, x - adjustX, y, rad(child.rotation), (w / child.imageWidth) * child.scaleX, h / child.imageHeight)
                    else
                        love.graphics.draw(child.image.frames[child.image.currentFrame], child.quad, x, y - adjustY, rad(child.rotation), w / child.imageWidth, (h / child.imageHeight) * child.scaleY)
                    end
                else
                    if child.image.frames[child.image.currentFrame] then
                        love.graphics.draw(child.image.frames[child.image.currentFrame], child.quad, x, y, rad(child.rotation), w / child.imageWidth, h / child.imageHeight)
                    end
                end
            else
                if type(child.scaleX) == "number" and child.scaleX < 0 or type(child.scaleY) == "number" and child.scaleY < 0 then
                    local sx, sy = child.scaleX, child.scaleY
                    local adjustX, adjustY = child.scaleX * w, child.scaleY * h
                    if sx < 0 and sy < 0 then
                        love.graphics.draw(child.image, child.quad, x - adjustX, y - adjustY, rad(child.rotation), (w / child.imageWidth) * child.scaleX, (h / child.imageHeight) * child.scaleY)
                    elseif sx < 0 then
                        love.graphics.draw(child.image, child.quad, x - adjustX, y, rad(child.rotation), (w / child.imageWidth) * child.scaleX, h / child.imageHeight)
                    else
                        love.graphics.draw(child.image, child.quad, x, y - adjustY, rad(child.rotation), w / child.imageWidth, (h / child.imageHeight) * child.scaleY)
                    end
                else
                    love.graphics.draw(child.image, child.quad, x, y, rad(child.rotation), w / child.imageWidth, h / child.imageHeight)
                end
            end
        end
    end,
    [2] = function(child, x, y, w, h)
        local mul = 1
        if (child.formFactor == gui.FORM_ARC) or (child.formFactor == gui.FORM_CIRCLE) then
            mul = 2
        end
        if child.textScale then
            child.font = font.set(child.font, math.floor(h*child.textScale))
        end
        if child.centerText then
            local _, wrappedtext = child.font:getWrap(child.text, w*mul)
            local fh = child.font:getHeight()
            child.textOffsetY = (h-(fh*#wrappedtext))/2
        end
        love.graphics.setColor(child.textColor[1], child.textColor[2],
                               child.textColor[3], child.textVisibility)
        love.graphics.setFont(child.font)
        love.graphics.printf(child.text, child.adjust + x + child.textOffsetX,
                             y + child.textOffsetY, w*mul, ({[0]="center","left", "right", "justify"})[child.align], child.rotation,
                             child.textScaleX, child.textScaleY, 0, 0,
                             child.textShearingFactorX,
                             child.textShearingFactorY)
    end,
    [4] = function(child, x, y, w, h)
        if child.bar_show then
            local lw = love.graphics.getLineWidth()
            love.graphics.setLineWidth(1)
            local font = child.font
            local fh = font:getHeight()
            local fw = font:getWidth(child.text:sub(1, child.cur_pos))
            love.graphics.line(child.textOffsetX + child.adjust + x + fw, y + 4,
                               child.textOffsetX + child.adjust + x + fw,
                               y + fh - 2)
            love.graphics.setLineWidth(lw)
        end
        if child:HasSelection() then
            local blue = highlighter_blue
            local start, stop = child.selection[1], child.selection[2]
            if start > stop then start, stop = stop, start end
            local x1, y1 = child.font:getWidth(child.text:sub(1, start - 1)), 0
            local x2, y2 = child.font:getWidth(child.text:sub(1, stop)), h
            love.graphics.setColor(blue[1], blue[2], blue[3], .5)
            draw_factor(child,"fill", x + x1 + child.adjust, y + y1, x2 - x1, y2 - y1)
            --love.graphics.rectangle("fill", x + x1 + child.adjust, y + y1,x2 - x1, y2 - y1)
        end
    end,
    [8] = function(child, x, y, w, h)
        if child.video and child.playing then
            love.graphics.setColor(child.videoColor[1], child.videoColor[2],
                                   child.videoColor[3], child.videoVisibility)
            if w ~= child.imageWidth and h ~= child.imageHeight then
                love.graphics.draw(child.video, x, y, rad(child.rotation),
                                   w / child.videoWidth, h / child.videoHeigth)
            else
                love.graphics.draw(child.video, child.quad, x, y,
                                   rad(child.rotation), w / child.videoWidth,
                                   h / child.videoHeigth)
            end
        end
    end,
    [16] = function(child, x, y, w, h)
        --
    end
}

local draw_factor = function(child, mode, x, y, w, h, rx, ry, as, ae, seg)
    if child.formFactor == gui.FORM_RECTANGLE then
        love.graphics.rectangle(mode, x, y, w, h, rx, ry, seg)
    elseif child.formFactor == gui.FORM_CIRCLE then
        love.graphics.circle(mode, x+child.__radius, y+child.__radius, child.__radius, seg)
    elseif child.formFactor == gui.FORM_ARC then
        love.graphics.arc(mode, child.arcType, x+child.__radius, y+child.__radius, child.__radius, child.__angleS, child.__angleE, seg)
    else
        error("Invalid form factor selected: ".. tostring(child.formFactor))
    end
end

local draw_handler = function(child, no_draw, dt)
    local bg = child.color
    local bbg = child.borderColor
    local ctype = child.type
    local vis = child.visibility
    local x, y, w, h = child:getAbsolutes()
    local roundness = child.roundness
    local rx, ry, segments = child.__rx or 0, child.__ry or 0,
                             child.__segments or child.segments or 0
    child.x = x
    child.y = y
    child.w = w
    child.h = h

    if no_draw then return end

    if child.clipDescendants then
        local children = child:getAllChildren()
        for c = 1, #children do
            local clip = children[c].__clip
            if not clip then
                clip = {false, 0, 0, 0, 0}
                children[c].__clip = clip
            end
            clip[1] = true
            clip[2] = x
            clip[3] = y
            clip[4] = w
            clip[5] = h
        end
    end

    if child.shader then
        if child.shader:hasUniform("size") then
            child.shader:send("size", {w, h})
        end
        if child.shader:hasUniform("position") then
            child.shader:send("position", {x, y})
        end
        love.graphics.setShader(child.shader)
    end

    if child.__clip and child.__clip[1] then
        local clip = child.__clip
        love.graphics.setScissor(clip[2], clip[3], clip[4], clip[5])
    elseif type(roundness) == "string" then
        love.graphics.setScissor(x - 1, y - 2, w + 2, h + 3)
    end

    local drawB = child.drawBorder

    love.graphics.setColor(bg[1], bg[2], bg[3], vis)
    draw_factor(child,"fill", x, y, w, h, rx, ry, nil, nil, segments)

    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(1)

    if drawB then
        love.graphics.setColor(bbg[1], bbg[2], bbg[3], vis)
        draw_factor(child,"line", x, y, w, h, rx, ry, nil, nil, segments)
        if roundness == "top" then
            love.graphics.setColor(bg[1], bg[2], bg[3], vis)
            draw_factor(child,"fill", x, y + ry / 2, w, h - ry / 2 + 1)
            --love.graphics.rectangle("fill", x, y + ry / 2, w, h - ry / 2 + 1)
            love.graphics.setLineStyle("smooth")
            love.graphics.setColor(bbg[1], bbg[2], bbg[3], 1)
            love.graphics.setLineWidth(1)
            love.graphics.line(x, y + ry, x, y + h + 1, x + 1 + w, y + h + 1,
                            x + 1 + w, y + ry)
            love.graphics.line(x, y + h, x + 1 + w, y + h)
        
            love.graphics.setScissor()
            love.graphics.setColor(bbg[1], bbg[2], bbg[3], .6)
            love.graphics.line(x - 1, y + ry / 2 + 2, x - 1, y + h + 2)
            love.graphics.line(x + w + 2, y + ry / 2 + 2, x + w + 2, y + h + 2)
        elseif roundness == "bottom" then
            love.graphics.setColor(bg[1], bg[2], bg[3], vis)
            draw_factor(child,"fill", x, y, w, h - ry + 2)
            --love.graphics.rectangle("fill", x, y, w, h - ry + 2)
            love.graphics.setLineStyle("smooth")
            love.graphics.setColor(bbg[1], bbg[2], bbg[3], 1)
            love.graphics.setLineWidth(2)
            love.graphics.line(x - 1, y + ry + 1, x - 1, y - 1, x + w + 1, y - 1,
                            x + w + 1, y + ry + 1)
            love.graphics.setScissor()
            love.graphics.line(x - 1, y - 1, x + w + 1, y - 1)

            love.graphics.setColor(bbg[1], bbg[2], bbg[3], .6)
            love.graphics.setLineWidth(2)
            love.graphics.line(x - 1, y + 2, x - 1, y + h - 4 - ry / 2)
            love.graphics.line(x + w + 1, y + 2, x + w + 1, y + h - 4 - ry / 2)
        end
    end

    -- Start object specific stuff
    drawtypes[band(ctype, video)](child, x, y, w, h)
    drawtypes[band(ctype, image)](child, x, y, w, h)
    drawtypes[band(ctype, text)](child, x, y, w, h)
    drawtypes[band(ctype, box)](child, x, y, w, h)

    if child.post then child:post() end

    if child.__clip and child.__clip[1] then
        love.graphics.setScissor() -- Remove the scissor
    end

    if child.shader then
        love.graphics.setShader()
    end
end

gui.draw_handler = draw_handler

local function has_blur_ancestor(child)
    local parent = child.parent
    while parent and parent ~= gui and parent ~= gui.virtual do
        if parent.__blur then return parent end
        parent = parent.parent
    end
    return nil
end

local function blur_draw(child, dt)
    local x, y, w, h = child:getAbsolutes()
    child.x = x
    child.y = y
    child.w = w
    child.h = h

    local b = child.__blur
    local pw, ph = math.max(1, math.ceil(w)), math.max(1, math.ceil(h))

    if not b.canvas1
    or b.canvas1:getWidth()  ~= pw
    or b.canvas1:getHeight() ~= ph then
        b.canvas1 = love.graphics.newCanvas(pw, ph)
        b.canvas2 = love.graphics.newCanvas(pw, ph)
    end

    local prevCanvas = love.graphics.getCanvas()
    local prevShader = love.graphics.getShader()
    local pr, pg, pb, pa = love.graphics.getColor()

    -- -------------------------------------------------------
    -- Pass 1: draw the object AND all its descendants onto canvas1
    -- -------------------------------------------------------
    love.graphics.setCanvas(b.canvas1)
    love.graphics.setShader()
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setScissor()

    -- Shift everything into canvas space by offsetting by -x, -y
    love.graphics.push()
    love.graphics.translate(-x, -y)

    -- Draw the parent object itself
    draw_handler(child, nil, dt)

    -- Draw all descendants in order
    local descendants = child:getAllChildren()
    for i = 1, #descendants do
        local desc = descendants[i]
        -- Recalculate absolutes so positions are correct
        local dx, dy, dw, dh = desc:getAbsolutes()
        desc.x = dx
        desc.y = dy
        desc.w = dw
        desc.h = dh
        draw_handler(desc, nil, dt)
    end

    love.graphics.pop()

    -- -------------------------------------------------------
    -- Pass 2: horizontal blur canvas1 → canvas2
    -- -------------------------------------------------------
    b.shader_h:send("size",   {pw, ph})
    b.shader_h:send("radius", b.radius)

    love.graphics.setCanvas(b.canvas2)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(b.shader_h)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(b.canvas1, 0, 0)

    -- -------------------------------------------------------
    -- Pass 3: vertical blur canvas2 → screen
    -- -------------------------------------------------------
    b.shader_v:send("size",   {pw, ph})
    b.shader_v:send("radius", b.radius)

    love.graphics.setCanvas(prevCanvas)
    love.graphics.setShader(b.shader_v)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(b.canvas2, x, y)

    -- Restore state
    love.graphics.setShader(prevShader)
    love.graphics.setColor(pr, pg, pb, pa)
    love.graphics.setScissor()
end

local draw_loop = drawer:newLoop(function(self, dt)
    local children = gui:getAllChildren()
    for i = 1, #children do
        local child = children[i]
        -- Skip if this child belongs to a blur parent
        -- (blur_draw handles drawing it during the canvas capture pass)
        if has_blur_ancestor(child) then
            -- update x/y/w/h so layout still works, but don't draw
            local x, y, w, h = child:getAbsolutes()
            child.x = x
            child.y = y
            child.w = w
            child.h = h
        elseif child.__blur then
            blur_draw(child, dt)
        elseif child.effect then
            child.effect(function() draw_handler(child, nil, dt) end)
        else
            draw_handler(child, nil, dt)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end)
draw_loop:setName("GUI Draw Handler")

drawer:newThread("Draw Handler",function()
    while true do
        thread.sleep(.1)
        local children = gui.virtual:getAllChildren()
        for i = 1, #children do
            local child = children[i]
            draw_handler(child, true, 0)
        end
    end
end)

local processors = {
    updater.run
}

-- Drawing and Updating
gui.draw = drawer.run
gui.update = function(dt)
    for i = 1, #processors do
        processors[i](dt)
    end
end

function gui:newProcessor(name)
    local proc = multi:newProcessor(name or "UnNamedProcess_"..multi.randomString(4), true)
    table.insert(processors, proc.run)
    return proc
end

-- Virtual gui
gui.virtual.type = frame
gui.virtual.children = {}
gui.virtual.dualDim = gui:newDualDim()
gui.virtual.x = 0
gui.virtual.y = 0
setmetatable(gui.virtual, gui)

local w, h = love.graphics.getDimensions()

gui.virtual.dualDim.offsetW = w
gui.virtual.dualDim.offsetH = h
gui.virtual.w = w
gui.virtual.h = h
gui.virtual.parent = gui.virtual

-- Root gui
gui.parent = gui
gui.type = frame
gui.children = {}
gui.dualDim = gui:newDualDim()
gui.x = 0
gui.y = 0

local w, h = love.graphics.getDimensions()
gui.dualDim.offsetW = w
gui.dualDim.offsetH = h
gui.w = w
gui.h = h

function gui:GetSizeAdjustedToAspectRatio(dWidth, dHeight)

    local newHeight = 0
    local newWidth = 0

    if self.g_width / self.g_height > dWidth / dHeight then
        newHeight = dWidth * self.g_height / self.g_width
        newWidth = dWidth
    else
        newWidth = dHeight * self.g_width  / self.g_height
        newHeight = dHeight
    end
    return newWidth, newHeight, (dWidth-newWidth)/2, (dHeight-newHeight)/2
end

--gui.GetSizeAdjustedToAspectRatio = GetSizeAdjustedToAspectRatio

function gui:setAspectSize(w, h)
    if w and h then
        self.g_width, self.g_height = w, h
    else
        self.g_width, self.g_height = 0, 0
    end
end

updater:newThread(function()
    while true do
        thread.yield()
        local w, h = love.graphics.getDimensions()
        if gui.aspect_ratio then
            local nw, nh, xt, yt = gui:GetSizeAdjustedToAspectRatio(w, h)
            gui.x = xt
            gui.y = yt
            gui.dualDim.offsetW = nw
            gui.dualDim.offsetH = nh
            gui.w = nw
            gui.h = nh

            gui.virtual.x = xt
            gui.virtual.y = yt
            gui.virtual.dualDim.offsetW = nw
            gui.virtual.dualDim.offsetH = nh
            gui.virtual.w = nw
            gui.virtual.h = nh
        else
            gui.dualDim.offsetW = w
            gui.dualDim.offsetH = h
            gui.w = w
            gui.h = h

            gui.virtual.dualDim.offsetW = w
            gui.virtual.dualDim.offsetH = h
            gui.virtual.w = w
            gui.virtual.h = h
        end
    end
end)

-- start global updater
updater:newThread(function()
    while true do
        thread.skip(1)
        gui.Events.OnUpdate.Fire()
    end
end)

-- load shaders
files = love.filesystem.getDirectoryItems("gui/shaders")
for i,v in pairs(files) do
    require("gui.shaders."..v:sub(1,-5)).init(gui)
end

return gui
