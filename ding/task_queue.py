"""
任务队列 - 基于 Unix Domain Socket 的进程间通信

替代原有的文件轮询机制（/tmp/autobot_tasks/task.json）
优势：
- 实时通信，无轮询延迟
- 更可靠，无需文件同步
- 支持超时、重连

用法：
    # Worker (Server)
    from task_queue import TaskServer
    server = TaskServer("/tmp/autobot.sock")
    for task in server.listen():
        result = do_task(task)
        server.send_result(result)

    # Bot (Client)
    from task_queue import TaskClient
    client = TaskClient("/tmp/autobot.sock")
    result = client.dispatch_task(task_dict, timeout=60)
"""
import socket
import json
import os
import struct
import time
from typing import Optional

from logger import app_logger as logger


DEFAULT_SOCKET_PATH = "/tmp/autobot.sock"
RECV_BUFFER_SIZE = 65536


class TaskServer:
    """任务服务器 - Worker 进程使用"""
    
    def __init__(self, socket_path: str = DEFAULT_SOCKET_PATH):
        self.socket_path = socket_path
        self.server_socket: Optional[socket.socket] = None
        self.client_conn: Optional[socket.socket] = None
        self._cleanup_socket()
    
    def _cleanup_socket(self):
        """清理旧的 socket 文件"""
        try:
            if os.path.exists(self.socket_path):
                os.unlink(self.socket_path)
                logger.info(f"[TaskServer] 清理旧 socket: {self.socket_path}")
        except Exception as e:
            logger.warning(f"[TaskServer] 清理 socket 失败: {e}")
    
    def start(self) -> bool:
        """启动服务器，监听 socket"""
        try:
            self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.server_socket.bind(self.socket_path)
            self.server_socket.listen(1)
            os.chmod(self.socket_path, 0o777)  # 允许所有用户连接
            logger.info(f"[TaskServer] 启动成功，监听: {self.socket_path}")
            return True
        except Exception as e:
            logger.error(f"[TaskServer] 启动失败: {e}")
            return False
    
    def listen(self):
        """生成器：监听客户端连接，接收任务"""
        if not self.server_socket:
            if not self.start():
                return
        
        logger.info("[TaskServer] 等待主进程连接...")
        
        while True:
            try:
                # 接受连接
                self.client_conn, addr = self.server_socket.accept()
                logger.info("[TaskServer] 主进程已连接")
                
                while True:
                    # 接收任务
                    task = self._recv_json(self.client_conn)
                    if task is None:
                        logger.info("[TaskServer] 主进程断开连接")
                        break
                    
                    logger.info(f"[TaskServer] 收到任务: {task.get('id', 'unknown')}, 类型: {task.get('type')}")
                    
                    # yield 任务给外部处理
                    yield task
                    
                    # 注意：result 需要通过 send_result() 发送
                
            except Exception as e:
                logger.error(f"[TaskServer] 连接处理异常: {e}")
            finally:
                if self.client_conn:
                    try:
                        self.client_conn.close()
                    except Exception:
                        pass
                    self.client_conn = None
                
                logger.info("[TaskServer] 等待重新连接...")
                time.sleep(1)
    
    def send_result(self, result: dict) -> bool:
        """发送任务结果给主进程"""
        if not self.client_conn:
            logger.error("[TaskServer] 无客户端连接，无法发送结果")
            return False
        
        try:
            success = self._send_json(self.client_conn, result)
            if success:
                logger.info(f"[TaskServer] 结果已发送: {result.get('task_id', 'unknown')}")
            return success
        except Exception as e:
            logger.error(f"[TaskServer] 发送结果失败: {e}")
            return False
    
    def stop(self):
        """停止服务器"""
        if self.client_conn:
            try:
                self.client_conn.close()
            except Exception:
                pass
        if self.server_socket:
            try:
                self.server_socket.close()
            except Exception:
                pass
        self._cleanup_socket()
        logger.info("[TaskServer] 已停止")
    
    def _recv_json(self, conn: socket.socket) -> Optional[dict]:
        """接收 JSON 数据（带长度头）"""
        try:
            # 先接收 4 字节长度头
            length_bytes = conn.recv(4)
            if not length_bytes or len(length_bytes) < 4:
                return None
            
            length = struct.unpack('!I', length_bytes)[0]
            if length == 0 or length > RECV_BUFFER_SIZE:
                logger.warning(f"[TaskServer] 非法数据长度: {length}")
                return None
            
            # 接收数据
            data = b""
            while len(data) < length:
                chunk = conn.recv(min(length - len(data), 8192))
                if not chunk:
                    return None
                data += chunk
            
            return json.loads(data.decode('utf-8'))
        except json.JSONDecodeError as e:
            logger.error(f"[TaskServer] JSON 解析失败: {e}")
            return None
        except Exception as e:
            logger.error(f"[TaskServer] 接收数据异常: {e}")
            return None
    
    def _send_json(self, conn: socket.socket, data: dict) -> bool:
        """发送 JSON 数据（带长度头）"""
        try:
            json_bytes = json.dumps(data, ensure_ascii=False).encode('utf-8')
            length = len(json_bytes)
            
            # 发送长度头 + 数据
            conn.sendall(struct.pack('!I', length))
            conn.sendall(json_bytes)
            return True
        except Exception as e:
            logger.error(f"[TaskServer] 发送数据异常: {e}")
            return False


class TaskClient:
    """任务客户端 - 主进程使用"""
    
    def __init__(self, socket_path: str = DEFAULT_SOCKET_PATH):
        self.socket_path = socket_path
        self.socket: Optional[socket.socket] = None
    
    def _connect(self) -> bool:
        """连接到 Worker"""
        try:
            if self.socket:
                try:
                    self.socket.close()
                except Exception:
                    pass
            
            self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.socket.connect(self.socket_path)
            self.socket.settimeout(None)  # 阻塞模式
            logger.info(f"[TaskClient] 已连接到 Worker: {self.socket_path}")
            return True
        except Exception as e:
            logger.error(f"[TaskClient] 连接 Worker 失败: {e}")
            self.socket = None
            return False
    
    def dispatch_task(self, task: dict, timeout: int = 60) -> dict:
        """
        发送任务并等待结果
        
        Args:
            task: 任务字典
            timeout: 超时时间（秒）
        
        Returns:
            任务结果字典
        """
        task_id = task.get("id", "unknown")
        task_type = task.get("type", "unknown")
        
        # 确保连接
        if not self.socket:
            if not self._connect():
                return {
                    "task_id": task_id,
                    "type": task_type,
                    "success": False,
                    "error": "无法连接到 Worker",
                    "stdout": ""
                }
        
        try:
            # 设置发送和接收超时
            self.socket.settimeout(timeout + 10)  # 稍微多一点时间
            
            # 发送任务
            logger.info(f"[TaskClient] 发送任务: {task_id}, 类型: {task_type}")
            if not self._send_json(self.socket, task):
                return {
                    "task_id": task_id,
                    "type": task_type,
                    "success": False,
                    "error": "发送任务失败",
                    "stdout": ""
                }
            
            # 等待结果
            logger.info(f"[TaskClient] 等待结果: {task_id} (timeout={timeout}s)")
            result = self._recv_json(self.socket)
            
            if result is None:
                return {
                    "task_id": task_id,
                    "type": task_type,
                    "success": False,
                    "error": "接收结果失败或 Worker 断开",
                    "stdout": ""
                }
            
            logger.info(f"[TaskClient] 收到结果: {task_id}, 成功: {result.get('success')}")
            return result
            
        except socket.timeout:
            logger.error(f"[TaskClient] 任务超时: {task_id}")
            return {
                "task_id": task_id,
                "type": task_type,
                "success": False,
                "error": f"超时 ({timeout}秒)",
                "stdout": ""
            }
        except Exception as e:
            logger.error(f"[TaskClient] 任务异常: {task_id}, {e}")
            # 连接可能断开，下次重连
            try:
                self.socket.close()
            except Exception:
                pass
            self.socket = None
            
            return {
                "task_id": task_id,
                "type": task_type,
                "success": False,
                "error": f"通信异常: {str(e)}",
                "stdout": ""
            }
    
    def close(self):
        """关闭连接"""
        if self.socket:
            try:
                self.socket.close()
            except Exception:
                pass
            self.socket = None
            logger.info("[TaskClient] 已关闭连接")
    
    def _send_json(self, conn: socket.socket, data: dict) -> bool:
        """发送 JSON 数据（带长度头）"""
        try:
            json_bytes = json.dumps(data, ensure_ascii=False).encode('utf-8')
            length = len(json_bytes)
            
            conn.sendall(struct.pack('!I', length))
            conn.sendall(json_bytes)
            return True
        except Exception as e:
            logger.error(f"[TaskClient] 发送数据异常: {e}")
            return False
    
    def _recv_json(self, conn: socket.socket) -> Optional[dict]:
        """接收 JSON 数据（带长度头）"""
        try:
            # 接收 4 字节长度头
            length_bytes = conn.recv(4)
            if not length_bytes or len(length_bytes) < 4:
                return None
            
            length = struct.unpack('!I', length_bytes)[0]
            if length == 0 or length > RECV_BUFFER_SIZE:
                logger.warning(f"[TaskClient] 非法数据长度: {length}")
                return None
            
            # 接收数据
            data = b""
            while len(data) < length:
                chunk = conn.recv(min(length - len(data), 8192))
                if not chunk:
                    return None
                data += chunk
            
            return json.loads(data.decode('utf-8'))
        except json.JSONDecodeError as e:
            logger.error(f"[TaskClient] JSON 解析失败: {e}")
            return None
        except Exception as e:
            logger.error(f"[TaskClient] 接收数据异常: {e}")
            return None


if __name__ == "__main__":
    # 测试代码
    import threading
    
    def test_server():
        server = TaskServer("/tmp/test_autobot.sock")
        for task in server.listen():
            print(f"[Server] 收到任务: {task}")
            result = {"task_id": task.get("id"), "success": True, "stdout": "测试成功"}
            server.send_result(result)
    
    def test_client():
        time.sleep(1)
        client = TaskClient("/tmp/test_autobot.sock")
        result = client.dispatch_task({"id": "test-1", "type": "test", "content": {}}, timeout=5)
        print(f"[Client] 收到结果: {result}")
        client.close()
    
    t1 = threading.Thread(target=test_server, daemon=True)
    t2 = threading.Thread(target=test_client, daemon=True)
    
    t1.start()
    t2.start()
    
    t2.join(timeout=10)
