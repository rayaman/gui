local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local multi, thread = require("multi"):init()
local mediaProc = gui:newProcessor("media-updater")
local miscProc = gui:newProcessor("misc-updater")

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh, draggable, th)
    local window = self:newWindow(x, y, w, h, sx, sy, sw, sh, "", draggable, th or theme:new({
        primary     = "#000000",
        primaryDark = "#10465c",
        primaryText = "#ffffff"
    }))
    local video = window:newVideo(source, 0, 0, 0, 0, 0, .05, 1, .75)
    local length = video:getDuration()
    local play_pause = window:newImageButton("gui/assets/play.png",0,0,0,0,.45,.86,0,.14)
    local seek = window:newProgressBar(0,0,0,0,0,.8,1,.05,length*100,0)
    seek.OnProgressUpdated(function(self,_,value, drag)
        if drag then
            local status = video:isPlaying()
            video:seek(value/100)
            if status then
                video:play()
            else
                video:stop()
            end
        end
    end)
    seek:isClickable(true)
    play_pause.square = "h"
    play_pause.isPaused = true
    play_pause:OnReleased(function(self)
        if self.isPaused then
            self:setImage("gui/assets/pause.png")
            video:play()
        else
            self:setImage("gui/assets/play.png")
            video:pause()
        end
        self.isPaused = not self.isPaused
    end)
    
    mediaProc:newThread(function()
        while true do
            thread.hold(function() return video:isPlaying() end)
            local p = video:tell()
            seek:update(p*100)
        end
    end)

    function window:seek(...)
        video.video:seek(...)
    end

    function window:play()
        video:play()
    end

    function window:stop()
        video:stop()
    end

    window.OnClose(function()
        video:pause()
    end)

    return window
end

function gui:newCheckbox(label, x, y, size, sx, sy, checked)
    local checkbox = self:newFrame(x, y, size, size, sx, sy)
    checkbox.color = color.black
    local border = checkbox:newVisualFrame(noOf(.1,.1,.8,.8))
    border.color = color.white
    local toggle = border:newFrame(noOf(.3,.3,.4,.4))
    toggle.color = color.black
    toggle.visible = false

    checkbox:OnReleased(function()
        checkbox:check(not toggle.visible)
    end)
    
    if label ~= "" then
        local text = checkbox:newTextLabel(label, noOf(1.25,0,15,1))
        text:OnUpdate(function()
            text:centerFont()
        end)
        text:setFont(size-2)
        text.visibility = 0
    end

    function checkbox:check(value)
        toggle.visible = value
        self.OnChanged:Fire(value)
    end

    function checkbox:isChecked()
        return toggle.visible
    end

    function checkbox:getLabel()
        return label or ""
    end

    checkbox.OnChanged = miscProc:newConnection()

    return checkbox
end

function gui:newRadioGroup(options, x, y, sx, sy, size)
    local group = {}
    local rg = self:newFrame()
    local selected

    rg.OnSelectionChanged = miscProc:newConnection()

    for i,v in ipairs(options or {}) do
        table.insert(group,self:newCheckbox(tostring(v),x,y+((i-1)*size+((options.padding or 0)*(i-1))),size,sx,sy))
    end

    gui.apply({
        OnReleased=function(self)
            gui.apply({check={false}},unpack(group))
            self:check(true)
            if selected ~= self then
                rg.OnSelectionChanged:Fire(rg, self)
            end
            selected = self
        end,
    },unpack(group))

    function rg:getSelectedOption()
        return selected
    end

    return rg
end

function gui:newProgressBar(x, y, w, h, sx, sy, sw, sh, count, value)
    local value = value or 0
    local count = count or 100
    local progressbar = self:newFrame(x,y,w,h,sx,sy,sw,sh)
    local fillframe = progressbar:newFrame(2,2,-4,-4,0,0,1,1)
    local fill = fillframe:newFrame(noOf(0, 0, 1, 1))
    local percentDisplay = fillframe:newTextLabel("",noOf(0,0,1,1))
    percentDisplay.align = gui.ALIGN_CENTER
    percentDisplay.textColor = color.new("#CC5500")
    fillframe.visibility = 0
    progressbar.color = color.new("#000000")
    fill.color = color.new("#ffffff")
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
                _,_,_h = percentDisplay:getAbsolutes()
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
    
    fillframe.OnDragging(calcFunc)

    fillframe.OnPressed(function(self, x, y, dx, dy, istouch)
        calcFunc(self, dx, dy, x, y, istouch)
    end)

    function progressbar:update(v, drag)
        v = v or value
        if v > count then v = count end
        if v < 0 then v = 0 end
        local percent = value/count
        fill:setDualDim(noOf(nil,nil,percent))
        if displayPercent then
            percentDisplay.text = math.floor((percent*100)+.5).. "%"
            percentDisplay:centerFont()
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