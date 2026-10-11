return {
  window = "微信",
  controls = {
    -- 左侧功能栏（图标，窗口相对中心 x≈34）
    rail_chat        = { x=12, y=104,  w=44, h=30 },  -- 聊天
    rail_contacts    = { x=12, y=163,  w=44, h=30 },  -- 通讯录
    rail_favorites   = { x=12, y=222,  w=44, h=30 },  -- 收藏
    rail_moments     = { x=12, y=281,  w=44, h=30 },  -- 朋友圈（独立窗口）
    rail_channels    = { x=12, y=340,  w=44, h=30 },  -- 视频号
    rail_search      = { x=12, y=406,  w=44, h=30 },  -- 搜一搜
    rail_miniprogram = { x=12, y=458,  w=44, h=30 },  -- 小程序
    rail_menu        = { x=12, y=1287, w=44, h=30 },  -- 底部菜单/设置

    -- 会话列表
    search_box   = { x=95,   y=26,   w=290,  h=40   },
    new_chat     = { x=443,  y=18,   w=40,   h=34   },  -- “+”新建会话
    chat_list    = { x=65,   y=60,   w=420,  h=1340 },

    -- 会话主区
    title        = { x=490,  y=0,    w=2070, h=80   },
    message_area = { x=490,  y=80,   w=2070, h=955  },

    -- 输入区工具条（图标，中心 y≈1052）
    btn_emoji    = { x=504,  y=1036, w=32,   h=32   },  -- 表情
    btn_file     = { x=572,  y=1036, w=32,   h=32   },  -- 文件
    btn_note     = { x=644,  y=1036, w=32,   h=32   },  -- 笔记
    btn_snip     = { x=714,  y=1036, w=32,   h=32   },  -- 截图
    btn_voice    = { x=779,  y=1036, w=32,   h=32   },  -- 语音

    input_box    = { x=490,  y=1075, w=2070, h=330  },
    send_btn     = { x=2415, y=1362, w=115,  h=38   },
  },
}
