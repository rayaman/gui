local utf8 = require("utf8")
local multi, thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local color = require("gui.core.color")
local gui = {}
local updater = multi:newProcessor("UpdateManager", true)

local drawer = multi:newProcessor("DrawManager", true)

local bit = require("bit")
local band, bor = bit.band, bit.bor
local cursor_hand = love.mouse.getSystemCursor("hand")
local clips = {}
local max, min, abs, rad, floor, ceil = math.max, math.min, math.abs, math.rad,
                                        math.floor, math.ceil
local frame, image, text, box, video, button, anim = 0, 1, 2, 4, 8, 16, 32
local global_drag
local object_focus = gui
local first_loop = false

-- Types
gui.TYPE_FRAME = frame
gui.TYPE_IMAGE = image
gui.TYPE_TEXT = text
gui.TYPE_BOX = box
gui.TYPE_VIDEO = video
gui.TYPE_BUTTON = button
gui.TYPE_ANIM = anim

-- Variables

gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

gui.ALIGN_CENTER = 0
gui.ALIGN_LEFT = 1
gui.ALIGN_RIGHT = 2

-- Connections
gui.Events = {} -- We are using fastmode for all connection objects.
gui.Events.OnQuit = multi:newConnection()
gui.Events.OnDirectoryDropped = multi:newConnection()
gui.Events.OnDisplayRotated = multi:newConnection()
gui.Events.OnFilesDropped = multi:newConnection()
gui.Events.OnFocus = multi:newConnection()
gui.Events.OnMouseFocus = multi:newConnection()
gui.Events.OnResized = multi:newConnection()
gui.Events.OnVisible = multi:newConnection()
gui.Events.OnKeyPressed = multi:newConnection()
gui.Events.OnKeyReleased = multi:newConnection()
gui.Events.OnTextEdited = multi:newConnection()
gui.Events.OnTextInputed = multi:newConnection()
gui.Events.OnMouseMoved = multi:newConnection()
gui.Events.OnMousePressed = multi:newConnection()
gui.Events.OnMouseReleased = multi:newConnection()
gui.Events.OnWheelMoved = multi:newConnection()
gui.Events.OnTouchMoved = multi:newConnection()
gui.Events.OnTouchPressed = multi:newConnection()
gui.Events.OnTouchReleased = multi:newConnection()

-- Non Love Events

gui.Events.OnThemeChanged = multi:newConnection()

-- Virtual gui init
gui.virtual = {}

-- Internal Connections
gui.Events.OnObjectFocusChanged = multi:newConnection()

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

Hook("quit", gui.Events.OnQuit.Fire)
Hook("directorydropped", gui.Events.OnDirectoryDropped.Fire)
Hook("displayrotated", gui.Events.OnDisplayRotated.Fire)
Hook("filedropped", gui.Events.OnFilesDropped.Fire)
Hook("focus", gui.Events.OnFocus.Fire)
Hook("mousefocus", gui.Events.OnMouseFocus.Fire)
Hook("resize", gui.Events.OnResized.Fire)
Hook("visible", gui.Events.OnVisible.Fire)
Hook("keypressed", gui.Events.OnKeyPressed.Fire)
Hook("keyreleased", gui.Events.OnKeyReleased.Fire)
Hook("textedited", gui.Events.OnTextEdited.Fire)
Hook("textinput", gui.Events.OnTextInputed.Fire)
Hook("mousemoved", gui.Events.OnMouseMoved.Fire)
Hook("mousepressed", gui.Events.OnMousePressed.Fire)
Hook("mousereleased", gui.Events.OnMouseReleased.Fire)
Hook("wheelmoved", gui.Events.OnWheelMoved.Fire)
Hook("touchmoved", gui.Events.OnTouchMoved.Fire)
Hook("touchpressed", gui.Events.OnTouchPressed.Fire)
Hook("touchreleased", gui.Events.OnTouchReleased.Fire)

-- Hotkeys

local has_hotkey = false
local hot_keys = {}

-- Wait for keys to release to reset
local unPress = updater:newFunction(function(keys)
    thread.hold(function()
        for key = 1, #keys["Keys"] do
            if not love.keyboard.isDown(keys["Keys"][key]) then
                keys.isBusy = false
                return true
            end
        end
    end)
end)

updater:newThread("GUI Hotkey Manager", function()
    while true do
        thread.hold(function() return has_hotkey end)
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
    local conn = conn or multi:newConnection()
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

gui.newFunction = updater.newFunction

function gui:getProcessor() return updater end

function gui:getObjectFocus() return object_focus end

function gui:hasType(t) return band(self.type, t) == t end

function gui:move(x, y)
    self.dualDim.offset.pos.x = self.dualDim.offset.pos.x + x
    self.dualDim.offset.pos.y = self.dualDim.offset.pos.y + y
    self.OnPositionChanged:Fire(self, x, y)
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
    while parent ~= gui do
        if parent == obj then return true end
        parent = parent.parent
    end
    return false
end

function gui:getChildren() return self.children end

function gui:getAbsolutes() -- returns x, y, w, h
    return (self.parent.w * self.dualDim.scale.pos.x) +
               self.dualDim.offset.pos.x + self.parent.x,
           (self.parent.h * self.dualDim.scale.pos.y) +
               self.dualDim.offset.pos.y + self.parent.y, (self.parent.w *
               self.dualDim.scale.size.x) + self.dualDim.offset.size.x,
           (self.parent.h * self.dualDim.scale.size.y) +
               self.dualDim.offset.size.y
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
    --[[
    dd.offset.pos = {x = x or 0, y = y or 0}
    self.dualDim.offset.size = {x = w or 0, y = h or 0}
    self.dualDim.scale.pos = {x = sx or 0, y = sy or 0}
    self.dualDim.scale.size = {x = sw or 0, y = sh or 0}
    ]]
    self.dualDim = self:newDualDim(
        x or self.dualDim.offset.pos.x, 
        y or self.dualDim.offset.pos.y, 
        w or self.dualDim.offset.size.x, 
        h or self.dualDim.offset.size.y, 
        sx or self.dualDim.scale.pos.x, 
        sy or self.dualDim.scale.pos.y, 
        sw or self.dualDim.scale.size.x, 
        sh or self.dualDim.scale.size.y)
    self.OnSizeChanged:Fire(self, x, y, w, h, sx, sy, sw, sh)
end

function gui:rawSetDualDim(x, y, w, h, sx, sy, sw, sh)
    self.dualDim = self:newDualDim(
        x or self.dualDim.offset.pos.x, 
        y or self.dualDim.offset.pos.y, 
        w or self.dualDim.offset.size.x, 
        h or self.dualDim.offset.size.y, 
        sx or self.dualDim.scale.pos.x, 
        sy or self.dualDim.scale.pos.y, 
        sw or self.dualDim.scale.size.x, 
        sh or self.dualDim.scale.size.y)
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

function gui:OnUpdate(func) -- Not crazy about this approach, will probably rework this
    if type(self) == "function" then func = self end
    mainupdater(function() func(c) end)
end

local mainupdater = updater:newLoop().OnLoop

function gui:canPress(mx, my) -- Get the intersection of the clip area and the self then test with the clip, otherwise test as normal
    local x, y, w, h
    if self.__variables.clip[1] then
        local clip = self.__variables.clip
        x, y, w, h = self:intersecpt(clip[2], clip[3], clip[4], clip[5])
        return mx < x + w and mx > x and my + h < y + h and my + h > y
    else
        x, y, w, h = self:getAbsolutes()
    end
    return not (mx > x + w or mx < x or my > y + h or my < y)
end

function gui:isBeingCovered(mx, my)
    local children = gui:getAllChildren()
    for i = #children, 1, -1 do
        if children[i] == self then
            return false
        elseif children[i]:canPress(mx, my) and not (children[i] == self) and
            not (children[i].ignore) then
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

local function processDo(ref) ref.Do[1]() end

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
        temp = processDo(u)
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
                        temp[i] = multi:newConnection()
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
    return self.active and not (self:isDescendantOf(gui.virtual))
end

function gui:isOnScreen()
    
    return 
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
        rotation = self.rotation
    }

    if tab then for i, v in pairs(tab) do base[i] = tab[i] end end
    return base
end

-- Base Library
function gui:newBase(typ, x, y, w, h, sx, sy, sw, sh, virtual)
    local c = {}
    local buildBackBetter
    local centerX = false
    local centerY = false
    local centering = false
    local dragbutton = 2
    local draggable = false
    local hierarchy = false

    local function testHierarchy(c, x, y, button, istouch, presses)
        if hierarchy then
            return not (global_drag or c:isBeingCovered(x, y))
        end
        return true
    end

    local function defaultCheck(...)
        if not c:isActive() then return false end
        local x, y = love.mouse.getPosition()
        if c:canPress(x, y) then
            return c, ...
        end
        return false
    end
    setmetatable(c, self)
    c.__index = self.__index
    c.__variables = {clip = {false, 0, 0, 0, 0}}
    c.active = true
    c.type = typ
    c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
    c.children = {}
    c.visible = true
    c.visibility = 1
    c.color = {.6, .6, .6}
    c.borderColor = color.black
    c.drawBorder = true
    c.rotation = 0

    c.OnLoad = multi:newConnection()

    c.OnPressed = testHierarchy .. multi:newConnection()
    c.OnPressedOuter = multi:newConnection()
    c.OnReleased = testHierarchy .. multi:newConnection()
    c.OnReleasedOuter = multi:newConnection()
    c.OnReleasedOther = multi:newConnection()

    c.OnDragStart = multi:newConnection()
    c.OnDragging = multi:newConnection()
    c.OnDragEnd = multi:newConnection()

    c.OnEnter = testHierarchy .. multi:newConnection()
    c.OnExit = multi:newConnection()

    c.OnMoved = testHierarchy .. multi:newConnection()
    c.OnWheelMoved = defaultCheck / gui.Events.OnWheelMoved

    c.OnSizeChanged = multi:newConnection()
    c.OnPositionChanged = multi:newConnection()

    local dragging = false
    local entered = false
    local moved = false
    local pressed = false

    gui.Events.OnMouseMoved(function(x, y, dx, dy, istouch)
        if not c:isActive() then return end
        if c:canPress(x, y) then
            c.OnMoved:Fire(c, x, y, dx, dy, istouch)
            if entered == false then
                c.OnEnter:Fire(c, x, y)
                entered = true
            end
            if dragging then
                c.OnDragging:Fire(c, dx, dy, x, y, istouch)
            end
        elseif entered then
            entered = false
            c.OnExit:Fire(c, x, y)
        end
    end)

    gui.Events.OnMouseReleased(function(x, y, button, istouch, presses)
        if not c:isActive() then return end
        if c:canPress(x, y) then
            c.OnReleased:Fire(c, x, y, dx, dy, istouch, presses)
        elseif pressed then
            c.OnReleasedOuter:Fire(c, x, y, button, istouch, presses)
        else
            c.OnReleasedOther:Fire(c, x, y, button, istouch, presses)
        end
        pressed = false
        if dragging and button == dragbutton then
            dragging = false
            global_drag = false
            c.OnDragEnd:Fire(c, dx, dy, x, y, istouch, presses)
        end
    end)

    gui.Events.OnMousePressed(function(x, y, button, istouch, presses)
        if not c:isActive() then return end
        if c:canPress(x, y) then
            c.OnPressed:Fire(c, x, y, dx, dy, istouch)
            pressed = true

            -- Only change and trigger the event if it is a different object
            if c ~= object_focus then
                gui.Events.OnObjectFocusChanged:Fire(object_focus, c)
                object_focus = c
            end

            if draggable and button == dragbutton and not c:isBeingCovered(x, y) and
                not global_drag then
                dragging = true
                global_drag = true
                c.OnDragStart:Fire(c, dx, dy, x, y, istouch)
            end
        else
            c.OnPressedOuter:Fire(c, x, y, button, istouch, presses)
        end
    end)

    function c:setRoundness(rx, ry, seg, side)
        self.roundness = side or true
        self.__rx, self.__ry, self.__segments = rx or 5, ry or 5, seg or 30
    end

    function c:setRoundnessDirection(hori, vert)
        self.__rhori = hori
        self.__rvert = vert
    end

    function c:respectHierarchy(bool) hierarchy = bool end

    local function centerthread()
        if centerX or centerY then
            local x, y, w, h = c:getAbsolutes()
            if centerX then
                c:rawSetDualDim(-w / 2, nil, nil, nil, .5)
            end
            if centerY then
                c:rawSetDualDim(nil, -h / 2, nil, nil, nil, .5)
            end
        end
    end

    function c:enableDragging(but)
        if not but then
            draggable = false
            return
        end
        dragbutton = but or dragbutton
        draggable = true
    end

    function c:centerX(bool)
        centerX = bool
        if centering then return end
        centering = true
        self.OnSizeChanged(centerthread)
        self.OnPositionChanged(centerthread)
        updater:newLoop(centerthread)
    end

    function c:centerY(bool)
        centerY = bool
        if centering then return end
        centering = true
        self.OnSizeChanged(centerthread)
        self.OnPositionChanged(centerthread)
        updater:newLoop(centerthread)
    end

    function c:fullFrame()
        self:setDualDim(0,0,0,0,0,0,1,1)
    end

    -- Add to the parents children table
    if virtual then
        c.parent = gui.virtual
        table.insert(gui.virtual.children, c)
    else
        c.parent = self
        table.insert(self.children, c)
    end
    local a = 0
    return c
end

function gui:newDualDim(x, y, w, h, sx, sy, sw, sh)
    local dd = {}
    dd.offset = {}
    dd.scale = {}
    dd.offset.pos = {x = x or 0, y = y or 0}
    dd.offset.size = {x = w or 0, y = h or 0}
    dd.scale.pos = {x = sx or 0, y = sy or 0}
    dd.scale.size = {x = sw or 0, y = sh or 0}
    return dd
end

function gui:getDualDim()
    local dd = self.dualDim
    return dd.offset.pos.x, dd.offset.pos.y, dd.offset.size.x, dd.offset.size.y,
           dd.scale.pos.x, dd.scale.pos.y, dd.scale.size.x, dd.scale.size.y
end

-- Frames
function gui:newFrame(x, y, w, h, sx, sy, sw, sh)
    return self:newBase(frame, x, y, w, h, sx, sy, sw, sh)
end

function gui:newVirtualFrame(x, y, w, h, sx, sy, sw, sh)
    return self:newBase(frame, x, y, w, h, sx, sy, sw, sh, true)
end
local testIMG
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
    c.textColor = color.black
    c.OnFontUpdated = multi:newConnection()

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

    function c:setFont(font, size)
        if type(font) == "number" then
            self.font = love.graphics.newFont(font)
        elseif type(font) == "string" then
            self.fontFile = font
            self.font = love.graphics.newFont(font, size)
        else
            self.font = font
        end
        self.OnFontUpdated:Fire(self)
    end

    function c:fitFont(min_size, max_size)
        local font
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
        local text = self.text
        local x, y, max_width, max_height = self:getAbsolutes()
        local min_size = min_size or 1
        local max_size = max_size or 100 -- You can adjust the maximum font size as needed
        local tolerance = 0.1
        local f
        while max_size - min_size > tolerance do
            local size = (min_size + max_size) / 2
    
            f = font(size)
            local text_width = f:getWidth(text)
            local text_height = f:getHeight()
    
            if text_width > max_width or text_height > max_height then
                max_size = size
            else
                min_size = size
            end
        end
        self:setFont(f)
        return min_size
    end

    -- function c:fitFont(n, max)
    --     local max = max or math.huge
    --     local font
    --     local isdefault = false
    --     if self.fontFile then
    --         if self.fontFile:match("ttf") then
    --             font = function(n)
    --                 return love.graphics.newFont(self.fontFile, n, "normal")
    --             end
    --         else
    --             font = function(n)
    --                 return love.graphics.newFont(self.fontFile, n)
    --             end
    --         end
    --     else
    --         isdefault = true
    --         font = function(n) return love.graphics.setNewFont(n) end
    --     end
    --     local x, y, width, height = self:getAbsolutes()
    --     local Font, text = self.Font, self.text
    --     local s = 3
    --     Font = font(s)
    --     while height < max and Font:getHeight() < height and Font:getWidth(text) < width do
    --         s = s + 1
    --         Font = font(s)
    --     end
    --     Font = font(s - (4 + (n or 0)))
    --     Font:setFilter("linear", "nearest", 4)
    --     self.font = Font
    --     self.textOffsetY = 0
    --     local top, bottom = self:calculateFontOffset(Font, 0)
    --     self.textOffsetY = floor(((height - bottom) - top) / 2)
    --     self.OnFontUpdated:Fire(self)
    --     return s - (4 + (n or 0))
    -- end

    function c:centerFont()
        local x, y, width, height = self:getAbsolutes()
        local top, bottom = self:calculateFontOffset(self.font, 0)
        self.textOffsetY = floor(((height - bottom) - top) / 2)
        self.OnFontUpdated:Fire(self)
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

function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
    local c = self:newTextBase(button, txt, x, y, w, h, sx, sy, sw, sh)
    c:respectHierarchy(true)

    c.OnEnter(function(c, x, y, dx, dy, istouch)
        love.mouse.setCursor(cursor_hand)
    end)

    c.OnExit(function(c, x, y, dx, dy, istouch) love.mouse.setCursor() end)

    return c
end

function gui:newTextLabel(txt, x, y, w, h, sx, sy, sw, sh)
    return self:newTextBase(frame, txt, x, y, w, h, sx, sy, sw, sh)
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

    c.OnReturn = multi:newConnection()

    c.cur_pos = 0
    c.selection = {0, 0}

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

    c.OnEnter(function(c, x, y, dx, dy, istouch)
        love.mouse.setCursor(love.mouse.getSystemCursor("ibeam"))
    end)

    c.OnExit(function(c, x, y, dx, dy, istouch) love.mouse.setCursor(cur) end)

    c.OnPressed(function(c, x, y, dx, dy, istouch)
        object_focus.bar_show = true
        c.cur_pos = getTextPosition(c.text, c, c:getLocalCords(x, y))
        c.selection[1] = c.cur_pos
        c.doSelection = true
    end)

    c.OnMoved(function(c, x, y, dx, dy, istouch)
        if c.doSelection then
            local xx, yy = c:getLocalCords(x, y)
            c.selection[2] = getTextPosition(c.text, c, xx, yy, true)
        end
    end); -- Needed to keep next line from being treated like a function call

    -- Connect to both events
    (c.OnReleased + c.OnReleasedOuter)(function(c, x, y, dx, dy, istouch)
        c.doSelection = false
    end);

    -- ReleasedOther is different than ReleasedOuter (Other/Outer)
    (c.OnReleasedOther + c.OnPressedOuter)(function()
        c.doSelection = false
        c.selection = {0, 0}
    end)

    c.OnPressedOuter(function() c.bar_show = false end)

    return c
end

local function textBoxThread()
    updater:newThread("Textbox Handler", function()
        while true do
            -- Do nothing if we aren't dealing with a textbox
            thread.hold(function() return object_focus:hasType(box) end)
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

gui.Events.OnObjectFocusChanged(function(prev, new)
    --
end)

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
        sThread.pushStatus(i, images, love.image.newImageData(paths[i]))
    end
end)

-- Loads a resource and adds it to the cache
gui.cacheImage = thread:newFunction(function(self, path_or_paths)
    if type(path_or_paths) == "string" then
        -- runs thread to load image then cache it for faster loading
        load_image(path_or_paths).OnReturn(function(img)
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
    self.imageColor = color.white
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
    c.color = color.white
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

    c.setImage = function(self, i, x, y, w, h)
        if i == nil then return end
        img = love.image.newImageData(i)
        img = love.graphics.newImage(img)
        IMAGE = i
        if type(i) == "string" then i = image_cache[i] or i end

        if i and x then
            c.imageHeight = h
            c.imageWidth = w

            if type(i) == "string" then
                image_cache[i] = img
                i = image_cache[i]
            end

            c.image = i
            c.image:setWrap("repeat", "repeat")
            c.imageColor = color.white
            c.quad = love.graphics.newQuad(x, y, w, h, c.image:getWidth(), c.image:getHeight())
            c.imageVisibility = 1

            return
        end
        
        if type(i) == "userdata" and i:type() == "Image" then
            img = i
        end

        local x, y, w, h = c:getAbsolutes()
        c.imageColor = color.white
        c.imageVisibility = 1
        c.image = img
        c.image:setWrap("repeat", "repeat")
        c.imageHeight = img:getHeight()
        c.imageWidth = img:getWidth()
        c.quad = love.graphics.newQuad(0, 0, c.imageWidth, c.imageHeight, c.imageWidth, c.imageHeight)
    end
    return c
end

function gui:newImageLabel(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(frame, x, y, w, h, sx, sy, sw, sh)
    c:setImage(source)
    return c
end

function gui:newImageButton(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(frame, x, y, w, h, sx, sy, sw, sh)
    c:respectHierarchy(true)
    c:setImage(source)

    c.OnEnter(function(c, x, y, dx, dy, istouch)
        love.mouse.setCursor(cursor_hand)
    end)

    c.OnExit(function(c, x, y, dx, dy, istouch) love.mouse.setCursor() end)

    return c
end

-- Video
function gui:newVideo(source, x, y, w, h, sx, sy, sw, sh)
    local c = self:newImageBase(video, x,  y, w, h, sx, sy, sw, sh)
    c.OnVideoFinished = multi:newConnection()
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

    c:newThread(function(self)

        local testCompletion = function() -- More intensive test
            if self.video:tell() == 0 then
                self.OnVideoFinished:Fire(self)
                return true
            end
        end

        local isplaying = function() -- Less intensive test
            return self.video:isPlaying()
        end

        while true do thread.chain(isplaying, testCompletion) end

    end)

    c.videoVisibility = 1
    c.videoColor = color.white

    return c
end

-- Draw Function

-- local label, image, text, button, box, video, animation (spritesheet)
local drawtypes = {
    [0] = function(child, x, y, w, h) end,
    [1] = function(child, x, y, w, h)
        if child.image then
            if child.scaleX < 0 or child.scaleY < 0 then
                local sx, sy = child.scaleX, child.scaleY
                local adjustX, adjustY = child.scaleX * w, child.scaleY * h
                love.graphics.setColor(child.imageColor[1], child.imageColor[2],
                                    child.imageColor[3], child.imageVisibility)
                if sx < 0 and sy < 0 then
                    love.graphics.draw(child.image, child.quad, x - adjustX, y - adjustY, rad(child.rotation), (w / child.imageWidth) * child.scaleX, (h / child.imageHeight) * child.scaleY)
                elseif sx < 0 then
                    love.graphics.draw(child.image, child.quad, x - adjustX, y, rad(child.rotation), (w / child.imageWidth) * child.scaleX, h / child.imageHeight)
                else
                    love.graphics.draw(child.image, child.quad, x, y - adjustY, rad(child.rotation), w / child.imageWidth, (h / child.imageHeight) * child.scaleY)
                end
            else
                love.graphics.setColor(child.imageColor[1], child.imageColor[2],
                                    child.imageColor[3], child.imageVisibility)
                
                love.graphics.draw(child.image, child.quad, x, y, rad(child.rotation), w / child.imageWidth, h / child.imageHeight)
            end
        end
    end,
    [2] = function(child, x, y, w, h)
        love.graphics.setColor(child.textColor[1], child.textColor[2],
                               child.textColor[3], child.textVisibility)
        love.graphics.setFont(child.font)
        if child.align == gui.ALIGN_LEFT then
            child.adjust = 0
        elseif child.align == gui.ALIGN_CENTER then
            local fw = child.font:getWidth(child.text)
            child.adjust = (w - fw) / 2
        elseif child.align == gui.ALIGN_RIGHT then
            local fw = child.font:getWidth(child.text)
            child.adjust = w - fw - 4
        end
        love.graphics.printf(child.text, child.adjust + x + child.textOffsetX,
                             y + child.textOffsetY, w, "left", child.rotation,
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
            local blue = color.highlighter_blue
            local start, stop = child.selection[1], child.selection[2]
            if start > stop then start, stop = stop, start end
            local x1, y1 = child.font:getWidth(child.text:sub(1, start - 1)), 0
            local x2, y2 = child.font:getWidth(child.text:sub(1, stop)), h
            love.graphics.setColor(blue[1], blue[2], blue[3], .5)
            love.graphics.rectangle("fill", x + x1 + child.adjust, y + y1,
                                    x2 - x1, y2 - y1)
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

local draw_handler = function(child, no_draw)
    local bg = child.color
    local bbg = child.borderColor
    local ctype = child.type
    local vis = child.visibility
    local x, y, w, h = child:getAbsolutes()
    local roundness = child.roundness
    local rx, ry, segments = child.__rx or 0, child.__ry or 0,
                             child.__segments or 0
    child.x = x
    child.y = y
    child.w = w
    child.h = h

    if no_draw then return end

    if child.clipDescendants then
        local children = child:getAllChildren()
        for c = 1, #children do -- Tell the children to clip themselves
            local clip = children[c].__variables.clip
            clip[1] = true
            clip[2] = x
            clip[3] = y
            clip[4] = w
            clip[5] = h
        end
    end

    if child.__variables.clip[1] then
        local clip = child.__variables.clip
        love.graphics.setScissor(clip[2], clip[3], clip[4], clip[5])
    elseif type(roundness) == "string" then
        love.graphics.setScissor(x - 1, y - 2, w + 2, h + 3)
    end
    local drawB = child.drawBorder
    -- Set color
    love.graphics.setLineStyle("smooth")
    love.graphics.setLineWidth(3)
    if drawB then
        love.graphics.setColor(bbg[1], bbg[2], bbg[3], vis)
        love.graphics.rectangle("line", x, y, w, h, rx, ry, segments)
    end
    love.graphics.setColor(bg[1], bg[2], bg[3], vis)
    love.graphics.rectangle("fill", x, y, w, h, rx, ry, segments)
    
    if drawB then
        if roundness == "top" then
            love.graphics.rectangle("fill", x, y + ry / 2, w, h - ry / 2 + 1)
            love.graphics.setLineStyle("rough")
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
            love.graphics.rectangle("fill", x, y, w, h - ry + 2)
            love.graphics.setLineStyle("rough")
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

    if child.__variables.clip[1] then
        love.graphics.setScissor() -- Remove the scissor
    end
end

gui.draw_handler = draw_handler

drawer:newLoop(function()
    local children = gui:getAllChildren()
    for i = 1, #children do
        local child = children[i]
        if child.effect then
            child.effect(function() draw_handler(child) end)
        else
            draw_handler(child)
        end
    end
    first_loop = true
end)

drawer:newThread(function()
    while true do
        thread.sleep(.01)
        local children = gui.virtual:getAllChildren()
        for i = 1, #children do
            local child = children[i]
            if child.effect then
                child.effect(function() draw_handler(child, true) end)
            else
                draw_handler(child, true)
            end
        end
        first_loop = true
    end
end)

local processors = {
    updater.run
}

-- Drawing and Updating
gui.draw = drawer.run
gui.update = function()
    for i = 1, #processors do
        processors[i]()
    end
end

function gui:newProcessor(name)
    local proc = multi:newProcessor(name or "UnNamedProcess_"..multi.randomString(8), true)
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
gui.virtual.dualDim.offset.size.x = w
gui.virtual.dualDim.offset.size.y = h
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
gui.dualDim.offset.size.x = w
gui.dualDim.offset.size.y = h
gui.w = w
gui.h = h

local g_width, g_height
local function GetSizeAdjustedToAspectRatio(dWidth, dHeight)
    local isLandscape = g_width > g_height

    local newHeight = 0
    local newWidth = 0

    if g_width / g_height > dWidth / dHeight then
        newHeight = dWidth * g_height / g_width
        newWidth = dWidth
    else
        newWidth = dHeight * g_width  / g_height
        newHeight = dHeight
    end

    return newWidth, newHeight, (dWidth-newWidth)/2, (dHeight-newHeight)/2
end

gui.GetSizeAdjustedToAspectRatio = GetSizeAdjustedToAspectRatio

function gui:setAspectSize(w, h)
    if w and h then
        g_width, g_height = w, h
        gui.aspect_ratio = true
    else
        gui.aspect_ratio = false
    end
end

gui.Events.OnResized(function(w, h)
    if gui.aspect_ratio then
        local nw, nh, xt, yt = GetSizeAdjustedToAspectRatio(w, h)
        gui.x = xt
        gui.y = yt
        gui.dualDim.offset.size.x = nw
        gui.dualDim.offset.size.y = nh
        gui.w = nw
        gui.h = nh

        gui.virtual.x = xt
        gui.virtual.y = yt
        gui.virtual.dualDim.offset.size.x = nw
        gui.virtual.dualDim.offset.size.y = nh
        gui.virtual.w = nw
        gui.virtual.h = nh
    else
        gui.dualDim.offset.size.x = w
        gui.dualDim.offset.size.y = h
        gui.w = w
        gui.h = h

        gui.virtual.dualDim.offset.size.x = w
        gui.virtual.dualDim.offset.size.y = h
        gui.virtual.w = w
        gui.virtual.h = h
    end
end)

return gui
