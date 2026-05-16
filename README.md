# GuiManager

This library due to the changes in love2d. Too many things are broken and instead of doing patch work, I've decided to do a total rewrite. Also I'll be able to make use of the new multi manager features and build a better library from the ground up.

Core Objects:
- ~~Frame~~ ✔️
- Text:
  - ~~Label~~ ✔️
  - ~~Box~~ ✔️
  - ~~Button~~ ✔️
  - utf8 support with textbox (Forgot about this, will have to rework some things)
- Image:
  - ~~Label~~ ✔️
  - ~~Button~~ ✔️
  - Animation
- ~~Video~~ ✔️

Events:
- Mouse Events
  - ~~Enter~~ ✔️
  - ~~Exit~~ ✔️
  - ~~Pressed~~ ✔️
  - ~~Released~~ ✔️
  - ~~Moved~~ ✔️
  - ~~WheelMoved~~ ✔️
  - ~~DragStart~~ ✔️
  - ~~Dragging~~ ✔️
  - ~~DragEnd~~ ✔️
- Keyboard Events
  - ~~Hotkey~~ ✔️ Refer to [KeyConstants](https://love2d.org/wiki/KeyConstant) wiki page
    - Some default hotkeys have been added:
      - ~~(conn)gui.HotKeys.OnSelectAll~~ ✔️ `Ctrl + A`
      - ~~(conn)gui.HotKeys.OnCopy~~ ✔️ `Ctrl + C`
      - ~~(conn)gui.HotKeys.OnPaste~~ ✔️ `Ctrl + V`
      - ~~(conn)gui.HotKeys.OnUndo~~ ✔️ `Ctrl + Z`
      - ~~(conn)gui.HotKeys.OnRedo~~ ✔️ `Ctrl + Y, Ctrl + Shift + Z`
- Other Events
  - ~~OnUpdate~~ ✔️
  - ~~OnDraw~~ ✔️
Polish:
  - ~~gui:newCheckbox()~~
  - ~~gui:isOnScreen()~~
  - ~~gui:newRadioGroup()~~
  - gui:newSlider()
  - ~~gui:newProgressBar()~~
  - gui:newTooltip()
  - gui:newTextArea()
    - TODO: selection, hotkeys
  - gui:newListFrame()
  - gui:newGridFrame()

Better Transistions:
  - ease.easeIn(start, stop, time)      -- accelerates from start
  - ease.easeOut(start, stop, time)     -- decelerates into stop
  - ease.easeInOut(start, stop, time)   -- smooth S-curve
  - ease.easeInCubic(...)               -- more aggressive acceleration
  - ease.easeOutCubic(...)              -- more aggressive deceleration
  - ease.bounce(start, stop, time)      -- bounces at the end
  - ease.elastic(start, stop, time)     -- overshoots then settles
  - ease.back(start, stop, time)        -- slight pull-back before moving

Focus Management:
  -   gui.focus.set(element)       -- programmatically set focus
  -   gui.focus.get()              -- returns currently focused element (or nil)
  -   gui.focus.clear()            -- clear focus (no element focused)
  -   gui.focus.setTabOrder(list)  -- set a list of elements for Tab navigation
  -   gui.focus.tabNext()          -- focus the next element in the tab order
  -   gui.focus.tabPrev()          -- focus the previous element

Z-index Enhancments:
 - gui:setLayer(n)
 - gui:getLayer()