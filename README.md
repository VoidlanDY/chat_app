# Chat App

跨平台聊天应用 - C++ 服务器端 (asio) + Flutter 客户端 (Android支持)

## 功能特性

- 用户注册与登录
- 私聊消息 (实时送达、历史记录)
- 好友系统 (搜索、添加、接受、拒绝、删除、备注)
- 群组功能 (创建群组、邀请成员)
- 群聊消息 (开发中)
- 多媒体消息 (计划中)

## 技术栈

- **服务器**: C++17, asio (异步网络), MySQL 8.0, OpenSSL
- **客户端**: Flutter 3.0+, Dart, Provider (状态管理)
- **平台**: Android (API 21+)

## 项目结构

```
chat_app/
├── server/              # C++ 服务器
│   ├── src/            # 源代码
│   ├── include/        # 头文件
│   └── build/          # 编译输出
├── client/             # Flutter 客户端
│   └── chat_app/       # Flutter 项目
└── docs/               # 文档
```

## 快速开始

### 服务器启动

```bash
# 1. 启动 MySQL
service mysql start

# 2. 构建服务器 (首次)
cd server/build
cmake ..
make

# 3. 启动服务器
./chat_server
```

服务器默认运行在 `0.0.0.0:8888`

### 客户端运行

```bash
cd client/chat_app
flutter pub get
flutter run
```

## 功能测试方法

### 使用 Python 测试脚本

项目提供了多个 Python 测试脚本，可以快速验证功能：

```bash
# 私聊功能测试
python3 /root/test_private_message.py

# 好友功能测试
python3 /root/test_friend_feature.py

# 群组功能测试
python3 /root/test_group_feature.py
```

### 使用测试机器人交互测试

可以启动一个测试机器人，模拟真实用户进行交互测试：

```bash
# 启动测试机器人
python3 /root/test_bot.py
```

**机器人账号信息：**
- 用户名: `testbot`
- 密码: `bot123456`
- 昵称: `测试机器人`

启动后，机器人会：
1. 自动登录并保持在线
2. 自动接受好友请求
3. 实时接收并显示消息

**测试流程示例：**

1. 在 App 中搜索 `testbot` 或 `测试机器人`
2. 发送好友请求 → 机器人自动接受
3. 发送私聊消息 → 可在终端查看消息内容
4. 使用 Python 脚本让机器人回复：

```python
import socket
import struct
import json

def send_message(to_user_id, content):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(('127.0.0.1', 8888))
    
    # 登录
    body = json.dumps({'username': 'testbot', 'password': 'bot123456'}).encode()
    sock.sendall(struct.pack('<IBI', len(body), 3, 1) + body)
    sock.recv(1024)  # 接收登录响应
    
    # 发送消息
    body = json.dumps({'receiver_id': to_user_id, 'content': content}).encode()
    sock.sendall(struct.pack('<IBI', len(body), 40, 1) + body)
    sock.recv(1024)  # 接收发送响应
    
    sock.close()

# 发送消息给用户 ID 18
send_message(18, "你好！这是机器人的回复")
```

### 查看私聊历史

```python
import socket
import struct
import json

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(('127.0.0.1', 8888))

# 登录 testbot
body = json.dumps({'username': 'testbot', 'password': 'bot123456'}).encode()
sock.sendall(struct.pack('<IBI', len(body), 3, 1) + body)
sock.recv(1024)

# 获取与用户 18 的聊天历史
body = json.dumps({'peer_id': 18, 'limit': 20}).encode()
sock.sendall(struct.pack('<IBI', len(body), 43, 1) + body)

# 读取响应
header = sock.recv(9)
length, _, _ = struct.unpack('<IBI', header)
body = sock.recv(length)
print(json.loads(body))

sock.close()
```

## 消息协议

| 类型 ID | 名称 | 说明 |
|---------|------|------|
| 1 | REGISTER | 用户注册 |
| 3 | LOGIN | 用户登录 |
| 12 | USER_SEARCH | 用户搜索 |
| 20 | FRIEND_ADD | 添加好友 |
| 22 | FRIEND_ACCEPT | 接受好友 |
| 24 | FRIEND_REJECT | 拒绝好友 |
| 26 | FRIEND_REMOVE | 删除好友 |
| 28 | FRIEND_LIST | 好友列表 |
| 30 | FRIEND_REQUESTS | 好友请求列表 |
| 32 | FRIEND_REQUEST_NOTIFICATION | 好友请求通知 |
| 40 | PRIVATE_MESSAGE | 私聊消息 |
| 43 | PRIVATE_HISTORY | 私聊历史 |
| 50 | GROUP_MESSAGE | 群聊消息 |
| 60 | GROUP_CREATE | 创建群组 |
| 62 | GROUP_INVITE | 邀请成员 |

## 数据库配置

- 数据库: `chat_app`
- 用户: `chat_user`
- 密码: `chat_password_2026`
- 主机: `localhost:3306`

## 开发进度

已完成 7/12 功能:
- [x] F001 MySQL 数据库配置
- [x] F002 用户注册功能
- [x] F003 用户登录功能
- [x] F004 私聊消息功能
- [x] F005 好友系统 - 添加好友
- [x] F006 好友系统 - 管理好友
- [x] F007 群组创建功能
- [ ] F008 群聊消息功能
- [ ] F009 群组管理功能
- [ ] F010 多媒体消息 - 图片
- [ ] F011 多媒体消息 - 文件
- [ ] F012 心跳和重连机制

## 许可证

MIT License
