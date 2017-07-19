local api, CHILDS, CONTENTS = ...

local co = require "cotool"
local json = require "json"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local M = {}

local font
local background
local fullscreen = true
local show_logo = true
local char_per_sec = 7
local include_in_scroller = false
local logo = resource.load_image{
    file = api.localized "twitter-logo.png"
}

local shade_text = false
local shading = resource.create_colored_texture(0,0,0, .3)

local function update_tweets(tweets)
    local playlist, scroller = {}, {}

    for idx = 1, #tweets do
        local tweet = tweets[idx]

        local ok, profile, image, video
        local text_time = math.max(6, #tweet.text / char_per_sec)
        local media_time = 0

        ok, profile = pcall(resource.open_file, api.localized(tweet.profile_image))
        if not ok then
            print("cannot use this tweet. profile image missing", profile)
            profile = nil
        end

        if #tweet.images > 0 then
            -- TODO: load more than only the first image
            ok, image = pcall(resource.open_file, api.localized(tweet.images[1]))
            if not ok then
                print("cannot open image", image)
                image = nil
            else
                text_time = text_time / 2
                media_time = 10
            end
        end

        if tweet.video then
            ok, video = pcall(resource.open_file, api.localized(tweet.video.filename))
            if ok then
                if tweet.video.duration then
                    media_time = 2 + tweet.video.duration
                else
                    media_time = 2 + 5
                end
            else
                print("cannot open video", video)
                video = nil
            end
        end
            
        if profile then
            playlist[#playlist+1] = {
                duration = text_time + media_time,
                prepare = 2,
                value = {
                    screen_name = tweet.screen_name,
                    name = tweet.name,
                    lines = tweet.lines,
                    profile = profile,
                    image = image,
                    video = video,
                    text_time = text_time,
                    created_at = tweet.created_at,
                }
            }

            if include_in_scroller then
                print('include in scroller???', include_in_scroller)
                scroller[#scroller+1] = {
                    text = "@" .. tweet.screen_name .. "/ " .. tweet.text,
                    image = profile,
                }
            end
        end
    end

    api.playlist(playlist, true)
    api.scroller(scroller)
end

local function update_config(config)
    print "config updated"
    pp(config)

    background = api.pinned_asset(config.background)
    fullscreen = config.fullscreen
    char_per_sec = config.char_per_sec
    include_in_scroller = config.include_in_scroller
    font = resource.load_font(api.localized(config.font.asset_name))

    if config.shading > 0.0 then
        shade_text = true
        shading = resource.create_colored_texture(0,0,0, config.shading)
    else
        shade_text = false
    end

    show_logo = config.show_logo

    node.gc()
end

function M.content_update(name)
    print("Twitter content update:", name)
    if name == "tweets.json" then
        update_tweets(json.decode(resource.load_file(api.localized "tweets.json")))
    elseif name == "config.json" then
        update_config(json.decode(resource.load_file(api.localized "config.json")))
    end
end

M.prepare = co.fun(function(starts, duration, key, tweet)
    local ends = starts + duration

    pp(tweet)

    local profile = resource.load_image{
        file = tweet.profile:copy(),
        mipmap = true,
    }

    co.wait_t(starts-1.5)

    local image, video

    if tweet.image then
        image = resource.load_image{
            file = tweet.image:copy(),
        }
    end

    if tweet.video then
        video = resource.load_video{
            file = tweet.video:copy(),
            paused = true,
        }
    end

    co.wait_frame()

    local age = os.time() - tweet.created_at
    if age < 100 then
        age = string.format("%ds", age)
    elseif age < 3600 then
        age = string.format("%dm", age/60)
    elseif age < 86400 then
        age = string.format("%dh", age/3600)
    else
        age = string.format("%dd", age/86400)
    end

    local start_y = 100

    local x = 100
    local y = start_y
    local a = anims.Set()

    local S = starts - .5
    local M = starts + tweet.text_time
    local E = ends + .5

    local x2 = 30
    local y2 = 30

    if video or image then
        local obj = video or image
        a.add(anims.moving_2pos_image(S,M,E, obj,
            WIDTH - 600, 100, WIDTH - 30, 1000,
            30, 150, WIDTH - 30, HEIGHT - 150 
        ))

        if shade_text then
            local profile_width = math.max(
                font:width(tweet.name, 70),
                font:width("@" .. tweet.screen_name, 40)
            )
            a.add(anims.moving_2pos_image_raw(S,M,E, shading,
                x-10, y-10, x+140+profile_width+10, y+80+40+10,
                x2-10, y2-10, x2+profile_width+10, y2+75+40+10
            ))
        end

        a.add(anims.moving_2pos_font(S,M,E, font, x+140, y, x2, y2, tweet.name, 70, 1,1,1,1)); y=y+75; y2=y2+75
        a.add(anims.moving_2pos_font(S,M,E, font, x+140, y, x2, y2, "@"..tweet.screen_name, 40, 1,1,1,.8)); S=S+0.1
        y = y + 90

        local size1, size2 = 70, 40
        y2 = 1080 - 30 - #tweet.lines * size2

        if shade_text then
            local text_width_big, text_width_sml = 0, 0
            for idx = 1, #tweet.lines do
                local line = tweet.lines[idx]
                text_width_big = math.max(text_width_big, font:width(line, size1))
                text_width_sml = math.max(text_width_sml, font:width(line, size2))
            end
            a.add(anims.moving_2pos_image_raw(S,M,E, shading,
                x-10, y-10, x+text_width_big+10, y+#tweet.lines*size1+80,
                x2-10, y2-10, x2+text_width_sml+10, y2+#tweet.lines*size2+10
            ))
        end

        for idx = 1, #tweet.lines do
            local line = tweet.lines[idx]
            a.add(anims.moving_2pos_scale_font(S,M,E, font, x, y, x2, y2, size2/size1, line, size1, 1,1,1,1)); S=S+0.1; y=y+size1; y2=y2+size2
        end
        y = y + 20

        a.add(anims.moving_2pos_font(S,M,E, font, x, y, -300, HEIGHT, age .. " ago", 50, 1,1,1,.8))
        if show_logo then
            a.add(anims.logo(S, E, WIDTH-130, HEIGHT-130, logo, 100))
        end
        a.add(anims.tweet_profile(S, M+0.8, x, start_y, profile, 120))
    else
        if shade_text then
            local profile_width = math.max(
                font:width(tweet.name, 70),
                font:width("@" .. tweet.screen_name, 40)
            )
            a.add(anims.moving_image_raw(S,E, shading,
                x-10, y-10, x+140+profile_width+10, y+80+40+10, 1
            ))
        end
        a.add(anims.moving_font(S, E, font, x+140, y, tweet.name, 70, 1,1,1,1)); y=y+75
        a.add(anims.moving_font(S, E, font, x+140, y, "@"..tweet.screen_name, 40, 1,1,1,.8)); S=S+0.1;
        y = y + 80

        if shade_text then
            local text_width = 0
            for idx = 1, #tweet.lines do
                local line = tweet.lines[idx]
                text_width = math.max(text_width, font:width(line, 80))
            end
            a.add(anims.moving_image_raw(S,E, shading,
                x-10, y-10, x+text_width+10, y+#tweet.lines*80+10+70, 1
            ))
        end

        for idx = 1, #tweet.lines do
            local line = tweet.lines[idx]
            a.add(anims.moving_font(S, E, font, x, y, line, 80, 1,1,1,1)); S=S+0.1; y=y+80
        end
        y = y + 20
        a.add(anims.moving_font(S, E, font, x, y, age .. " ago", 50, 1,1,1,.8))
        if show_logo then
            a.add(anims.logo(S, E, WIDTH-130, HEIGHT-130, logo, 100))
        end
        a.add(anims.tweet_profile(S, E, x, start_y, profile, 120))
    end

    api.background(background, ends)

    for now in co.from_to(starts-.5, ends+.5) do
        if fullscreen and now > starts and now < ends then
            api.fullscreen()
        end
        if now > M+1 and video then
            video:start()
        end
        a.draw(now)
    end

    profile:dispose()

    if image then
        co.sleep(0.1)
        image:dispose()
    end

    if video then
        co.sleep(0.1)
        video:dispose()
    end
end)

return M
