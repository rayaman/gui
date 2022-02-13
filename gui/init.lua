local multi,thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local color = require("gui.color")
local gui = {}
local updater = multi:newProcessor("UpdateManager",true)
local drawer = multi:newProcessor("DrawManager",true)
local bit = require("bit")
local band, bor = bit.band, bit.bor
local floor, ceil = math.floor,math.ceil
gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

local frame, image, text, button, box, video = 0, 1, 2, 4, 8, 16

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
			table.insert(Stuff,Objs[i])
			local Items = Objs[i]:getChildren()
			if Items ~= nil then
				Seek(Items)
			end
		end
	end
	return Stuff
end

function gui:newThread(func)
	return updater:newThread("ThreadHandler", func, self, thread)
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

local mainupdater = updater:newLoop().OnLoop

-- Base Library
function gui:newBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = {}
	local centerX = false
	local centerY = false
	local centering = false
	local pressed = false
	setmetatable(c, gui)
	c.parent = self
	c.type = typ
	c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
	c.children = {}
	c.visible = true
	c.visibility = 1
	c.color = {.6,.6,.6}
	c.borderColor = color.black
	c.rotation = 0

	c.WhilePressing = multi:newConnection()
	c.OnPressed = multi:newConnection()
	c.OnReleased = multi:newConnection()
	c.maxMouseButtons = 5

	c:newThread(function()
		while true do
			thread.sleep(.1)
			local x, y, w, h = c:getAbsolutes()
			local mx, my = love.mouse.getPosition()
			for i=1,c.maxMouseButtons do
				if love.mouse.isDown(i) and not(mx > x + w or mx < x or my > y + h or my < y) then
					if not pressed then
						c.OnPressed:Fire(c, i, mx, my)
					end
					pressed = true
					c.WhilePressing:Fire(c, i, mx, my)
					c:newThread(function()
						thread.hold(function() return not(love.mouse.isDown(i)) end)
						if pressed then
							c.OnReleased:Fire(c, i, mx, my)
						end
						pressed = false
					end)
				end
			end
		end
	end)
	c:WhilePressing(function(x,y,self)
		if not pressed then
			pressed = true
			c.OnPressed:Fire(x,y,self)
		end
	end)

	function c:OnUpdate(func) -- Not crazy about this approach, will probably rework this
		if type(self)=="function" then func = self end
		mainupdater(function()
			func(c)
		end)
	end

	local function centerthread()
		updater:newThread("Object_Centering",function()
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
	local c = self:newTextBase(button, txt, x, y, w, h, sx, sy, sw, sh)

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
	local c = self:newImageBase(button, x, y, w, h, sx, sy, sw, sh)
	c:setImage(source)
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
		c.videoHeigth=c.video:getHeight()
		c.videoWidth=c.video:getWidth()
		c.quad=love.graphics.newQuad(0,0,w,h,c.videoWidth,c.videoHeigth)
	end
	if type(source)=="string" then
		c:setVideo(source)
	end
	function c:play()
		c.playing = true
		c.video:play()
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
				love.graphics.draw(child.image,x,y,math.rad(child.rotation),w/child.imageWidth,h/child.imageHeigth)
			else
				love.graphics.draw(child.image,child.quad,x,y,math.rad(child.rotation),w/child.imageWidth,h/child.imageHeigth)
			end
		end
	end,
	[2] = function(child, x, y, w, h)
		love.graphics.setColor(child.textColor[1],child.textColor[2],child.textColor[3],child.textVisibility)
		love.graphics.setFont(child.font)
		love.graphics.printf(child.text, x + child.textOffsetX, y + child.textOffsetY, w, child.align, child.rotation, child.textScaleX, child.textScaleY, 0, 0, child.textShearingFactorX, child.textShearingFactorY)
	end,
	[4] = function(child, x, y, w, h)
		-- button
	end,
	[8] = function(child, x, y, w, h)
		-- box
	end,
	[16] = function(child, x, y, w, h)
		if child.video and child.playing then
			love.graphics.setColor(child.videoColor[1],child.videoColor[2],child.videoColor[3],child.videoVisibility)
			if w~=child.imageWidth and h~=child.imageHeigth then
				love.graphics.draw(child.video,x,y,math.rad(child.rotation),w/child.videoWidth,h/child.videoHeigth)
			else
				love.graphics.draw(child.video,child.quad,x,y,math.rad(child.rotation),w/child.videoWidth,h/child.videoHeigth)
			end
		end
	end,
}

drawer:newLoop(function()
	local children = gui:getAllChildren()
	for i=1,#children do
		local child = children[i]
		local bg = child.color
		local bbg = child.borderColor
		local type = child.type
		local vis = child.visibility
		local x, y, w, h = child:getAbsolutes()
		child.x = x
		child.y = y
		child.w = w
		child.h = h
		-- local x = (child.parent.dualDim.offset.size.x*child.dualDim.scale.pos.x)+child.dualDim.offset.pos.x+child.parent.dualDim.offset.pos.x
		-- local y = (child.parent.dualDim.offset.size.y*child.dualDim.scale.pos.y)+child.dualDim.offset.pos.y+child.parent.dualDim.offset.pos.y
		-- local w = (child.parent.dualDim.offset.size.x*child.dualDim.scale.size.x)+child.dualDim.offset.size.x
		-- local h = (child.parent.dualDim.offset.size.y*child.dualDim.scale.size.y)+child.dualDim.offset.size.y
		
		-- Set color
		love.graphics.setColor(bg[1],bg[2],bg[3],vis)
		love.graphics.rectangle("fill", x, y, w, h--[[, rx, ry, segments]])
		love.graphics.setColor(bbg[1],bbg[2],bbg[3],vis)
		love.graphics.rectangle("line", x, y, w, h--[[, rx, ry, segments]])
		-- Start object specific stuff
		drawtypes[band(type,video)](child,x,y,w,h)
		drawtypes[band(type,image)](child,x,y,w,h)
		drawtypes[band(type,text)](child,x,y,w,h)
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
