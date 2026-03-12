import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// 通知服务
/// 管理本地通知的发送和管理
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _initializing = false;

  /// 初始化通知服务（非阻塞）
  Future<void> init() async {
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      // Android 初始化设置
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS 初始化设置
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // 创建通知渠道 (Android 8.0+)
      await _createNotificationChannels();

      // 请求权限
      await _requestPermissions();

      _initialized = true;
      debugPrint('NotificationService initialized');
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    } finally {
      _initializing = false;
    }
  }

  /// 创建通知渠道
  Future<void> _createNotificationChannels() async {
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    // 消息通知渠道 - 小米手机需要最高优先级
    final messagesChannel = AndroidNotificationChannel(
      'messages',
      '消息通知',
      description: '接收新消息的通知',
      importance: Importance.max,  // 最高优先级
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      showBadge: true,
    );

    // 好友请求通知渠道 - 小米手机需要最高优先级
    final friendRequestsChannel = AndroidNotificationChannel(
      'friend_requests',
      '好友请求',
      description: '好友请求通知',
      importance: Importance.max,  // 最高优先级
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await android.createNotificationChannel(messagesChannel);
    await android.createNotificationChannel(friendRequestsChannel);
    debugPrint('Notification channels created with max importance');
  }

  /// 请求通知权限
  Future<bool> _requestPermissions() async {
    bool granted = false;
    
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      granted = await android.requestNotificationsPermission() ?? false;
      debugPrint('Android notification permission: $granted');
    }

    final ios = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      ) ?? false;
      debugPrint('iOS notification permission: $granted');
    }

    return granted;
  }

  /// 检查通知权限
  Future<bool> hasPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  /// 通知点击回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // 可以在这里处理通知点击事件，比如跳转到聊天页面
  }

  /// 显示消息通知
  Future<void> showMessageNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      await init();
    }

    // 检查权限
    final hasPer = await hasPermission();
    if (!hasPer) {
      debugPrint('Notification permission not granted');
      return;
    }

    // 小米手机需要最高优先级和特殊配置
    final androidDetails = AndroidNotificationDetails(
      'messages',
      '消息通知',
      channelDescription: '接收新消息的通知',
      // 最高优先级确保小米手机也能显示
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Colors.blue,
      playSound: true,
      // 前台通知设置
      ongoing: false,
      autoCancel: true,
      // 设置大图标
      icon: '@mipmap/ic_launcher',
      // 通知样式
      styleInformation: BigTextStyleInformation(body),
      // 小米手机需要这些设置
      channelShowBadge: true,
      // 确保在锁屏和通知栏显示
      visibility: NotificationVisibility.public,
      // 设置通知类别为消息
      category: AndroidNotificationCategory.message,
      // 设置ticker确保通知能够显示
      ticker: '$title: $body',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
      debugPrint('Notification shown: $title - $body');
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }

  /// 显示好友请求通知
  Future<void> showFriendRequestNotification({
    required int id,
    required String username,
    String? nickname,
  }) async {
    if (!_initialized) {
      await init();
    }

    final title = '好友请求';
    final body = nickname != null && nickname.isNotEmpty
        ? '$nickname ($username) 请求添加你为好友'
        : '$username 请求添加你为好友';

    // 小米手机需要最高优先级和特殊配置
    final androidDetails = AndroidNotificationDetails(
      'friend_requests',
      '好友请求',
      channelDescription: '好友请求通知',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
      channelShowBadge: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
      ticker: '$title: $body',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: 'friend_request',
      );
      debugPrint('Friend request notification shown: $body');
    } catch (e) {
      debugPrint('Failed to show friend request notification: $e');
    }
  }

  /// 取消指定通知
  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }

  /// 取消所有通知
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }
}