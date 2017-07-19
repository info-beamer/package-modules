gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)
WIDTH, HEIGHT = 1920, 1080

util.noglobals()

node.alias "root"
node.set_flag "no_jit"

local easing = require "easing"
local inspect = require "inspect"
local json = require "json"
local deque = require "deque"
local loader = require "loader"
local matrix = require "matrix"

local raw_video = sys.get_ext "raw_video"
local screen = sys.get_ext "screen"

do
    -- Make require non-caching, so that
    -- reloading a module.lua will re-require
    -- all its dependencies.
    local old_require = require
    function require(module)
        package.loaded[module] = nil
        return old_require(module)
    end
end

local content_mods = loader.setup 'z-content.lua'
local scroller_mods = loader.setup 'z-scroller.lua'
local sidebar_mods = loader.setup 'z-sidebar.lua'

local background_loop

local function reset_view()
    local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    return gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
                               WIDTH/2, HEIGHT/2, 0)
end

local function printf(fmt, ...)
    return print(string.format(fmt, ...))
end

local function cycled(items, offset)
    offset = offset % #items + 1
    return items[offset], offset 
end

local function Time()
    local base_t = 0

    local function unix()
        if base_t == 0 then
            local unix = os.time()
            if unix > 100000 then
                base_t = unix - sys.now()
            end
        end
        return base_t + sys.now()
    end

    return {
        unix = unix;
    }
end

local function Visibility(speed)
    speed = speed or 0.016
    local visibility = 0
    local target = 0
    local restore = sys.now()

    local function hide(duration)
        target = 0
        restore = sys.now() + duration
    end

    local current_speed = 0
    local function tick()
        if sys.now() > restore then
            target = 1
        end
        if target > visibility then
            visibility = math.min(1, visibility + speed)
        elseif target < visibility then
            visibility = math.max(0, visibility - speed)
        end
    end

    local function get()
        return visibility
    end

    return {
        tick = tick;

        hide = hide;
        get = get;
    }
end

local function Background(layout)
    local pq = deque.new() -- play queue of background objects

    local fallback = {
        key = newproxy(),
        obj = resource.create_colored_texture(0,0,0,0),
        type = "image",
        needs_dispose = true,
    }

    local function enqueue_fallback()
        pq:push_right(fallback)
        fallback.ends = sys.now() + 0.5
    end

    local function convert_to_playable(asset)
        if asset.filename == "empty.png" then
            return nil
        elseif asset.type == "image" then
            local ok, res = pcall(resource.load_image, {
                file = (asset.file and asset.file:copy()) or asset.path or asset.asset_name,
            })
            if not ok then
                print("BG: cannot find assigned background image: " .. res)
                return nil
            else
                return res
            end
        else
            local ok, res = pcall(raw_video.load_video, {
                file = (asset.file and asset.file:copy()) or asset.path or asset.asset_name,
                looped = true,
                stopped = true,
            })
            if not ok then
                print("BG: cannot find assigned background video: " .. res)
                return nil
            else
                return res
            end
        end
    end

    local function set_fallback(asset)
        -- end current fallback
        fallback.ends = sys.now()
        fallback.needs_dispose = true

        -- create a new fallback
        fallback = {
            key = newproxy(),
            ends = sys.now() + 0.5,
            obj = convert_to_playable(asset) or resource.create_colored_texture(0, 0, 0, 1),
            type = asset.type,
            needs_dispose = false,
        }
    end

    local function add_overlay(asset, ends)
        print(string.format("BG: Adding overlay until %f: %fs", ends, sys.now() - ends))
        pp(asset)

        local playing = pq:peek_left()
        local latest = pq:peek_right()
        assert(playing)
        assert(latest)

        if latest.ends > ends then
            -- Ignore overlay request, if we have an
            -- item enqueued that ends later than the
            -- one we try to enqueue.
            return
        end

        if playing.key == asset.filename then
            print "BG: extended current overlay, as it's the same file"
            playing.ends = ends
            return
        end

        local obj = convert_to_playable(asset)
        if not obj then
            print "BG: no overlay given or overlay not available"
            -- no overlay given. Nothing to add to the 
            -- play queue in that case.
            return
        end

        if playing == fallback then
            -- Fallback playing, then end that now.
            print "BG: prematurely ending fallback"
            playing.ends = sys.now()
        end

        pq:push_right{
            key = asset.filename,
            ends = ends,
            obj = obj,
            type = asset.type,
            needs_dispose = true,
        }
    end

    local function switch_current()
        local old_playing = pq:pop_left()
        assert(old_playing)

        if old_playing.type == "video" then
            old_playing.obj:target(-1000, -1000, -1000, -1000)
        end

        if old_playing.needs_dispose then
            print "BG: disposing"
            old_playing.obj:dispose()
        elseif old_playing.type == "video" then
            print "BG: stopping old video"
            old_playing.obj:stop()
        else
            print "BG: did nothing to old background"
        end

        local playing = pq:peek_left()

        if playing.type == "video" then
            playing.obj:layer(-5):start()
        end
    end

    enqueue_fallback()

    local mode = "playback"
    local visibility = Visibility(0.05)

    local function tick()
        visibility.tick()

        if mode ~= "playback" then
            -- already switching.
            return
        end

        local playing = pq:peek_left()

        if sys.now() < playing.ends then
            -- Current background still playing? Nothing to do.
            return
        end

        print("BG: current background ends. Seeing what's next")

        if pq:length() < 2 then
            enqueue_fallback()
        end

        assert(pq:length() >= 2)
        print("BG: background queue length is " .. pq:length())

        local current = pq:pop_left()
        local next = pq:peek_left()

        print("BG: current key " .. tostring(current.key) .. " next key " .. tostring(next.key))

        if current.key == next.key then
            -- next background is the same as the current
            -- one. Don't to any transitions in that case.
            print "BG: playing the same background again. Nothing to do"
        else
            -- push current element back into the queue.
            pq:push_left(current)
            mode = "fade_out"
            print "BG: fading to next background"
        end
    end

    local function draw(optimize)
        local alpha = 1

        if mode == "fade_out" then
            visibility.hide(0.1)
            alpha = visibility.get()
            if alpha < 0.05 then
                switch_current()
                mode = "fade_in"
            end
        elseif mode == "fade_in" then
            alpha = visibility.get()
            if alpha == 1 then
                mode = "playback"
            end
        end

        local playing = pq:peek_left()
        -- print(mode, playing.obj, playing.needs_dispose, playing.ends, sys.now())

        if playing.type == "image" then
            local x1, y1, x2, y2, tx1, ty1, tx2, ty2
            if optimize then
                x1, y1, x2, y2 = layout.content_area()
                tx1 = 1/WIDTH * x1
                ty1 = 1/HEIGHT * y1
                tx2 = 1/WIDTH * x2
                ty2 = 1/HEIGHT * y2
            else
                x1, y1, x2, y2 = 0, 0, WIDTH, HEIGHT
                tx1, ty1, tx2, ty2 = 0, 0, 1, 1
            end
            playing.obj:draw(x1, y1, x2, y2, alpha, tx1, ty1, tx2, ty2)
        else
            layout.target_raw_video(playing.obj, 0, 0, WIDTH, HEIGHT, alpha)
        end
    end

    return {
        set_fallback = set_fallback;
        add_overlay = add_overlay;

        tick = tick;
        draw = draw;
    }
end

local function Scroller(content, layout)
    local modules = {}
    local next_name
    local current_module

    local function set_module(name)
        print("SCROLLER: setting next name to " .. name)
        next_name = name
    end

    local function register(name, impl, height)
        modules[name] = {
            draw = impl(content.get_next);
            height = height;
            name = name;
        }
        if current_module and current_module.name == name then
            set_module(name)
        end
    end

    local function unregister(name)
        modules[name] = nil
    end

    local function tick()
        if next_name then
            if layout.scroller_visible() then
                layout.scroller_hide(0.05, true)
            else
                print("SCROLLER: now starting " .. next_name)

                current_module = modules[next_name]
                next_name = nil

                layout.scroller_set_height(current_module.height)
            end
        end
    end

    local function draw()
        if layout.scroller_visible() then
            local y = layout.scroller_top()
            return current_module.draw(y)
        end
    end

    return {
        register = register;
        unregister = unregister;

        set_module = set_module;

        tick = tick;
        draw = draw;
    }
end

local function Sidebar(layout)
    local modules = {}
    local next_name
    local current_module

    local function set_module(name)
        next_name = name
    end

    local function register(name, impl, width)
        print("REGISTER SIDEBAR", name, impl, width)
        modules[name] = {
            draw = impl();
            width = width;
            name = name;
        }
        if current_module and current_module.name == name then
            set_module(name)
        end
    end

    local function unregister(name)
        modules[name] = nil
    end

    local function tick()
        if next_name then
            print("NEXT_NAME", next_name)
            if layout.sidebar_visible() then
                layout.sidebar_hide(0.1, true)
            else
                current_module = modules[next_name]
                next_name = nil

                layout.sidebar_set_width(current_module.width)
            end
        end
    end

    local function draw()
        if layout.sidebar_visible() then
            return current_module.draw(layout.sidebar_area())
        end
    end

    return {
        register = register;
        unregister = unregister;

        set_module = set_module;

        tick = tick;
        draw = draw;
    }
end


local function ScrollerPlaylist()
    local module_schedules = {}
    local module_offsets = {}

    local modules = {}
    local current_module = 0 -- index into modules

    local function get_next()
        if #modules == 0 then
            return
        end
        local start_module = math.max(1, current_module)
        repeat
            local module
            module, current_module = cycled(modules, current_module)

            local item
            local schedule = module_schedules[module]
            if schedule and #schedule > 0 then
                local schedule_idx = module_offsets[module]
                item, schedule_idx = cycled(schedule, schedule_idx)
                module_offsets[module] = schedule_idx
                return item
            end
        until current_module == start_module
    end

    local function update_modules()
        modules = {}
        for module, _ in pairs(module_schedules) do
            modules[#modules+1] = module
        end
        print "scroll content update"
        pp(modules)
    end

    local function schedule_update(module, schedule, restart)
        module_schedules[module] = schedule
        if restart then
            module_offsets[module] = 0
        else
            module_offsets[module] = module_offsets[module] or 0
        end
        update_modules()
    end

    local function schedule_remove(module)
        module_schedules[module] = nil
        module_offsets[module] = nil
        update_modules()
    end

    return {
        schedule_update = schedule_update;
        schedule_remove = schedule_remove;

        get_next = get_next;
    }
end

local function ContentPlaylist()
    local module_schedules = {}
    local module_offsets = {}

    local module_infos = {}
    local current_module = 0 -- index into module_infos

    local function update_playlist(playlist)
        module_infos = {}
        for idx = 1, #playlist do
            local module = playlist[idx]
            if module.num_items > 0 then
                module_infos[#module_infos+1] = {
                    num_items = module.num_items,
                    module = module.module.asset_name,
                }
            end
        end

        -- Nothing configured
        if #module_infos == 0 then
            module_infos = {{
                num_items = 1,
                module = "idle",
            }}
        end

        print "updated base playlist"
    end

    local module_info -- information about the current module
    local quota = 0 -- how many items to play from the current module

    local function get_next()
        local start_module = math.max(1, current_module)
        repeat
            quota = quota - 1
            if quota <= 0 then
                module_info, current_module = cycled(module_infos, current_module)
                print("XXX: switched to next module", module_info.module)
                quota = module_info.num_items
            end

            local item
            local module = module_info.module
            local schedule = module_schedules[module]
            if schedule and #schedule > 0 then
                print("XXX: selecting item from schedule ", module)
                local schedule_idx = module_offsets[module]
                item, schedule_idx = cycled(schedule, schedule_idx)
                module_offsets[module] = schedule_idx
                print("XXX: selected ", module, "at offset", schedule_idx, item)
                return module, item
            end
        until current_module == start_module
        return nil
    end

    local function schedule_update(module, schedule, restart)
        print "schedule updated"
        module_schedules[module] = schedule
        if restart then
            module_offsets[module] = 0
        else
            module_offsets[module] = module_offsets[module] or 0
        end
    end

    local function schedule_remove(module)
        module_schedules[module] = nil
        module_offsets[module] = nil
    end

    local function get_schedules()
        return module_schedules
    end

    return {
        update_playlist = update_playlist;

        schedule_update = schedule_update;
        schedule_remove = schedule_remove;

        get_schedules = get_schedules;
        get_next = get_next;
    }
end

local function Job(module, prepare, autoscale, runner)
    local done = false

    local function draw(now)
        if now < prepare or done then
            return
        end

        local ok, err = xpcall(runner, debug.traceback, now)
        if not ok then
            printf("error running module '%s': %s", module, err)
            done = true
        elseif not err then
            printf("module '%s' finished", module)
            done = true
        end
    end

    local function is_finished()
        return done
    end
    return {
        draw = draw;
        autoscale = autoscale;
        is_finished = is_finished;
    }
end

local function Content(playlist, layout)
    local min_queue_size = 3
    local queue = deque.new()

    local scheduled_until = sys.now()

    local function enqueue(module, item)
        local module_ns = content_mods.modules[module]
        local ok, runner = xpcall(module_ns.prepare, debug.traceback,
            scheduled_until, item.duration, item.key, item.value, layout
        )
        if not ok then
            print(("item prepare returned error: %s"):format(runner))
        else
            queue:push_right(Job(
                module,
                scheduled_until - (item.prepare or 0),
                not module_ns.no_autoscale,
                runner
            ))
            scheduled_until = scheduled_until + item.duration
        end
    end

    local function fill_queue()
        local retry = 3
        while queue:length() < min_queue_size do
            retry = retry - 1
            if retry < 0 then
                break
            end

            local module, item = playlist.get_next()

            if not module then
                print "cannot get a module from master playlist"
            elseif not item then
                print "module has no items"
            elseif not content_mods.modules[module] then
                print "module not available"
            else
                enqueue(module, item)
            end
         end

         if queue:length() <= 1 then
             print "enqueueing idle"
             enqueue("idle", {
                 duration = 1,
                 prepare = 0,
                 value = {
                     text = "No runnable module found"
                 },
             })
         end
     end

     local function tick()
         fill_queue()
     end

     local function draw()
         local now = sys.now()
         for job in queue:iter_left() do
             gl.pushMatrix()
             if job.autoscale then
                 layout.update_matrix(layout.content_area())
             end
             job.draw(now)
             gl.popMatrix()
         end

         while not queue:is_empty() do
             local job = queue:peek_left()
             if not job.is_finished() then
                 break
             end
             queue:pop_left()
         end
     end

     return {
         tick = tick;
         draw = draw;
     }
end

local function LayoutVariable()
    local value = 0
    local next_value
    local visibility = Visibility()

    local function get()
        return value * easing.inOutSine(visibility.get(), 0, 1, 1)
    end

    local function set(new_next_value)
        if next_value == new_next_value then
            return
        end
        next_value = new_next_value
        visibility.hide(1.5)
    end

    local function tick()
        visibility.tick()
        if next_value and visibility.get() == 0 then
            value = next_value
            next_value = nil
        end
    end

    return {
        get = get;
        set = set;
        hide = visibility.hide;

        tick = tick;
    }
end

local function Layout()
    local sidebar_width = LayoutVariable()
    local scroller_height = LayoutVariable()

    local sidebar_mode = "child"
    local scroller_mode = "child"
    
    -- Precalculate the surface2screen translation function
    -- that maps coordinates from the surface to physical
    -- coordinates on the screen.
    local vx1, vy1, vx2, vy2 = util.scale_into(NATIVE_WIDTH, NATIVE_HEIGHT, WIDTH, HEIGHT)
    local surface2screen = matrix.trans(vx1, vy1) *
                           matrix.scale(
                               (vx2-vx1) / WIDTH,
                               (vy2-vy1) / HEIGHT
                           )
                           
    local function s2s(x1, y1, x2, y2)
        local tx1, ty1 = surface2screen(x1, y1)
        local tx2, ty2 = surface2screen(x2, y2)
        return tx1, ty1, tx2, ty2
    end

    print(string.format("S2S: %d,%d - %d,%d", s2s(0, 0, WIDTH, HEIGHT)))

    local function scroller_set_mode(new_mode)
        scroller_mode = new_mode
    end

    local function sidebar_set_mode(new_mode)
        sidebar_mode = new_mode
    end

    local function content_topleft()
        return 0, 0
    end

    local function content_area()
        return 0, 0, WIDTH - sidebar_width.get(), HEIGHT - scroller_height.get()
    end

    local function sidebar_area()
        return WIDTH - sidebar_width.get(), 0, WIDTH, HEIGHT - scroller_height.get()
    end

    local function sidebar_visible()
        return sidebar_width.get() ~= 0
    end

    local function scroller_top()
        return HEIGHT - scroller_height.get()
    end

    local function scroller_visible()
        return scroller_height.get() ~= 0
    end

    local function update_matrix(x1, y1, x2, y2)
        local area_w = x2 - x1
        local area_h = y2 - y1
        local sx1, sy1, sx2, sy2 = util.scale_into(area_w, area_h, WIDTH, HEIGHT)
        local w = sx2 - sx1
        local h = sy2 - sy1
        -- print(sx1, sy1, w, h, WIDTH, HEIGHT)                                                                                                                                                                                                                                                                                                                                                   
        gl.translate(sx1, sy1)
        gl.scale(w/WIDTH, h/HEIGHT)
    end

    local function target_raw_video(raw, x1, y1, x2, y2, alpha)
        x1, y1, x2, y2 = s2s(x1, y1, x2, y2)
        return raw:target(x1, y1, x2, y2, alpha)
    end

    local function tick()
        if sidebar_mode == "never" then
            sidebar_width.hide(0.2)
        end
        if scroller_mode == "never" then
            scroller_height.hide(0.2)
        end

        sidebar_width.tick()
        scroller_height.tick()
    end

    local function sidebar_hide(t, force)
        if sidebar_mode ~= "always" or force then
            return sidebar_width.hide(t)
        end
    end

    local function scroller_hide(t, force)
        if scroller_mode ~= "always" or force then
            return scroller_height.hide(t)
        end
    end

    return {
        content_area = content_area;
        content_topleft = content_topleft;

        sidebar_set_mode = sidebar_set_mode;
        sidebar_area = sidebar_area;
        sidebar_set_width = sidebar_width.set;
        sidebar_hide = sidebar_hide;
        sidebar_visible = sidebar_visible;

        scroller_set_mode = scroller_set_mode;
        scroller_top = scroller_top;
        scroller_set_height = scroller_height.set;
        scroller_hide = scroller_hide;
        scroller_visible = scroller_visible;

        update_matrix = update_matrix;
        target_raw_video = target_raw_video;

        tick = tick;
    }
end

local time = Time()

local layout = Layout()

local background = Background(layout)

local content_playlist = ContentPlaylist()
local content = Content(content_playlist, layout)

local scroller_playlist = ScrollerPlaylist()
local scroller = Scroller(scroller_playlist, layout)

local sidebar = Sidebar(layout)

util.file_watch("config.json", function(raw)
    local config = json.decode(raw)

    content_playlist.update_playlist(config.playlist)

    scroller.set_module(config.scroller.asset_name)
    sidebar.set_module(config.sidebar.asset_name)

    layout.scroller_set_mode(config.show_scroller)
    layout.sidebar_set_mode(config.show_sidebar)

    background.set_fallback(config.background)
end)

function content_mods.make_api(child)
    return {
        time = time;

        playlist = function(schedule, restart)
            content_playlist.schedule_update(child, schedule, restart)
        end;
        playlist_remove = function()
            content_playlist.schedule_remove(child)
        end;

        scroller = function(schedule)
            scroller_playlist.schedule_update(child, schedule)
        end;
        scroller_remove = function(schedule)
            scroller_playlist.schedule_remove(child)
        end;

        scroller_hide = function()
            layout.scroller_hide(0.05)
        end;

        sidebar_hide = function()
            layout.sidebar_hide(0.05)
        end;

        fullscreen = function()
            layout.scroller_hide(0.05)
            layout.sidebar_hide(0.05)
        end;

        background = function(obj, ends)
            obj.path = child .. "/" .. obj.asset_name
            background.add_overlay(obj, ends)
        end;
    }
end

function scroller_mods.make_api(child)
    return {
        time = time;

        register = function(class, height)
            scroller.register(child, class, height)
        end;

        scroller = function(schedule)
            scroller_playlist.schedule_update(child, schedule)
        end;
    }
end

function sidebar_mods.make_api(child)
    return {
        time = time;

        register = function(class, width)
            sidebar.register(child, class, width)
        end;
    }
end

node.event("module_unload", function(child)
    print "running unload code"
    content_playlist.schedule_remove(child)
    scroller_playlist.schedule_remove(child)
    scroller.unregister(child)
    sidebar.unregister(child)
end)

function node.render()
    gl.clear(0,0,0,0)

    -- tick phase
    background.tick()
    content.tick()
    sidebar.tick()
    scroller.tick()
    layout.tick()

    -- draw phase
    reset_view()
    background.draw(true)
    content.draw()
    sidebar.draw()
    scroller.draw()
end
