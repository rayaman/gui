local gui = require("gui")

function newCanvas()
    local c = gui:newVirtualFrame(0,0,0,0,0,0,1,1)
    
    function c:swap(c1, c2)
        local temp = c1.children
        c1.children = c2.children
        c2.children = temp
        for i,v in pairs(c1.children) do
            v.parent = c1
        end
        for i,v in pairs(c2.children) do
            v.parent = c2
        end
    end

    return c
end

return newCanvas