function gui:SetImage(i)
	if not i then return end
	if type(i) == "userdata" and i:type() == "Image" then
		self.Image=i
		self.ImageHeigth=self.Image:getHeight()
		self.ImageWidth=self.Image:getWidth()
		self.Quad=love.graphics.newQuad(0,0,self.width,self.height,self.ImageWidth,self.ImageHeigth)
	elseif type(i)=="string" then
		gui.loadImageData(i,nil,function(imagedata)
			self.Image = love.graphics.newImage(imagedata)
			self.ImageHeigth=self.Image:getHeight()
			self.ImageWidth=self.Image:getWidth()
			self.Quad=love.graphics.newQuad(0,0,self.width,self.height,self.ImageWidth,self.ImageHeigth)
		end)
	end
end