local gui = require("gui")
local multi, thread = require("multi"):init()
local processor = gui:newProcessor("Transition Processor")
local transition = {}

local width, height, flags = love.window.getMode()
local fps = 60

if flags.refreshrate > 0 then
    fps = flags.refreshrate
end

transition.__index = transition
transition.__call = function(t, start, stop, time, ...)
    local args = {...}
    return function(st, sp, ti)
        local s = st or start
        local e = sp or stop
        local dur = ti or time or 1
        if not s or not e then return multi.error("start and stop must be supplied") end
        if s == e then
            local temp = {
                OnStep = function() end,
                OnStop = processor:newConnection()
            }
            processor:newTask(function()
                temp.OnStop:Fire()
            end)
            return temp
        end
        local handle = t.func(t, s, e, dur, unpack(args))
        return {
            OnStep = handle.OnStatus,
            OnStop = handle.OnReturn + handle.OnError,
            Kill = function() t:Kill() end
        }
    end
end

function transition:newTransition(func)
    local c = {}
    setmetatable(c, self)

    c.fps = fps
    c.func = processor:newFunction(func)
    c.OnStop = processor:newConnection()
    c.kill = false

    function c:SetFPS(f)
        self.fps = f
    end

    function c:GetFPS()
        return self.fps
    end

    function c:Kill()
        if c.running then
            c.kill = true
        end
    end

    return c
end

transition.glide = transition:newTransition(function(t, start, stop, time)
    local split = stop - start
    local startTime = love.timer.getTime()
    local endTime = startTime + time
    local stepTime = 1 / t.fps

    t.running = true

    while not t.kill do
        thread.sleep(stepTime)

        local now = love.timer.getTime()
        local elapsed = now - startTime
        local clamped = math.min(elapsed, time)
        local value = start + (clamped / time) * split

        thread.pushStatus(value, clamped)

        if now >= endTime then
            break
        end
    end

    t.running = false
    t.kill = false
end)

return transition