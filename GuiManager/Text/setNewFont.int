function gui:setNewFont(filename,FontSize)
	if type(filename)=="string" then
		self.FontFile = filename
		self.Font = love.graphics.newFont(filename, tonumber(FontSize))
	else
		self.Font=love.graphics.newFont(tonumber(filename))
	end
	self.Font:setFilter("linear","nearest",4)
end