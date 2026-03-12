package com.ey.echat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 注册后台服务管理器
        BackgroundServiceManager.getInstance(applicationContext)
            .registerChannel(flutterEngine)
        
        // 自动启动前台服务保持后台运行
        try {
            ForegroundService.start(applicationContext)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
