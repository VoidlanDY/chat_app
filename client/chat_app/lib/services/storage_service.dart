import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  // ===== 认证相关 =====
  static const String _keyRememberMe = 'remember_me';
  static const String _keySavedUsername = 'saved_username';
  static const String _keySavedPassword = 'saved_password';
  static const String _keyServerHost = 'server_host';
  static const String _keyServerPort = 'server_port';
  static const String _keyCurrentUser = 'current_user';
  static const String _keyToken = 'auth_token';
  static const String _keyUseFCMPush = 'use_fcm_push';
  static const String _keyAutoStartService = 'auto_start_service';

  // ===== 通知设置 =====
  static const String _keyNotificationsEnabled = 'notifications_enabled';
  static const String _keySoundEnabled = 'sound_enabled';
  static const String _keyVibrationEnabled = 'vibration_enabled';

  // ===== 隐私设置 =====
  static const String _keyFriendVerification = 'friend_verification';
  static const String _keyShowOnlineStatus = 'show_online_status';
  static const String _keyShowReadReceipt = 'show_read_receipt';

  /// 初始化
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 强制更新 localhost 为局域网 IP（解决 Android 网络隔离问题）
    final savedHost = _prefs?.getString(_keyServerHost);
    if (savedHost == '127.0.0.1' || savedHost == 'localhost') {
      await _prefs?.setString(_keyServerHost, '192.168.110.197');
      debugPrint('已自动更新服务器地址: 127.0.0.1 -> 192.168.110.197');
    }
  }

  /// 保存认证信息
  Future<void> saveCredentials(String username, String password, bool rememberMe) async {
    if (rememberMe) {
      await _prefs?.setBool(_keyRememberMe, true);
      await _prefs?.setString(_keySavedUsername, username);
      await _prefs?.setString(_keySavedPassword, password);
    } else {
      await _prefs?.remove(_keyRememberMe);
      await _prefs?.remove(_keySavedUsername);
      await _prefs?.remove(_keySavedPassword);
    }
  }

  String? get savedUsername => _prefs?.getString(_keySavedUsername);
  String? get savedPassword => _prefs?.getString(_keySavedPassword);
  bool get rememberMe => _prefs?.getBool(_keyRememberMe) ?? false;

  /// 保存服务器配置
  Future<void> saveServerConfig(String host, int port) async {
    await _prefs?.setString(_keyServerHost, host);
    await _prefs?.setInt(_keyServerPort, port);
  }

  String get serverHost => _prefs?.getString(_keyServerHost) ?? '192.168.110.197';
  int get serverPort => _prefs?.getInt(_keyServerPort) ?? 8888;
  String get mediaServerHost => '$serverHost:8889';
  
  String fixMediaUrl(String url) {
    if (url.contains('localhost')) {
      return url.replaceFirst(RegExp(r'http://localhost:\d+'), 'http://$mediaServerHost');
    }
    return url;
  }

  /// 用户相关
  Future<void> saveCurrentUser(User user) async {
    await _prefs?.setString(_keyCurrentUser, jsonEncode(user.toJson()));
  }

  User? get currentUser {
    final json = _prefs?.getString(_keyCurrentUser);
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCurrentUser() async {
    await _prefs?.remove(_keyCurrentUser);
    await _prefs?.remove(_keyToken);
  }

  Future<void> saveToken(String token) async {
    await _prefs?.setString(_keyToken, token);
  }

  String? get token => _prefs?.getString(_keyToken);

  /// 主题设置
  Future<void> saveThemeMode(int mode) async {
    await _prefs?.setInt('theme_mode', mode);
  }

  int getThemeMode() {
    return _prefs?.getInt('theme_mode') ?? 0;
  }

  /// 推送设置
  bool get useFCMPush => _prefs?.getBool(_keyUseFCMPush) ?? false;
  Future<void> setUseFCMPush(bool useFCM) async {
    await _prefs?.setBool(_keyUseFCMPush, useFCM);
  }
  
  bool get autoStartService => _prefs?.getBool(_keyAutoStartService) ?? true;
  Future<void> setAutoStartService(bool autoStart) async {
    await _prefs?.setBool(_keyAutoStartService, autoStart);
  }

  // ===== 通知设置 =====
  bool get notificationsEnabled => _prefs?.getBool(_keyNotificationsEnabled) ?? true;
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _prefs?.setBool(_keyNotificationsEnabled, enabled);
  }

  bool get soundEnabled => _prefs?.getBool(_keySoundEnabled) ?? true;
  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs?.setBool(_keySoundEnabled, enabled);
  }

  bool get vibrationEnabled => _prefs?.getBool(_keyVibrationEnabled) ?? true;
  Future<void> setVibrationEnabled(bool enabled) async {
    await _prefs?.setBool(_keyVibrationEnabled, enabled);
  }

  // ===== 隐私设置 =====
  bool get friendVerification => _prefs?.getBool(_keyFriendVerification) ?? true;
  Future<void> setFriendVerification(bool enabled) async {
    await _prefs?.setBool(_keyFriendVerification, enabled);
  }

  bool get showOnlineStatus => _prefs?.getBool(_keyShowOnlineStatus) ?? true;
  Future<void> setShowOnlineStatus(bool show) async {
    await _prefs?.setBool(_keyShowOnlineStatus, show);
  }

  bool get showReadReceipt => _prefs?.getBool(_keyShowReadReceipt) ?? true;
  Future<void> setShowReadReceipt(bool show) async {
    await _prefs?.setBool(_keyShowReadReceipt, show);
  }

  /// 清除所有数据
  Future<void> clearAll() async {
    await _prefs?.clear();
  }
}
