function gui:newAnim(file,delay, x, y, w, h, sx ,sy ,sw ,sh)
	local _files=alphanumsort(love.filesystem.getDirectoryItems(file))
	local x,y,w,h,sx,sy,sw,sh=filter(file, x, y, w, h, sx ,sy ,sw ,sh)
	local c=self:newBase("ImageAnimation",file, x, y, w, h, sx ,sy ,sw ,sh)
	if not w and not h then
		local w,h = love.graphics.newImage(file.."/".._files[1]):getDimensions()
		c:setDualDim(nil,nil,w,h)
	end
	c.Visibility=0
	c.ImageVisibility=1
	c.delay=delay or .05
	c.files={}
	c.AnimStart={}
	c.AnimEnd={}
	local count = 0
	local max
	for i=1,#_files do
		if string.sub(_files[i],-1,-1)~="b" then
			count = count + 1
			gui.loadImageData(file.."/".._files[i],count,function(imagedata,id)
				c.files[id] = love.graphics.newImage(imagedata)
			end)
		end
	end
	c.step=multi:newTStep(1,count,1,c.delay)
	c.step.parent=c
	c.rotation=0
	c.step:OnStart(function(step)
		for i=1,#step.parent.AnimStart do
			step.parent.AnimStart[i](step.parent)
		end
	end)
	c.step:OnStep(function(step,pos)
		step.parent:SetImage(step.parent.files[pos])
	end)
	c.step:OnEnd(function(step)
		for i=1,#step.parent.AnimEnd do
			step.parent.AnimEnd[i](step.parent)
		end
	end)
	function c:OnAnimStart(func)
		table.insert(self.AnimStart,func)
	end
	function c:OnAnimEnd(func)
		table.insert(self.AnimEnd,func)
	end
	function c:Pause()
		self.step:Pause()
	end
	function c:Resume()
		self.step:Resume()
	end
	function c:Reset()
		self.step.pos=1
		self.step:Reset()
	end
	function c:getFrames()
		return #self.files
	end
	function c:getFrame()
		return self.step.pos
	end
	function c:setFrame(n)
		return self:SetImage(self.files[n])
	end
	return c
end