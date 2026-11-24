local USER   = "5bor"
local REPO   = "bor.wtf"
local BRANCH = "main"
local FILE   = "headlock.lua"

local SOURCES = {
    "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. BRANCH .. "/" .. FILE,
    "https://cdn.jsdelivr.net/gh/" .. USER .. "/" .. REPO .. "@" .. BRANCH .. "/" .. FILE,
}

local BUST = "?v=" .. tostring(os.time())

local function fetch(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if not (ok and type(body) == "string" and #body > 100) then
        ok, body = pcall(function() return game:HttpGet(url) end)
    end
    if ok and type(body) == "string" and #body > 100 then
        return body
    end
    return nil
end

local lastErr = "no source reachable"
for _, base in ipairs(SOURCES) do
    local body = fetch(base .. BUST)
    if body then
        if body:sub(1, 3) == "404" then
            lastErr = "404 on " .. base
        else
            local chunk, err = loadstring(body)
            if chunk then
                local ok, runErr = pcall(chunk)
                if not ok then
                    warn("[loader] runtime error: " .. tostring(runErr))
                end
                return
            end
            lastErr = "compile error: " .. tostring(err)
        end
    end
end

warn("[loader] failed - " .. lastErr)
