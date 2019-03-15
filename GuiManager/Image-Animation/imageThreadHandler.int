local queueUpload = love.thread.getChannel("ImageUploader")
local queueDownload = love.thread.getChannel("ImageDownloader")
local code = [[
require("love.image")
require("love.timer")
local queueUpload = love.thread.getChannel("ImageUploader")
local queueDownload = love.thread.getChannel("ImageDownloader")
while true do
	love.timer.sleep(.001)
	local data = queueUpload:pop()
	if data then
	queueDownload:push{data[1],love.image.newImageData(data[2])}
	end
end
]]
local count = 0
local conn = multi:newConnection()
function gui.loadImageData(path,tag,callback)
	local c = count
	count = count + 1
	queueUpload:push{c,path}
	if not callback then
		return conn
	else
		local cd
		cd = conn(function(id,data)
			if id == c then
				callback(data,tag,id)
				cd:Destroy()
			end
		end)
	end
	return c
end
multi:newLoop(function()
	local dat = queueDownload:pop()
	if dat then
		conn:Fire(dat[1],dat[2])
	end
end)
for i = 1,love.system.getProcessorCount() do
	local t = love.thread.newThread(code)
	t:start()
end