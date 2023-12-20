local gui = require("gui")
local multi, thread = require("multi"):init()

local canvas = {}

-- Run the canvas logic within another processor
local proc = gui:newProcessor("Canvas Handler")
local updater = proc:newLoop().OnLoop

local draw_handler = gui.draw_handler

function canvas:newCanvas()
    local c = {}
    setmetatable(c, gui)
    local active = false
    c.type = gui.TYPE_FRAME
    c.children = {}
    c.dualDim = gui:newDualDim()
    c.x = 0
    c.y = 0

    local w, h = love.graphics.getDimensions()
    c.dualDim.offset.size.x = w
    c.dualDim.offset.size.y = h
    c.w = w
    c.h = h
    c.parent = c

    table.insert(canvas, c)

    proc:newThread(function()
        while true do
            print("Holding...")
            thread.hold(c.isActive)
            local children = c:getAllChildren()
            for i = 1, #children do
                local child = children[i]
                if child.effect then
                    child.effect(function() draw_handler(child, true) end)
                else
                    draw_handler(child, true)
                end
            end
            first_loop = true
        end
    end)

    function c:isActive(b)
        if b == nil then
            return active
        end
        active = b
    end

    function c:OnUpdate(func)
        if type(self) == "function" then func = self end
        updater(function() func(c) end)
    end
    
    function c:newThread(func)
        return proc:newThread("ThreadHandler<" .. self.type .. ">", func, self, thread)
    end
    
    function c:swap(c1, c2)
        local ch1 = c1:getChildren()
        local ch2 = c2:getChildren()
        for i = 1, #ch1 do
            ch1[i]:setParent(c2)
        end
        for i = 1, #ch2 do
            ch2[i]:setParent(c1)
        end
    end

    return c
end

gui.Events.OnResized(proc:newFunction(function(w, h)
    for i = 1, #canvas do
        local c = canvas[i]
        if gui.aspect_ratio then
            local nw, nh, xt, yt = gui.GetSizeAdjustedToAspectRatio(w, h)
            c.x = xt
            c.y = yt
            c.dualDim.offset.size.x = nw
            c.dualDim.offset.size.y = nh
            c.w = nw
            c.h = nh
        else
            c.dualDim.offset.size.x = w
            c.dualDim.offset.size.y = h
            c.w = w
            c.h = h
        end
    end
end))

return canvas