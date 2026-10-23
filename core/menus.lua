local gui = require("gui")
local menu = {}
local menus = {}
local frame
local menuRef = {}
local mt = {
    __index = menuRef
}

function menu.registerMenu(name, menu, delete)
    local c = {}
    c.MenuFunc = menu
    c.Delete = delete
    setmetatable(c, mt)
    menus[name] = c
    return c
end

function menu.getMenu(name)
    return menus[name] or nil, "Menu ".. name .. " not found."
end

function menu.init(f)
    frame = f
end

function menu.hideMenus()
    for k,v in pairs(menus) do
        if v.frame then
            if v.Delete then
                v.frame:destroy()
                menus[k] = nil
            else
                v.frame.visible = false
                v.frame.active = false
                v.frame:setParent(gui.virtual)
            end
        end
    end
end

function menu.getCurrentMenu()
    return frame
end

function menuRef:visible(value, ...)
    menu.hideMenus()
    if self.__menuConfigured and self.frame then
        self.frame.visible = true
        self.frame.active = true
        self.frame:setParent(frame)
    else
        self.__menuConfigured = true
        self.frame = self.MenuFunc(frame, ...)
    end
end

return menu