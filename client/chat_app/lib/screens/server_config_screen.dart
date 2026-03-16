import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostController;
  late TextEditingController _portController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final storage = StorageService();
    _hostController = TextEditingController(text: storage.serverHost);
    _portController = TextEditingController(text: storage.serverPort.toString());
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final storage = StorageService();
      await storage.saveServerConfig(
        _hostController.text.trim(),
        int.parse(_portController.text.trim()),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器配置已保存')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, 
                            color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('连接说明', 
                            style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• 同一设备: 使用 127.0.0.1\n'
                        '• 局域网: 使用服务器局域网 IP\n'
                        '• 端口: WebSocket 8888, HTTP 8889',
                        style: TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // 服务器地址
              TextFormField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如: 192.168.1.100',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入服务器地址';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              // 端口
              TextFormField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '默认: 8888',
                  prefixIcon: Icon(Icons.settings_ethernet),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入端口';
                  }
                  final port = int.tryParse(value.trim());
                  if (port == null || port < 1 || port > 65535) {
                    return '请输入有效端口 (1-65535)';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 32),
              
              // 保存按钮
              ElevatedButton(
                onPressed: _isLoading ? null : _saveConfig,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
              
              const SizedBox(height: 16),
              
              // 重置按钮
              OutlinedButton(
                onPressed: () {
                  _hostController.text = '192.168.110.197';
                  _portController.text = '8888';
                },
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}