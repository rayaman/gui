require("utils")
require("bin")
print("Library binder version 1.0\n")
ver=io.getInput("Version #? ")
merged=bin.new()
init=bin.load("GuiManager/init.lua")
init:gsub("gui.Version=\"VERSION\"","gui.Version=\""..ver.."\"")
print("Parsing init file...")
a,b=init.data:find("-- Start Of Load")
c,d=init.data:find("-- End of Load")
_o=init:sub(b+1,c-1)
print("Setting up headers...")
start=init:sub(1,a-1)
_end=init:sub(d+1,-1)
merged:tackE(start.."\n")
print("Parsing paths...")
for path in _o:gmatch("\"(.-)\"") do
	files=io.scanDir(path)
	for i=1,#files do
		merged:tackE(bin.load(path.."/"..files[i]).data.."\n")
	end
end
merged:tackE(_end.."\n")
print("Finishing up...")
merged:tofile("GuiManager.lua")
print("GuiManager.lua has been created!")
os.sleep(3)
--[[
-- Start Of Load
gui.LoadAll("GuiManager/Core")
gui.LoadAll("GuiManager/Animation")
gui.LoadAll("GuiManager/Frame")
gui.LoadAll("GuiManager/Image")
gui.LoadAll("GuiManager/Item")
gui.LoadAll("GuiManager/Misc")
gui.LoadAll("GuiManager/Text")
gui.LoadAll("GuiManager/Drawing")
-- End of Load
]]
