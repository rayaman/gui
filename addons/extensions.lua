local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local multi, thread = require("multi"):init()
local mediaProc = gui:newProcessor()

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh)
    local window = gui:newWindow(x, y, w, h, source, true, theme:new({
        primary     = "#000000",
        primaryDark = "#10465c",
        primaryText = "#ffffff"
    }))
    local video = window:newVideo(source, 0, 0, 0, 0, 0, .05, 1, .75)
    local play_pause = window:newImageButton("gui/assets/play.png",0,0,0,0,.45,.82,0,.175)
    local seek = window:newFrame(0,0,0,0,0,.8,1,.015)
    seek.color = color.new("#3c434c")
    local seeker = seek:newFrame(0,0,0,0,0,.1,0,.8)
    seeker.drawBorder = false
    seeker.color = color.new("#0c278a")
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
    
    local length = video:getDuration()
    mediaProc:newThread(function()
        while true do
            thread.yield()
            seeker:setDualDim(nil,nil,nil,nil,nil,nil,video:tell()/length)
        end
    end)

    -- print()

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

    checkbox.OnChanged = multi:newConnection()

    return checkbox
end

function gui:newRadioGroup(options, x, y, sx, sy, size)
    local group = {}
    local rg = self:newFrame()
    local selected

    rg.OnSelectionChanged = multi:newConnection()

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
    local progressbar = self:newFrame(x,y,w,h,sx,sy,sw,sh)
    local fillframe = progressbar:newFrame(noOf(.025, .1, .95, .8))
    local fill = fillframe:newFrame(noOf(0, 0, 1, 1))

    fillframe.visibility = 0
    progressbar.color = color.new("#000000")
    fill.color = color.new("#ffffff")
    progressbar.fillframe = fillframe
    progressbar.fill = fill

    function progressbar:update(value)
        if value > count then value = count end
        if value < 0 then value = 0 end
        local percent = value/count
        fill:setDualDim(noOf(nil,nil,percent))
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
        value = count
        self:update(value)
    end

    function progressbar:min()
        value = 0
        self:update(value)
    end

    progressbar:update(value)

    -- to change colors and modify main components
    return progressbar, fill, fillframe
end