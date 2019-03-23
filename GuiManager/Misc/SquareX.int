function gui:SquareX(n)
	local n = n or 1
	local w = self.Parent.width
	local rw = w*n
	local s = (w-rw)/2
	self:setDualDim(self.x+s,self.y+s,rw,rw,sx,sy)
	self:Move(s,s)
	return self.Parent.width,rw
end