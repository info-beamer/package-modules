local api, CHILDS, CONTENTS = ...

local M = {}

local json = require "json"

local black = resource.create_colored_texture(0,0,0,1)

local background = resource.create_colored_texture(0,0,0,1)
local foreground = {r=1,g=1,b=1,a=1}
local title = ""

local SPEED = 100
local HEIGHT = 50
local FONT_HEIGHT = HEIGHT - 6

local font

local function Scroller(feed)
    local items = {}
    local current_left = 0
    local last = sys.now()

    local function draw(y)
        black:draw(0, y, WIDTH, y+50, 0.9)

        local now = sys.now()
        local delta = now - last
        last = now
        local advance = delta * SPEED

        local idx = 1
        local x = current_left

        local function prepare_image(obj)
            if not obj then
                return
            end
            local ok, obj_copy = pcall(obj.copy, obj)
            if ok then
                return resource.load_image{
                    file = obj_copy,
                    mipmap = true,
                }
            else
                return obj
            end
        end

        while x < WIDTH do
            if idx > #items then
                local item = feed()
                if item then
                    items[#items+1] = {
                        text = item.text .. "    -    ",
                        image = prepare_image(item.image)
                    }
                else
                    items[#items+1] = {
                        text = "                      ",
                    }
                end
            end

            local item = items[idx]

            if item.image then
                local state, w, h = item.image:state()
                if state == "loaded" then
                    local width = HEIGHT / h * w
                    item.image:draw(x, y, x+width, y+HEIGHT)
                    x = x + width + 30
                end
            end

            local text_width = font:write(x, y+3, item.text, FONT_HEIGHT, 1,1,1,1)
            x = x + text_width

            if x < 0 then
                assert(idx == 1)
                if item.image then
                    item.image:dispose()
                end
                table.remove(items, idx)
                current_left = x
            else
                idx = idx + 1
            end
        end
        current_left = math.floor(current_left - advance)

        if title ~= "" then
            local width = font:width(title, FONT_HEIGHT)
            background:draw(0, y, width+40, y+50)
            font:write(20, y+3, title, FONT_HEIGHT,
                foreground.r, foreground.g, foreground.b, foreground.a
            )
        end
    end
    return draw
end

function M.load()
    api.register(Scroller, HEIGHT)
end

function M.content_update(name)
    if name == "config.json" then
        local config = json.decode(resource.load_file(api.localized "config.json"))
        font = resource.load_font(api.localized(config.font.asset_name))
        title = config.title
        background = resource.create_colored_texture(
            config.background.r, config.background.g, config.background.b, config.background.a
        )
        foreground = config.foreground
        local scroller = {}
        for idx = 1, #config.items do
            local item = config.items[idx]
            scroller[#scroller+1] = {
                text = item.text,
            }
        end
        api.scroller(scroller)
    end
end

return M
