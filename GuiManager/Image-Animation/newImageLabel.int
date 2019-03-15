function gui:newImageLabel(i,name, x, y, w, h, sx ,sy ,sw ,sh)
	if not name then name = "Imagelabel" end
	x,y,w,h,sx,sy,sw,sh=filter(name, x, y, w, h, sx ,sy ,sw ,sh)
	local c=self:newBase("ImageLabel",name, x, y, w, h, sx ,sy ,sw ,sh)
	c:SetImage(i)
	c.Visibility=0
	c.ImageVisibility=1
	c.rotation=0
	return c
end