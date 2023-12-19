local gui = require("gui")
local multi, thread = require("multi"):init()
local processor = gui:newProcessor("Transistion Processor")
local transition = {}

local width, height, flags = love.window.getMode()
local fps = 60

if flags.refreshrate > 0 then
    fps = flags.refreshrate
end

transition.__index = transition
transition.__call = function(t, start, stop, time, ...)
    local args = {...}
    return function()
        if not start or not stop then return multi.error("start and stop must be supplied") end
        if start == stop then return multi.error("start and stop cannot be the same!") end
        local handle = t.func(t, start, stop, time or 1, unpack(args))
        return {
            OnStep = handle.OnStatus,
            OnStop = handle.OnReturn + handle.OnError
        }
    end
end

function transition:newTransition(func)
    local c = {}
    setmetatable(c, self)

    c.fps = fps
    c.func = processor:newFunction(func)
    c.OnStop = multi:newConnection()

    function c:SetFPS(fps)
        self.fps = fps
    end

    function c:GetFPS(fps)
        return self.fps
    end

    return c
end

transition.glide = transition:newTransition(function(t, start, stop, time, ...)
    local steps = t.fps*time
    local piece = time/steps
    local split = stop-start
    for i = 0, steps do
        thread.sleep(piece)
        thread.pushStatus(start + i*(split/steps))
    end
end)

return transition