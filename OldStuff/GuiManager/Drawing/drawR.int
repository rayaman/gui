function gui:drawR()
	if love.mouse.isDown("l")==false and love.mouse.isDown("m")==false and love.mouse.isDown("r")==false then
		_GuiPro.DragItem={}
		_GuiPro.hasDrag=false
	end
	if self.hidden then
		self.x=(self.Parent.width*self.scale.pos.x)+self.offset.pos.x+self.Parent.x
		self.y=(self.Parent.height*self.scale.pos.y)+self.offset.pos.y+self.Parent.y
		self.width=(self.Parent.width*self.scale.size.x)+self.offset.size.x
		self.height=(self.Parent.height*self.scale.size.y)+self.offset.size.y
		self.VIS = false
	end
	if self.Visible==true and self.VIS==true then
		self.x=(self.Parent.width*self.scale.pos.x)+self.offset.pos.x+self.Parent.x
		self.y=(self.Parent.height*self.scale.pos.y)+self.offset.pos.y+self.Parent.y
		self.width=(self.Parent.width*self.scale.size.x)+self.offset.size.x
		self.height=(self.Parent.height*self.scale.size.y)+self.offset.size.y
		local b=true
		for i,v in pairs(_GuiPro.Clips) do
			if self:isDescendant(v)==true then
				b=false
			end
		end
		if b==true then
			love.graphics.setStencilTest()
			love.graphics.setScissor()
		end
		if self.DrawRulesB then
			for dr=1,#self.DrawRulesB do
				self.DrawRulesB[dr](self)
			end
		end
		love.graphics.setColor(self.Color[1],self.Color[2],self.Color[3],self.Visibility)
		if self.ClipDescendants==true then
			_GuiPro.Clips[tostring(self)]=self
			love.graphics.setScissor(self.x, self.y, self.width, self.height)
		end
		if self:hasRoundness() then
			-- love.graphics.stencil(self.stfunc, "replace", 1)
			-- love.graphics.setStencilTest("greater", 0)
		end
		love.graphics.rectangle("fill", self.x, self.y, self.width, self.height,(self.rx or 1)*self.DPI,(self.ry or 1)*self.DPI,(self.segments or 1)*self.DPI)
		if string.find(self.Type, "Image") then
			self:ImageRule()
		end
		if self.Type=="Video" then
			self:VideoRule()
		end
		if self:hasRoundness() then
		  -- love.graphics.setStencilTest()
		end
		love.graphics.setColor(self.BorderColor[1], self.BorderColor[2], self.BorderColor[3],(self.BorderVisibility or 1))
		for b=0,self.BorderSize-1 do
			love.graphics.rectangle("line", self.x-(b/2), self.y-(b/2), self.width+b, self.height+b,(self.rx or 1)*self.DPI,(self.ry or 1)*self.DPI,(self.segments or 1)*self.DPI)
		end
		if string.find(self.Type, "Text") then
			if self.text~=nil and self.TextFormat ~= "center" then
				love.graphics.setColor(self.TextColor[1],self.TextColor[2],self.TextColor[3],self.TextVisibility)
				love.graphics.setFont(self.Font)
				love.graphics.printf(self.text, self.x, self.y, self.width, self.TextFormat,self.TextRotaion)
			elseif self.text~=nil and self.TextFormat == "center" then
				love.graphics.setColor(self.TextColor[1],self.TextColor[2],self.TextColor[3],self.TextVisibility)
				love.graphics.setFont(self.Font)
				love.graphics.printf(self.text, self.x+(self.width-self.Font:getWidth(self.text))/2, self.y+(self.height-self.Font:getHeight())/2, self.width, "left",self.TextRotaion)
			end
		end
		if self.DrawRulesE then
			for dr=1,#self.DrawRulesE do
				self.DrawRulesE[dr](self)
			end
		end
	end
end