-- Shared resources for the extension widgets under addons/extensions/.
-- Created exactly once (require caches this module): the extension palette,
-- the media/misc processors, and the theme snapshot every widget reads.
-- Addons modify the gui interface directly and do not return anything, but
-- this module is context rather than an addon itself, so it returns a table.

local gui   = require("gui")
local theme = require("gui.core.theme")
local color = require("gui.core.color")
local multi, thread = require("multi"):init()

local shared = {}

shared.gui, shared.theme, shared.color = gui, theme, color
shared.multi, shared.thread = multi, thread

local palette = color.newPalette("extensions")
palette:indexColor("white","#ffffff")
palette:indexColor("blue","#10465c")
palette:indexColor("black","#000000")
palette:indexColor("orange","#CC5500")
shared.palette = palette

shared.th = theme:getTheme()

-- Processors are created once for the whole extension set: mediaProc drives
-- the video player's seek thread, miscProc owns the widgets' connections and
-- helper threads.
shared.mediaProc = gui:newProcessor("media-updater")
shared.miscProc  = gui:newProcessor("misc-updater")

function shared.noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

return shared
