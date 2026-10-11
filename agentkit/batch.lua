-- agentkit/batch.lua — 批量执行 + 批量记录，生成结果集
--   local recs = ak.batch.run("google", "search", {"OpenAI","DeepSeek","Anthropic"})
--   ak.batch.save_jsonl("/opt/my-agent/agentkit/results/google.jsonl", recs)
--   ak.batch.save_lua(..., recs)
local cjson = require("cjson")
local M = {}

-- kind: "search"（google）| "ask"（gemini）| "send"（wechat）...
-- opts = { call={...}, between=秒, read="read_results"|"read" }
function M.run(app, kind, items, opts)
    opts = opts or {}
    local adapter = require("agentkit.adapters." .. app)
    local read_fn = opts.read or (adapter.read_results and "read_results" or "read")
    local recs = {}
    for i, item in ipairs(items) do
        local rec = { index = i, app = app, kind = kind, input = item,
                      ts = os.date("%Y-%m-%d %H:%M:%S") }
        local ok, err = pcall(function()
            adapter[kind](item, opts.call)
            if adapter[read_fn] then rec.result = adapter[read_fn]() end
        end)
        if not ok then rec.error = tostring(err) end
        recs[#recs + 1] = rec
        if opts.between then os.execute("sleep " .. tostring(opts.between)) end
    end
    return recs
end

function M.save_jsonl(path, recs)
    local f = assert(io.open(path, "w"))
    for _, r in ipairs(recs) do f:write(cjson.encode(r), "\n") end
    f:close()
    return path
end

function M.save_lua(path, recs)
    local L = { "-- auto-generated dataset by agentkit.batch", "return {" }
    for _, r in ipairs(recs) do
        L[#L + 1] = "  {"
        L[#L + 1] = ("    input = %q,"):format(tostring(r.input))
        L[#L + 1] = ("    app = %q, kind = %q,"):format(tostring(r.app), tostring(r.kind))
        L[#L + 1] = ("    ts = %q,"):format(tostring(r.ts))
        if r.error then
            L[#L + 1] = ("    error = %q,"):format(r.error)
        else
            L[#L + 1] = "    result = {"
            for _, line in ipairs(r.result or {}) do
                L[#L + 1] = ("      %q,"):format(tostring(line))
            end
            L[#L + 1] = "    },"
        end
        L[#L + 1] = "  },"
    end
    L[#L + 1] = "}"
    local f = assert(io.open(path, "w"))
    f:write(table.concat(L, "\n") .. "\n")
    f:close()
    return path
end

return M
