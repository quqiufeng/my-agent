#!/usr/bin/env python3
"""
Planner模块 - 任务分解和进度管理
让大模型和本地都知道当前做到哪一步了
"""

import json
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
from dataclasses import dataclass, asdict


@dataclass
class Step:
    """步骤数据类"""
    id: int
    action: str        # file/shell/code/dir/log
    target: str       # 文件路径/命令/目录
    content: str = ""  # 文件内容/代码
    status: str = "pending"  # pending/completed/failed
    result: str = ""   # 执行结果
    timestamp: str = ""


class Planner:
    """任务规划器"""

    def __init__(self, project_root: str = "."):
        self.project_root = Path(project_root)
        self.state_file = self.project_root / ".opencode_state.json"

        # 任务状态
        self.current_task: str = ""
        self.steps: List[Step] = []
        self.current_step_index: int = 0
        self.completed_steps: List[str] = []

        # 加载已有状态
        self.load_state()

    def start_new_task(self, task_name: str):
        """
        开始新任务

        Args:
            task_name: 任务名称
        """
        self.current_task = task_name
        self.steps = []
        self.current_step_index = 0
        self.completed_steps = []
        self.save_state()

    def add_step(self, action: str, target: str, content: str = ""):
        """
        添加步骤

        Args:
            action: 操作类型 (file/shell/code/dir/log)
            target: 目标 (文件路径/命令/目录)
            content: 内容（可选）
        """
        step = Step(
            id=len(self.steps) + 1,
            action=action,
            target=target,
            content=content,
            status="pending"
        )
        self.steps.append(step)
        self.save_state()

    def mark_completed(self, step_id: int, result: str = ""):
        """
        标记步骤完成

        Args:
            step_id: 步骤ID
            result: 执行结果
        """
        for step in self.steps:
            if step.id == step_id:
                step.status = "completed"
                step.result = result
                step.timestamp = datetime.now().isoformat()

                # 记录已完成操作
                action_str = f"#{step.action} {step.target}"
                if step.content:
                    action_str += f" ({len(step.content)} chars)"
                self.completed_steps.append(action_str)

        self.save_state()

    def mark_failed(self, step_id: int, error: str):
        """
        标记步骤失败

        Args:
            step_id: 步骤ID
            error: 错误信息
        """
        for step in self.steps:
            if step.id == step_id:
                step.status = "failed"
                step.result = error
                step.timestamp = datetime.now().isoformat()

        self.save_state()

    def get_current_step(self) -> Optional[Step]:
        """
        获取当前待执行的步骤

        Returns:
            当前步骤
        """
        for step in self.steps:
            if step.status == "pending":
                return step
        return None

    def get_progress_info(self) -> str:
        """
        获取进度信息（发送给大模型）

        Returns:
            格式化的进度字符串
        """
        if not self.current_task:
            return "=== 进度 ===\n新任务，尚未开始"

        lines = [f"=== 当前任务: {self.current_task} ==="]

        # 计算进度
        total = len(self.steps)
        completed = len([s for s in self.steps if s.status == "completed"])
        lines.append(f"进度: {completed}/{total}")

        # 已完成步骤
        if self.completed_steps:
            lines.append("\n已完成操作:")
            for i, step_str in enumerate(self.completed_steps, 1):
                lines.append(f"  ✓ {step_str}")

        # 待完成步骤
        pending_steps = [s for s in self.steps if s.status == "pending"]
        if pending_steps:
            lines.append("\n待完成操作:")
            for step in pending_steps[:10]:  # 限制显示数量
                lines.append(f"  ○ #{step.action} {step.target}")

        # 当前步骤
        current = self.get_current_step()
        if current:
            lines.append(f"\n当前步骤: #{current.action} {current.target}")

        return "\n".join(lines)

    def get_steps_summary(self) -> Dict:
        """
        获取步骤摘要

        Returns:
            步骤统计字典
        """
        return {
            'task': self.current_task,
            'total': len(self.steps),
            'completed': len([s for s in self.steps if s.status == "completed"]),
            'pending': len([s for s in self.steps if s.status == "pending"]),
            'failed': len([s for s in self.steps if s.status == "failed"]),
            'current_step': self.get_current_step().__dict__ if self.get_current_step() else None
        }

    def save_state(self):
        """保存状态到文件"""
        state = {
            'current_task': self.current_task,
            'current_step_index': self.current_step_index,
            'completed_steps': self.completed_steps,
            'steps': [asdict(s) for s in self.steps]
        }

        self.state_file.write_text(
            json.dumps(state, indent=2, ensure_ascii=False),
            encoding='utf-8'
        )

    def load_state(self):
        """从文件加载状态"""
        if not self.state_file.exists():
            return

        try:
            state = json.loads(self.state_file.read_text(encoding='utf-8'))
            self.current_task = state.get('current_task', '')
            self.current_step_index = state.get('current_step_index', 0)
            self.completed_steps = state.get('completed_steps', [])

            self.steps = []
            for s in state.get('steps', []):
                step = Step(**s)
                self.steps.append(step)

        except Exception as e:
            print(f"加载状态失败: {e}")

    def reset(self):
        """重置任务状态"""
        self.current_task = ""
        self.steps = []
        self.current_step_index = 0
        self.completed_steps = []

        if self.state_file.exists():
            self.state_file.unlink()


def create_progress_message(completed: List[str], pending: List[Dict], task_name: str = "") -> str:
    """
    便捷函数：创建进度消息

    Args:
        completed: 已完成操作列表
        pending: 待操作列表
        task_name: 任务名称

    Returns:
        格式化的消息
    """
    lines = []

    if task_name:
        lines.append(f"=== 任务: {task_name} ===")

    if completed:
        lines.append("\n已完成:")
        for item in completed:
            lines.append(f"  ✓ {item}")

    if pending:
        lines.append("\n待完成:")
        for item in pending:
            action = item.get('action', 'unknown')
            target = item.get('target', '')
            lines.append(f"  ○ #{action} {target}")

    return "\n".join(lines)


if __name__ == '__main__':
    # 测试
    print("=== Planner 测试 ===")

    planner = Planner(".")
    planner.start_new_task("创建Web服务器")
    planner.add_step("dir", "src")
    planner.add_step("file", "src/server.py", "def main(): pass")
    planner.add_step("shell", "pip install flask")

    print(planner.get_progress_info())
    print("\n=== 步骤摘要 ===")
    print(planner.get_steps_summary())
