function gui:newTextButton(t,name, x, y, w, h, sx ,sy ,sw ,sh)
	local x,y,w,h,sx,sy,sw,sh=filter(name, x, y, w, h, sx ,sy ,sw ,sh)
	local c=self:newTextBase("TextButton",t,name, x, y, w, h, sx ,sy ,sw ,sh)
	c:OnMouseEnter(function()
		love.mouse.setCursor(_GuiPro.CursorH)
	end)
	c:OnMouseExit(function()
		love.mouse.setCursor(_GuiPro.CursorN)
	end)
    return c
end