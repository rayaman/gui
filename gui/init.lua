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
local frame, label ,button, image, text, box = 0, 1, 2, 4, 8, 16
local children = {}
function gui:getChildren()
	return self.Children
end
function gui:getAllChildren()
	for i=0, #children do children[i]=nil end
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

drawer:newLoop(function()

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