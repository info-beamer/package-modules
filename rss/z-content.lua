local api, CHILDS, CONTENTS = ...

local co = require "cotool"
local json = require "json"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local M = {}

local font = resource.load_font(api.localized "font.ttf")
local background

local ticker = false
local title_color = {r=1, g=1, b=1, a=1}
local tint = resource.create_colored_texture(0,0,0,1)

local function rgba(t)
    return t.r, t.g, t.b, t.a
end

local TITLE_SIZE = 70
local SUMMARY_SIZE = 65
local SUMMARY_IMG_SIZE = 48

local function update_feed()
    local feed = json.decode(resource.load_file(api.localized "feed.json"))

    local feed_image, feed_image_file

    if feed.image then
        feed_image_file = resource.open_file(api.localized(feed.image))
        feed_image = resource.load_image(feed_image_file:copy())
    end

    local playlist = {}
    local scroller = {}
    for idx = 1, #feed.entries do
        local entry = feed.entries[idx]

        local ok, image
        if entry.image then
            ok, image = pcall(resource.open_file, api.localized(entry.image))
            if not ok then
                print("cannot load image: ".. image)
                image = nil
            end
        end

        local duration = (#entry.title + #entry.summary) / 10 + 2

        playlist[#playlist+1] = {
            duration = duration,
            prepare = 2,
            value = {
                feed_image = feed_image,
                feed_title = feed.title,

                image = image,
                title = utils.wrap_font(font, TITLE_SIZE, entry.title, 1860),
                summary = utils.wrap_font(font, SUMMARY_SIZE, entry.summary, 1860),
                summary_img = utils.wrap_font(font, SUMMARY_IMG_SIZE, entry.summary, 900),
                unix = entry.unix,
                human = entry.human,
            }
        }

        scroller[#scroller+1] = {
            image = feed_image_file;
            text = entry.title;
        }
    end

    api.playlist(playlist, true)
    if ticker then
        api.scroller(scroller)
    else
        api.scroller_remove()
    end
end

local function update_config(config)
    print "config updated"
    ticker = config.ticker
    title_color = config.title_color
    background = api.pinned_asset(config.background)
    pcall(update_feed)
end

function M.content_update(name)
    if name == "feed.json" then
        update_feed()
    elseif name == "config.json" then
        update_config(json.decode(resource.load_file(api.localized "config.json")))
    end
end

M.prepare = co.fun(function(starts, duration, key, item)
    pp(item)
    local ends = starts + duration

    co.wait_frame()

    local img
    if item.image then
        img = resource.load_image{
            file = item.image:copy(),
            mipmap = true,
        }
    end

    local x = 30
    local y = 50
    local a = anims.Set()

    local S = starts - .5
    local E = ends + .5

    a.add(anims.moving_image_noscale(S, E, tint, 10, 20, 1920-10, 1080-20, 0.9))

    local function anim_lines(x, lines, size, r,g,b)
        for idx = 1, #lines do
            local line = lines[idx]
            a.add(anims.moving_font(S, E, font, x, y, line, size, r,g,b,.9)); S=S+0.1; y=y+size+10
        end
    end

    if item.feed_image then
        a.add(anims.moving_image(S, E, item.feed_image, x, y-10, x+150, y+60, 1))
        a.add(anims.moving_font(S, E, font, x+170, y, item.feed_title, 50, 1,1,1,1)); y=y+55
    else
        a.add(anims.moving_font(S, E, font, x, y, item.feed_title, 50, 1,1,1,1)); y=y+55
    end
    y = y + 50

    anim_lines(x, item.title, TITLE_SIZE, rgba(title_color))
    y = y + 50

    if img then
        a.add(anims.moving_image(S, E, img, x+960, y, x+1920-30, y+600, 1))
        anim_lines(x, item.summary_img, SUMMARY_IMG_SIZE, .9,.9,.9)
    else
        anim_lines(x, item.summary, SUMMARY_SIZE, .9,.9,.9)
    end

    y = y + 40

    -- local age = os.time() - item.unix
    -- if age < 100 then
    --     age = string.format("%ds", age)
    -- elseif age < 3600 then
    --     age = string.format("%dm", age/60)
    -- else
    --     age = string.format("%dh", age/3600)
    -- end
    -- a.add(anims.moving_font(S, E, font, x, y, age .. " ago", 50, 1,1,1,1)); S=S+0.1; y=y+60
    a.add(anims.moving_font(S, E, font, x, y, item.human, 32, 1,1,1,1)); S=S+0.1; y=y+60

    api.background(background, ends)

    for now in co.from_to(starts-.5, ends+.5) do
        a.draw(now)
    end

    if img then
        img:dispose()
    end
end)

return M
