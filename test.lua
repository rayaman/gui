local function intersecpt(x1,y1,x2,y2,x3,y3,x4,y4)

	-- gives bottom-left point
    -- of intersection rectangle
    local x5 = math.max(x1, x3)
    local y5 = math.max(y1, y3)

	-- gives top-right point
	-- of intersection rectangle
    local x6 = math.min(x2, x4);
    local y6 = math.min(y2, y4);

	-- no intersection
    if x5 > x6 or y5 > y6 then
        return 0,0,0,0 -- Return a no
	end

	-- gives top-left point
    -- of intersection rectangle
    local x7 = x5
    local y7 = y6
 
    -- gives bottom-right point
    -- of intersection rectangle
    local x8 = x6
    local y8 = y5

	return x7, y7, math.abs(x7-x8), math.abs(y7-y8)
end

local function toCoordPoints(x,y,w,h)
	return x,y,x+w,y+h
end

function gui:intersecpt(obj)
	local x1,y1,x2,y2 = toCoordPoints(self:getAbsolutes())
	local x3,y3,x4,y4 = toCoordPoints(obj:getAbsolutes())

	return intersecpt(x1,y1,x2,y2,x3,y3,x4,y4)
end
