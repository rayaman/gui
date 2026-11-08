-- gui:newProgressBar — fill bar with optional percent readout and click/drag seeking
local shared   = require("gui.addons.extensions.shared")
local gui      = shared.gui
local palette  = shared.palette
local miscProc = shared.miscProc

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newProgressBar(x, y, w, h, sx, sy, sw, sh, count, value)
    local value = value or 0
    local count = count or 100
    local progressbar = self:newFrame(x,y,w,h,sx,sy,sw,sh)
    local fillframe = progressbar:newFrame(2,2,-4,-4,0,0,1,1)
    local fill = fillframe:newFrame(noOf(0, 0, 1, 1))
    local percentDisplay = fillframe:newTextLabel("",noOf(0,0,1,1))
    percentDisplay.align = gui.ALIGN_CENTER
    percentDisplay.textColor = palette.black
    fillframe.visibility = 0
    progressbar.color = palette.black
    fill.color = palette.white
    progressbar.fillframe = fillframe
    progressbar.fill = fill
    progressbar.display = percentDisplay
    progressbar.OnProgressUpdated = miscProc:newConnection()
    percentDisplay.visibility = 0
    local displayPercent = false

    function progressbar:showPercent(bool)
        displayPercent = bool
        if bool then
            miscProc:newThread(function()
                thread.skip(2)
                local _,_,_h = percentDisplay:getAbsolutes()
                percentDisplay:setFont(math.floor(h/1.3))
                self:update()
            end)
        end
    end

    function progressbar:isClickable(bool)
        fillframe:respectHierarchy(not bool)
        -- Makes the bar updatable by clicking on it
        fillframe:enableDragging(bool and gui.MOUSE_PRIMARY)
    end

    local calcFunc = function(self, dx, dy, x, y, istouch)
        local sx, sy, sw, sh = self:getAbsolutes()
        if x >= sx and x <= sx + sw then
            progressbar:update((((x - sx)/sw) * count), true)
        end
    end

    fillframe:OnDragStart(calcFunc)
    
    fillframe:OnDragging(calcFunc)

    fillframe:OnPressed(function(self, x, y, dx, dy, istouch)
        calcFunc(self, dx, dy, x, y, istouch)
    end)
    
    percentDisplay:centerFont()
    
    function progressbar:update(v, drag)
        v = v or value
        if v > count then v = count end
        if v < 0 then v = 0 end
        local percent = value/count
        fill:setDualDim(noOf(nil,nil,percent))
        if displayPercent then
            percentDisplay.text = math.floor((percent*100)+.5).. "%"
            
        end
        value = v
        self.OnProgressUpdated:Fire(self, percent, value, drag)
    end

    function progressbar:add(n)
        if value >= count then
            return
        end
        value = value + n
        self:update(value)
    end

    function progressbar:sub(n)
        if value <= 0 then
            return
        end
        value = value - n
        self:update(value)
    end

    function progressbar:max()
        self:update(count)
    end

    function progressbar:min()
        self:update(0)
    end

    function progressbar:half()
        self:update(math.floor(count/2))
    end

    function progressbar:getPercent()
        return math.floor(((value/count)*100)+.5)
    end

    function progressbar:getValue()
        return value
    end

    progressbar:update(value)

    -- to change colors and modify main components
    return progressbar, fill, percentDisplay, fillframe
end
