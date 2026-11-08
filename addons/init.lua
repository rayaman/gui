-- Addons modify the gui interface directly and do not return anything.
require("gui.addons.extensions")
-- system.lua provides newScrollFrame / newWindow / newMessageBox / newFilePicker,
-- required by the title and board screens and by the in-game editor.
require("gui.addons.system")