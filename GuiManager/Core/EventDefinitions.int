local buttonConv = {"l","r","m","x1","x2"} -- For the old stuff
function gui:OnClicked(func)
	if not self.clickEvnt then
		self.clickEvnt = true
		self._connClicked = multi:newConnection()
		self._connClicked(func)
		multi:newThread(self.Name.."_Updater",function()
			while true do
				thread.hold(function() return self.Active or self.Destroyed end)
				if love.mouse.isDown(1) and self:canPress() then
					self._connClicked:Fire("1",self,love.mouse.getX()-self.x,love.mouse.getY()-self.y)
				end
				if love.mouse.isDown(2) and self:canPress() then
					self._connClicked:Fire("r",self,love.mouse.getX()-self.x,love.mouse.getY()-self.y)
				end
				if love.mouse.isDown(3) and self:canPress() then
					self._connClicked:Fire("m",self,love.mouse.getX()-self.x,love.mouse.getY()-self.y)
				end
				if love.mouse.isDown(4) and self:canPress() then
					self._connClicked:Fire("x1",self,love.mouse.getX()-self.x,love.mouse.getY()-self.y)
				end
				if love.mouse.isDown(5) and self:canPress() then
					self._connClicked:Fire("x2",self,love.mouse.getX()-self.x,love.mouse.getY()-self.y)
				end
				if self.Destroyed then
					thread.kill()
				end
			end
		end)
	else
		self._connClicked(func)
	end
end
function gui:OnPressed(func)
	multi.OnMousePressed(function(x,y,b)
		if self:canPress() then
			func(buttonConv[b],self,x,y)
		end
	end)
end
function gui:OnPressedOuter(func)
	multi.OnMousePressed(function(x,y,b)
		if not(self:canPress()) then
			func(buttonConv[b],self)
		end
	end,nil,1)
end
function gui:OnReleased(func)
	multi.OnMouseReleased(function(x,y,b)
		if self:canPress() then
			func(buttonConv[b],self,x,y)
		end
	end)
end
function gui:OnReleasedOuter(func)
	multi.OnMouseReleased(function(x,y,b)
		if not(self:canPress()) then
			func(buttonConv[b],self)
		end
	end,nil,1)
end
function gui:OnUpdate(func)
	if not self.updateEvnt then
		self._connUpdate = multi:newConnection()
		self._connUpdate(func)
		self.updateEvnt = true
		multi:newThread(self.Name.."_Updater",function()
			while true do
				thread.hold(function() return self.Active end)
				self._connUpdate:Fire(self)
			end
		end)
	else
		self._connUpdate(func)
	end
end
function gui:OnMouseMoved(func)
	multi.OnMouseMoved(function(x,y,dx,dy)
		if self:canPress() then
			func(self,x-self.x,y-self.y,dx,dy)
		end
	end,nil,1)
end
gui.WhileHovering=gui.OnMouseMoved -- To keep older features working
local mbenter = multi:newConnection()
function gui:OnMouseEnter(func)
	self.HE=false
	mbenter(func)
	self:OnMouseMoved(function()
		if self.HE == false then
			self.HE=true
			self._HE = true
			mbenter:Fire(self)
		end
	end)
end
function gui:OnMouseExit(func)
	if not self.exitEvnt then
		self._connExit = multi:newConnection()
		self._connExit(func)
		self.exitEvnt = true
		self.HE=false
		multi:newThread(self.Name.."_OnExit",function()
			while true do
				thread.hold(function() return self.HE or self.Destroyed end)
				if not(self:canPress()) then
					self.HE=false
					self._connExit:Fire(self)
				end
				if self.Destroyed then
					thread.kill()
				end
			end
		end)
	else
		self._connExit(func)
	end
end
--[[
x=(love.mouse.getX()-self.x)
y=(love.mouse.getY()-self.y)
self:Move(x,y)
]]
function gui:OnMouseWheelMoved(func)
	multi.OnMouseWheelMoved(function(...)
		if self:canPress() then
			func(self,...)
		end
	end)
end
function gui:enableDragging(bool)
	self.draggable = bool
	if self.dragEvnt then
		return
	end
	self.dragEvnt = true
	self._connDragStart = multi:newConnection()
	self._connDragging = multi:newConnection()
	self._connDragEnd = multi:newConnection()
	self.hasDrag = false
	local startX
	local startY
	self:OnPressed(function(b,self,x,y)
		if b~=self.dragbut or not(self.draggable) then return end
		self._connDragStart:Fire(self)
		self.hasDrag = true
		startX = x
		startY = y
	end)
	multi.OnMouseMoved(function(x,y,dx,dy)
		if self.hasDrag and self.draggable then
			self:Move(dx,dy)
			self._connDragging:Fire(self)
		end
	end)
	multi.OnMouseReleased(function(x,y,b)
		if buttonConv[b]~=self.dragbut or not(self.draggable) or not(self.hasDrag) then return end
		self.hasDrag = false
		startX = nil
		startY = nil
		self._connDragEnd:Fire(self)
	end)
end
function gui:OnDragStart(func)
	if not self.dragEvnt then
		self:enableDragging(true)
		self._connDragStart(func)
	else
		self._connDragStart(func)
	end
end
function gui:OnDragging(func)
	if not self.dragEvnt then
		self:enableDragging(true)
		self._connDragging(func)
	else
		self._connDragging(func)
	end
end
function gui:OnDragEnd(func)
	if not self.dragEvnt then
		self:enableDragging(true)
		self._connDragEnd(func)
	else
		self._connDragEnd(func)
	end
end
function gui:OnHotKey(key,func)
	local tab=key:split("+")
	multi.OnKeyPressed(function()
		for i=1,#tab do
			if not(love.keyboard.isDown(tab[i])) then
				return
			end
		end
		func(self)
	end)
end
gui.addHotKey=gui.OnHotKey
gui.setHotKey=gui.OnHotKey