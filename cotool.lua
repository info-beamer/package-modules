local function wrap(fn, ...)
    local co = coroutine.create(fn)

    local ok, ret = coroutine.resume(co, ...)
    if not ok then
        return error(("%s\n%s\ninside coroutine %s started by"):format(
            ret, debug.traceback(co), co)
        )
    end

    local args = {...}
    return function(...)
        local ok, ret = coroutine.resume(co, ..., unpack(args))
        if not ok then
            return error(("%s\n%s\ninside coroutine %s resumed by"):format(
                ret, debug.traceback(co), co)
            )
        end
        return ret
    end
end

local function fun(fn)
    return function(...)
        return wrap(fn, ...)
    end
end

local function wait_frame()
    return coroutine.yield(true)
end

local function wait_t(t)
    while true do
        local now = wait_frame()
        if now >= t then
            return now
        end
    end
end

local function sleep(t)
    return wait_t(sys.now() + t)
end

local function until_t(t)
    return function()
        local now = wait_frame()
        if now < t then
            return now
        end
    end
end

local function from_to(starts, ends)
    return function()
        local now
        while true do
            now = wait_frame()
            if now >= starts then
                break
            end
        end
        if now < ends then
            return now
        end
    end
end



return {
    wrap = wrap;
    fun = fun;

    wait_t = wait_t;
    sleep = sleep;
    wait_frame = wait_frame;
    until_t = until_t;
    from_to = from_to;
}
