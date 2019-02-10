function gui:getFullSize()
	local maxx,maxy=self.width,self.height
	local px,py=self.x,self.y
	local temp = self:GetAllChildren()
	for i=1,#temp do
		if temp[i].width+temp[i].x>maxx then
			maxx=temp[i].width+temp[i].x
		end
		if temp[i].height+temp[i].y>maxy then
			maxy=temp[i].height+temp[i].y
		end
	end
	return maxx,maxy,px,py
end