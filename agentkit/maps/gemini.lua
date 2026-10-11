return {
  window = "Google Chrome",
  controls = {
    -- 左侧栏
    sidebar_new_chat  = { x=40,  y=228,  w=170, h=28 },   -- 发起新对话
    sidebar_search    = { x=40,  y=268,  w=190, h=26 },   -- 搜索对话内容
    sidebar_students  = { x=45,  y=300,  w=60,  h=24 },   -- 学生
    sidebar_library   = { x=45,  y=336,  w=44,  h=24 },   -- 库
    sidebar_gems      = { x=45,  y=373,  w=64,  h=24 },   -- Gem
    sidebar_notebooks = { x=40,  y=455,  w=150, h=26 },   -- 新建笔记本

    -- 输入条：空/新对话时居中；进入对话后移到底部
    input_box         = { x=1080, y=755,  w=735, h=50 },   -- 居中
    input_box_bottom  = { x=1080, y=1255, w=735, h=50 },   -- 底部
    model_selector    = { x=1595, y=758,  w=175, h=40 },   -- Gemini 自动
    mic               = { x=1755, y=757,  w=44,  h=44 },   -- 麦克风
    send_btn          = { x=1756, y=757,  w=46,  h=46 },   -- 发送（输入非空时出现）

    -- 主区
    convo_area        = { x=990,  y=230,  w=1440, h=720 },  -- 对话内容（问答）
    heading           = { x=1000, y=640,  w=900,  h=90 },   -- “有什么新灵感…”
  },
}
