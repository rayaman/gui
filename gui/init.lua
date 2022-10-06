local multi,thread = require("multi"):init()
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
local frame, image, text, box, video = 0, 1, 2, 4, 8

local global_drag

gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

-- Utils

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

	-- gives bottom-left point
    -- of intersection rectangle
    local x5 = max(x1, x3)
    local y5 = max(y1, y3)

	-- gives top-right point
	-- of intersection rectangle
    local x6 = min(x2, x4);
    local y6 = min(y2, y4);

	-- no intersection
    if x5 > x6 or y5 > y6 then
        return 0, 0, 0, 0 -- Return a no
	end

	-- gives top-left point
    -- of intersection rectangle
    local x7 = x5
    local y7 = y6
 
    -- gives bottom-right point
    -- of intersection rectangle
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

function gui:getAllChildren()
	local Stuff = {}
	function Seek(Items)
		for i=1,#Items do
			if Items[i].visible==true then
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
		--x1, y1, w1, h1 = self:getAbsolutes()
		return mx < x + w and mx > x and my+h < y + h and my+h > y
	else
		x, y, w, h = self:getAbsolutes()
	end
	return not(mx > x + w or mx < x or my > y + h or my < y)
end

function gui:isBeingCovered(mx,my)
	local children = gui:getAllChildren()
	local start = false
	for i=#children, 1, -1 do
		if children[i]:canPress(mx,my) and not(children[i] == self) then
			return true
		elseif children[i] == self then
			return false
		end
	end
	return false
end

-- Base Library
function gui:newBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = {}
	local buildBackBetter
	local centerX = false
	local centerY = false
	local centering = false
	local dragbutton = 2
	local draggable = false

	setmetatable(c, gui)
	c.__variables = {
		clip = {false,0,0,0,0}
	}
	c.active = true
	c.parent = self
	c.type = typ
	c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
	c.children = {}
	c.visible = true
	c.visibility = 1
	c.color = {.6,.6,.6}
	c.borderColor = color.black
	c.rotation = 0
	c.maxMouseButtons = 5

	c.WhilePressing = multi:newConnection()
	c.OnPressed = multi:newConnection()
	c.OnReleased = multi:newConnection()

	c.OnDragStart = multi:newConnection()
	c.OnDragging = multi:newConnection()
	c.OnDragEnd = multi:newConnection()

	c.OnEnter = multi:newConnection()
	c.OnExit = multi:newConnection()

	c.OnMoved = multi:newConnection()

	-- Mouse event thread
	buildBackBetter = function()
		c:newThread(function()
			local dragging = false
			local waiting = {}
			local pressed = {}
			local ox, oy = 0, 0
			local mox, moy = 0, 0
			local entered = false
			local moved = false
			local mx, my
			local movedFunc = thread:newFunction(function(self,ref,mx,my)
				self:Pause()
				thread.hold(function()
					return ref:canPress(mx,my)
				end)
				ref.OnExit(ref,mx,my)
				entered = false
				self:Resume()
			end)
			local releaseFunc = thread:newFunction(function(self, ref, mx, my, i)
				self:Pause()
				thread.hold(function() return not(love.mouse.isDown(i)) end)
				if pressed[i] then
					pressed[i] = false
					waiting[i] = false
					ref.OnReleased:Fire(ref, i, mx, my)
				end
				self:Resume()
			end)
			while true do
				thread.hold(function() -- Only Progress thread if events are subscribed to!
					return c.active and (draggable or c.OnEnter:hasConnections() or c.OnExit:hasConnections() or c.WhilePressing:hasConnections() or c.OnPressed:hasConnections() or c.OnReleased:hasConnections() or c.OnDragStart:hasConnections() or c.OnDragging:hasConnections() or c.OnDragEnd:hasConnections())
				end)
				thread.sleep(.01) -- Limits the potiential speed for events to 1/200. So 200 fps max, to be fair pressing mouse click 200 times by hand in a second is probably not possible
				if not love.mouse.isDown(1,2,3,4,5) then
					dragging = false
					waiting = {}
					pressed = {}
					ox, oy = 0, 0
					entered = false
					mx, my = nil, nil
					global_drag = nil
				end
				local x, y, w, h = c:getAbsolutes()
				mx, my = love.mouse.getPosition()
				--thread.hold(function() return c:canPress(mx,my) end)
				moved = false
				-- mouse moved
				if mx~=mox or my~=moy then
					moved = true
					c.OnMoved:Fire(c, mx - mox, my - moy)
					mox = mx
					moy = my
				end
				-- enter/exit
				if moved and not entered and c:canPress(mx,my) then
					entered = true
					c.OnEnter:Fire(c,mx,my)
					movedFunc(movedFunc, c, mx, my)
				end

				-- pressed/released/drag events
				for i=1,c.maxMouseButtons do
					if dragging and i == dragbutton then
						c.OnDragging:Fire(c, mx - ox, my - oy, mx, my)
						ox = mx
						oy = my
					end
					if love.mouse.isDown(i) and c:canPress(mx,my) then
						if not pressed[i] then
							if draggable and love.mouse.isDown(dragbutton) and (not global_drag or global_drag == c) then
								if not dragging and not c:isBeingCovered(mx, my) then
									global_drag = c
									c.OnDragStart:Fire(c, mx, my)
									ox, oy = mx, my
									dragging = true
									c:newThread(function()
										thread.hold(function() return not(love.mouse.isDown(dragbutton)) end)
										if dragging then
											global_drag = nil
											dragging = false
											c.OnDragEnd:Fire(c, mx, my)
										end
									end)
								end
							end
							c.OnPressed:Fire(c, i, mx, my)
						end
						pressed[i] = true
						-- Only process when the drag button turn is active
						c.WhilePressing:Fire(c, i, mx, my)
						if not waiting[i] then
							waiting[i] = true
							releaseFunc(releaseFunc, c, mx, my, i)
						end
					end
				end
			end
		end).OnError(function(self,err)
			print(err)
			buildBackBetter()
		end)
	end
	buildBackBetter()
	function c:OnUpdate(func) -- Not crazy about this approach, will probably rework this
		if type(self)=="function" then func = self end
		mainupdater(function()
			func(c)
		end)
	end

	local function centerthread()
		c:newThread(function()
			while true do
				thread.hold(function()
					return centerX or centerY -- If the condition is true it acts like a yield
				end)
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
	table.insert(self.children,c)
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

-- Frames
function gui:newFrame(x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(frame, x, y, w, h, sx, sy, sw, sh)

	return c
end

-- Texts
function gui:newTextBase(typ, txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(text + typ,x, y, w, h, sx, sy, sw, sh)
	c.text = txt
	c.align = "center"
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
		local Font,width,height,text=self.Font,self.dualDim.offset.size.x,self.dualDim.offset.size.y,self.text
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
	return c
end

function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(frame, txt, x, y, w, h, sx, sy, sw, sh)

	c.OnEnter(function()
		love.mouse.setCursor(cursor_hand)
	end)

	c.OnExit(function()
		love.mouse.setCursor()
	end)

	return c
end

function gui:newTextLabel(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(frame, txt, x, y, w, h, sx, sy, sw, sh)

	return c
end

function gui:newTextBox(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(box, txt, x, y, w, h, sx, sy, sw, sh)

	return c
end

-- Images
function gui:newImageBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(image + typ,x, y, w, h, sx, sy, sw, sh)
	c.color = color.white
	c.visibility = 0
	function c:setImage(i)
		drawer:newThread(function()
			thread.yield()
			local img
			if type(i)=="userdata" and i:type() == "Image" then
				img = i
			elseif type(i)=="string" then
				img = love.graphics.newImage(i)
			end
			local x, y, w, h = self:getAbsolutes()
			self.imageColor = color.white
			self.imageVisibility = 1
			self.image=img
			self.imageHeigth=img:getHeight()
			self.imageWidth=img:getWidth()
			self.quad=love.graphics.newQuad(0,0,w,h,self.imageWidth,self.imageHeigth)
		end).OnError(print)
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
	c:setImage(source)

	c.OnEnter(function()
		love.mouse.setCursor(cursor_hand)
	end)

	c.OnExit(function()
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
		while true do
			thread.hold(function() return self.video:isPlaying() end)
			if self.video:isPlaying() then
				status.color = color.green
			else
				status.color = color.red
				self.OnVideoFinished:Fire(self)
				thread.hold(function()
					return self.video:isPlaying()
				end)
			end
		end
	end)

	c.videoVisibility = 1
	c.videoColor = color.white

	return c
end

-- Draw Function

--local label, image, text, button, box, video
local drawtypes = {
	[0]= function(child, x, y, w, h) end,
	[1]=function(child, x, y, w, h)
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
		love.graphics.printf(child.text, x + child.textOffsetX, y + child.textOffsetY, w, child.align, child.rotation, child.textScaleX, child.textScaleY, 0, 0, child.textShearingFactorX, child.textShearingFactorY)
	end,
	[4] = function(child, x, y, w, h)
		-- box
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

	love.graphics.setScissor() -- Remove the scissor
end
drawer:newLoop(function()
	local children = gui:getAllChildren()
	for i=1,#children do
		local child = children[i]
		if child.effect then
			child.effect(function()
				draw_handler(child)
			end)
		elseif child.chain then
			child.chain.draw(function()
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

-- Root gui
gui.type = frame
gui.children = {}
gui.dualDim = gui:newDualDim()
gui.x = 0
gui.y = 0
updater:newLoop(function()
	gui.dualDim.offset.size.x, gui.dualDim.offset.size.y = love.graphics.getDimensions()
	gui.w = gui.dualDim.offset.size.x
	gui.h = gui.dualDim.offset.size.y
end)
return gui
