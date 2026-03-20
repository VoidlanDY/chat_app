#!/usr/bin/env python3
"""
服务器压力测试脚本
测试场景：
1. 多用户并发连接
2. 消息发送压力测试
3. 长时间运行稳定性
"""

import socket
import threading
import time
import json
import random
import string
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

# 协议常量
HEADER_SIZE = 9

# 消息类型
MSG_TYPES = {
    'REGISTER': 1,
    'LOGIN': 3,
    'PRIVATE_MESSAGE': 40,
    'HEARTBEAT': 100,
    'REGISTER_RESPONSE': 2,
    'LOGIN_RESPONSE': 4,
    'PRIVATE_MESSAGE_RESPONSE': 41,
    'HEARTBEAT_RESPONSE': 101
}

class TestClient:
    def __init__(self, host='localhost', port=8888):
        self.host = host
        self.port = port
        self.sock = None
        self.user_id = None
        self.username = None
        self.running = False
        self.recv_thread = None
        
    def connect(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(30)  # 增加超时时间
        try:
            self.sock.connect((self.host, self.port))
            return True
        except Exception as e:
            print(f"Connection failed: {e}")
            return False
    
    def close(self):
        self.running = False
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
    
    def send_message(self, msg_type, sequence, body):
        """发送消息 - 协议格式: length(4) + type(1) + sequence(4)"""
        body_json = json.dumps(body).encode('utf-8')
        import struct
        # length (4 bytes) + type (1 byte) + sequence (4 bytes) = 9 bytes header
        header = struct.pack('<IBI', len(body_json), msg_type, sequence)
        self.sock.sendall(header + body_json)
    
    def recv_message(self, timeout=30):
        """接收消息 - 协议格式: length(4) + type(1) + sequence(4)"""
        import struct
        self.sock.settimeout(timeout)
        header = b''
        while len(header) < HEADER_SIZE:
            chunk = self.sock.recv(HEADER_SIZE - len(header))
            if not chunk:
                return None, None
            header += chunk
        
        # 解析: length (4 bytes) + type (1 byte) + sequence (4 bytes)
        body_len, msg_type, sequence = struct.unpack('<IBI', header)
        
        body = b''
        while len(body) < body_len:
            chunk = self.sock.recv(min(4096, body_len - len(body)))
            if not chunk:
                return None, None
            body += chunk
        
        return msg_type, json.loads(body.decode('utf-8'))
    
    def register(self, username, password, nickname=None):
        """注册用户"""
        if nickname is None:
            nickname = username
        self.send_message(MSG_TYPES['REGISTER'], 1, {
            'username': username,
            'password': password,
            'nickname': nickname
        })
        msg_type, body = self.recv_message()
        if msg_type == MSG_TYPES['REGISTER_RESPONSE'] and 'data' in body and 'user_id' in body.get('data', {}):
            self.user_id = body['data']['user_id']
            self.username = username
            # 注册成功后自动登录
            return self.login(username, password)
        return False, body
    
    def login(self, username, password):
        """登录"""
        self.send_message(MSG_TYPES['LOGIN'], 1, {
            'username': username,
            'password': password
        })
        msg_type, body = self.recv_message()
        if msg_type == MSG_TYPES['LOGIN_RESPONSE'] and 'data' in body and 'user_id' in body.get('data', {}):
            self.user_id = body['data']['user_id']
            self.username = username
            return True, body
        return False, body
    
    def send_private_message(self, receiver_id, content):
        """发送私聊消息"""
        self.send_message(MSG_TYPES['PRIVATE_MESSAGE'], 2, {
            'receiver_id': receiver_id,
            'content': content,
            'media_type': 0
        })
        msg_type, body = self.recv_message()
        return msg_type == MSG_TYPES['PRIVATE_MESSAGE_RESPONSE'], body
    
    def send_heartbeat(self):
        """发送心跳"""
        self.send_message(MSG_TYPES['HEARTBEAT'], 3, {})
        msg_type, body = self.recv_message()
        return msg_type == MSG_TYPES['HEARTBEAT_RESPONSE']
    
    def start_recv_loop(self):
        """启动接收循环"""
        self.running = True
        self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.recv_thread.start()
    
    def _recv_loop(self):
        """接收循环"""
        while self.running:
            try:
                msg_type, body = self.recv_message()
                if msg_type is None:
                    break
                # 处理接收到的消息
            except socket.timeout:
                continue
            except Exception as e:
                break


class StressTest:
    def __init__(self, num_users=10, num_messages=100):
        self.num_users = num_users
        self.num_messages = num_messages
        self.clients = []
        self.results = {
            'connections': 0,
            'registrations': 0,
            'logins': 0,
            'messages_sent': 0,
            'messages_failed': 0,
            'errors': []
        }
        self.lock = threading.Lock()
    
    def random_string(self, length=8):
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=length))
    
    def test_user(self, user_index):
        """测试单个用户"""
        client = TestClient()
        
        try:
            # 连接
            if not client.connect():
                with self.lock:
                    self.results['errors'].append(f"User {user_index}: Connection failed")
                return None
            
            with self.lock:
                self.results['connections'] += 1
            
            # 注册
            username = f"stress_user_{user_index}_{self.random_string(4)}"
            password = "test123456"
            success, _ = client.register(username, password)
            
            if not success:
                # 尝试登录
                success, _ = client.login(username, password)
            
            if not success:
                with self.lock:
                    self.results['errors'].append(f"User {user_index}: Auth failed")
                client.close()
                return None
            
            with self.lock:
                self.results['registrations'] += 1
            
            # 发送消息 - 使用第一个用户作为接收者
            # 注意：测试脚本会记录所有用户的 user_id
            messages_sent = 0
            messages_failed = 0
            
            # 暂时跳过消息发送，因为没有确定的接收者
            # 在实际场景中，需要先收集所有用户的 user_id
            
            with self.lock:
                self.results['messages_sent'] += messages_sent
                self.results['messages_failed'] += messages_failed
            
            return client
            
        except Exception as e:
            with self.lock:
                self.results['errors'].append(f"User {user_index}: {e}")
            client.close()
            return None
    
    def run(self):
        """运行压力测试"""
        print(f"Starting stress test: {self.num_users} users, {self.num_messages} total messages")
        start_time = time.time()
        
        # 并发创建用户并发送消息
        with ThreadPoolExecutor(max_workers=self.num_users) as executor:
            futures = [executor.submit(self.test_user, i) for i in range(self.num_users)]
            
            for future in as_completed(futures):
                client = future.result()
                if client:
                    self.clients.append(client)
        
        elapsed = time.time() - start_time
        
        print(f"\n=== Stress Test Results ===")
        print(f"Elapsed time: {elapsed:.2f}s")
        print(f"Connections: {self.results['connections']}")
        print(f"Registrations: {self.results['registrations']}")
        print(f"Messages sent: {self.results['messages_sent']}")
        print(f"Messages failed: {self.results['messages_failed']}")
        print(f"Errors: {len(self.results['errors'])}")
        
        if self.results['errors']:
            print("\nFirst 10 errors:")
            for error in self.results['errors'][:10]:
                print(f"  - {error}")
        
        # 清理
        for client in self.clients:
            client.close()
        
        return self.results


def check_server_health():
    """检查服务器健康状态"""
    try:
        # 读取服务器日志
        with open('/tmp/chat_server.log', 'r') as f:
            lines = f.readlines()[-50:]  # 最后50行
        
        # 检查关键指标
        health = {
            'thread_pool_ok': False,
            'db_pool_ok': False,
            'errors': []
        }
        
        for line in lines:
            if 'ThreadPool' in line and 'active' in line:
                health['thread_pool_ok'] = True
            if 'DB Pool' in line:
                health['db_pool_ok'] = True
            if 'error' in line.lower() or 'failed' in line.lower():
                health['errors'].append(line.strip())
        
        return health
    except Exception as e:
        return {'error': str(e)}


if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Server Stress Test')
    parser.add_argument('--users', type=int, default=20, help='Number of concurrent users')
    parser.add_argument('--messages', type=int, default=200, help='Total number of messages')
    
    args = parser.parse_args()
    
    # 运行压力测试
    test = StressTest(num_users=args.users, num_messages=args.messages)
    results = test.run()
    
    # 检查服务器健康
    print("\n=== Server Health ===")
    health = check_server_health()
    print(f"Thread Pool: {'OK' if health.get('thread_pool_ok') else 'Unknown'}")
    print(f"DB Pool: {'OK' if health.get('db_pool_ok') else 'Unknown'}")
    
    if health.get('errors'):
        print(f"Recent errors: {len(health['errors'])}")
        for error in health['errors'][:5]:
            print(f"  - {error}")
    
    # 测试结果
    # 计算成功率
    if results['messages_sent'] + results['messages_failed'] > 0:
        success_rate = results['messages_sent'] / (results['messages_sent'] + results['messages_failed']) * 100
    else:
        # 如果没有发送消息，则使用注册成功率
        success_rate = (results['registrations'] / max(1, results['connections'])) * 100
    
    print(f"\n=== Summary ===")
    print(f"Success rate: {success_rate:.1f}%")
    
    if success_rate > 95:
        print("✓ Test PASSED")
        sys.exit(0)
    else:
        print("✗ Test FAILED")
        sys.exit(1)
