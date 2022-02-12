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

local frame, label, image, text, button, box, video = 0, 1, 2, 4, 8, 16, 32

function gui:getChildren()
	return self.children
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

-- Base Library
function gui:newBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = {}
	c.parent = self
	c.type = typ
	c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
	c.children = {}
	c.visible = true
	c.visibility = 1
	c.color = {.6,.6,.6}
	c.borderColor = color.black
	setmetatable(c, gui)
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
	c.radians = 0
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
		love.graphics.printf(self.text, 0, 0, self.dualDim.offset.size.x, "left", self.radians, self.textScaleX, self.textScaleY, 0, 0, self.textShearingFactorX, self.textShearingFactorY)
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
		return top, bottom
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
		self.OnFontUpdated:Fire(self)
		return s - (2+(n or 0))
	end
	c.OnFontUpdated(function(self)
		local h = (self.parent.dualDim.offset.size.y*self.dualDim.scale.size.y)+self.dualDim.offset.size.y
		local top, bottom = self:calculateFontOffset()
		self.textOffsetY = (bottom/2-top)/4 - 1
	end)
	return c
end

function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(button, txt, x, y, w, h, sx, sy, sw, sh)

	return c
end

function gui:newTextLabel(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(label, txt, x, y, w, h, sx, sy, sw, sh)

	return c
end

function gui:newTextBox(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(box, txt, x, y, w, h, sx, sy, sw, sh)

	return c
end

-- Images
function gui:newImageBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(image + typ,x, y, w, h, sx, sy, sw, sh)

	return c
end

function gui:newImageLabel(x, y, w, h, sx, sy, sw, sh)
	local c = self:newImageBase(label, x, y, w, h, sx, sy, sw, sh)

	return c
end

function gui:newImageButton(x, y, w, h, sx, sy, sw, sh)
	local c = self:newImageBase(button, x, y, w, h, sx, sy, sw, sh)

	return c
end
-- Draw Function

--local label, image, text, button, box, video
--[[
	c.text = txt
	c.align = "left"
	c.radians = 0
	c.textScaleX = 1
	c.textScaleY = 1
	c.textOffsetX = 0
	c.textOffsetY = 0
	c.textShearingFactorX = 0
	c.textShearingFactorY = 0
]]
local drawtypes = {
	[0]= function() end, -- 0 
	[1] = function() -- 1
		-- label
	end,
	[2]=function() -- 2
		-- image
	end,
	[4] = function(child, x, y, w, h) -- 4
		love.graphics.setColor(child.textColor[1],child.textColor[2],child.textColor[3],child.textVisibility)
		love.graphics.setFont(child.font)
		love.graphics.printf(child.text, x + child.textOffsetX, y + child.textOffsetY, w, child.align, child.radians, child.textScaleX, child.textScaleY, 0, 0, child.textShearingFactorX, child.textShearingFactorY)
	end,
	[8] = function() -- 8
		-- button
	end,
	[16] = function() -- 16
		-- box
	end,
	[32] = function() -- 32
		-- video
	end,
	[64] = function() -- 64
		-- item
	end
}

drawer:newLoop(function()
	local children = gui:getAllChildren()
	for i=1,#children do
		local child = children[i]
		local bg = child.color
		local bbg = child.borderColor
		local type = child.type
		local vis = child.visibility
		local x = (child.parent.dualDim.offset.size.x*child.dualDim.scale.pos.x)+child.dualDim.offset.pos.x+child.parent.dualDim.offset.pos.x
		local y = (child.parent.dualDim.offset.size.y*child.dualDim.scale.pos.y)+child.dualDim.offset.pos.y+child.parent.dualDim.offset.pos.y
		local w = (child.parent.dualDim.offset.size.x*child.dualDim.scale.size.x)+child.dualDim.offset.size.x
		local h = (child.parent.dualDim.offset.size.y*child.dualDim.scale.size.y)+child.dualDim.offset.size.y
		
		-- Do Frame stuff first
		-- Set color
		love.graphics.setColor(bg[1],bg[2],bg[3],vis)
		love.graphics.rectangle("fill", x, y, w, h--[[, rx, ry, segments]])
		love.graphics.setColor(bbg[1],bbg[2],bbg[3],vis)
		love.graphics.rectangle("line", x, y, w, h--[[, rx, ry, segments]])
		-- Start object specific stuff
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
updater:newLoop(function() gui.dualDim.offset.size.x, gui.dualDim.offset.size.y = love.graphics.getDimensions() end)
return gui
