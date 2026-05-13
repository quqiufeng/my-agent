"""
Test 任务 - 测试新功能

【AI 开发插件指南】

开发新插件只需 3 步：
1. 在 tasks/ 目录创建新文件，如 tasks/hello.py
2. 继承 BaseTask，实现 execute() 方法
3. 定义 task_type = "指令名"

示例：
    class HelloTask(BaseTask):
        task_type = "hello"
        
        def execute(self, content, session_webhook):
            # 获取用户输入
            user_input = content.get("user_input", "")
            # 处理业务逻辑
            result = f"你好: {user_input}"
            # 返回结果
            return TaskResult.ok(result).to_dict()

发送 #hello → 自动匹配 task_type="hello" 的任务

可用资源：
- dingtalk.get_dingtalk() - 钉钉 API (发消息、上传图片等)
- executor.execute(cmd) - 执行 Shell 命令
- executor.execute_python_subprocess(code) - 执行 Python 代码
- requests - 网络请求

【调试方法 - python -c】
调试单个模块：
    cd /mnt/e/app/my-game/scripts/autobot
    python3 -c "from tasks.test import TestTask; t = TestTask(); print(t.execute({}, None))"

调试任务加载：
    python3 -c "from tasks import load_all_tasks, list_tasks; load_all_tasks(); print(list_tasks())"

调试钉钉 API：
    python3 -c "import dingtalk; dt = dingtalk.get_dingtalk(); print(dt.get_token())"

调试执行器：
    python3 -c "from executor import Executor; e = Executor(); print(e.check_safety('ls -la'))"

【钉钉消息类型】
获取消息数据：
    data = callback.data
    msg_type = data.get("msgtype")        # 消息类型: text, picture, voice, file 等
    session_webhook = data.get("sessionWebhook")  # 会话 webhook
    robot_code = data.get("robotCode")          # 机器人 Code
    sender_id = data.get("senderId")            # 发送者 ID
    
文字消息：
    text = msg.text.content if msg.text else ""
    
图片消息：
    content = data.get("content", {})
    download_code = content.get("downloadCode")
    robot_code = data.get("robotCode")
    
消息类型列表：text, picture, voice, file, markdown, link, actionCard, feedCard
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
# from logger import task_logger as logger
# import dingtalk
# import requests


class TestTask(BaseTask):
    """测试任务 - 返回简单消息"""
    task_type = "test"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        # ============ 获取用户输入 (供参考) ============
        # 
        # # 文字消息
        # user_input = content.get("user_input", "")
        # 
        # # 图片消息
        # download_code = content.get("download_code", "")
        # robot_code = content.get("robot_code", "")
        # prompt = content.get("prompt", "描述这张图片")
        # 
        # # 如果有图片，下载图片
        # if download_code and robot_code:
        #     try:
        #         dt = dingtalk.get_dingtalk()
        #         image_url = dt.download_file(download_code, robot_code)
        #         logger.info(f"图片URL: {image_url}")
        #     except Exception as e:
        #         logger.error(f"图片下载失败: {e}")
        #
        # ============ 获取用户输入结束 ============
        
        # 测试新功能：直接返回消息
        return TaskResult.ok("这是新增的功能test").to_dict()


# ============ 发送图片消息示例 (供参考) ============
# 
# def send_image_example(session_webhook):
#     """发送图片消息示例"""
#     from logger import task_logger as logger
#     import dingtalk
#     import requests
#     import hashlib
#     import time
#     
#     # 1. 下载图片
#     image_url = "https://example.com/image.png"
#     img_resp = requests.get(image_url, timeout=60)
#     
#     if img_resp.status_code == 200:
#         # 2. 上传到钉钉
#         dt = dingtalk.get_dingtalk()
#         media_id = dt.upload_media("image", file_content=img_resp.content, filename="image.png")
#         
#         if media_id:
#             # 3. 发送 markdown 图片消息
#             dt.send_markdown_image(session_webhook, media_id)
#             logger.info(f"图片发送成功: {media_id}")
#         else:
#             logger.error("上传钉钉失败")
#     else:
#         logger.error(f"图片下载失败: {img_resp.status_code}")
#
# ============ 发送图片消息示例结束 ============
