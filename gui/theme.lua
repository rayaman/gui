local color = require("gui.color")
local theme = {}
local defaultFont = love.graphics.getFont()
theme.__index = theme

local function generate_harmonious_colors(num_colors)
    local base_hue = math.random(0, 360) -- random starting hue
    local colors = {}
    for i = 1, num_colors do
        local new_hue = (base_hue + (360 / num_colors) * i) % 360 -- offset hue by 1/n of the color wheel
        table.insert(colors, color.new(color.hsl(new_hue, math.random(50, 100), math.random(20, 70))))
    end
    return colors
end

function theme:random()
    local harmonious_colors = generate_harmonious_colors(5)
    return theme:new(unpack(harmonious_colors))
end

function theme:new(colorPrimary, primaryText, buttonNormal, buttonHighlight, 
                   buttonText, primaryTextFont, buttonTextFont)
    local c = {}
    setmetatable(c, theme)
    c.colorPrimary = color.new(colorPrimary)
    c.colorPrimaryDark = color.darken(c.colorPrimary,.4)
    c.colorPrimaryText = color.new(primaryText)
    c.colorButtonNormal = color.new(buttonNormal)
    c.colorButtonHighlight = color.new(buttonHighlight)
    c.colorButtonText = color.new(buttonText)
    c.fontPrimary = primaryTextFont or defaultFont
    c.fontButton = buttonTextFont or defaultFont
    return c
end

function theme:setColorPrimary(c)
    self.colorPrimary = color.new(c)
end

function theme:setColorPrimaryDark(c)
    self.colorPrimaryDark = color.new(c)
end

function theme:setColorPrimaryText(c)
    self.colorPrimaryText = color.new(c)
end

function theme:setColorButtonNormal(c)
    self.colorButtonNormal = color.new(c)
end

function theme:setColorButtonHighlight(c)
    self.colorButtonHighlight = color.new(c)
end

function theme:setColorButtonText(c)
    self.colorButtonText = color.new(c)
end

function theme:setFontPrimary(c)
    self.fontPrimary = color.new(c)
end

function theme:setFontButton(c)
    self.fontButton = color.new(c)
end



return theme