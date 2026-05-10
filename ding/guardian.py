#!/usr/bin/env python3
"""
AutoBot 守护进程
功能：
1. 监控 autobot_dingtalk.py 和 task_worker.py 两个进程
2. 进程挂了自动重启
3. 最多连续重启 10 次，超过则停止
4. 每 30 秒检查 GitHub 最新提交
5. 检测到关键字 "ok" 则重启进程
"""
import os
import sys
import time
import json
import signal
import subprocess
import requests
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from logger import guardian_logger as logger
from config import Config


# ============ 配置 ============
AUTOBOT_DIR = SCRIPT_DIR
PROCESSES = [
    {"name": "task_worker.py", "script": "task_worker.py"},
    {"name": "autobot_dingtalk.py", "script": "autobot_dingtalk.py"},
]
LOG_FILE = os.path.join(AUTOBOT_DIR, "guardian.log")
CHECK_INTERVAL = 10          # 检查进程存活间隔（秒）
GITHUB_CHECK_INTERVAL = 30  # 检查 GitHub 间隔（秒）
MAX_RESTART_COUNT = 10       # 最大连续重启次数
RESTART_COOLDOWN = 30        # 重启冷却时间（秒）


class Guardian:
    """守护进程主类"""
    
    def __init__(self):
        self.running = True
        self.restart_count = 0
        self.last_restart_time = 0
        self.last_commit_sha = ""
        
        self.status = {
            "processes": {},
            "restart_count": 0,
            "last_restart_time": None,
            "last_error": None,
            "github_last_check": None,
            "uptime_start": time.time()
        }
        
        self._init_log()
        self._log("=" * 50)
        self._log("守护进程启动")
        self._log(f"检查间隔: {CHECK_INTERVAL}秒")
        self._log(f"GitHub 检查间隔: {GITHUB_CHECK_INTERVAL}秒")
        self._log(f"最大重启次数: {MAX_RESTART_COUNT}")
    
    def _init_log(self):
        """初始化日志"""
        self.log_file = open(LOG_FILE, 'a', encoding='utf-8')
    
    def _log(self, msg):
        """写日志"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        log_msg = f"[{timestamp}] {msg}"
        logger.info(log_msg)
        self.log_file.write(log_msg + "\n")
        self.log_file.flush()
    
    def _get_process_pid(self, process_name):
        """获取进程 PID"""
        try:
            result = subprocess.run(
                ["pgrep", "-f", process_name],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                pids = result.stdout.strip().split('\n')
                my_pid = os.getpid()
                for pid in pids:
                    if pid != str(my_pid):
                        return int(pid)
        except Exception as e:
            self._log(f"获取 {process_name} PID 失败: {e}")
        return None
    
    def _is_process_running(self, process_name):
        """检查进程是否在运行"""
        pid = self._get_process_pid(process_name)
        if pid:
            try:
                os.kill(pid, 0)
                return pid
            except OSError:
                return None
        return None
    
    def _start_process(self, script_name):
        """启动进程"""
        try:
            cmd = f"cd {AUTOBOT_DIR} && nohup python3 {script_name} >> {AUTOBOT_DIR}/{script_name.replace('.py', '.log')} 2>&1 &"
            subprocess.run(cmd, shell=True, timeout=10)
            time.sleep(3)
            
            pid = self._is_process_running(script_name)
            if pid:
                self._log(f"{script_name} 启动成功，PID: {pid}")
                return True
            else:
                self._log(f"{script_name} 启动失败")
                return False
        except Exception as e:
            self._log(f"启动 {script_name} 异常: {e}")
            return False
    
    def _stop_process(self, process_name):
        """停止进程"""
        pid = self._get_process_pid(process_name)
        if pid:
            try:
                self._log(f"停止 {process_name}，PID: {pid}")
                os.kill(pid, signal.SIGTERM)
                time.sleep(2)
                try:
                    os.kill(pid, signal.SIGKILL)
                except Exception:
                    pass
                return True
            except Exception as e:
                self._log(f"停止 {process_name} 失败: {e}")
                return False
        return True
    
    def _stop_all_processes(self):
        """停止所有进程"""
        for proc in PROCESSES:
            self._stop_process(proc["script"])
    
    def _start_all_processes(self):
        """启动所有进程"""
        # 先启动 task_worker，再启动 autobot_dingtalk
        for proc in PROCESSES:
            self._start_process(proc["script"])
    
    def _restart_all(self):
        """重启所有进程"""
        now = time.time()
        
        # 检查冷却期
        if now - self.last_restart_time < RESTART_COOLDOWN:
            remaining = int(RESTART_COOLDOWN - (now - self.last_restart_time))
            self._log(f"冷却期内，跳过重启 (剩余 {remaining}秒)")
            return False
        
        # 检查重启次数
        if self.restart_count >= MAX_RESTART_COUNT:
            self._log(f"已达到最大重启次数 {MAX_RESTART_COUNT}，停止自动重启")
            self.status["last_error"] = "max_restart_reached"
            return False
        
        self._log("执行重启...")
        self._stop_all_processes()
        time.sleep(2)
        
        self.restart_count += 1
        self.last_restart_time = now
        self.status["restart_count"] = self.restart_count
        self.status["last_restart_time"] = datetime.fromtimestamp(now).isoformat()
        
        self._start_all_processes()
        
        # 检查是否都启动成功
        all_running = True
        for proc in PROCESSES:
            if not self._is_process_running(proc["script"]):
                all_running = False
        
        if all_running:
            self._log(f"重启成功，重启次数: {self.restart_count}")
            return True
        else:
            self._log("重启部分失败")
            return False
    
    def _check_github(self):
        """检查 GitHub 最新提交"""
        try:
            # 获取 GitHub repo
            repo = Config.GITHUB_REPO
            if not repo:
                return
            
            url = f"https://api.github.com/repos/{repo}/commits"
            resp = requests.get(url, params={"per_page": 1}, timeout=10)
            
            if resp.status_code == 200:
                commits = resp.json()
                if commits:
                    latest = commits[0]
                    sha = latest.get("sha", "")
                    message = latest.get("commit", {}).get("message", "")
                    
                    self.status["github_last_check"] = datetime.now().isoformat()
                    
                    # 检查是否是新车提交
                    if sha and sha != self.last_commit_sha:
                        self._log(f"检测到新提交: {sha[:7]} - {message[:50]}")
                        
                        # 检查关键字 "ok"
                        if "ok" in message.lower():
                            self._log("检测到关键字 'ok'，准备重启...")
                            self.restart_count = 0  # 重置计数
                            self._restart_all()
                        
                        self.last_commit_sha = sha
                        
        except Exception as e:
            self._log(f"检查 GitHub 失败: {e}")
    
    def _check_processes(self):
        """检查所有进程状态"""
        all_running = True
        
        for proc in PROCESSES:
            pid = self._is_process_running(proc["script"])
            self.status["processes"][proc["name"]] = {
                "running": pid is not None,
                "pid": pid
            }
            
            if not pid:
                self._log(f"检测到 {proc['script']} 未运行")
                all_running = False
        
        return all_running
    
    def run(self):
        """主循环"""
        self._log("进入主循环")
        
        last_github_check = 0
        was_all_running = False
        
        while self.running:
            try:
                # 检查进程
                all_running = self._check_processes()
                
                if not all_running:
                    if was_all_running:
                        # 之前在运行，现在挂了 → 重启
                        self._log("检测到进程崩溃，准备重启...")
                        self._restart_all()
                    else:
                        # 之前也没运行 → 启动
                        self._log("进程未运行，尝试启动...")
                        self._start_all_processes()
                else:
                    was_all_running = True
                    # 运行超过 5 分钟后重置计数
                    if self.restart_count > 0 and time.time() - self.last_restart_time > 300:
                        self.restart_count = 0
                        self._log("重置重启计数")
                
                # 检查 GitHub
                now = time.time()
                if now - last_github_check >= GITHUB_CHECK_INTERVAL:
                    self._check_github()
                    last_github_check = now
                
                time.sleep(CHECK_INTERVAL)
                
            except KeyboardInterrupt:
                self._log("收到中断信号，退出")
                self.running = False
            except Exception as e:
                self._log(f"主循环异常: {e}")
                time.sleep(CHECK_INTERVAL)
        
        self.log_file.close()


def main():
    guardian = Guardian()
    
    def signal_handler(sig, frame):
        logger.info("收到退出信号...")
        guardian.running = False
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    guardian.run()


if __name__ == "__main__":
    main()
