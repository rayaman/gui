local gui = require("gui")
local color = require("gui.core.color")
local theme = require("gui.core.theme")
local transition = require("gui.elements.transitions")
local processor = gui:newProcessor("menu")

function gui:newMenu(title, sx, position, trans, callback, t,t2)
    if not title then multi.error("Argument 1 string('title') is required") end
    if not sx then multi.error("Argument 2 number('sx') is required") end
    if callback then if not type(callback) == "function" then multi.error("Argument 5 function('callback(menu(self),align[left,center,right],transition_position)') must be a function") end end
    local t = t or .35
    local t2 = t2 or .25
    local position = position or gui.ALIGN_LEFT
    local trans = trans or transition.glide

    local menu, to, tc, open
    if callback then
        menu = self:newFrame(0, 0, 0, 0, .5 -sx/2, 1, sx, 1)
        to = trans(1, 0, t)
        tc = trans(0, 1, t)
    else
        if position == gui.ALIGN_LEFT then
            menu = self:newFrame(0, 0, 0, 0, -sx, 0, sx, 1)
            to = trans(-sx, 0, t2)
            tc = trans(0, -sx, t2)
        elseif position == gui.ALIGN_CENTER then
            menu = self:newFrame(0, 0, 0, 0, .5 -sx/2, 1, sx, 1)
            to = trans(1, 0, t)
            tc = trans(0, 1, t)
        elseif position == gui.ALIGN_RIGHT then
            menu = self:newFrame(0, 0, 0, 0, 1, 0, sx, 1)
            to = trans(1, 1 - sx, t2)
            tc = trans(1 - sx, 1, t2)
        end
    end

    function menu:isOpen()
        return open
    end

    function menu:Open(show)
        if show then
            if not menu.lock then
                menu.visible = true
                menu.lock = true 
                local t = to()
                t.OnStop(function()
                    open = true
                    menu.lock = false
                end)
                t.OnStep(function(p)
                    if callback then
                        callback(menu,position,p,"open")
                        for i,v in pairs(menu:getAllChildren()) do
                            callback(v,position,p,"open")
                        end
                    else
                        if position == gui.ALIGN_CENTER then
                            menu:setDualDim(nil, nil, nil, nil, nil, p)
                        else
                            menu:setDualDim(nil, nil, nil, nil, p)
                        end
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
                    menu.visible = false
                end)
                t.OnStep(function(p)
                    if callback then
                        callback(menu,position,p,"open")
                        for i,v in pairs(menu:getAllChildren()) do
                            callback(v,position,p,"open")
                        end
                    else
                        if position == gui.ALIGN_CENTER then
                            menu:setDualDim(nil, nil, nil, nil, nil, p)
                        else
                            menu:setDualDim(nil, nil, nil, nil, p)
                        end
                    end
                end)
            end
        end
    end

    menu.OnCreate = processor:newConnection()
    local items = {}
    function menu:addItem(text)
        local item = menu:newTextButton(text,0,100*#items,0,100,0,0,1)
        items[#items+1] = item
        item:fitFont()
        item.align = gui.ALIGN_CENTER
        self.OnCreate:Fire(self,item,items)
    end
    
    return menu
end
