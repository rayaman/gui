local multi,thread = require("multi"):init()
local GLOBAL, THREAD = require("multi.integration.loveManager"):init()
local gui = {}
gui.updater = multi:newProcessor("UpdateManager",true)
gui.drawer = multi:newProcessor("DrawManager",true)
gui.__index = gui
gui.MOUSE_PRIMARY = 1
gui.MOUSE_SECONDARY = 2
gui.MOUSE_MIDDLE = 3
-- Base Library
function gui:newBase(typ,dualDim)
	local c = {}
	c.parent = self
	c.dualDim = dualDim
	setmetatable(c, gui)
end
function gui:newDualDim(x,y,w,h,sx,sy,sw,sh)
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
function gui:newFrame()
	--
end
-- Texts
function gui:newTextBase(x,y,w,h,sx,sy,sw,sh)
	--
end
function gui:newTextLabel()
	--
end
function gui:newTextButton()
	--
end
function gui:newTextLabel()
	--
end
function gui:newTextBox()
	--
end
-- Images

-- Drawing
function gui:draw()
	gui.drawer.run()
end
-- Updating
function gui:update()
	gui.updater.run()
end
-- Root gui
gui.Type = "root"
gui.dualDim = gui:newDualDim()
gui.updater:newLoop(function() gui.dualDim.offset.width,gui.dualDim.offset.height = love.graphics.getDimensions() end)
return gui