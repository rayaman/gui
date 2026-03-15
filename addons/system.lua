local multi, thread = require("multi"):init() -- We need to inspect everything
local gui = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local default_theme = theme:new("64342e", "b2989e", "909b9a")

function gui:newWindow(x, y, w, h, text, draggable)
    local parent = self
    local pointer = love.mouse.getCursor()
    local sizewe = love.mouse.getSystemCursor("sizewe")
    local sizens = love.mouse.getSystemCursor("sizens")
    local sizenesw = love.mouse.getSystemCursor("sizenesw")
    local sizenwse = love.mouse.getSystemCursor("sizenwse")
    local theme = default_theme

    local header = self:newFrame(x, y, w, 30)
    header:setRoundness(10, 10, nil, "top")
    local window = header:newFrame(0, 30, 0, h - 30,0,0,1)
    window.clipDescendants = true
    local left = window:newFrame(0,-4,4,0,0,0,0,1):tag("left")
    local right = window:newFrame(-4,-4,4,0,1,0,0,1):tag("right")
    local bottom = window:newFrame(4,-4,-8,4,0,1,1):tag("bottom")
    local bottomleft = window:newFrame(0,-4,4,4,0,1):tag("bleft")
    local bottomright = window:newFrame(-4,-4,4,4,1,1):tag("bright")
    gui.apply({
        visibility = 0,
        I_enableDragging = {gui.MOUSE_PRIMARY},
        C_OnDragging = function(self, dx, dy)
            local ox,oy,ow,oh = header:getAbsolutes()
            local tag = self:getTag()
            print(tag)
            if tag == "left" or tag == "bleft" then
                window:size(0, dy)
                header:move(dx,0)
                header:size(-dx,0)
            else
                window:size(0, dy)
                header:size(dx,0)
            end
            local x,y,w,h = header:getAbsolutes()
            if w < 200 and (tag == "left" or tag == "bleft") then
                header:setDualDim(ox,nil,200)
            elseif w < 200 then
                header:setDualDim(nil,nil,200)
            end
            local x,y,w,h = window:getAbsolutes()
            if h < 100 then
                window:setDualDim(nil,nil,nil,100)
            end
        end,
        C_OnDragEnd = function(self)
            love.mouse.setCursor(pointer)
        end,
        C_OnEnter = function(self)
            local tag = self:getTag()
            if tag == "left" or tag == "right" then
                love.mouse.setCursor(sizewe)
            elseif tag == "bleft" then
                love.mouse.setCursor(sizenesw)
            elseif tag == "bright" then
                love.mouse.setCursor(sizenwse)
            else
                love.mouse.setCursor(sizens)
            end
        end,
        C_OnExit = function(self)
            love.mouse.setCursor(pointer)
        end
    },left,right,bottom,bottomleft,bottomright)
    local title = header:newTextLabel(text or "", 5, 0, w - 35, 30)
    title.visibility = 0
    title.ignore = true

    function window:setTitle(text)
        title.text = text
    end

    local X = header:newTextButton("", -25, -25, 20, 20, 1, 1)
    X:setRoundness(10, 10)
    X.align = gui.ALIGN_CENTER
    X.color = color.red
    local darkenX = color.darken(color.red, .2)

    X.OnEnter(function(self) self.color = darkenX end)

    X.OnExit(function(self) self.color = color.red end)

    if draggable then
        header:enableDragging(gui.MOUSE_PRIMARY)

        header:OnDragging(function(self, dx, dy)
            self:move(dx, dy)
        end)

        header:OnDragEnd(function(self)
            local x,y,w,h = self:getAbsolutes()
            local width, height = love.graphics.getDimensions()
            if x<=0 then
                self:setDualDim(0)
            end
            if y<=0 then
                self:setDualDim(nil,0)
            end
            if x+w >= width then
                self:setDualDim(width-w)
            end
            if y+h >= height then
                self:setDualDim(nil,height-30)
            end
        end)
    end

    -- Mutate the event args to point to our window object
    window.OnClose = function() return window end % X.OnPressed

    window.OnClose(function()
        header:setParent(gui.virtual)
        love.mouse.setCursor(pointer)
    end)

    function window:close() -- The OnClose connection itself does not modify values at all!
        window.OnClose:Fire(self)
    end

    function window:open() header:setParent(parent) end

    function window:setTheme(th)
        theme = th
        title.textColor = theme.colorPrimaryText
        title:setFont(theme.fontPrimary)
        title:fitFont()
        header.color = theme.colorPrimaryDark
        window.color = theme.colorPrimary
        local elements = self:getAllChildren()
        for _, element in pairs(elements) do
            if element:hasType(gui.TYPE_BUTTON) then
                element:setFont(theme.fontButton)
                element.color = theme.colorButtonNormal
                element.textColor = theme.colorButtonText
                if not element.__registeredTheme then

                    element.OnEnter(function(self)
                        self.color = theme.colorButtonHighlight
                    end)

                    element.OnExit(function(self)
                        self.color = theme.colorButtonNormal
                    end)

                end
                element:fitFont()
                element.align = gui.ALIGN_CENTER
                element.__registeredTheme = true
            elseif element:hasType(gui.TYPE_TEXT) then
                element.color = theme.colorPrimary
                element:setFont(theme.fontPrimary)
                element.textColor = theme.colorPrimaryText
                element:fitFont()
                element.align = gui.ALIGN_CENTER
            elseif element:hasType(gui.TYPE_FRAME) then
                if element.__isHeader then
                    element.color = theme.colorPrimaryDark
                else
                    element.color = theme.colorPrimary
                end
            end
        end
    end

    function window:getTheme() return theme end

    thread:newThread(function() window:setTheme(theme) end)

    return window
end

local taskManager -- only have one instance of this
function gui:showTaskManager()
    if not taskManager then
        taskManager = gui:newWindow(0,0,400,300,"Task Manager",true)
    end
    local stats = multi:getStats()
    for i,v in pairs(stats) do
        print(i,v)
    end
end

ToggleTaskManager = gui:setHotKey({"lctrl","t"}) + 
                    gui:setHotKey({"rctrl","t"})

ToggleTaskManager(function()
    if taskManager then
        if taskManager:isActive() then
            taskManager:close()
        else
            taskManager:open()
        end
    else
        gui:showTaskManager()
    end
end)

function printTable(t, indent, seen)
    indent = indent or 0
    seen = seen or {}
    
    if seen[t] then
        print(string.rep("  ", indent) .. "<circular reference>")
        return
    end
    seen[t] = true
    
    for k, v in pairs(t) do
        local prefix = string.rep("  ", indent) .. tostring(k) .. ": "
        if type(v) == "table" then
            print(prefix .. "{")
            printTable(v, indent + 1, seen)
            print(string.rep("  ", indent) .. "}")
        else
            print(prefix .. tostring(v))
        end
    end
end