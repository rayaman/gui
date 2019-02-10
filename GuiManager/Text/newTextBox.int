function gui:newTextBox(t,name, x, y, w, h, sx ,sy ,sw ,sh)
	x,y,w,h,sx,sy,sw,sh=filter(name, x, y, w, h, sx ,sy ,sw ,sh)
	local c=self:newTextBase("TextBox",t,name, x, y, w, h, sx ,sy ,sw ,sh)
	local realText = {}
	local hiddenText = {}
	for i = 1,#t do
		table.insert(realText,t:sub(i,i))
		table.insert(hiddenText,t:sub(i,i))
	end
	local curpos = 1
	c.ClearOnFocus=false
	c.LoseFocusOnEnter=true
	c.hideText = false
	local funcE = {}
	local clear = true
	local Focused = false
	local autoScaleFont = false
	local moved = false
	local alarm = multi:newAlarm(.5):OnRing(function(a)
		moved = false
	end)
	function c:AutoScaleFont(bool)
		autoScaleFont = bool
		self:fitFont()
	end
	function c:ClearOnFocus(bool)
		clear = bool
	end
	c.funcF={function()
		love.keyboard.setTextInput(true)
	end}
	c.funcE={function()
		love.keyboard.setTextInput(false)
	end}
	function c:OnEnter(func)
		table.insert(funcE,func)
	end
	function c:focus()
		Focused = true
		love.keyboard.setKeyRepeat(true)
		love.keyboard.setTextInput(true)
	end
	function c:unfocus()
		Focused = false
		love.keyboard.setKeyRepeat(false)
		love.keyboard.setTextInput(false)
	end
	c:OnPressed(function(b,self,x,y)
		if not Focused then
			if clear then
				realText = {}
				hiddenText = {}
				curpos = 1
			end
			tags:ClearOnFocus(false)
			self:focus()
		end
		moved = true
		alarm:Reset()
		local width = self.Font:getWidth(self.text)
		if x > self.x+width then
			curpos = #hiddenText+1
		elseif x < self.x then
			curpos = 1
		else
			for i = 1,#hiddenText do
				width = self.Font:getWidth(self.text:sub(1,i))
				if x-self.x < width then
					curpos = i
					break
				end
			end
		end
	end)
	c:OnPressedOuter(function(b,self)
		if Focused then
			self:unfocus()
		end
	end)
	c:OnUpdate(function(self)
		if #hiddenText==0 then self.text = "" return end
		if self.hideText then
			self.text = table.concat(hiddenText)
		else
			self.text = table.concat(realText)
		end
		self.TextFormat = "left"
	end)
	multi.OnTextInput(function(t)
		table.insert(hiddenText,curpos,"*")
		table.insert(realText,curpos,t)
		curpos = curpos + 1
		if autoScaleFont then
			c:fitFont()
		end
	end)
	multi.OnKeyPressed(function(key, scancode, isrepeat )
		if key == "backspace" then
			table.remove(hiddenText,curpos-1)
			table.remove(realText,curpos-1)
			curpos = curpos - 1
			if curpos < 1 then
				curpos = 1
			end
			if autoScaleFont then
				c:fitFont()
			end
		elseif key == "enter" then
			
		elseif key == "delete" then
			realText = {}
			hiddenText = {}
			curpos = 1
		elseif key == "left" then
			curpos = curpos - 1
			if curpos < 1 then
				curpos = 1
			end
			moved = true
			alarm:Reset()
		elseif key == "right" then
			curpos = curpos + 1
			if curpos > #realText+1 then
				curpos = #realText+1
			end
			moved = true
			alarm:Reset()
		end
	end)
	local blink = false
	multi:newThread("TextCursonBlinker",function()
		while true do
			thread.sleep(1.5)
			blink = not blink
		end
	end)
	self.DrawRulesE = {function()
		if --[[blink or moved]] true then
			local width = c.Font:getWidth(c.text:sub(1,curpos-1))
			local height = c.Font:getHeight()
			if c.TextFormat == "center" then
				-- print(c.x+(c.width/2+width),c.height,c.x+(c.width/2+width),c.height+height)
				-- love.graphics.line(c.x+(c.width/2+width),c.height,c.x+(c.width/2+width),c.height+height)
			elseif c.TextFormat == "right" then
			--love.graphics.line(c.x+width,c.y,c.x+width,c.y+c.Font:getHeight())
			elseif c.TextFormat == "left" then
				love.graphics.line(c.x+width,c.y,c.x+width,c.y+height)
			end
		end
	end}
    return c
end