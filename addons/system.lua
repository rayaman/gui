local gui = require("gui")
local default_theme = theme:new("64342e", "b2989e", "909b9a")

function gui:newWindow(x, y, w, h, text, draggable)
    local parent = self
    local pointer = love.mouse.getCursor()
    local theme = default_theme

    local header = self:newFrame(x, y, w, 30)
    header:setRoundness(10, 10, nil, "top")
    local window = header:newFrame(0, 30, w, h - 30)
    local title = header:newTextLabel(text or "", 5, 0, w - 35, 30)
    title.visibility = 0
    title.ignore = true

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
            -- window:move(dx,dy)
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