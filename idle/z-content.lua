local api, CHILDS, CONTENTS = ...

local co = require "cotool"

local M = {}

local font = resource.load_font(api.localized "silkscreen.ttf")

api.playlist{{
    duration = 3,
    prepare = 1,
    value = {
        text = "No playable item found",
    }
}}

-- api.scroller{{
--     text = "Hello";
-- }}

M.prepare = co.fun(function(starts, duration, key, value)
    local ends = starts + duration
    local text = value.text
    local width = font:width(text, 80)
    for now in co.from_to(starts, ends) do
        font:write((WIDTH-width)/2, 500, text, 80, 1,1,1,1)
    end
end)

return M
