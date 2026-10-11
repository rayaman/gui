local color = require("gui.core.color")
local palette = color.newPalette("$gui.core.theme")
local theme = {}
local defaultFont = love.graphics.getFont()
theme.__index = theme

palette:indexColor("primaryText","#000000")
palette:indexColor("primaryBG","#70bfc2")
palette:indexColor("primaryFG","#71c19c")
palette:indexColor("primaryNav","#7196c1")
palette:indexColor("primaryButton","#73bf76")
palette:indexColor("primaryLabel","#7673bf")
palette:indexColor("secondaryText","#444444")
palette:indexColor("secondaryBG","#80a2b2")
palette:indexColor("secondaryFG","#81b1a8")
palette:indexColor("secondaryNav","#818ab1")
palette:indexColor("secondaryButton","#82b091")
palette:indexColor("secondaryLabel","#9182b0")

function theme:getTheme()
    return palette
end

-- Hue offsets, in degrees, from the reference color to each palette slot.
-- Offsets are in color.hsl's hue frame (rgbToHsl returns hues in the same frame), which is
-- the frame the hand-tuned default palette above was built in: FG/Nav are analogous at
-- +/-30, Button/Label at +/-60, and the secondary group is the same hues desaturated.
local THEME_SLOTS = {
    {name = "primaryBG",     dh =   0, group = "primary"},
    {name = "primaryFG",     dh =  30, group = "primary"},
    {name = "primaryNav",    dh = -30, group = "primary"},
    {name = "primaryButton", dh =  60, group = "primary"},
    {name = "primaryLabel",  dh = -60, group = "primary"},
    {name = "secondaryBG",     dh =   0, group = "secondary"},
    {name = "secondaryFG",     dh =  30, group = "secondary"},
    {name = "secondaryNav",    dh = -30, group = "secondary"},
    {name = "secondaryButton", dh =  60, group = "secondary"},
    {name = "secondaryLabel",  dh = -60, group = "secondary"},
}

-- Generates every theme slot from a single reference color.
-- reference: any color parseColor understands ("#70bfc2", "hsl(...)", {r,g,b}, ...).
-- opts (all optional):
--   saturation         primary saturation, 0-100 (defaults to the reference's own saturation)
--   secondarySaturation secondary saturation    (defaults to 60% of the primary)
--   lightness          background lightness, 0-100 (defaults to the reference's own lightness)
--   primaryText / secondaryText  override the contrast colors
--   darkText           force dark text on light backgrounds (auto-detected when omitted)
--   apply              when true, also writes the result into the theme palette
function theme:newTheme(reference, opts)
    opts = opts or {}

    local refH, refS, refL = color.rgbToHsl(reference)
    local primaryS   = opts.saturation or refS
    local secondaryS = opts.secondarySaturation or (primaryS * .6)
    local lightness  = opts.lightness or refL

    local th = {reference = color.new(reference)}

    for _, slot in ipairs(THEME_SLOTS) do
        local s = slot.group == "primary" and primaryS or secondaryS
        local h = (refH + slot.dh) % 360
        th[slot.name] = color.new(color.hsl(h, s, lightness))
    end

    -- Text is picked for contrast against the generated backgrounds.
    local darkText = opts.darkText
    if darkText == nil then
        darkText = color.getAverageLightness(th.primaryBG) >= .5
    end
    th.primaryText   = opts.primaryText   or (darkText and color.new("#000000") or color.new("#ffffff"))
    th.secondaryText = opts.secondaryText or (darkText and color.new("#444444") or color.new("#bbbbbb"))

    if opts.apply then
        theme:setTheme(th)
    end

    return th
end

-- Dark obsidian preset: near-black blue glass with faint analogous tints.
-- Call theme:obsidian({apply = true}) to swap the live palette over.
-- opts may override saturation / secondarySaturation / lightness / primaryText / secondaryText / reference.
function theme:obsidian(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#1c1c24", {
        saturation          = opts.saturation or 18,
        secondarySaturation = opts.secondarySaturation or 10,
        lightness           = opts.lightness or 14,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- All presets below follow the obsidian pattern: one reference color, tuned saturation /
-- secondarySaturation / lightness, and the same opts overrides. Each accepts {apply = true}
-- to swap the live palette over, e.g. theme:midnight({apply = true}).

-- Midnight preset: deep navy night, cool blue accents.
function theme:midnight(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#16202e", {
        saturation          = opts.saturation or 28,
        secondarySaturation = opts.secondarySaturation or 16,
        lightness           = opts.lightness or 15,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Abyss preset: deep ocean teal, like looking down into dark water.
function theme:abyss(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#0f2430", {
        saturation          = opts.saturation or 32,
        secondarySaturation = opts.secondarySaturation or 18,
        lightness           = opts.lightness or 14,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Forest preset: deep woodland green with mossy analogous tints.
function theme:forest(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#17251c", {
        saturation          = opts.saturation or 26,
        secondarySaturation = opts.secondarySaturation or 15,
        lightness           = opts.lightness or 15,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Amethyst preset: dark purple jewel tones, soft violet accents.
function theme:amethyst(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#221830", {
        saturation          = opts.saturation or 30,
        secondarySaturation = opts.secondarySaturation or 17,
        lightness           = opts.lightness or 16,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Ember preset: dark forge warmth, burnt orange and red coals.
function theme:ember(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#2b1712", {
        saturation          = opts.saturation or 32,
        secondarySaturation = opts.secondarySaturation or 18,
        lightness           = opts.lightness or 15,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Mocha preset: warm dark coffee brown, cozy and low-contrast.
function theme:mocha(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#241c15", {
        saturation          = opts.saturation or 24,
        secondarySaturation = opts.secondarySaturation or 14,
        lightness           = opts.lightness or 15,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Synthwave preset: near-black with punchy neon magenta/violet accents.
function theme:synthwave(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#1e1226", {
        saturation          = opts.saturation or 45,
        secondarySaturation = opts.secondarySaturation or 26,
        lightness           = opts.lightness or 14,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Parchment preset: warm light paper cream with dark text (auto-detected).
function theme:parchment(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#efe6d2", {
        saturation          = opts.saturation or 35,
        secondarySaturation = opts.secondarySaturation or 20,
        lightness           = opts.lightness or 90,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Arctic preset: pale icy blue, crisp light theme with dark text.
function theme:arctic(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#d9e6ef", {
        saturation          = opts.saturation or 30,
        secondarySaturation = opts.secondarySaturation or 18,
        lightness           = opts.lightness or 90,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Blush preset: soft rose light theme, gentle pastel accents.
function theme:blush(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#f2dbe2", {
        saturation          = opts.saturation or 40,
        secondarySaturation = opts.secondarySaturation or 22,
        lightness           = opts.lightness or 90,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Mint preset: fresh pale green light theme, clean and airy.
function theme:mint(opts)
    opts = opts or {}
    return theme:newTheme(opts.reference or "#d9eede", {
        saturation          = opts.saturation or 32,
        secondarySaturation = opts.secondarySaturation or 19,
        lightness           = opts.lightness or 90,
        primaryText         = opts.primaryText,
        secondaryText       = opts.secondaryText,
        apply               = opts.apply,
    })
end

-- Registry of the built-in presets, handy for a theme picker UI:
--   for name, preset in pairs(theme.presets) do ... end
--   theme.presets.synthwave({apply = true})
theme.presets = {
    obsidian   = theme.obsidian,
    midnight   = theme.midnight,
    abyss      = theme.abyss,
    forest     = theme.forest,
    amethyst   = theme.amethyst,
    ember      = theme.ember,
    mocha      = theme.mocha,
    synthwave  = theme.synthwave,
    parchment  = theme.parchment,
    arctic     = theme.arctic,
    blush      = theme.blush,
    mint       = theme.mint,
}

-- Writes a generated theme table back into the palette that getTheme() hands out,
-- so anything already holding a reference to it picks up the new colors.
function theme:setTheme(th)
    if not th then
        return palette
    end
    for _, name in ipairs(palette.colors) do
        local c = th[name] or th[string.lower(name)]
        if c then
            palette:reindexColor(name, c)
        end
    end
    return palette
end

return theme