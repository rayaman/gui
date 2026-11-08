-- gui:newVideoPlayer — a window with a video, play/pause button and seek bar.
local shared = require("gui.addons.extensions.shared")
local gui     = shared.gui
local palette = shared.palette
local th      = shared.th
local thread  = shared.thread
local mediaProc = shared.mediaProc

function gui:newVideoPlayer(source, x, y, w, h, sx, sy, sw, sh, draggable, th)
    local window = self:newWindow{
        x, y, w, h, sx, sy, sw, sh,
        title     = "",
        draggable = draggable,
        theme     = th or {
            primaryBG   = palette.black,
            primaryNav  = palette.blue,
            primaryText = palette.white,
        },
    }
    local video = window.content:newVideo(source, 0, 0, 0, 0, 0, .05, 1, .75)
    local length = video:getDuration()
    local play_pause = window.content:newImageButton("gui/assets/play.png",0,0,0,0,.45,.86,0,.14)
    local seek = window.content:newProgressBar(0,0,0,0,0,.8,1,.05,length*100,0)
    seek:OnProgressUpdated(function(self,_,value, drag)
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

    window:OnClose(function()
        video:pause()
    end)

    return window
end
