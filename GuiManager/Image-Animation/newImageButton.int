function gui:newImageButton(i,name, x, y, w, h, sx ,sy ,sw ,sh)
	x,y,w,h,sx,sy,sw,sh=filter(name, x, y, w, h, sx ,sy ,sw ,sh)
	local c=self:newBase("ImageButton",name, x, y, w, h, sx ,sy ,sw ,sh)
	c:SetImage(i)
	c.Visibility=0
	c.ImageVisibility=1
	c.rotation=0
	c:OnEnter(function()
		love.mouse.setCursor(_GuiPro.CursorH)
	end)
	c:OnExit(function()
		love.mouse.setCursor(_GuiPro.CursorN)
	end)
    return c
end