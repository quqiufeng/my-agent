local M = {}

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function has(bin)
    return os.execute("command -v " .. q(bin) .. " >/dev/null 2>&1") == 0
end

function M.play(wav, cfg)
    if os.getenv("SAY_DRY") == "1" then return true end
    local ok = false
    if has("pw-play") then
        local cmd = "pw-play "
        if cfg.VOICE_SINK and cfg.VOICE_SINK ~= "" then
            cmd = cmd .. "--target " .. q(cfg.VOICE_SINK) .. " "
        end
        if os.execute(cmd .. q(wav) .. " 2>/dev/null") == 0 then ok = true end
    end
    if not ok and cfg.VOICE_SPEAKER and cfg.VOICE_SPEAKER ~= "" then
        if os.execute("aplay -D " .. q(cfg.VOICE_SPEAKER) .. " -q " .. q(wav) ..
            " 2>/dev/null") == 0 then ok = true end
    end
    if not ok then
        if os.execute("aplay -q " .. q(wav) .. " 2>/dev/null") == 0 then ok = true end
    end
    return ok
end

return M
