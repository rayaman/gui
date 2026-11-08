function love.conf(t)
    t.identity = "list-demo"
    t.console = false -- inherit parent stdout so `love ... > out.txt` captures PASS/FAIL

    t.window.title = "newListFrame Demo + Autotest"
    t.window.width = 900
    t.window.height = 700
    t.window.resizable = true
    t.window.minwidth = 500
    t.window.minheight = 400
end
