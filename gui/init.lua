local utf8 = require("utf8")
local multi, thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local color = require("gui.color")
local gui = {}
local updater = multi:newProcessor("UpdateManager",true)
local drawer = multi:newProcessor("DrawManager",true)
local bit = require("bit")
local band, bor = bit.band, bit.bor
local cursor_hand = love.mouse.getSystemCursor("hand")
local clips = {}
local max, min, abs, rad, floor, ceil = math.max, math.min, math.abs, math.rad, math.floor,math.ceil
local frame, image, text, box, video, button, anim = 0, 1, 2, 4, 8, 16, 32
local global_drag
local object_focus = gui

gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

gui.ALLIGN_CENTER = 0
gui.ALLIGN_LEFT = 1
gui.ALLIGN_RIGHT = 2

-- Connections
gui.Events = {} -- We are using fastmode for all connection objects.
gui.Events.OnQuit = multi:newConnection():fastMode()
gui.Events.OnDirectoryDropped = multi:newConnection():fastMode()
gui.Events.OnDisplayRotated = multi:newConnection():fastMode()
gui.Events.OnFilesDropped = multi:newConnection():fastMode()
gui.Events.OnFocus = multi:newConnection():fastMode()
gui.Events.OnMouseFocus = multi:newConnection():fastMode()
gui.Events.OnResized = multi:newConnection():fastMode()
gui.Events.OnVisible = multi:newConnection():fastMode()
gui.Events.OnKeyPressed = multi:newConnection():fastMode()
gui.Events.OnKeyReleased = multi:newConnection():fastMode()
gui.Events.OnTextEdited = multi:newConnection():fastMode()
gui.Events.OnTextInputed = multi:newConnection():fastMode()
gui.Events.OnMouseMoved = multi:newConnection():fastMode()
gui.Events.OnMousePressed = multi:newConnection():fastMode()
gui.Events.OnMouseReleased = multi:newConnection():fastMode()
gui.Events.OnWheelMoved = multi:newConnection():fastMode()
gui.Events.OnTouchMoved = multi:newConnection():fastMode()
gui.Events.OnTouchPressed = multi:newConnection():fastMode()
gui.Events.OnTouchReleased = multi:newConnection():fastMode()

-- Virtual gui init
gui.virtual = {}

-- Internal Connections
gui.Events.OnObjectFocusChanged = multi:newConnection():fastMode()

-- Hooks

local function Hook(funcname, func)
	if love[funcname] then
		local cache = love[funcname]
		love[funcname] = function(...)
			cache(...)
			func({},...)
		end
	else
		love[funcname] = function(...) func({},...) end
	end
end

-- This will run the hooks after everything has loaded
updater:newTask(function()
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
end)

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

updater:newThread("GUI Hotkey Manager",function()
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

function gui:SetHotKey(keys, conn)
	has_hotkey = true
	local conn = conn or multi:newConnection():fastMode()
	table.insert(hot_keys, {Ref=self, Connection = conn, Keys = {unpack(keys)}})
	return conn
end

-- Default HotKeys
gui.HotKeys = {}

-- Connections can be added together to create an OR logic to them, they can be multiplied together to create an AND logic to them
gui.HotKeys.OnSelectAll	= gui:SetHotKey({"lctrl","a"})
						+ gui:SetHotKey({"rctrl","a"})

gui.HotKeys.OnCopy		= gui:SetHotKey({"lctrl","c"})
						+ gui:SetHotKey({"rctrl","c"})

gui.HotKeys.OnPaste		= gui:SetHotKey({"lctrl","v"})
						+ gui:SetHotKey({"rctrl","v"})

gui.HotKeys.OnCut		= gui:SetHotKey({"lctrl","x"})
						+ gui:SetHotKey({"rctrl","x"})

gui.HotKeys.OnUndo		= gui:SetHotKey({"lctrl","z"})
						+ gui:SetHotKey({"rctrl","z"})

gui.HotKeys.OnRedo 		= gui:SetHotKey({"lctrl","y"})
						+ gui:SetHotKey({"rctrl","y"})
						+ gui:SetHotKey({"lctrl", "lshift", "z"})
						+ gui:SetHotKey({"rctrl", "lshift", "z"})
						+ gui:SetHotKey({"lctrl", "rshift", "z"})
						+ gui:SetHotKey({"rctrl", "rshift", "z"})

-- Utils

function gui:getObjectFocus()
	return object_focus
end

function gui:hasType(t)
	return band(object_focus.type, t) == t
end

function gui:move(x,y)
	self.dualDim.offset.pos.x = self.dualDim.offset.pos.x + x
	self.dualDim.offset.pos.y = self.dualDim.offset.pos.y + y
end

function gui:moveInBounds(dx,dy)
	local x, y, w, h = self:getAbsolutes()
	local x1, y1, w1, h1 = self.parent:getAbsolutes()
	if (x + dx >= x1 or dx > 0) and (x + w + dx <= x1 + w1 or dx < 0) and (y + dy >= y1 or dy > 0) and (y + h + dy <= y1 + h1 or dy < 0) then
		self:move(dx,dy)
	end
end

local function intersecpt(x1,y1,x2,y2,x3,y3,x4,y4)

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

	return x7, y7, abs(x7-x8), abs(y7-y8)
end

local function toCoordPoints(x, y, w, h)
	return x,y,x+w,y+h
end

function gui:intersecpt(x, y, w, h)
	local x1,y1,x2,y2 = toCoordPoints(self:getAbsolutes())
	local x3,y3,x4,y4 = toCoordPoints(x,y,w,h)

	return intersecpt(x1,y1,x2,y2,x3,y3,x4,y4)
end

function gui:isDescendantOf(obj)
	local parent = self.parent
	while parent~=gui do
		if parent==obj then
			return true
		end
		parent = parent.parent
	end
	return false
end

function gui:getChildren()
	return self.children
end

function gui:getAbsolutes() -- returns x, y, w, h
	return (self.parent.w*self.dualDim.scale.pos.x)+self.dualDim.offset.pos.x+self.parent.x,
		(self.parent.h*self.dualDim.scale.pos.y)+self.dualDim.offset.pos.y+self.parent.y,
		(self.parent.w*self.dualDim.scale.size.x)+self.dualDim.offset.size.x,
		(self.parent.h*self.dualDim.scale.size.y)+self.dualDim.offset.size.y
end

function gui:getAllChildren(callback)
	local Stuff = {}
	function Seek(Items)
		for i=1,#Items do
			if Items[i].visible==true then
				if callback then callback(Items[i]) end
				table.insert(Stuff,Items[i])
				local NItems = Items[i]:getChildren()
				if NItems ~= nil then
					Seek(NItems)
				end
			end
		end
	end
	local Objs = self:getChildren()
	for i=1,#Objs do
		if Objs[i].visible==true then
			if callback then callback(Objs[i]) end
			table.insert(Stuff, Objs[i])
			local Items = Objs[i]:getChildren()
			if Items ~= nil then
				Seek(Items)
			end
		end
	end
	return Stuff
end

function gui:newThread(func)
	return updater:newThread("ThreadHandler<"..self.type..">", func, self, thread)
end

function gui:setDualDim(x,y,w,h,sx,sy,sw,sh)
	self.dualDim.offset = {
		pos={x=x or self.dualDim.offset.pos.x,y=y or self.dualDim.offset.pos.y},
		size={x=w or self.dualDim.offset.size.x,y=h or self.dualDim.offset.size.y}
	}
	self.dualDim.scale = {
		pos={x=sx or self.dualDim.scale.pos.x,y=sy or self.dualDim.scale.pos.y},
		size={x=sw or self.dualDim.scale.size.x,y=sh or self.dualDim.scale.size.y}
	}
end

function gui:getTile(i,x,y,w,h)-- returns imagedata
	if type(i)=="string" then
		i=love.graphics.newImage(i)
	elseif type(i)=="userdata" then
		-- do nothing
	elseif string.find(self.Type,"Image",1,true) then
		local i,x,y,w,h=self.Image,i,x,y,w
	else
		error("getTile invalid args!!! Usage: ImageElement:getTile(x,y,w,h) or gui:getTile(imagedata,x,y,w,h)")
	end
	local iw,ih=i:getDimensions()
	local id,_id=i:getData(),love.image.newImageData(w,h)
	for _x=x,w+x-1 do
		for _y=y,h+y-1 do
			_id:setPixel(_x-x,_y-y,id:getPixel(_x,_y))
		end
	end
	return love.graphics.newImage(_id)
end

function gui:topStack()
	local siblings = self.parent.children
	for i=1,#siblings do
		if siblings[i]==self then
			table.remove(siblings,i)
			break
		end
	end
	siblings[#siblings+1]=self
end

local mainupdater = updater:newLoop().OnLoop

function gui:canPress(mx,my) -- Get the intersection of the clip area and the self then test with the clip, otherwise test as normal
	local x, y, w, h
	if self.__variables.clip[1] then
		local clip = self.__variables.clip
		x, y, w, h = self:intersecpt(clip[2], clip[3], clip[4], clip[5])
		return mx < x + w and mx > x and my+h < y + h and my+h > y
	else
		x, y, w, h = self:getAbsolutes()
	end
	return not(mx > x + w or mx < x or my > y + h or my < y)
end

function gui:isBeingCovered(mx,my)
	local children = gui:getAllChildren()
	for i = #children, 1, -1 do
		if children[i] == self then
			return false
		elseif children[i]:canPress(mx,my) and not(children[i] == self) and not(children[i].ignore) then
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

local function processDo(ref)
	ref.Do[1]()
end

function gui:clone(opt)
	--[[
		{
			copyTo: Who to set the parent to
			connections: Do we copy connections? (true/false)
		}
	]] 
	-- DO = {[[setImage]], c.image or IMAGE}
	-- Connections are used greatly throughout do we copy those
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
		temp = gui:newImageButton(u.DO[2], self:getDualDim())
	elseif self.type == image then
		temp = gui:newImageLabel(u.DO[2], self:getDualDim())
	else -- We are dealing with a complex object
		temp = processDo(u)
	end

	for i, v in pairs(u) do
		temp[i] = v
	end
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             
	local conn
	if opt then
		temp:setParent(opt.copyTo or gui.virtual)
		if opt.connections then
			conn = true
			for i, v in pairs(self) do
				if v.Type == "connector" then
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
	return self.active and not(self:isDescendantOf(gui.virtual))
end

-- Base get uniques
function gui:getUniques(tab)
	local base = {
		active = self.active,
		visible = self.visible,
		visibility = self.visibility,
		color = self.color,
		borderColor = self.borderColor,
		rotation = self.rotation,
	}

	if tab then
		for i, v in pairs(tab) do
			base[i] = tab[i]
		end
	end
	return base
end

-- Base Library
function gui:newBase(typ,x, y, w, h, sx, sy, sw, sh, virtual)
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
			return not(global_drag or c:isBeingCovered(x, y))
		end
		return true
	end

	setmetatable(c, gui)
	c.__variables = {
		clip = {false,0,0,0,0}
	}
	c.active = true
	c.type = typ
	c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
	c.children = {}
	c.visible = true
	c.visibility = 1
	c.color = {.6, .6, .6}
	c.borderColor = color.black
	c.rotation = 0

	c.OnPressed = testHierarchy .. multi:newConnection()
	c.OnPressedOuter = multi:newConnection()
	c.OnReleased = testHierarchy .. multi:newConnection()
	c.OnReleasedOuter =  multi:newConnection()
	c.OnReleasedOther = multi:newConnection()

	c.OnDragStart = multi:newConnection()
	c.OnDragging = multi:newConnection()
	c.OnDragEnd = multi:newConnection()

	c.OnEnter = testHierarchy .. multi:newConnection()
	c.OnExit = multi:newConnection()

	c.OnMoved = testHierarchy .. multi:newConnection()

	local dragging = false
	local entered = false
	local moved = false
	local pressed = false

	gui.Events.OnMouseMoved(function(x, y, dx, dy, istouch)
		if not c:isActive() then return end
		if c:canPress(x,y) then
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
		if c:canPress(x,y) then
			c.OnPressed:Fire(c, x, y, dx, dy, istouch)
			pressed = true
			
			-- Only change and trigger the event if it is a different object
			if c ~= object_focus then
				gui.Events.OnObjectFocusChanged:Fire(object_focus, c)
				object_focus = c
			end

			if draggable and button == dragbutton and not c:isBeingCovered(x, y) and not global_drag then
				dragging = true
				global_drag = true
				c.OnDragStart:Fire(c, dx, dy, x, y, istouch)
			end
		else
			c.OnPressedOuter:Fire(c, x, y, button, istouch, presses)
		end
	end)

	function c:respectHierarchy(bool)
		hierarchy = bool
	end

	function c:OnUpdate(func) -- Not crazy about this approach, will probably rework this
		if type(self)=="function" then func = self end
		mainupdater(function()
			func(c)
		end)
	end

	local function centerthread()
		local centerfunc = function()
			return centerX or centerY -- If the condition is true it acts like a yield
		end
		c:newThread(function()
			while true do
				thread.hold(centerfunc)
				local x, y, w, h = c:getAbsolutes()
				if centerX then
					c:setDualDim(-w/2,nil,nil,nil,.5)
				end
				if centerY then
					c:setDualDim(nil,-h/2,nil,nil,nil,.5)
				end
			end
		end)
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
		centerthread()
	end

	function c:centerY(bool)
		centerY = bool
		if centering then return end
		centering = true
		centerthread()
	end

	-- Add to the parents children table
	if virtual then
		c.parent = gui.virtual
		table.insert(gui.virtual.children, c)
	else
		c.parent = self
		table.insert(self.children, c)
	end
	return c
end

function gui:newDualDim(x, y, w, h, sx, sy, sw, sh)
	local dd = {}
	dd.offset={}
	dd.scale={}
	dd.offset.pos = {
		x = x or 0,
		y = y or 0
	}
	dd.offset.size = {
		x = w or 0,
		y = h or 0
	}
	dd.scale.pos = {
		x = sx or 0,
		y = sy or 0
	}
	dd.scale.size = {
		x = sw or 0,
		y = sh or 0
	}
	return dd
end

function gui:getDualDim()
	local dd = self.dualDim
	return dd.offset.pos.x, dd.offset.pos.y, dd.offset.size.x, dd.offset.size.y, dd.scale.pos.x, dd.scale.pos.y, dd.scale.size.x, dd.scale.size.y
end

-- Frames
function gui:newFrame(x, y, w, h, sx, sy, sw, sh)
	return self:newBase(frame, x, y, w, h, sx, sy, sw, sh)
end

function gui:newVirtualFrame(x, y, w, h, sx, sy, sw, sh)
	return self:newBase(frame, x, y, w, h, sx, sy, sw, sh, true)
end

-- Texts
function gui:newTextBase(typ, txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(text + typ, x, y, w, h, sx, sy, sw, sh)
	c.text = txt
	c.align = gui.ALLIGN_LEFT
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

	function c:calculateFontOffset()
		local width, height = floor(w+w/4), floor(h+h/4)
		local canvas = love.graphics.newCanvas(width, height)
		local top = height
		local bottom = 0
		love.graphics.setCanvas(canvas)
		love.graphics.setColor(1,1,1,1)
		love.graphics.setFont(self.font)
		love.graphics.printf(self.text, 0, h/8, self.dualDim.offset.size.x, "left", self.radians, self.textScaleX, self.textScaleY, 0, 0, self.textShearingFactorX, self.textShearingFactorY)
		love.graphics.setCanvas()
		local data = canvas:newImageData(nil, nil, 0, 0, width, height )
		for x = 0, width-1 do
			for y = 0, height-1 do
				local r,g,b,a = data:getPixel(x,y)
				if r==1 and g==1 and b==1 then
					if y<top then top = y end
					if y>bottom then bottom = y end
				end
			end
		end
		return top-h/8, bottom-h/8
	end

	function c:setFont(font,size)
		if type(font)=="string" then
			self.fontFile = font
			self.font = love.graphics.newFont(font, size)
		else
			self.font = font
		end
		self.OnFontUpdated:Fire(self)
	end

	function c:fitFont(n)
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
			font = function(n)
				return love.graphics.newFont(n)
			end
		end
		local x, y, width, height = self:getAbsolutes()
		local Font, text = self.Font, self.text
		local s = 3
		Font = font(s)
		while Font:getHeight()<height and Font:getWidth(text)<width do
			s = s + 1
			Font = font(s)
		end
		Font = font(s - (2+(n or 0)))
		Font:setFilter("linear","nearest",4)
		self.font = Font
		local h = (self.parent.dualDim.offset.size.y*self.dualDim.scale.size.y)+self.dualDim.offset.size.y
		local top, bottom = self:calculateFontOffset()
		self.textOffsetY = (h-bottom-top/2)/2
		self.OnFontUpdated:Fire(self)
		return s - (2+(n or 0))
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
			textColor = c.textColor,
		})
	end
	return c
end

function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(frame, txt, x, y, w, h, sx, sy, sw, sh)
	c:respectHierarchy(true)

	c.OnEnter(function(c, x, y, dx, dy, istouch)
		love.mouse.setCursor(cursor_hand)
	end)

	c.OnExit(function(c, x, y, dx, dy, istouch)
		love.mouse.setCursor()
	end)

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
		local x, y, w, h = math.floor(width + self.adjust + self.textOffsetX), 0, _w, height

		width = width + _w

		if not(mx > x + w or mx < x or my > y + h or my < y) then
			if not(exact) and (_w - (width - (mx - math.floor(self.adjust + self.textOffsetX))) < _w/2  and i >= 1) then
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

	c.OnReturn = multi:newConnection():fastMode()

	c.cur_pos = 0
	c.adjust = 0
	c.selection = {0,0}

	function c:getUniques()
		return gui.getUniques(c, {
			doSelection = c.doSelection,
			cur_pos = c.cur_pos,
			adjust = c.adjust,
		})
	end

	function c:HasSelection()
		return c.selection[1] ~= 0 and c.selection[2] ~= 0
	end

	function c:GetSelection()
		local start, stop = c.selection[1], c.selection[2]
		if start > stop then
			start, stop = stop, start
		end
		return start, stop
	end

	function c:GetSelectedText()
		if not c:HasSelection() then return "" end
		local sta, sto = c.selection[1], c.selection[2]
		if sta > sto then sta, sto = sto, sta end
		return c.text:sub(sta,sto)
	end

	function c:ClearSelection()
		c.doSelection = false
		c.selection = {0, 0}
	end

	c.OnEnter(function(c, x, y, dx, dy, istouch)
		love.mouse.setCursor(love.mouse.getSystemCursor("ibeam"))
	end)

	c.OnExit(function(c, x, y, dx, dy, istouch)
		love.mouse.setCursor(cur)
	end)

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

	c.OnPressedOuter(function()
		c.bar_show = false
	end)

	return c
end

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
end)

local function insert(obj, n_text)
	if obj:HasSelection() then
		local start, stop = obj:GetSelection()
		obj.text = obj.text:sub(1, start - 1) .. n_text .. obj.text:sub(stop + 1, -1)
		obj:ClearSelection()
		obj.cur_pos = start
		if #n_text > 1 then
			obj.cur_pos = start + #n_text
		end
	else
		obj.text = obj.text:sub(1, obj.cur_pos) .. n_text .. obj.text:sub(obj.cur_pos + 1,-1)
		obj.cur_pos = obj.cur_pos + 1
		if #n_text > 1 then
			obj.cur_pos = obj.cur_pos + #n_text
		end
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
			obj.text = obj.text:sub(1, obj.cur_pos) .. obj.text:sub(obj.cur_pos + 2, -1)
		else
			obj.text = obj.text:sub(1, obj.cur_pos - 1) .. obj.text:sub(obj.cur_pos + 1, -1)
			object_focus.cur_pos = object_focus.cur_pos - 1
			if object_focus.cur_pos == 0 then object_focus.cur_pos = 1 end
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
	if object_focus:hasType(box) then
		insert(object_focus, text)
	end
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
function gui:newImageBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(image + typ,x, y, w, h, sx, sy, sw, sh)
	c.color = color.white
	c.visibility = 0
	local IMAGE
	function c:getUniques()
		return gui.getUniques(c, {
			-- Recreating the image object using set image is the way to go
			DO = {[[setImage]], c.image or IMAGE}
		})
	end
	function c:setImage(i)
		IMAGE = i
		drawer:newThread(function()
			thread.yield()
			local img
			if type(i) == "userdata" and i:type() == "Image" then
				img = i
			elseif type(i) == "string" then
				img = love.graphics.newImage(i)
			end
			local x, y, w, h = self:getAbsolutes()
			self.imageColor = color.white
			self.imageVisibility = 1
			self.image = img
			self.imageHeigth = img:getHeight()
			self.imageWidth = img:getWidth()
			self.quad = love.graphics.newQuad(0, 0, w, h, self.imageWidth, self.imageHeigth)
		end)
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

	c.OnExit(function(c, x, y, dx, dy, istouch)
		love.mouse.setCursor()
	end)

	return c
end

-- Video
function gui:newVideo(source, x, y, w, h, sx, sy, sw, sh)
	local c = self:newImageBase(video, x, y, w, h, sx, sy, sw, sh)
	c.OnVideoFinished = multi:newConnection()
	c.playing = false

	function c:setVideo(v)
		if type(v)=="string" then
			c.video=love.graphics.newVideo(v)
		elseif v then
			c.video=v
		end
		c.audiosource = c.video:getSource( )
		if c.audiosource then
			c.audioLength = c.audiosource:getDuration()
		end
		c.videoHeigth=c.video:getHeight()
		c.videoWidth=c.video:getWidth()
		c.quad=love.graphics.newQuad(0,0,w,h,c.videoWidth,c.videoHeigth)
	end

	function c:getVideo()
		return self.video
	end

	if type(source)=="string" then
		c:setVideo(source)
	end

	function c:play()
		c.playing = true
		c.video:play()
	end

	function c:setVolume(vol)
		if self.audiosource then
			self.audiosource:setVolume(vol)
		end
	end

	function c:pause()
		c.video:pause()
	end

	function c:stop()
		c.playing = false
		c.video:pause()
		c.video:rewind()
	end

	function c:rewind()
		c.video:rewind()
	end

	function c:seek(n)
		c.video:seek(n)
	end

	function c:tell()
		return c.video:tell()
	end

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

		while true do
			thread.chain(isplaying, testCompletion)
		end
	
	end)

	c.videoVisibility = 1
	c.videoColor = color.white

	return c
end

-- Draw Function

--local label, image, text, button, box, video, animation (spritesheet)
local drawtypes = {
	[0] = function(child, x, y, w, h) end,
	[1] = function(child, x, y, w, h)
		if child.image then
			love.graphics.setColor(child.imageColor[1],child.imageColor[2],child.imageColor[3],child.imageVisibility)
			if w~=child.imageWidth and h~=child.imageHeigth then
				love.graphics.draw(child.image,x,y,rad(child.rotation),w/child.imageWidth,h/child.imageHeigth)
			else
				love.graphics.draw(child.image,child.quad,x,y,rad(child.rotation),w/child.imageWidth,h/child.imageHeigth)
			end
		end
	end,
	[2] = function(child, x, y, w, h)
		love.graphics.setColor(child.textColor[1],child.textColor[2],child.textColor[3],child.textVisibility)
		love.graphics.setFont(child.font)
		if child.align == gui.ALLIGN_LEFT then
			child.adjust = 0
		elseif child.align == gui.ALLIGN_CENTER then
			local fw = child.font:getWidth(child.text)
			child.adjust = (w-fw)/2
		elseif child.align == gui.ALLIGN_RIGHT then
			local fw = child.font:getWidth(child.text)
			child.adjust = w - fw - 4
		end
		love.graphics.printf(child.text, child.adjust + x + child.textOffsetX, y + child.textOffsetY, w, "left", child.rotation, child.textScaleX, child.textScaleY, 0, 0, child.textShearingFactorX, child.textShearingFactorY)
	end,
	[4] = function(child, x, y, w, h)
		if child.bar_show then
			local font = child.font
			local fh = font:getHeight()
			local fw = font:getWidth(child.text:sub(1, child.cur_pos))
			love.graphics.line(child.textOffsetX + child.adjust + x + fw, y + 4, child.textOffsetX + child.adjust + x + fw, y + fh - 2)
		end
		if child:HasSelection() then
			local blue = color.highlighter_blue
			local start, stop = child.selection[1], child.selection[2]
			if start > stop then
				start, stop = stop, start
			end
			local x1, y1 = child.font:getWidth(child.text:sub(1, start-1)), 0
			local x2, y2 = child.font:getWidth(child.text:sub(1, stop)), h
			love.graphics.setColor(blue[1],blue[2],blue[3],.5)
			love.graphics.rectangle("fill", x + x1 + child.adjust, y + y1, x2 - x1, y2 - y1)
		end
	end,
	[8] = function(child, x, y, w, h)
		if child.video and child.playing then
			love.graphics.setColor(child.videoColor[1],child.videoColor[2],child.videoColor[3],child.videoVisibility)
			if w~=child.imageWidth and h~=child.imageHeigth then
				love.graphics.draw(child.video,x,y,rad(child.rotation),w/child.videoWidth,h/child.videoHeigth)
			else
				love.graphics.draw(child.video,child.quad,x,y,rad(child.rotation),w/child.videoWidth,h/child.videoHeigth)
			end
		end
	end,
	[16] = function(child, x, y, w, h)
		--
	end,
}

local draw_handler = function(child)
	local bg = child.color
	local bbg = child.borderColor
	local type = child.type
	local vis = child.visibility
	local x, y, w, h = child:getAbsolutes()
	child.x = x
	child.y = y
	child.w = w
	child.h = h

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
	end

	-- Set color
	love.graphics.setColor(bg[1],bg[2],bg[3],vis)
	love.graphics.rectangle("fill", x, y, w, h--[[, rx, ry, segments]])
	love.graphics.setColor(bbg[1],bbg[2],bbg[3],vis)
	love.graphics.rectangle("line", x, y, w, h--[[, rx, ry, segments]])

	-- Start object specific stuff
	drawtypes[band(type,video)](child,x,y,w,h)
	drawtypes[band(type,image)](child,x,y,w,h)
	drawtypes[band(type,text)](child,x,y,w,h)
	drawtypes[band(type,box)](child,x,y,w,h)
	
	if child.__variables.clip[1] then
		love.graphics.setScissor() -- Remove the scissor
	end
end

drawer:newLoop(function()
	local children = gui:getAllChildren()
	for i=1,#children do
		local child = children[i]
		if child.effect then
			child.effect(function()
				draw_handler(child)
			end)
		else
			draw_handler(child)
		end
	end
end)

-- Drawing and Updating
gui.draw = drawer.run
gui.update = updater.run

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

-- Root gui
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

gui.Events.OnResized(function(w,h)
	gui.dualDim.offset.size.x = w
	gui.dualDim.offset.size.y = h
	gui.w = w
	gui.h = h
end)

return gui
