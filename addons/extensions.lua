-- addons/extensions.lua — loader for the extension widgets.
--
-- Each widget lives in its own file under addons/extensions/ and is required
-- individually below; to add a widget, drop a file in that folder and add one
-- require here. Shared resources (the extension palette, the media/misc
-- processors, the theme snapshot) are created once in
-- addons/extensions/shared.lua and required by the widgets that need them.
--
-- Addons modify the gui interface directly and do not return anything.

require("gui.addons.extensions.shared")

require("gui.addons.extensions.videoplayer")
require("gui.addons.extensions.checkbox")
require("gui.addons.extensions.listframe")
require("gui.addons.extensions.progressbar")
require("gui.addons.extensions.numberpicker")
require("gui.addons.extensions.colorpicker")
