-- agentkit/adapters/google.lua — Google 搜索（走 CDP/DOM 精准取结果，非 OCR）
--   local g = ak.app("google")
--   g.search("DeepSeek")
--   for _, r in ipairs(g.results(10)) do print(r.title, r.url) end
--   print(g.text())        -- 可选：整页可见文本
-- 依赖：固定端口 Chrome（tools/chrome_debug.sh）+ agentkit.cdp
local cjson = require("cjson")
local cdp = require("agentkit.cdp")
local M = {}

local function enc(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- 搜索：直接导航到结果页
function M.search(q, opts)
    cdp.goto("https://www.google.com/search?q=" .. enc(q))
    return true
end

-- 结构化结果（首页全部）：[{title, url, url_real, cite, snippet}, ...]
function M.results(limit)
    local js = [[(()=>{
      const res=[...document.querySelectorAll('#search a h3, #rso a h3, #center_col a h3')];
      const seen=new Set(), out=[];
      for(const h of res){
        const t=(h.innerText||'').trim(); if(!t) continue;
        const a=h.closest('a'); let url=a?a.href:'';
        const key=t+'|'+url; if(seen.has(key)) continue; seen.add(key);
        // 解一层 Google 跳转壳 -> 真实地址（若可解）
        let real=''; const m=url.match(/[?&](?:url|q)=([^&]+)/); if(m){ try{ real=decodeURIComponent(m[1]); }catch(e){} }
        if(real && !/^https?:/.test(real)) real='';
        let c=h.closest('div.g')||h.closest('div[data-hveid]')||(a&&a.closest('div[data-hveid]'));
        let cite='', snip='';
        if(c){ const ce=c.querySelector('cite'); if(ce) cite=ce.innerText.trim();
               const se=c.querySelector('.VwiC3b, div[data-sncf], .IsZvec, span.aCOpRe, .lEBKkf'); if(se) snip=se.innerText.trim(); }
        out.push({title:t, url:url, url_real:(real||''), cite:cite, snippet:snip});
      }
      return JSON.stringify(out);
    })()]]
    local out = cdp.eval(js)
    local ok, res = pcall(cjson.decode, out or "")
    return (ok and type(res) == "table") and res or {}
end

-- 供批量/大脑：一行行文本（标题 | 来源 | 摘要）
function M.read_results(limit)
    local lines = {}
    for _, r in ipairs(M.results(limit)) do
        local src = (r.cite ~= "" and r.cite) or (r.url_real ~= "" and r.url_real) or r.url
        lines[#lines + 1] = string.format("%s\n    %s\n    %s", r.title, src, r.snippet)
    end
    return lines
end
M.read = M.read_results

-- 当前页标题 / 可见文本
function M.title() return cdp.title() end
function M.text() return cdp.eval("document.body.innerText") end
function M.url() return cdp.url() end

return M
