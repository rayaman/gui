-- gui:newCheckbox and gui:newRadioGroup
local shared = require("gui.addons.extensions.shared")
local gui      = shared.gui
local palette  = shared.palette
local miscProc = shared.miscProc

local function noOf(sx,sy,sw,sh)
    return nil,nil,nil,nil,sx,sy,sw,sh
end

function gui:newCheckbox(label, x, y, size, sx, sy, checked)
    local checkbox = self:newFrame(x, y, size, size, sx, sy)
    checkbox.color = palette.black
    local border = checkbox:newVisualFrame(noOf(.1,.1,.8,.8))
    border.color = palette.white
    local toggle = border:newFrame(noOf(.3,.3,.4,.4))
    toggle.color = palette.black
    toggle.visible = false

    checkbox:OnReleased(function()
        checkbox:check(not toggle.visible)
    end)
    
    if label ~= "" then
        local text = checkbox:newTextLabel(label, noOf(1.25,0,15,1))
        text:centerFont()
        text:setFont(size-2)
        text.visibility = 0
    end

    function checkbox:check(value)
        toggle.visible = value
        self.OnChanged:Fire(value)
    end

    function checkbox:isChecked()
        return toggle.visible
    end

    function checkbox:getLabel()
        return label or ""
    end

    checkbox.OnChanged = miscProc:newConnection()

    return checkbox
end

function gui:newRadioGroup(options, x, y, sx, sy, size)
    local group = {}
    local rg = self:newFrame()
    local selected

    rg.OnSelectionChanged = miscProc:newConnection()

    for i,v in ipairs(options or {}) do
        table.insert(group,self:newCheckbox(tostring(v),x,y+((i-1)*size+((options.padding or 0)*(i-1))),size,sx,sy))
    end

    gui.apply({
        OnReleased=function(self)
            gui.apply({check={false}},unpack(group))
            self:check(true)
            if selected ~= self then
                rg.OnSelectionChanged:Fire(rg, self)
            end
            selected = self
        end,
    },unpack(group))

    function rg:getSelectedOption()
        return selected
    end

    return rg
end
