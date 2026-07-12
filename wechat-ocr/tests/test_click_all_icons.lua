package.path = "/usr/local/lualib/?.lua;/usr/local/lualib/?/init.lua;./lua/?.lua;./?.lua;" .. (package.path or "")
package.cpath = "/usr/local/lualib/?.so;" .. (package.cpath or "")

local robot = require("wechat_robot")
robot.init()

local icons, err = robot.scan_icons()
if not icons then
    print("scan_icons failed: " .. tostring(err))
    os.exit(1)
end

print(string.format("Found %d icons:", #icons))
for i, icon in ipairs(icons) do
    local pos = icon.pos
    print(string.format("  %d. %s (%s)  (%d,%d)", i, icon.name_cn, icon.name, pos and pos.x or 0, pos and pos.y or 0))
end

print("\nClicking each icon in sequence with 1s pause...")
for i, icon in ipairs(icons) do
    print(string.format("  -> Clicking: %s (%s)", icon.name_cn, icon.name))
    local ok, err = robot.click_icon(icon.name_en or icon.name)
    if not ok then
        print(string.format("  !! Failed: %s", tostring(err)))
    end
    os.execute("sleep 1")
end

robot.vlm_free()
print("Done.")
