assert(sys.provides "nested-nodes", "nested nodes feature missing")

local GLOBAL_CONTENTS, GLOBAL_CHILDS = node.make_nested()

local function setup(module_name)
    local M = {}

    local modules = {}
    local modules_content_versions = {}

    function M.make_api()
        return {}
    end

    local function module_event(child, event_name, content, ...)
        if not modules[child] then
            return
        end
        local event = modules[child][event_name]
        if event then
            -- print('-> event', event_name, content)
            return event(content, ...)
        end
    end

    local function module_unload(child)
        print("MODULE: " .. child .. " is unloading")
        for content, version in pairs(modules_content_versions[child]) do
            module_event(child, 'content_remove', content)
        end
        module_event(child, 'unload')
        modules[child] = nil
        node.dispatch("module_unload", child)
        node.gc()
    end

    local function module_load(child, module_func)
        if modules[child] then
            print("MODULE: about to replace ".. child)
            module_unload(child)
        end
        print("MODULE: loading ".. child)
        local api = M.make_api(child)

        local function localized(name)
            return child .. "/" .. name
        end
        api.localized = localized 

        api.pinned_asset = function(asset)
            print("MODULE: localizing asset " .. asset.asset_name)
            asset.file = resource.open_file(child .. "/" .. asset.asset_name)
            return asset
        end

        local module = module_func(api, GLOBAL_CHILDS[child], GLOBAL_CONTENTS[child], child)
        modules[child] = module
        module_event(child, 'load')
        local contents = {}
        for content, version in pairs(modules_content_versions[child]) do
            contents[#contents+1] = content
        end
        table.sort(contents)
        for idx = 1, #contents do
            local content = contents[idx]
            module_event(child, 'content_update', content, localized(content))
        end
        node.gc()
    end

    local function module_update_content(child, content, version)
        local mcv = modules_content_versions[child]
        if not mcv[content] or mcv[content] < version then
            mcv[content] = version
            return module_event(child, 'content_update', content)
        end
    end

    local function module_delete_content(child, content)
        local mcv = modules_content_versions[child]
        modules_content_versions[child][content] = nil
        return module_event(child, 'content_remove', content)
    end

    node.event("child_add", function(child)
        modules_content_versions[child] = {}
    end)

    node.event("child_remove", function(child)
        modules_content_versions[child] = nil
    end)

    node.event("content_update", function(name, obj)
        local child, content = util.splitpath(name)

        if child == '' then -- not interested in top level events
            return
        elseif content == module_name then
            return module_load(child, assert(
                loadstring(resource.load_file(obj), "=" .. name)
            ))
        else
            return module_update_content(child, content, GLOBAL_CONTENTS[child][name])
        end
    end)

    node.event("content_remove", function(name)
        local child, content = util.splitpath(name)

        if child == '' then -- not interested in top level events
            return
        elseif content == module_name then
            return module_unload(child)
        else
            return module_delete_content(child, content)
        end
    end)

    M.modules = modules

    return M
end

return {
    setup = setup;
}
