import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = '正在初始化...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final appProvider = context.read<AppProvider>();
    final storage = StorageService();
    
    try {
      // 初始化应用，设置超时
      await appProvider.init().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('Init timeout, continuing...');
        },
      );
      
      if (!mounted) return;
      
      // 最少显示启动画面 1 秒
      await Future.delayed(const Duration(seconds: 1));
      
      if (!mounted) return;
      
      final chatService = context.read<ChatService>();
      
      // 检查是否已登录
      if (chatService.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
        return;
      }
      
      // 尝试自动登录
      if (storage.rememberMe && 
          storage.savedUsername != null && 
          storage.savedPassword != null) {
        
        setState(() => _status = '正在自动登录...');
        
        debugPrint('尝试自动登录: ${storage.savedUsername}');
        
        // 确保已连接服务器
        if (!chatService.isConnected) {
          await chatService.connect(storage.serverHost, storage.serverPort).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('连接服务器超时');
              return false;
            },
          );
        }
        
        if (chatService.isConnected) {
          // 尝试登录
          final success = await chatService.login(
            storage.savedUsername!,
            storage.savedPassword!,
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('登录超时');
              return false;
            },
          );
          
          if (success && mounted) {
            debugPrint('自动登录成功');
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainScreen()),
            );
            return;
          } else {
            debugPrint('自动登录失败');
          }
        }
      }
      
      if (!mounted) return;
      
      // 自动登录失败或未启用，跳转到登录页面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      debugPrint('Init error: $e');
      
      if (!mounted) return;
      
      // 即使出错也进入登录页面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.chat_bubble_rounded,
                size: 60,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // App Name
            const Text(
              'Chat App',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Connect with friends',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            
            const SizedBox(height: 48),
            
            // Status text
            Text(
              _status,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}