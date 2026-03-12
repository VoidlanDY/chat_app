import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';

class AppProvider extends ChangeNotifier {
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  ThemeMode _themeMode = ThemeMode.system;
  
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ThemeMode get themeMode => _themeMode;

  /// 初始化应用
  Future<void> init() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final storage = StorageService();
      
      // 加载主题设置
      _themeMode = ThemeMode.values[storage.getThemeMode()];
      
      // 异步连接服务器，不阻塞初始化
      _connectInBackground();
      
      _isInitialized = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    
    _isLoading = false;
    notifyListeners();
  }
  
  /// 后台连接服务器
  Future<void> _connectInBackground() async {
    try {
      final storage = StorageService();
      final chatService = ChatService();
      
      final host = storage.serverHost;
      final port = storage.serverPort;
      
      // 尝试连接，但不阻塞
      final success = await chatService.connect(host, port).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Connection timeout during init');
          return false;
        },
      );
      
      if (success) {
        debugPrint('Connected to server during init');
        
        // 检查是否有保存的用户
        final savedUser = storage.currentUser;
        if (savedUser != null) {
          // 可以尝试自动登录
          debugPrint('Found saved user: ${savedUser.username}');
        }
      } else {
        debugPrint('Failed to connect to server during init');
      }
    } catch (e) {
      debugPrint('Background connection error: $e');
    }
  }

  /// 设置主题模式
  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    StorageService().saveThemeMode(mode.index);
    notifyListeners();
  }

  /// 连接服务器
  Future<bool> connect(String host, int port) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await ChatService().connect(host, port).timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      
      if (success) {
        await StorageService().saveServerConfig(host, port);
      }
      
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}