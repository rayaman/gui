function love.conf(t)
    t.identity = "svg-demo"
    t.console = false -- inherit parent stdout so `love ... > out.txt` captures PASS/FAIL

    t.window.title = "SVG Vector Loader Demo"
    t.window.width = 1000
    t.window.height = 800
    t.window.resizable = true
    t.window.minwidth = 400
    t.window.minheight = 300
    t.window.msaa = 4 -- anti-alias the live vector edges to match the reference PNG
end
