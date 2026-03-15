local color = require("gui.core.color")
local theme = {}
local defaultFont = love.graphics.getFont()
theme.__index = theme

local function generate_harmonious_colors(num_colors, lightness)
    local base_hue = math.random(0, 360) -- random starting hue
    local colors = {}
    for i = 1, num_colors do
        local new_hue = (base_hue + (360 / num_colors) * i) % 360 -- offset hue by 1/n of the color wheel
        if lightness == "dark" then
            table.insert(colors, color.new(color.hsl(new_hue, math.random(45, 55), math.random(30, 40))))
        elseif lightness == "light" then
            table.insert(colors, color.new(color.hsl(new_hue, math.random(45, 55), math.random(60, 80))))
        else
            table.insert(colors, color.new(color.hsl(new_hue, math.random(45, 55), math.random(30, 80))))
        end
            
    end
    return colors
end

function theme:random(seed, lightness, rand)
    local seed = seed or math.random(0,9999999999)
    math.randomseed(seed)
    local harmonious_colors = generate_harmonious_colors(3, lightness)
    local t = theme:new(unpack(harmonious_colors))

    if lightness == "dark" then
        t.colorPrimaryText = color.lighten(t.colorPrimaryText, .8)
        t.colorButtonText = color.lighten(t.colorButtonText, .7)
    elseif lightness == "light" then
        t.colorPrimaryText = color.darken(t.colorPrimaryText, .8)
        t.colorButtonText = color.darken(t.colorButtonText, .7)
    else
        if color.getAverageLightness(t.colorPrimary)<.5 then
            t.colorPrimaryText = color.lighten(t.colorPrimaryText, .5)
            t.colorButtonNormal = color.lighten(t.colorButtonNormal, .2)
        else
            t.colorPrimaryText =  color.darken(t.colorPrimaryText, .3)
        end

        if color.getAverageLightness(t.colorPrimary)<.5 then
            t.colorButtonText = color.lighten(t.colorButtonText, .5)
        else
            t.colorButtonText = color.darken(t.colorButtonText, .3)
        end
    end
    

    t.seed = seed
    return t
end

function theme:dump()
    return '"' .. table.concat({color.rgbToHex(self.colorPrimary), color.rgbToHex(self.colorPrimaryText), color.rgbToHex(self.colorButtonText)},"\",\"") .. '"'
end

function theme:new(colorPrimary, primaryText, buttonText, primaryTextFont, buttonTextFont)
    local c = {}
    setmetatable(c, theme)
    c.colorPrimary = color.new(colorPrimary)
    c.colorPrimaryDark = color.darken(c.colorPrimary,.4)
    c.colorPrimaryText = color.new(primaryText)
    c.colorButtonNormal = color.darken(c.colorPrimary,.2)
    c.colorButtonHighlight = color.darken(c.colorButtonNormal,.2)
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
    self.fontPrimary = c
end

function theme:setFontButton(c)
    self.fontButton = c
end

function theme:getSeed()
    return self.seed
end

return theme