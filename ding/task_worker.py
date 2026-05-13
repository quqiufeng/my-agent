"""AutoBot Task Worker - 基于 Socket 通信

替代原有的文件轮询机制，使用 Unix Domain Socket 实时通信
用法:
    python task_worker.py
"""
import os
import sys
import json
import time
import re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from config import Config
from logger import task_logger as logger
from tasks import load_all_tasks, get_task, list_tasks
import dingtalk
from task_queue import TaskServer


# 懒加载标记
_initialized = False


def _ensure_initialized():
    """确保已初始化"""
    global _initialized
    if not _initialized:
        load_all_tasks()
        logger.info(f"已加载任务: {list_tasks()}")
        _initialized = True


def do_task(task):
    """执行任务 - 委托给任务注册表"""
    # 确保已初始化
    _ensure_initialized()
    
    task_type = task.get("type")
    content = task.get("content", {})
    session_webhook = task.get("session_webhook")
    task_id = task.get("id", "unknown")
    
    result = {"task_id": task_id, "type": task_type, "success": False, "stdout": "", "stderr": "", "error": ""}
    
    try:
        # 从注册表获取任务处理器
        task_handler = get_task(task_type)
        
        if task_handler is None:
            result["error"] = f"未知任务类型: {task_type}"
            logger.error(f"未知任务类型: {task_type}")
            return result
        
        # 执行任务
        task_result = task_handler.execute(content, session_webhook)
        
        # 合并结果
        result.update(task_result)
        
        # 注意：图片发送已在 ai_analyze.py 中处理，这里不再重复发送
        result.update(task_result)
        
        # 处理图片生成结果
        if task_type == "ai_analyze":
            exec_responses = task_result.get("exec_responses", "")
            if exec_responses:
                # 提取 media_id 并发送 markdown 消息
                media_id_match = re.search(r'__MEDIA_ID__: (\S+)', exec_responses)
                if media_id_match and session_webhook:
                    media_id = media_id_match.group(1)
                    dt = dingtalk.get_dingtalk()
                    dt.send_markdown_image(session_webhook, media_id)
        
    except Exception as e:
        result["error"] = f"{type(e).__name__}: {str(e)}"
        logger.error(f"任务执行失败: {e}")
    
    return result


def run_worker():
    """Worker 主循环 - 基于 Socket"""
    _ensure_initialized()
    
    server = TaskServer()
    logger.info(f"Task Worker 启动，支持的任务: {list_tasks()}")
    
    try:
        for task in server.listen():
            task_id = task.get("id", "unknown")
            logger.info(f"收到任务: {task_id}, 类型: {task.get('type')}")
            
            # 执行任务
            result = do_task(task)
            
            # 发送结果
            server.send_result(result)
            
            logger.info(f"任务完成: {task_id}, 成功: {result.get('success')}")
            
    except KeyboardInterrupt:
        logger.info("Worker 收到退出信号")
    finally:
        server.stop()
        logger.info("Task Worker 已停止")


if __name__ == "__main__":
    run_worker()
