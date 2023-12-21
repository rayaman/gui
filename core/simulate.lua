local gui = require("gui")
local multi, thread = require("multi"):init()
local transition = require("gui.elements.transitions")

-- Triggers press then release
local function getPosition(obj, x, y)
    if not x or y then
        local cx, cy, w, h = obj:getAbsolutes()
        return cx + w/2, cy + h/2
    else
        return x, y
    end
end

proc = gui:getProcessor()

local simulate = {}
local cursor = false
local smooth = false

function simulate:moveCursor(bool)
    cursor = bool
end

function simulate:smoothMovement(bool)
    smooth = bool
end

function simulate:Press(button, x, y, istouch)
    if self then
        x, y = getPosition(self, x, y)
    elseif x == nil or y == nil then
        x, y = love.mouse.getPosition()
    end
    if cursor then
        love.mouse.setPosition(x, y)
    end
    gui.Events.OnMousePressed:Fire(x, y, button or gui.MOUSE_PRIMARY, istouch or false)
end

function simulate:Release(button, x, y, istouch)
    if self then
        x, y = getPosition(self, x, y)
    elseif x == nil or y == nil then
        x, y = love.mouse.getPosition()
    end
    if cursor then
        love.mouse.setPosition(x, y)
    end
    gui.Events.OnMouseReleased:Fire(x, y, button or gui.MOUSE_PRIMARY, istouch or false)
end

simulate.Click = proc:newFunction(function(self, button, x, y, istouch)
    if self then
        x, y = getPosition(self, x, y)
    elseif x == nil or y == nil then
        x, y = love.mouse.getPosition()
    end
    if cursor then
        love.mouse.setPosition(x, y)
    end
    gui.Events.OnMousePressed:Fire(x, y, button or gui.MOUSE_PRIMARY, istouch or false)
    thread.skip(1)
    gui.Events.OnMouseReleased:Fire(x, y, button or gui.MOUSE_PRIMARY, istouch or false)
end, true)

simulate.Move = proc:newFunction(function(self, dx, dy, x, y, istouch)
    local dx, dy = dx or 0, dy or 0

    if self then
        x, y = getPosition(self, x, y)
    elseif x == nil or y == nil then
        x, y = love.mouse.getPosition()
    end
    gui.Events.OnMouseMoved:Fire(x, y, 0, 0, istouch or false)
    thread.skip(1)
    if smooth then
        local gx = transition.glide(0, dx, .25)
        local gy = transition.glide(0, dy, .25)
        local xx = gx()
        xx.OnStep(function(p)
            _x, _y = love.mouse.getPosition()
            if cursor then
                love.mouse.setPosition(x + p, _y)
            else
                gui.Events.OnMouseMoved:Fire(x + p, _y, 0, 0, istouch or false)
            end
        end)
        local yy = gy()
        yy.OnStep(function(p)
            _x, _y = love.mouse.getPosition()
            if cursor then
                love.mouse.setPosition(_x, y + p)
            else
                gui.Events.OnMouseMoved:Fire(_x, y + p, 0, 0, istouch or false)
            end
        end)
        thread.hold(xx.OnStop * yy.OnStop)
        gui.Events.OnMouseMoved:Fire(x + dx, y + dy, 0, 0, istouch or false)
    else
        if cursor then
            love.mouse.setPosition(x + dx, y + dy)
        end
        gui.Events.OnMouseMoved:Fire(x + dx, y + dy, 0, 0, istouch or false)
    end
end, true)

return simulate