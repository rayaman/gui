# GuiManager

Use with love2d. Copy GuiManager.lua into your game and the multi library and the bin library

require like this
```lua
require("bin")
require("multi.compat.love2d") -- requires the entire library and rewrites the love.run function so you don't need worry about any modifications to the love.update and love.draw methods
require("GuiManager")
test=gui:newTextLabel("HI!",0,0,0,0,.5,.5)
test:centerX()
test:centerY()
```

Documentation will take a while. I have to finish writing the documentation for the multi library and start writing documentation for the bin, and net library 
