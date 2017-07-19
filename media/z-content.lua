local api, CHILDS, CONTENTS = ...

local co = require "cotool"
local json = require "json"

local M = {}

local shaders = {
    multisample = resource.create_shader[[
        uniform sampler2D Texture;
        varying vec2 TexCoord;
        uniform vec4 Color;
        uniform float x, y, s;
        void main() {
            vec2 texcoord = TexCoord * vec2(s, s) + vec2(x, y);
            vec4 c1 = texture2D(Texture, texcoord);
            vec4 c2 = texture2D(Texture, texcoord + vec2(0.0002, 0.0002));
            gl_FragColor = (c2+c1)*0.5 * Color;
        }
    ]], 
    simple = resource.create_shader[[
        uniform sampler2D Texture;
        varying vec2 TexCoord;
        uniform vec4 Color;
        uniform float x, y, s;
        void main() {
            gl_FragColor = texture2D(Texture, TexCoord * vec2(s, s) + vec2(x, y)) * Color;
        }
    ]], 
}

local FALLBACK_PLAYLIST = {{
    duration = 3,
    prepare = 1,
    value = {
        switch_time = 0,
        asset_name = "blank.png",
        type = "image",
    },
}}

local black = {
    asset_name = "black.png";
    filename = "black.png";
    type = "image";
}

local switch_time = 1
local kenburns = false
local audio = false
local video_background = black
local image_background = black

local function update_config(raw)
    print "updated config.json"
    local config = json.decode(raw)
    local playlist

    kenburns = config.kenburns
    audio = config.audio
    video_background = api.pinned_asset(config.video_background)
    image_background = api.pinned_asset(config.image_background)

    if #config.playlist == 0 then
        playlist = FALLBACK_PLAYLIST
        kenburns = false
    else
        playlist = {}

        for idx = 1, #config.playlist do
            local item = config.playlist[idx]
            if item.duration > 0 then
                playlist[#playlist+1] = {
                    duration = item.duration,
                    prepare = (function() 
                        if item.file.type == "image" then
                            return config.switch_time/2 + 1
                        else
                            return 0.5
                        end
                    end)(),
                    value = {
                        fullscreen = item.fullscreen,
                        switch_time = config.switch_time,
                        asset_name = item.file.asset_name,
                        type = item.file.type,
                    }
                }
            end
        end
        switch_time = config.switch_time
    end

    api.playlist(playlist)
end

local function ramp(t_s, t_e, t_c, ramp_time)
    if ramp_time == 0 then return 1 end
    local delta_s = t_c - t_s
    local delta_e = t_e - t_c
    return math.min(1, delta_s * 1/ramp_time, delta_e * 1/ramp_time)
end

local function image(starts, duration, fullscreen, switch_time, asset_name, layout)
    local ends = starts + duration
    local file = resource.open_file(api.localized(asset_name))

    co.wait_frame()

    local res = resource.load_image(file)

    for now in co.wait_frame do
        local state, err = res:state()
        if state == "loaded" then
            break
        elseif state == "error" then
            error("preloading failed: " .. err)
        end
    end

    starts = starts - switch_time/ 2
    ends = ends + switch_time / 2

    co.until_t(starts-0.1)
    api.background(image_background, ends+0.1)

    if kenburns then
        local function lerp(s, e, t)
            return s + t * (e-s)
        end

        local paths = {
            {from = {x=0.0,  y=0.0,  s=1.0 }, to = {x=0.08, y=0.08, s=0.9 }},
            {from = {x=0.05, y=0.0,  s=0.93}, to = {x=0.03, y=0.03, s=0.97}},
            {from = {x=0.02, y=0.05, s=0.91}, to = {x=0.01, y=0.05, s=0.95}},
            {from = {x=0.07, y=0.05, s=0.91}, to = {x=0.04, y=0.03, s=0.95}},
        }

        local path = paths[math.random(1, #paths)]

        local to, from = path.to, path.from
        if math.random() >= 0.5 then
            to, from = from, to
        end

        local w, h = res:size()
        local multisample = w / WIDTH > 0.8 or h / HEIGHT > 0.8
        local shader = multisample and shaders.multisample or shaders.simple

        for now in co.from_to(starts, ends) do
            if fullscreen then
                api.fullscreen()
            end

            local t = (now - starts) / duration
            shader:use{
                x = lerp(from.x, to.x, t);
                y = lerp(from.y, to.y, t);
                s = lerp(from.s, to.s, t);
            }
            -- local x1, y1, x2, y2 = layout.content_area()
            -- util.draw_correct(res, x1, y1, x2, y2, ramp(
            util.draw_correct(res, 0, 0, WIDTH, HEIGHT, ramp(
                starts, ends, now, switch_time
            ))
            shader:deactivate()
        end
    else
        for now in co.from_to(starts, ends) do
            if fullscreen then
                api.fullscreen()
            end
            -- local x1, y1, x2, y2 = layout.content_area()
            -- util.draw_correct(res, x1, y1, x2, y2, ramp(
            util.draw_correct(res, 0, 0, WIDTH, HEIGHT, ramp(
                starts, ends, now, switch_time
            ))
        end
    end

    res:dispose()
    print "image job completed"
end

local function video(starts, duration, fullscreen, switch_time, asset_name, layout)
    local ends = starts + duration
    local file = resource.open_file(api.localized(asset_name))

    co.wait_frame()

    local raw = sys.get_ext "raw_video"
    local res = raw.load_video{
        file = file,
        audio = audio,
        looped = false,
        paused = true,
    }

    for now in co.wait_frame do
        local state, err = res:state()
        if state == "paused" then
            break
        elseif state == "error" then
            error("preloading failed: " .. err)
        end
    end

    local _, width, height = res:state()

    co.until_t(starts-0.1)
    api.background(video_background, ends+0.1)

    for now in co.from_to(starts, ends) do
        if fullscreen then
            api.fullscreen()
        end

        res:layer(1):start()
        local lx1, ly1, lx2, ly2 = layout.content_area()
        local area_width, area_height = lx2 - lx1, ly2 - ly1
        local x1, y1, x2, y2 = util.scale_into(area_width, area_height, width, height)
        layout.target_raw_video(res, x1+lx1, y1+ly1, x2+lx1, y2+ly1, ramp(
            starts, ends, now, switch_time
        ))
    end

    res:dispose()
    print "video job completed"
end

M.prepare = co.fun(function(starts, duration, key, value, layout)
    if value.type == "image" then
        return image(starts, duration, value.fullscreen, value.switch_time, value.asset_name, layout)
    else
        return video(starts, duration, value.fullscreen, value.switch_time, value.asset_name, layout)
    end
end)

function M.content_update(name)
    if name == "config.json" then
        update_config(resource.load_file(api.localized "config.json"))
    end
end

return M
