 function love.conf(t)
    t.identity = "flex-demo"
    t.console = false -- inherit parent stdout so `love ... > out.txt` captures PASS/FAIL

    t.window.title = "Flexbox Integration Demo (Phases 1-4)"
    t.window.width = 1000
    t.window.height = 1300
    t.window.resizable = true
    t.window.minwidth = 400
    t.window.minheight = 300
end
