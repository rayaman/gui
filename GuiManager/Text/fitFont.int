function gui:fitFont(n)
	local font
	if self.FontFile then
		if self.FontFile:match("ttf") then
			font = function(n)
				return love.graphics.newFont(self.FontFile, n,"normal")
			end
		else
			font = function(n)
				return love.graphics.newFont(self.FontFile, n)
			end
		end
	else
		font = function(n)
			return love.graphics.newFont(n)
		end
	end
	local Font,width,height,text=self.Font,self.width,self.height,self.text
	local s = 3
	Font = font(s)
	while Font:getHeight()<height and Font:getWidth(text)<width do
		s = s + 1
		Font = font(s)
	end
	Font = font(s - (2+(n or 0)))
	Font:setFilter("linear","nearest",4)
	self.Font = Font
	return s - (2+(n or 0))
end