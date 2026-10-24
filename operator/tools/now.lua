local ok = os.setlocale("", "time")
if not ok then os.setlocale("", "all") end
print(os.date("%Y-%m-%d %H:%M:%S %A"))
