function gui:ClipDescendants(bool)
	local c = self:GetAllChildren()
	if not c[#c] then return end
	if bool then
		self.clipParent = self.Parent
		self.Clipping = true
		c[#c].resetClip = true
		for i = 1,#c do
			c[i].ClipReference = self
		end
	else
		self.Clipping = nil
		c[#c].resetClip = nil
		for i = 1,#c do
			c[i].ClipReference = nil
		end
	end
end