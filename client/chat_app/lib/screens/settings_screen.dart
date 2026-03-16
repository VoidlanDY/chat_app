import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/app_provider.dart';
import '../services/storage_service.dart';
import '../services/message_database.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late StorageService _storage;
  late bool _notificationsEnabled;
  late bool _soundEnabled;
  late bool _vibrationEnabled;
  late bool _friendVerification;
  late bool _showOnlineStatus;
  late bool _showReadReceipt;
  ThemeMode _themeMode = ThemeMode.system;
  
  String _cacheSize = '计算中...';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _storage = StorageService();
    _loadSettings();
    _calculateCacheSize();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _notificationsEnabled = _storage.notificationsEnabled;
      _soundEnabled = _storage.soundEnabled;
      _vibrationEnabled = _storage.vibrationEnabled;
      _friendVerification = _storage.friendVerification;
      _showOnlineStatus = _storage.showOnlineStatus;
      _showReadReceipt = _storage.showReadReceipt;
      _themeMode = ThemeMode.values[_storage.getThemeMode()];
    });
  }

  Future<void> _calculateCacheSize() async {
    try {
      final size = await MessageDatabase().getDatabaseSize();
      setState(() {
        _cacheSize = _formatBytes(size);
      });
    } catch (e) {
      setState(() {
        _cacheSize = '未知';
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 通知设置
          _buildSection(
            title: '通知设置',
            children: [
              SwitchListTile(
                title: const Text('消息通知'),
                subtitle: const Text('接收新消息通知'),
                secondary: const Icon(Icons.notifications),
                value: _notificationsEnabled,
                onChanged: _onNotificationsChanged,
              ),
              SwitchListTile(
                title: const Text('声音'),
                subtitle: const Text('消息提醒声音'),
                secondary: const Icon(Icons.volume_up),
                value: _soundEnabled,
                onChanged: (value) async {
                  await _storage.setSoundEnabled(value);
                  setState(() => _soundEnabled = value);
                },
              ),
              SwitchListTile(
                title: const Text('震动'),
                subtitle: const Text('消息震动提醒'),
                secondary: const Icon(Icons.vibration),
                value: _vibrationEnabled,
                onChanged: (value) async {
                  await _storage.setVibrationEnabled(value);
                  setState(() => _vibrationEnabled = value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_applications),
                title: const Text('系统通知设置'),
                subtitle: const Text('打开系统通知权限设置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openNotificationSettings,
              ),
            ],
          ),
          
          // 隐私设置
          _buildSection(
            title: '隐私设置',
            children: [
              SwitchListTile(
                title: const Text('加好友需要验证'),
                subtitle: const Text('其他人添加你为好友时需要验证'),
                secondary: const Icon(Icons.person_add),
                value: _friendVerification,
                onChanged: (value) async {
                  await _storage.setFriendVerification(value);
                  setState(() => _friendVerification = value);
                },
              ),
              SwitchListTile(
                title: const Text('显示在线状态'),
                subtitle: const Text('让好友看到你的在线状态'),
                secondary: const Icon(Icons.visibility),
                value: _showOnlineStatus,
                onChanged: (value) async {
                  await _storage.setShowOnlineStatus(value);
                  setState(() => _showOnlineStatus = value);
                },
              ),
              SwitchListTile(
                title: const Text('消息已读回执'),
                subtitle: const Text('发送消息已读状态给对方'),
                secondary: const Icon(Icons.done_all),
                value: _showReadReceipt,
                onChanged: (value) async {
                  await _storage.setShowReadReceipt(value);
                  setState(() => _showReadReceipt = value);
                },
              ),
            ],
          ),
          
          // 外观设置
          _buildSection(
            title: '外观设置',
            children: [
              ListTile(
                leading: const Icon(Icons.palette),
                title: const Text('主题模式'),
                subtitle: Text(_getThemeModeName(_themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showThemeDialog,
              ),
            ],
          ),
          
          // 存储设置
          _buildSection(
            title: '存储设置',
            children: [
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('本地缓存'),
                subtitle: Text('已使用 $_cacheSize'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showCacheDetails,
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services, color: Colors.orange),
                title: const Text('清除缓存'),
                subtitle: const Text('清除本地消息记录和缓存'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showClearCacheDialog,
              ),
            ],
          ),
          
          // 关于
          _buildSection(
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('版本'),
                subtitle: const Text('1.0.127'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showAboutDialog,
              ),
              ListTile(
                leading: const Icon(Icons.description),
                title: const Text('用户协议'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSimpleDialog('用户协议', '欢迎使用 Chat App...\n\n1. 本软件仅供个人学习交流使用。\n2. 请勿用于非法用途。\n3. 用户需对自己的账号安全负责。'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip),
                title: const Text('隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSimpleDialog('隐私政策', '我们重视您的隐私保护...\n\n1. 我们不会收集您的个人敏感信息。\n2. 您的消息内容仅存储在您的设备上。\n3. 我们不会向第三方分享您的数据。'),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return '跟随系统';
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
    }
  }

  Future<void> _onNotificationsChanged(bool value) async {
    if (value) {
      // 请求通知权限
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请授予通知权限')),
            );
          }
          return;
        }
      }
    }
    await _storage.setNotificationsEnabled(value);
    setState(() => _notificationsEnabled = value);
  }

  void _openNotificationSettings() async {
    if (Platform.isAndroid) {
      await openAppSettings();
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色模式'),
              value: ThemeMode.light,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色模式'),
              value: ThemeMode.dark,
              groupValue: _themeMode,
              onChanged: (value) => _setThemeMode(value!),
            ),
          ],
        ),
      ),
    );
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    context.read<AppProvider>().setThemeMode(mode);
    _storage.saveThemeMode(mode.index);
    Navigator.pop(context);
  }

  void _showCacheDetails() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('本地消息记录'),
              subtitle: Text('缓存大小: $_cacheSize'),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '本地缓存包括：\n• 私聊和群聊消息记录\n• 用户头像缓存\n• 媒体文件元数据',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要清除所有缓存数据吗？'),
            const SizedBox(height: 8),
            Text('当前缓存大小: $_cacheSize', 
              style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(height: 8),
            const Text('这将删除：',
              style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• 本地消息记录'),
            const Text('• 会话列表'),
            const Text('• 头像缓存'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _isLoading ? null : () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              
              try {
                // 清除本地数据库
                await MessageDatabase().clearAll();
                
                // 重新计算缓存大小
                await _calculateCacheSize();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('缓存已清除')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('清除失败: $e')),
                  );
                }
              } finally {
                setState(() => _isLoading = false);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Chat App',
      applicationVersion: '1.0.127',
      applicationIcon: const Icon(Icons.chat_bubble, size: 48),
      applicationLegalese: '© 2026 Chat App\n基于 Flutter 开发的即时通讯应用',
    );
  }

  void _showSimpleDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(content),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
