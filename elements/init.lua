local gui = require("gui")
local color = require("gui.core.color")
local theme = require("gui.core.theme")
local transition = require("gui.elements.transitions")

function gui:newMenu(title, sx, position, trans)
    if not title then multi.error("Argument 1 string('title') is required") end
    if not sx then multi.error("Argument 2 number('sx') is required") end

    local position = position or gui.ALIGN_LEFT
    local trans = trans or transition.glide

    local menu, to, tc, open
    if position == gui.ALIGN_LEFT then
        menu = self:newFrame(0, 0, 0, 0, -sx, 0, sx, 1)
        to = trans(-sx, 0, .25)
        tc = trans(0, -sx, .25)
    elseif position == gui.ALIGN_CENTER then
        menu = self:newFrame(0, 0, 0, 0, .5 -sx/2, 1.1, sx, 1)
        to = trans(1.1, 0, .35)
        tc = trans(0, 1.1, .35)
    elseif position == gui.ALIGN_RIGHT then
        menu = self:newFrame(0, 0, 0, 0, 1, 0, sx, 1)
        to = trans(1, 1 - sx, .25)
        tc = trans(1 - sx, 1, .25)
    end

    function menu:isOpen()
        return open
    end

    function menu:Open(show)
        if show then
            if not menu.lock then
                menu.lock = true 
                local t = to()
                t.OnStop(function()
                    open = true
                    menu.lock = false
                end)
                t.OnStep(function(p)
                    if position == gui.ALIGN_CENTER then
                        menu:setDualDim(nil, nil, nil, nil, nil, p)
                    else
                        menu:setDualDim(nil, nil, nil, nil, p)
                    end
                end)
            end
        else
            if not menu.lock then
                menu.lock = true 
                local t = tc()
                t.OnStop(function()
                    open = false
                    menu.lock = false
                end)
                t.OnStep(function(p)
                    if position == gui.ALIGN_CENTER then
                        menu:setDualDim(nil, nil, nil, nil, nil, p)
                    else
                        menu:setDualDim(nil, nil, nil, nil, p)
                    end
                end)
            end
        end
    end
    
    return menu
end
