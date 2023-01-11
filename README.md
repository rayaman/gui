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

