_GuiPro.Frames = {}
_GuiPro.Type = "Window"
_GuiPro.depth = 0
function gui.enableAutoWindowScaling(b)
  _GuiPro.DPI_ENABLED=b or true
  _defaultfont=love.graphics.newFont(12*love.window.getPixelScale())
end
function filter(name, x, y, w, h, sx ,sy ,sw ,sh)
	if type(name)~="string" then
		sh=sw
		sw=sy
		sy=sx
		sx=h
		h=w
		w=y
		y=x
		x=name
	end
	return x,y,w,h,sx,sy,sw,sh
end
function gui:getChildren()
	return self.Children
end
function gui:newBase(tp,name, x, y, w, h, sx ,sy ,sw ,sh)
	_GuiPro.count=_GuiPro.count+1
    local c = {}
    setmetatable(c, gui)
	if self==gui then
		c.Parent=_GuiPro
	else
		c.Parent=self
	end
	if tp:match("Frame") then
		_GuiPro.Frames[#_GuiPro.Frames+1] = c
	end
	if self.Type and self.Type:match("Frame") then
		c.FrameRef = self
	else
		c.FrameRef = self.FrameRef
	end
	c.segments=nil
	c.ry=nil
	c.rx=nil
	c.DPI=1
	c.isLeaf = true
	c.Parent.isLeaf = false
	if _GuiPro.DPI_ENABLED then
		c.DPI=love.window.getPixelScale()
		x, y, w, h=c.DPI*x,c.DPI*y,c.DPI*w,c.DPI*h
	end
	c.centerFontY=true
	c.FormFactor="rectangle"
	c.Type=tp
	c.Active=true
	c.form="rectangle"
	c.Draggable=false
	c.Name=name or "Gui"..tp
	c:SetName(name)
	c.BorderSize=1
	c.BorderColor={0,0,0}
	c.VIS=true
	c.Visible=true
	c.oV=true
	c.Children={}
	c.hovering=false
	c.rclicked=false
	c.lclicked=false
	c.mclicked=false
	c.clicked=false
	c.Visibility=1
	c.TextWrap=true
	c.scale={}
	c.scale.size={}
	c.scale.size.x=sw or 0
	c.scale.size.y=sh or 0
	c.offset={}
	c.offset.size={}
	c.offset.size.x=w or 0
	c.offset.size.y=h or 0
	c.scale.pos={}
	c.scale.pos.x=sx or 0
	c.scale.pos.y=sy or 0
	c.offset.pos={}
	c.offset.pos.x=x or 0
	c.offset.pos.y=y or 0
    c.width = 0
    c.height = 0
	c.LRE=false
	c.RRE=false
	c.MRE=false
	c.Color = {255, 255, 255}
	function c:setRoundness(rx,ry,segments)
		self.segments=segments
		self.ry=ry
		self.rx=rx
	end
	function c.stfunc()
		love.graphics.rectangle("fill", c.x, c.y, c.width, c.height,c.rx,c.ry,c.segments)
	end
	function c:hasRoundness()
		return (self.ry or self.rx)
	end
	c.tid={}
	c.touchcount=0
	c.x=(c.Parent.width*c.scale.pos.x)+c.offset.pos.x+c.Parent.x
	c.y=(c.Parent.height*c.scale.pos.y)+c.offset.pos.y+c.Parent.y
	c.width=(c.Parent.width*c.scale.size.x)+c.offset.size.x
	c.height=(c.Parent.height*c.scale.size.y)+c.offset.size.y
	function c:ImageRule()
		if self.Image then
			local sx=self.width/self.ImageWidth
			local sy=self.height/self.ImageHeigth
			love.graphics.setColor(self.Color[1],self.Color[2],self.Color[3],self.ImageVisibility*255)
			if self.width~=self.ImageWidth and self.height~=self.ImageHeigth then
				love.graphics.draw(self.Image,self.x,self.y,math.rad(self.rotation),sx,sy)
			else
				love.graphics.draw(self.Image,self.Quad,self.x,self.y,math.rad(self.rotation),sx,sy)
			end
		end
	end
	function c:VideoRule()
		if self.Video then
			local sx=self.width/self.VideoWidth
			local sy=self.height/self.VideoHeigth
			love.graphics.setColor(self.Color[1],self.Color[2],self.Color[3],self.VideoVisibility*255)
			if self.width~=self.VideoWidth and self.height~=self.VideoHeigth then
				love.graphics.draw(self.Video,self.x,self.y,math.rad(self.rotation),sx,sy)
			else
				love.graphics.draw(self.Video,self.Quad,self.x,self.y,math.rad(self.rotation),sx,sy)
			end
		end
	end
	function c:repeatImage(b,b2)
		if b then
			self.Image:setWrap(b,b2 or "repeat")
			function self:ImageRule()
				love.graphics.setColor(self.Color[1],self.Color[2],self.Color[3],self.ImageVisibility*255)
				love.graphics.draw(self.Image,self.Quad,self.x,self.y,math.rad(self.rotation))
			end
		else
			sx=self.width/self.ImageWidth
			sy=self.height/self.ImageHeigth
			love.graphics.setColor(self.Color[1],self.Color[2],self.Color[3],self.ImageVisibility*255)
			love.graphics.draw(self.Image,self.Quad,self.x,self.y,math.rad(self.rotation),sx,sy)
		end
	end
	function c:Mutate(t)
		for i,v in pairs(t) do
			_GuiPro.self=self
			if type(i)=="number" then
				loadstring("_GuiPro.self:"..v)()
			elseif i:match"__self__" then
				local ind=i:match"__self__(.+)"
				if not self[ind] then self[ind]={} end
				loadstring("_GuiPro.self."..ind.."=_GuiPro.self:"..v)()
			elseif i:match"__child__" then
				local ind,child = i:match"__child__(%S-)_(.+)"
				self[ind][child]=v
			else
				self[i]=v
			end
		end
		return self
	end
	table.insert(c.Parent.Children,c)
	return c
end