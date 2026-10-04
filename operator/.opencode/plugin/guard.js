// 白名单兜底插件
// opencode 的 bash 权限用的是通配匹配，* 可能把 `tools/x.sh && rm -rf` 这类
// 拼接命令一起放行。本插件在命令真正执行前再做一次严格校验：
// 只允许“单条 tools/<name>.sh [无 shell 元字符的参数]”。
export const Guard = async () => ({
  "tool.execute.before": async (input, output) => {
    const tool = input?.tool ?? input?.name
    if (tool !== "bash") return
    const cmd = String(output?.args?.command ?? "").trim()
    const ok = /^(?:\/opt\/my-agent\/operator\/)?(?:\.\/)?tools\/[a-z0-9_]+\.sh(?: [^;&|`$<>(){}]*)?$/.test(cmd)
    if (!ok) {
      throw new Error("命令被白名单拦截（只允许单条 tools/*.sh，禁止拼接与重定向）: " + cmd)
    }
  },
})
