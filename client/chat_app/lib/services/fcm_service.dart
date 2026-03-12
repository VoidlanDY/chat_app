import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

/// 后台消息处理器（必须是顶级函数）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 初始化 Firebase
  await Firebase.initializeApp();
  
  debugPrint('=== FCM Background Message ===');
  debugPrint('Message ID: ${message.messageId}');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
  debugPrint('Data: ${message.data}');
  
  // 显示本地通知
  final notificationService = NotificationService();
  await notificationService.init();
  
  final title = message.notification?.title ?? '新消息';
  final body = message.notification?.body ?? '';
  
  await notificationService.showMessageNotification(
    id: message.data['sender_id']?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
    title: title,
    body: body,
    payload: message.data['payload'],
  );
}

/// Firebase Cloud Messaging 服务
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final NotificationService _notificationService = NotificationService();
  
  String? _fcmToken;
  bool _initialized = false;
  
  String? get fcmToken => _fcmToken;
  
  /// 初始化 FCM
  Future<void> init() async {
    if (_initialized) return;
    
    try {
      // 请求权限 (iOS)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      
      debugPrint('FCM Permission status: ${settings.authorizationStatus}');
      
      // 获取 FCM Token
      _fcmToken = await _messaging.getToken();
      debugPrint('FCM Token: $_fcmToken');
      
      // 监听 Token 刷新
      _messaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        debugPrint('FCM Token refreshed: $token');
        // TODO: 发送新 Token 到服务器
      });
      
      // 前台消息监听
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // 后台点击通知打开 App
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
      
      // 检查 App 是否通过通知打开
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
      
      _initialized = true;
      debugPrint('FCM Service initialized');
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }
  
  /// 处理前台消息
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('=== FCM Foreground Message ===');
    debugPrint('Message ID: ${message.messageId}');
    debugPrint('Title: ${message.notification?.title}');
    debugPrint('Body: ${message.notification?.body}');
    debugPrint('Data: ${message.data}');
    
    final title = message.notification?.title ?? '新消息';
    final body = message.notification?.body ?? '';
    
    _notificationService.showMessageNotification(
      id: message.data['sender_id']?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      payload: message.data['payload'],
    );
  }
  
  /// 处理点击通知打开 App
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('=== FCM Message Opened App ===');
    debugPrint('Data: ${message.data}');
    
    // TODO: 根据消息数据跳转到相应页面
    // 例如：跳转到聊天页面
  }
}