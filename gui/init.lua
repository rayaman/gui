local multi,thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local gui = {}
local updater = multi:newProcessor("UpdateManager",true)
local drawer = multi:newProcessor("DrawManager",true)
local bit = require("bit")
local band, bor = bit.band, bit.bor
gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3

local label, image, text, button, box, video = 1, 2, 4, 8, 16, 32
function gui:getChildren()
	return self.Children
end
function gui:getAllChildren()
	local Stuff = {}
	function Seek(Items)
		for i=1,#Items do
			if Items[i].Visible==true then
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
		if Objs[i].Visible==true then
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
	c.Type = typ
	c.dualDim = self:newDualDim(x, y, w, h, sx, sy, sw, sh)
	c.Children = {}
	c.Visible = true
	c.Visibility = 1
	setmetatable(c, gui)
	
	-- Add to the parents children table
	table.insert(self.Children,c)
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
-- Objects
-- Frames
function gui:newFrame(x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(frame, x, y, w, h, sx, sy, sw, sh)
end
-- Texts
function gui:newTextBase(typ, txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(text + typ,x, y, w, h, sx, sy, sw, sh)
	c.text = txt
end
function gui:newTextButton(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(button, txt, x, y, w, h, sx, sy, sw, sh)
end
function gui:newTextLabel(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(label, txt, x, y, w, h, sx, sy, sw, sh)
end
function gui:newTextBox(txt, x, y, w, h, sx, sy, sw, sh)
	local c = self:newTextBase(box, txt, x, y, w, h, sx, sy, sw, sh)
end
-- Images
function gui:newImageBase(typ,x, y, w, h, sx, sy, sw, sh)
	local c = self:newBase(image + typ,x, y, w, h, sx, sy, sw, sh)
end
function gui:newImageLabel(x, y, w, h, sx, sy, sw, sh)
	local c = self:newImageBase(label, x, y, w, h, sx, sy, sw, sh)
end
function gui:newImageButton(x, y, w, h, sx, sy, sw, sh)
	local c = self:newImageBase(button, x, y, w, h, sx, sy, sw, sh)
end
-- Draw Function

--local label, image, text, button, box, video

local drawtypes = {
	[0]= function() end, -- 0 
	[1] = function() -- 1
		-- label
	end,
	[2]=function() -- 2
		-- image
	end,
	[4] = function() -- 4
		-- text
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
--[[
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
]]
drawer:newLoop(function()
	local children = gui:getAllChildren()
	for i=1,#children do
		local child = children[i]
		local type = child.Type
		local x = (child.Parent.dualDim.offset.size.x*child.dualDim.scale.pos.x)+child.dualDim.offset.pos.x+child.Parent.dualdim.offset.pos.x
		local y = (child.Parent.dualDim.offset.size.y*child.dualDim.scale.pos.y)+child.dualDim.offset.pos.y+child.Parent.dualdim.offset.pos.y
		local width = (child.Parent.dualDim.offset.size.x*child.dualDim.scale.size.x)+child.dualDim.offset.size.x
		local heigh = (child.Parent.dualDim.offset.size.y*child.dualDim.scale.size.y)+child.dualDim.offset.size.y
		-- Do Frame stuff first

		-- Start object specific stuff
		drawtypes[band(type,label)](child)
	end
end)

-- Drawing and Updating
gui.draw = drawer.run
gui.update = updater.run

-- Root gui
gui.Type = "root"
gui.Children = {}
gui.dualDim = gui:newDualDim()
updater:newLoop(function() gui.dualDim.offset.width, gui.dualDim.offset.height = love.graphics.getDimensions() end)
return gui