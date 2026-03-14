import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 极光推送服务
/// 支持 Android 和 iOS 平台
/// 
/// 使用 jpush_flutter 3.x 版本 API
class JPushService {
  static final JPushService _instance = JPushService._internal();
  factory JPushService() => _instance;
  JPushService._internal();

  static const String _keyRegistrationId = 'jpush_registration_id';
  static const String _keyAlias = 'jpush_alias';
  
  // 使用 JPush.newJPush() 创建实例 (3.x API)
  final JPushFlutterInterface _jPush = JPush.newJPush();
  
  String? _registrationId;
  String? _alias;
  bool _isInitialized = false;
  bool _isSetup = false;
  
  // 回调
  Function(Map<String, dynamic> message)? onNotificationReceived;
  Function(Map<String, dynamic> message)? onNotificationOpened;
  Function(String registrationId)? onRegistrationIdReceived;
  
  String? get registrationId => _registrationId;
  String? get alias => _alias;
  bool get isInitialized => _isInitialized;
  
  /// 初始化极光推送
  /// 返回 true 表示初始化流程已启动（异步完成 setup）
  Future<bool> init() async {
    if (_isInitialized) {
      debugPrint('JPush 已初始化');
      return true;
    }
    
    try {
      debugPrint('JPush 开始初始化...');
      
      // 加载保存的 Registration ID 和别名
      await _loadSavedData();
      
      // 设置事件处理器 (必须在 setup 之前)
      _setupEventHandlers();
      
      // 初始化 JPush SDK
      // 注意：AppKey 已在 AndroidManifest.xml 和 build.gradle 中配置
      // 但 setup 方法仍需要传入 appKey
      _jPush.setup(
        appKey: '16d9f5ae7a467d54f3d9f775',
        channel: 'developer-default',
        production: !kDebugMode,  // 生产环境
        debug: kDebugMode,        // 调试模式输出日志
      );
      
      _isSetup = true;
      debugPrint('JPush setup 完成');
      
      // 异步获取 Registration ID（不阻塞主流程）
      _getRegistrationIdAsync();
      
      _isInitialized = true;
      return true;
    } catch (e, stack) {
      debugPrint('JPush 初始化失败: $e');
      debugPrint('Stack: $stack');
      return false;
    }
  }
  
  /// 设置事件处理器
  void _setupEventHandlers() {
    _jPush.addEventHandler(
      // 收到通知回调
      onReceiveNotification: (Map<String, dynamic> message) async {
        debugPrint('JPush 收到通知: $message');
        onNotificationReceived?.call(message);
      },
      // 打开通知回调
      onOpenNotification: (Map<String, dynamic> message) async {
        debugPrint('JPush 打开通知: $message');
        onNotificationOpened?.call(message);
      },
      // 收到自定义消息回调
      onReceiveMessage: (Map<String, dynamic> message) async {
        debugPrint('JPush 收到自定义消息: $message');
      },
      // 连接状态回调
      onConnected: (Map<String, dynamic> message) async {
        debugPrint('JPush 已连接: $message');
      },
      // 通知授权状态回调 (iOS)
      onNotifyMessageUnShow: (Map<String, dynamic> message) async {
        debugPrint('JPush 通知未显示: $message');
      },
      // 通知设置回调 (iOS)
      onNotifyMessageOpened: (Map<String, dynamic> message) async {
        debugPrint('JPush 通知设置: $message');
      },
      // App 并未运行，通知点击回调
      onAppOpenWithNotification: (Map<String, dynamic> message) async {
        debugPrint('JPush App 通过通知打开: $message');
        onNotificationOpened?.call(message);
      },
    );
  }
  
  /// 加载保存的数据
  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _registrationId = prefs.getString(_keyRegistrationId);
      _alias = prefs.getString(_keyAlias);
      debugPrint('JPush 加载保存的数据: regId=$_registrationId, alias=$_alias');
    } catch (e) {
      debugPrint('JPush 加载保存数据失败: $e');
    }
  }
  
  /// 设置别名 (用户ID)
  /// 别名用于精准推送，通常设置为 user_{userId}
  Future<bool> setAlias(String alias) async {
    if (!_isSetup) {
      debugPrint('JPush 未初始化，无法设置别名');
      return false;
    }
    
    try {
      // 使用新的 alias 设置序列号
      final sequence = DateTime.now().millisecondsSinceEpoch;
      await _jPush.setAlias(alias, sequence);
      
      _alias = alias;
      
      // 保存到本地
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAlias, alias);
      
      debugPrint('JPush 设置别名成功: $alias');
      return true;
    } catch (e) {
      debugPrint('JPush 设置别名失败: $e');
      return false;
    }
  }
  
  /// 删除别名
  Future<bool> deleteAlias() async {
    if (!_isSetup) {
      debugPrint('JPush 未初始化，无法删除别名');
      return false;
    }
    
    try {
      final sequence = DateTime.now().millisecondsSinceEpoch;
      await _jPush.deleteAlias(sequence);
      
      _alias = null;
      
      // 清除本地保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAlias);
      
      debugPrint('JPush 删除别名成功');
      return true;
    } catch (e) {
      debugPrint('JPush 删除别名失败: $e');
      return false;
    }
  }
  
  /// 设置标签
  /// 标签用于分组推送
  Future<bool> setTags(List<String> tags) async {
    if (!_isSetup) {
      debugPrint('JPush 未初始化，无法设置标签');
      return false;
    }
    
    try {
      final sequence = DateTime.now().millisecondsSinceEpoch;
      await _jPush.setTags(tags, sequence);
      debugPrint('JPush 设置标签成功: $tags');
      return true;
    } catch (e) {
      debugPrint('JPush 设置标签失败: $e');
      return false;
    }
  }
  
  /// 添加标签
  Future<bool> addTags(List<String> tags) async {
    if (!_isSetup) {
      debugPrint('JPush 未初始化，无法添加标签');
      return false;
    }
    
    try {
      final sequence = DateTime.now().millisecondsSinceEpoch;
      await _jPush.addTags(tags, sequence);
      debugPrint('JPush 添加标签成功: $tags');
      return true;
    } catch (e) {
      debugPrint('JPush 添加标签失败: $e');
      return false;
    }
  }
  
  /// 删除标签
  Future<bool> deleteTags(List<String> tags) async {
    if (!_isSetup) {
      debugPrint('JPush 未初始化，无法删除标签');
      return false;
    }
    
    try {
      final sequence = DateTime.now().millisecondsSinceEpoch;
      await _jPush.deleteTags(tags, sequence);
      debugPrint('JPush 删除标签成功: $tags');
      return true;
    } catch (e) {
      debugPrint('JPush 删除标签失败: $e');
      return false;
    }
  }
  
  /// 清除所有通知
  Future<void> clearAllNotifications() async {
    if (!_isSetup) {
      return;
    }
    
    try {
      await _jPush.clearAllNotifications();
      debugPrint('JPush 清除所有通知');
    } catch (e) {
      debugPrint('JPush 清除通知失败: $e');
    }
  }
  
  /// 设置通知角标 (iOS)
  Future<void> setBadge(int badge) async {
    if (!_isSetup) {
      return;
    }
    
    try {
      await _jPush.setBadge(badge);
      debugPrint('JPush 设置角标: $badge');
    } catch (e) {
      debugPrint('JPush 设置角标失败: $e');
    }
  }
  
  /// 申请通知权限 (iOS, Android 13+)
  Future<void> requestPermission() async {
    if (!_isSetup) {
      return;
    }
    
    try {
      if (Platform.isIOS) {
        // iOS 需要申请权限
        // JPush SDK 会自动处理
        debugPrint('JPush iOS 权限申请由 SDK 自动处理');
      } else if (Platform.isAndroid) {
        // Android 13+ 需要 POST_NOTIFICATIONS 权限
        // 已在 AndroidManifest.xml 中配置
        debugPrint('JPush Android 通知权限已配置');
      }
    } catch (e) {
      debugPrint('JPush 申请权限失败: $e');
    }
  }
  
  /// 停止推送服务
  Future<void> stop() async {
    if (!_isSetup) {
      return;
    }
    
    try {
      await deleteAlias();
      _isInitialized = false;
      _isSetup = false;
      debugPrint('JPush 服务已停止');
    } catch (e) {
      debugPrint('JPush 停止失败: $e');
    }
  }
  
  /// 异步获取 Registration ID（非阻塞）
  void _getRegistrationIdAsync() {
    Future(() async {
      // 最多尝试 15 次，每次间隔 500ms
      for (int i = 0; i < 15; i++) {
        try {
          final regId = await _jPush.getRegistrationID();
          if (regId != null && regId.isNotEmpty) {
            _registrationId = regId;
            debugPrint('JPush Registration ID 获取成功: $_registrationId');
            
            // 保存到本地
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_keyRegistrationId, _registrationId!);
            
            // 通知外部
            onRegistrationIdReceived?.call(_registrationId!);
            
            // 如果有保存的别名，重新设置
            if (_alias != null) {
              await setAlias(_alias!);
            }
            return;
          }
        } catch (e) {
          debugPrint('获取 JPush Registration ID 失败 (尝试 ${i + 1}/15): $e');
        }
        
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      debugPrint('JPush 未能获取 Registration ID，请检查网络和配置');
    });
  }
  
  /// 获取当前 Registration ID
  Future<String?> getRegistrationId() async {
    if (!_isSetup) {
      return null;
    }
    
    try {
      final regId = await _jPush.getRegistrationID();
      if (regId != null && regId.isNotEmpty) {
        _registrationId = regId;
        
        // 保存到本地
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyRegistrationId, _registrationId!);
      }
      return _registrationId;
    } catch (e) {
      debugPrint('获取 JPush Registration ID 失败: $e');
      return _registrationId;
    }
  }
  
  /// 检查是否已获取到 Registration ID
  bool get hasRegistrationId => _registrationId != null && _registrationId!.isNotEmpty;
}