local api, CHILDS, CONTENTS = ...

local M = {}

local function Sidebar()
    local function draw(x1, y1, x2, y2)
    end

    return draw
end

M.load = function()
    api.register(Sidebar, 0)
end

return M
