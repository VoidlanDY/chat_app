import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../models/models.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 自定义标题栏
          _buildHeader(context),
          
          // 搜索栏
          _buildSearchBar(),
          
          // 会话列表
          Expanded(
            child: Consumer<ChatService>(
              builder: (context, chatService, child) {
                final conversations = _filterConversations(chatService.conversations);
                
                if (conversations.isEmpty) {
                  return _buildEmptyState();
                }
                
                // 分离置顶和普通会话
                final pinnedConvs = conversations.where((c) => c.isPinned).toList();
                final normalConvs = conversations.where((c) => !c.isPinned).toList();
                
                return RefreshIndicator(
                  onRefresh: () async {
                    // 刷新会话列表
                  },
                  child: ListView(
                    children: [
                      if (pinnedConvs.isNotEmpty) ...[
                        _buildSectionHeader('置顶消息'),
                        ...pinnedConvs.map((c) => _buildConversationItem(context, c)),
                      ],
                      if (normalConvs.isNotEmpty) ...[
                        if (pinnedConvs.isNotEmpty) _buildSectionHeader('最近消息'),
                        ...normalConvs.map((c) => _buildConversationItem(context, c)),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 12,
        left: 20,
        right: 16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text(
            '消息',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 搜索按钮
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              size: 26,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          // 更多选项
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 26),
            onSelected: (value) {
              _handleMenuAction(value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all),
                    SizedBox(width: 12),
                    Text('全部标记已读'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'new_group',
                child: Row(
                  children: [
                    Icon(Icons.group_add),
                    SizedBox(width: 12),
                    Text('创建群聊'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    if (!_isSearching) return const SizedBox.shrink();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _isSearching ? 56 : 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
        decoration: InputDecoration(
          hintText: '搜索聊天记录',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无消息',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方通讯录开始聊天',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationItem(BuildContext context, Conversation conv) {
    final timeStr = _formatTime(conv.lastMessage?.createdAt ?? 0);
    final hasUnread = conv.unreadCount > 0;
    final isRecalled = conv.lastMessage?.content == '[消息已撤回]';
    
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              peerId: conv.groupId > 0 ? conv.groupId : conv.peerId,
              peerName: conv.name,
              isGroup: conv.groupId > 0,
            ),
          ),
        );
      },
      onLongPress: () => _showConversationOptions(context, conv),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 头像
            _buildAvatar(context, conv, hasUnread),
            
            const SizedBox(width: 12),
            
            // 消息内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 第一行：名称和时间
                  Row(
                    children: [
                      // 置顶图标
                      if (conv.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      // 名称
                      Expanded(
                        child: Text(
                          conv.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 时间
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // 第二行：消息预览和未读数
                  Row(
                    children: [
                      // 消息预览
                      Expanded(
                        child: Row(
                          children: [
                            // 群聊显示发送者
                            if (conv.isGroup && conv.lastMessage != null)
                              FutureBuilder<String>(
                                future: _getSenderPrefix(context, conv.lastMessage!.senderId),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                                    return Text(
                                      '${snapshot.data}: ',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                },
                              ),
                            // 消息内容
                            Expanded(
                              child: Text(
                                _getMessagePreview(conv.lastMessage, isRecalled),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: hasUnread
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // 静音图标
                      if (conv.isMuted)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.notifications_off_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      
                      // 未读数
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: conv.isMuted
                                ? Theme.of(context).colorScheme.outline
                                : Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            conv.unreadCount > 99 ? '99+' : conv.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, Conversation conv, bool hasUnread) {
    return Stack(
      children: [
        // 头像容器
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getAvatarColor(conv.name).withOpacity(0.8),
                _getAvatarColor(conv.name),
              ],
            ),
            boxShadow: hasUnread
                ? [
                    BoxShadow(
                      color: _getAvatarColor(conv.name).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: conv.avatar.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      conv.avatar,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarText(conv),
                    ),
                  )
                : _buildAvatarText(conv),
          ),
        ),
        
        // 在线状态指示器（私聊）
        if (!conv.isGroup && conv.peer?.onlineStatus == 1)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        
        // 群聊角标
        if (conv.isGroup)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.group,
                size: 10,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarText(Conversation conv) {
    return Text(
      conv.name.isNotEmpty ? conv.name[0].toUpperCase() : '?',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFFEF4444), // Red
      const Color(0xFFF97316), // Orange
      const Color(0xFFEAB308), // Yellow
      const Color(0xFF22C55E), // Green
      const Color(0xFF14B8A6), // Teal
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF3B82F6), // Blue
    ];
    
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  String _formatTime(int timestamp) {
    if (timestamp == 0) return '';
    
    final messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    final difference = now.difference(messageTime);
    
    if (difference.inDays == 0) {
      // 今天
      return '${messageTime.hour.toString().padLeft(2, '0')}:${messageTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return '昨天';
    } else if (difference.inDays < 7) {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[messageTime.weekday - 1];
    } else {
      return '${messageTime.month}/${messageTime.day}';
    }
  }

  String _getMessagePreview(Message? message, bool isRecalled) {
    if (message == null) return '';
    
    if (isRecalled) {
      return '消息已撤回';
    }
    
    // 根据消息类型显示不同预览
    switch (message.mediaType) {
      case 1: // Image
        return '[图片]';
      case 2: // Audio
        return '[语音]';
      case 3: // Video
        return '[视频]';
      case 4: // File
        return '[文件] ${message.content}';
      default:
        return message.content;
    }
  }

  Future<String> _getSenderPrefix(BuildContext context, int senderId) async {
    final chatService = context.read<ChatService>();
    // 尝试从缓存获取用户名
    // 这里简化处理，实际应该有用户缓存机制
    return '';
  }

  List<Conversation> _filterConversations(List<Conversation> conversations) {
    if (_searchQuery.isEmpty) {
      return conversations;
    }
    
    return conversations.where((conv) {
      final name = conv.name.toLowerCase();
      final lastMessage = conv.lastMessage?.content.toLowerCase() ?? '';
      return name.contains(_searchQuery) || lastMessage.contains(_searchQuery);
    }).toList();
  }

  void _handleMenuAction(String action) {
    final chatService = context.read<ChatService>();
    switch (action) {
      case 'mark_all_read':
        // 标记全部已读
        for (final conv in chatService.conversations) {
          if (conv.unreadCount > 0) {
            chatService.markConversationRead(
              conv.groupId > 0 ? conv.groupId : conv.peerId,
              isGroup: conv.groupId > 0,
            );
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已全部标记为已读')),
        );
        break;
      case 'new_group':
        // 跳转到创建群聊页面
        break;
    }
  }

  void _showConversationOptions(BuildContext context, Conversation conv) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conv.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(conv.isPinned ? '取消置顶' : '置顶'),
              onTap: () {
                Navigator.pop(context);
                context.read<ChatService>().toggleConversationPin(
                  conv.groupId > 0 ? conv.groupId : conv.peerId,
                  isGroup: conv.groupId > 0,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(conv.isPinned ? '已取消置顶' : '已置顶')),
                );
              },
            ),
            ListTile(
              leading: Icon(conv.isMuted ? Icons.notifications : Icons.notifications_off_outlined),
              title: Text(conv.isMuted ? '取消免打扰' : '消息免打扰'),
              onTap: () {
                Navigator.pop(context);
                context.read<ChatService>().toggleConversationMute(
                  conv.groupId > 0 ? conv.groupId : conv.peerId,
                  isGroup: conv.groupId > 0,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(conv.isMuted ? '已取消免打扰' : '已开启免打扰')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('标记为已读'),
              onTap: () {
                Navigator.pop(context);
                context.read<ChatService>().markConversationRead(
                  conv.groupId > 0 ? conv.groupId : conv.peerId,
                  isGroup: conv.groupId > 0,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除会话', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteConversation(context, conv);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteConversation(BuildContext context, Conversation conv) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除与 ${conv.name} 的会话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<ChatService>().deleteConversation(
                conv.groupId > 0 ? conv.groupId : conv.peerId,
                isGroup: conv.groupId > 0,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('会话已删除')),
              );
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}