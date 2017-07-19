local M = {}

function M.wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi-here > limit then
            here = st
            return "\n"..word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token
    end
    return splitted
end

function M.wrap_font(font, size, text, max_width)
    local lines = {}

    local line = {}
    local w = 0

    local space_w = font:width(" ", size)

    local function flush(tw)
        lines[#lines+1] = table.concat(line, " ")
        line = {}
        w = 0
    end

    for token in text:gmatch("[^\n ]+") do
        local tw = font:width(token, size)
        if w + tw > max_width and w > 0 then
            flush(tw)
        end
        line[#line+1] = token
        w = w + tw + space_w
    end
    if #line > 0 then
        flush()
    end
    
    return lines

end

function M.cycled(items, offset)
    offset = offset % #items + 1
    return items[offset], offset
end

function M.easeInOut(t, b, c)
    c = c - b
    return -c * math.cos(t * (math.pi/2)) + c + b;
end

return M
