local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local multi, thread = require("multi"):init()
require("gui.addons.system")
local proc = gui:newProcessor()
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
    proc:newThread(function()
        while true do
            thread.yield()
            seeker:setDualDim(nil,nil,nil,nil,nil,nil,video:tell()/length)
        end
    end)

    -- print()

end
