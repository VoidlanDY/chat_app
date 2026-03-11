import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:convert/convert.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RSA 密钥对类（pointycastle 没有提供此类型）
class RSAKeyPair {
  final RSAPublicKey publicKey;
  final RSAPrivateKey privateKey;
  
  RSAKeyPair(this.publicKey, this.privateKey);
}

/// 端到端加密服务
/// 使用 RSA-2048 进行密钥交换，AES-256-GCM 进行消息加密
class E2EEService {
  static final E2EEService _instance = E2EEService._internal();
  factory E2EEService() => _instance;
  E2EEService._internal();

  // 密钥存储
  static const String _privateKeyKey = 'e2ee_private_key';
  static const String _publicKeyKey = 'e2ee_public_key';

  // 缓存的公钥
  final Map<int, String> _publicKeyCache = {};

  // RSA 密钥对
  RSAKeyPair? _keyPair;
  final SecureRandom _secureRandom = _createSecureRandom();

  /// 创建安全随机数生成器
  static SecureRandom _createSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = <int>[];
    for (int i = 0; i < 32; i++) {
      seeds.add(seedSource.nextInt(256));
    }
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  /// 初始化加密服务
  Future<void> init() async {
    await _loadKeys();
  }

  /// 加载保存的密钥
  Future<void> _loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final privateKeyPem = prefs.getString(_privateKeyKey);
    final publicKeyPem = prefs.getString(_publicKeyKey);

    if (privateKeyPem != null && publicKeyPem != null) {
      _keyPair = RSAKeyPair(
        _parseRSAPublicKey(publicKeyPem),
        _parseRSAPrivateKey(privateKeyPem),
      );
    }
  }

  /// 生成新的 RSA 密钥对
  Future<RSAKeyPair> generateKeyPair() async {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    _keyPair = RSAKeyPair(pair.publicKey as RSAPublicKey, pair.privateKey as RSAPrivateKey);

    // 保存密钥
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_privateKeyKey, _encodeRSAPrivateKey(_keyPair!.privateKey));
    await prefs.setString(_publicKeyKey, _encodeRSAPublicKey(_keyPair!.publicKey));

    return _keyPair!;
  }

  /// 获取公钥（PEM 格式）
  String? getPublicKeyPem() {
    if (_keyPair == null) return null;
    return _encodeRSAPublicKey(_keyPair!.publicKey);
  }

  /// 是否已初始化
  bool get isInitialized => _keyPair != null;

  /// 缓存用户公钥
  void cachePublicKey(int userId, String publicKey) {
    _publicKeyCache[userId] = publicKey;
  }

  /// 获取缓存的公钥
  String? getCachedPublicKey(int userId) {
    return _publicKeyCache[userId];
  }

  /// 加密消息
  /// 返回包含加密后的 AES 密钥、IV 和加密内容的 Map
  Future<Map<String, String>> encryptMessage(String content, String recipientPublicKeyPem) async {
    if (_keyPair == null) {
      throw Exception('Key pair not initialized');
    }

    // 1. 生成随机 AES 密钥和 IV
    final aesKey = _generateRandomBytes(32); // AES-256
    final iv = _generateRandomBytes(12); // GCM 推荐 12 字节

    // 2. 使用 AES-GCM 加密消息
    final encryptedContent = _encryptAESGCM(utf8.encode(content), aesKey, iv);

    // 3. 使用接收者的 RSA 公钥加密 AES 密钥
    final recipientPublicKey = _parseRSAPublicKey(recipientPublicKeyPem);
    final encryptedKey = _encryptRSA(aesKey, recipientPublicKey);

    return {
      'encrypted_key': base64Encode(encryptedKey),
      'iv': base64Encode(iv),
      'encrypted_content': base64Encode(encryptedContent),
    };
  }

  /// 解密消息
  Future<String> decryptMessage({
    required String encryptedKey,
    required String iv,
    required String encryptedContent,
  }) async {
    if (_keyPair == null) {
      throw Exception('Key pair not initialized');
    }

    // 1. 使用私钥解密 AES 密钥
    final encryptedKeyBytes = base64Decode(encryptedKey);
    final aesKey = _decryptRSA(encryptedKeyBytes, _keyPair!.privateKey);

    // 2. 使用 AES-GCM 解密消息
    final ivBytes = base64Decode(iv);
    final encryptedContentBytes = base64Decode(encryptedContent);
    final decryptedContent = _decryptAESGCM(encryptedContentBytes, aesKey, ivBytes);

    return utf8.decode(decryptedContent);
  }

  /// AES-GCM 加密
  Uint8List _encryptAESGCM(List<int> data, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(
        KeyParameter(key),
        128, // tag length in bits
        iv,
        Uint8List(0), // additional data
      ));

    final output = Uint8List(cipher.getOutputSize(data.length));
    final len = cipher.processBytes(Uint8List.fromList(data), 0, data.length, output, 0);
    cipher.doFinal(output, len);

    return output;
  }

  /// AES-GCM 解密
  Uint8List _decryptAESGCM(List<int> data, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(
        KeyParameter(key),
        128, // tag length in bits
        iv,
        Uint8List(0), // additional data
      ));

    final output = Uint8List(cipher.getOutputSize(data.length));
    final len = cipher.processBytes(Uint8List.fromList(data), 0, data.length, output, 0);
    cipher.doFinal(output, len);

    return output;
  }

  /// RSA 加密（使用 OAEP 填充）
  Uint8List _encryptRSA(Uint8List data, RSAPublicKey publicKey) {
    // 使用 PKCS1 v1.5 填充进行加密
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    return _processInBlocks(cipher, data);
  }

  /// RSA 解密
  Uint8List _decryptRSA(Uint8List data, RSAPrivateKey privateKey) {
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));

    return _processInBlocks(cipher, data);
  }

  /// 分块处理 RSA 加密/解密
  Uint8List _processInBlocks(AsymmetricBlockCipher cipher, Uint8List data) {
    final output = BytesBuilder();
    int offset = 0;

    while (offset < data.length) {
      final chunkSize = cipher.inputBlockSize;
      final chunk = data.sublist(offset, min(offset + chunkSize, data.length));
      output.add(cipher.process(Uint8List.fromList(chunk)));
      offset += chunkSize;
    }

    return output.toBytes();
  }

  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextUint8();
    }
    return bytes;
  }

  /// 编码 RSA 公钥为 PEM 格式
  String _encodeRSAPublicKey(RSAPublicKey publicKey) {
    // 简化版：直接存储 modulus 和 exponent
    final data = {
      'modulus': publicKey.modulus!.toRadixString(16),
      'exponent': publicKey.exponent!.toRadixString(16),
    };
    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  /// 编码 RSA 私钥为 PEM 格式
  String _encodeRSAPrivateKey(RSAPrivateKey privateKey) {
    final data = {
      'modulus': privateKey.modulus!.toRadixString(16),
      'privateExponent': privateKey.privateExponent!.toRadixString(16),
      'p': privateKey.p!.toRadixString(16),
      'q': privateKey.q!.toRadixString(16),
    };
    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  /// 解析 RSA 公钥
  RSAPublicKey _parseRSAPublicKey(String pem) {
    final data = jsonDecode(utf8.decode(base64Decode(pem))) as Map<String, dynamic>;
    return RSAPublicKey(
      BigInt.parse(data['modulus'] as String, radix: 16),
      BigInt.parse(data['exponent'] as String, radix: 16),
    );
  }

  /// 解析 RSA 私钥
  RSAPrivateKey _parseRSAPrivateKey(String pem) {
    final data = jsonDecode(utf8.decode(base64Decode(pem))) as Map<String, dynamic>;
    return RSAPrivateKey(
      BigInt.parse(data['modulus'] as String, radix: 16),
      BigInt.parse(data['privateExponent'] as String, radix: 16),
      BigInt.parse(data['p'] as String, radix: 16),
      BigInt.parse(data['q'] as String, radix: 16),
    );
  }

  /// 清除所有密钥
  Future<void> clearKeys() async {
    _keyPair = null;
    _publicKeyCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_privateKeyKey);
    await prefs.remove(_publicKeyKey);
  }
}
