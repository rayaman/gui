local gui = require("gui")

function gui:enableGrid(cellSize)
    local grid
    if cellSize ~= nil then grid = true end

    local cellSize = cellSize or 10 -- Width and height of cells.

    self.post = function(self)
        local gridLines = {}
        if not grid then return end
        local xx, yy, windowWidth, windowHeight = self:getAbsolutes()

        -- Vertical lines.
        for x = cellSize, windowWidth, cellSize do
            local line = {xx + x, yy + 0, xx + x, yy + windowHeight}
            table.insert(gridLines, line)
        end
        -- Horizontal lines.
        for y = cellSize, windowHeight, cellSize do
            local line = {xx + 0, yy + y, xx + windowWidth, yy + y}
            table.insert(gridLines, line)
        end
        love.graphics.setLineWidth(1)
        for i, line in ipairs(gridLines) do love.graphics.line(line) end
    end
end