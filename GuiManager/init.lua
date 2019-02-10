local multi = require("multi")
local GLOBAL,THREAD=require("multi.integration.loveManager").init()
-- automatic resource loading will be added soonish
utf8 = require("utf8")
gui = {}
gui.__index = gui
gui.TB={}
gui.Version="VERSION" -- Is it really ready for release?
_GuiPro={
	GLOBAL = GLOBAL,
	THREAD = THREAD,
	jobqueue = multi:newSystemThreadedJobQueue(4),
	imagecache = {},
	GBoost=true,
	hasDrag=false,
	DragItem={},
	Children={},
	Visible=true,
	count=0,
	x=0,
	y=0,
	height=0,
	width=0,
	getChildren=function(self)
		return self.Children
	end
}
_GuiPro.jobqueue:registerJob("LoadImage",function(path,t)
	local dat = love.image.newImageData(path)
	return dat,path,t
end)
_GuiPro.Clips={}
_GuiPro.rotate=0
_defaultfont = love.graphics.setNewFont(12)
setmetatable(_GuiPro, gui)
function gui:LoadInterface(file)
	local add=".int"
	if string.find(file,".",1,true) then add="" end
	if love.filesystem.getInfo(file..add) then
    a,b=pcall(love.filesystem.load(file..add))
		if a then
			--print("Loaded: "..file)
		else
			print("Error loading file: "..file,b)
		end
	else
		print("File does not exist!")
		return false
	end
end
function gui.LoadAll(dir)
	files=love.filesystem.getDirectoryItems(dir)
	for i=1,#files do
		if string.sub(files[i],-4)==".int" then
			gui:LoadInterface(dir.."/"..files[i])
		end
	end
end
-- Start Of Load

gui.LoadAll("GuiManager/Core")
gui.LoadAll("GuiManager/Image-Animation")
gui.LoadAll("GuiManager/Frame")
gui.LoadAll("GuiManager/Item")
gui.LoadAll("GuiManager/Misc")
gui.LoadAll("GuiManager/Text")
gui.LoadAll("GuiManager/Drawing")

-- End of Load
gui:respectHierarchy()
_GuiPro.width,_GuiPro.height=love.graphics.getDimensions()
multi:newLoop(function() _GuiPro.width,_GuiPro.height=love.graphics.getDimensions() end)
multi:onDraw(function()
	local items=GetAllChildren(_GuiPro)
	for i=1,#items do
		items[i]:draw()
	end
end)
gui.ff=gui:newFrame("",0,0,0,0,0,0,1,1)
gui.ff.Color={0,0,0}
gui.ff:OnUpdate(function(self)
	self:BottomStack()
end)
