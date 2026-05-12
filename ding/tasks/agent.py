"""
Agent 任务 - 调用 Master Agent 或其他 Agent 执行指令

用法:
    #agent master 查看当前目录结构
    #agent coder 写一个 Python 爬虫

参数:
    - agent_name: Agent 名称（必填）
    - instruction: 指令内容（必填）
"""
import sys
import os
import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger


# Master Agent 默认端口
MASTER_PORT = 4097
AGENT_BASE_URL = "http://localhost"


class AgentTask(BaseTask):
    """Agent 任务 - 通过 HTTP API 发送指令给指定 Agent"""
    task_type = "agent"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        # 去掉 #agent 前缀
        args_str = raw.replace("#agent", "").strip()
        
        if not args_str:
            return TaskResult.err("请提供 Agent 名称和指令，例如: #agent master 查看当前目录").to_dict()
        
        # 解析 agent_name 和 instruction
        parts = args_str.split(maxsplit=1)
        agent_name = parts[0]
        instruction = parts[1] if len(parts) > 1 else ""
        
        if not instruction:
            # 如果没有指令，可以查询 Agent 状态
            if agent_name == "master":
                return self._check_master_status()
            return TaskResult.err(f"未提供指令，用法: #agent {agent_name} <指令>").to_dict()
        
        logger.info(f"[AgentTask] 发送指令到 {agent_name}: {instruction[:100]}...")
        
        # 构建 Agent URL
        if agent_name == "master":
            port = MASTER_PORT
        else:
            # 其他 Agent 的端口需要从注册表获取，这里暂时用默认规则
            # 后续可以从 registry.json 读取
            port = MASTER_PORT + hash(agent_name) % 1000
        
        agent_url = f"{AGENT_BASE_URL}:{port}"
        
        try:
            # 1. 发送提示词
            resp_append = requests.post(
                f"{agent_url}/tui/append-prompt",
                json={"text": instruction},
                timeout=10
            )
            
            if resp_append.status_code != 200:
                return TaskResult.err(f"Agent 连接失败 (append): HTTP {resp_append.status_code}").to_dict()
            
            # 2. 提交执行
            resp_submit = requests.post(
                f"{agent_url}/tui/submit-prompt",
                timeout=10
            )
            
            if resp_submit.status_code != 200:
                return TaskResult.err(f"Agent 连接失败 (submit): HTTP {resp_submit.status_code}").to_dict()
            
            logger.info(f"[AgentTask] 指令已发送到 {agent_name}")
            
            return TaskResult.ok(
                f"指令已发送给 {agent_name}，请在 tmux 窗口查看执行结果\n"
                f"查看命令: tmux attach -t {agent_name}"
            ).to_dict()
            
        except requests.exceptions.ConnectionError:
            logger.error(f"[AgentTask] 无法连接到 {agent_name} ({agent_url})")
            return TaskResult.err(
                f"Agent '{agent_name}' 未启动或未响应\n"
                f"请先启动: ./start.sh start"
            ).to_dict()
        except Exception as e:
            logger.error(f"[AgentTask] 异常: {e}")
            return TaskResult.err(f"Agent 调用异常: {str(e)}").to_dict()
    
    def _check_master_status(self) -> dict:
        """检查 Master Agent 状态"""
        try:
            resp = requests.get(f"{AGENT_BASE_URL}:{MASTER_PORT}/global/health", timeout=5)
            if resp.status_code == 200:
                return TaskResult.ok("Master Agent 运行中").to_dict()
            return TaskResult.err(f"Master Agent 异常: HTTP {resp.status_code}").to_dict()
        except Exception as e:
            return TaskResult.err(f"Master Agent 未启动: {e}").to_dict()
