"""
Agent 任务 - 路由指令到指定 Agent 执行

用法:
    #agent 查看当前目录结构          → 发给 master
    #agent master 查看当前目录        → 发给 master（显式指定）
    #agent coder 写一个 Python 爬虫   → 发给 coder（如未启动则自动启动）
"""
import sys
import os
import subprocess
import requests
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tasks.base import BaseTask, TaskResult
from logger import task_logger as logger
import dingtalk


MASTER_PORT = 4097
AGENT_BASE_URL = "http://localhost"
SCRIPT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class AgentTask(BaseTask):
    """Agent 任务 - 智能路由指令到目标 Agent"""
    task_type = "agent"
    
    def execute(self, content: dict, session_webhook=None) -> dict:
        raw = content.get("raw", "")
        args_str = raw.replace("#agent", "").strip()
        
        if not args_str:
            return TaskResult.err(
                "请提供指令，例如:\n"
                "#agent 查看当前目录\n"
                "#agent coder 写一个爬虫"
            ).to_dict()
        
        # 解析：第一个词可能是 agent_name，也可能是指令的一部分
        agent_name, instruction = self._parse_args(args_str)
        
        logger.info(f"[AgentTask] 目标: {agent_name}, 指令: {instruction[:100]}...")
        
        # 获取 Agent 端口
        port = self._get_agent_port(agent_name)
        agent_url = f"{AGENT_BASE_URL}:{port}"
        
        # 检查 Agent 是否运行，没运行则启动
        if not self._is_agent_running(agent_name):
            logger.info(f"[AgentTask] Agent '{agent_name}' 未运行，正在启动...")
            start_result = self._start_agent(agent_name, port)
            if not start_result["success"]:
                return TaskResult.err(f"启动 Agent '{agent_name}' 失败: {start_result['error']}").to_dict()
            # 等待服务启动
            if not self._wait_for_agent(port, timeout=10):
                return TaskResult.err(f"Agent '{agent_name}' 启动后未响应").to_dict()
        
        # 发送指令
        return self._send_instruction(agent_name, agent_url, instruction, session_webhook)
    
    def _parse_args(self, args_str: str) -> tuple:
        """
        解析参数
        
        规则：
        - #agent <agent_name> <instruction> → 指定 agent
        - #agent <instruction> → 默认给 master
        """
        parts = args_str.split(maxsplit=1)
        if not parts:
            return "master", ""
        
        # 只要有第二个词，第一个词就是 agent_name
        if len(parts) > 1:
            return parts[0], parts[1]
        
        # 只有一个词，默认给 master
        return "master", args_str
    
    def _get_agent_port(self, agent_name: str) -> int:
        """根据 agent_name 计算端口"""
        if agent_name == "master":
            return MASTER_PORT
        # 其他 agent 使用固定偏移，避免冲突
        return MASTER_PORT + 1 + (hash(agent_name) % 100)
    
    def _is_agent_running(self, agent_name: str) -> bool:
        """检查 Agent 是否运行（通过 tmux session）"""
        try:
            result = subprocess.run(
                ["tmux", "has-session", "-t", agent_name],
                capture_output=True,
                timeout=2
            )
            return result.returncode == 0
        except Exception:
            return False
    
    def _start_agent(self, agent_name: str, port: int) -> dict:
        """启动 Agent（创建 tmux session）"""
        try:
            # 创建工作目录
            work_dir = os.path.expanduser(f"~/agents/{agent_name}")
            os.makedirs(work_dir, exist_ok=True)
            
            # 创建 tmux session 启动 opencode serve
            cmd = [
                "tmux", "new-session", "-d", "-s", agent_name,
                f"cd '{work_dir}' && opencode serve --port {port}"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                error = result.stderr or "未知错误"
                logger.error(f"[AgentTask] 启动 {agent_name} 失败: {error}")
                return {"success": False, "error": error}
            
            logger.info(f"[AgentTask] Agent '{agent_name}' 已启动 (port {port})")
            return {"success": True}
            
        except Exception as e:
            logger.error(f"[AgentTask] 启动异常: {e}")
            return {"success": False, "error": str(e)}
    
    def _wait_for_agent(self, port: int, timeout: int = 10) -> bool:
        """等待 Agent 服务就绪"""
        url = f"{AGENT_BASE_URL}:{port}/global/health"
        for i in range(timeout):
            try:
                resp = requests.get(url, timeout=2)
                if resp.status_code == 200:
                    logger.info(f"[AgentTask] Agent 就绪 (port {port})")
                    return True
            except Exception:
                pass
            time.sleep(1)
        return False
    
    def _send_instruction(self, agent_name: str, agent_url: str, instruction: str, session_webhook=None) -> dict:
        """发送指令到 Agent"""
        try:
            # 1. 发送提示词
            resp_append = requests.post(
                f"{agent_url}/tui/append-prompt",
                json={"text": instruction},
                timeout=10
            )
            
            if resp_append.status_code != 200:
                return TaskResult.err(f"发送指令失败: HTTP {resp_append.status_code}").to_dict()
            
            # 2. 提交执行
            resp_submit = requests.post(
                f"{agent_url}/tui/submit-prompt",
                timeout=10
            )
            
            if resp_submit.status_code != 200:
                return TaskResult.err(f"提交执行失败: HTTP {resp_submit.status_code}").to_dict()
            
            logger.info(f"[AgentTask] 指令已发送到 {agent_name}")
            
            # 3. 构建 Markdown 回复内容
            markdown_content = (
                f"### Agent 指令已发送\n\n"
                f"**目标 Agent:** `{agent_name}`\n"
                f"**服务地址:** `{agent_url}`\n"
                f"**指令内容:**\n```\n{instruction}\n```\n\n"
                f"**查看执行:** `tmux attach -t {agent_name}`"
            )
            
            exec_responses = ""
            # 如果提供了 session_webhook，直接发送 Markdown 消息
            if session_webhook:
                try:
                    dt = dingtalk.get_dingtalk()
                    dt.send_markdown(session_webhook, "Agent 指令", markdown_content)
                    exec_responses = "__MARKDOWN_SENT__"
                    logger.info("[AgentTask] Markdown 消息已发送到钉钉")
                except Exception as e:
                    logger.error(f"[AgentTask] 发送 Markdown 消息失败: {e}")
            
            return TaskResult(
                success=True,
                stdout=markdown_content,
                exec_responses=exec_responses
            ).to_dict()
            
        except requests.exceptions.ConnectionError:
            return TaskResult.err(
                f"Agent '{agent_name}' 连接失败\n"
                f"可能正在启动中，请稍后再试"
            ).to_dict()
        except Exception as e:
            logger.error(f"[AgentTask] 发送异常: {e}")
            return TaskResult.err(f"发送异常: {str(e)}").to_dict()
