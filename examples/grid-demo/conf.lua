function love.conf(t)
    t.identity = "grid-demo"
    t.console = false -- inherit parent stdout so `love ... > out.txt` captures PASS/FAIL

    t.window.title = "CSS Grid Integration Demo (Phases P1-P5)"
    t.window.width = 1200
    t.window.height = 1300
    t.window.resizable = true
    t.window.minwidth = 400
    t.window.minheight = 300
end
