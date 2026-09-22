import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Native struct for Windows DataBlob (DATA_BLOB)
final class DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef CryptProtectDataNative = Int32 Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef CryptProtectDataDart = int Function(
  Pointer<DataBlob> pDataIn,
  Pointer<Void> szDataDescr,
  Pointer<DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<DataBlob> pDataOut,
);

typedef LocalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

class SecureStorageService {
  static const _activeProviderKey = 'khwarizmi_active_provider';
  static const _geminiModelKey = 'khwarizmi_gemini_model';

  // Windows DPAPI Functions
  static CryptProtectDataDart? _cryptProtect;
  static CryptProtectDataDart? _cryptUnprotect;
  static LocalFreeDart? _localFree;
  static bool _dpapiInitialized = false;

  static void _initDpapi() {
    if (_dpapiInitialized) return;
    _dpapiInitialized = true;

    if (!Platform.isWindows) return;

    try {
      final crypt32 = DynamicLibrary.open('crypt32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      _cryptProtect = crypt32
          .lookup<NativeFunction<CryptProtectDataNative>>('CryptProtectData')
          .asFunction<CryptProtectDataDart>();

      _cryptUnprotect = crypt32
          .lookup<NativeFunction<CryptProtectDataNative>>('CryptUnprotectData')
          .asFunction<CryptProtectDataDart>();

      _localFree = kernel32
          .lookup<NativeFunction<LocalFreeNative>>('LocalFree')
          .asFunction<LocalFreeDart>();
    } catch (e) {
      debugPrint('DPAPI initialization failed: $e');
    }
  }

  /// Encrypts plaintext using Windows DPAPI (tied to current Windows user login)
  static String? _encrypt(String plainText) {
    _initDpapi();
    if (_cryptProtect == null || _localFree == null) {
      // Fallback: base64 if not on Windows
      return base64Encode(utf8.encode(plainText));
    }

    final rawBytes = utf8.encode(plainText);
    final inBytesPtr = malloc<Uint8>(rawBytes.length);
    for (var i = 0; i < rawBytes.length; i++) {
      inBytesPtr[i] = rawBytes[i];
    }

    final inBlob = malloc<DataBlob>();
    inBlob.ref.cbData = rawBytes.length;
    inBlob.ref.pbData = inBytesPtr;

    final outBlob = malloc<DataBlob>();
    outBlob.ref.cbData = 0;
    outBlob.ref.pbData = nullptr;

    try {
      // 1 = CRYPTPROTECT_UI_FORBIDDEN
      final success = _cryptProtect!(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        1,
        outBlob,
      );

      if (success != 0 && outBlob.ref.cbData > 0) {
        final length = outBlob.ref.cbData;
        final cipherBytes = Uint8List(length);
        for (var i = 0; i < length; i++) {
          cipherBytes[i] = outBlob.ref.pbData[i];
        }
        _localFree!(outBlob.ref.pbData.cast());
        return base64Encode(cipherBytes);
      }
    } catch (e) {
      debugPrint('DPAPI encryption error: $e');
    } finally {
      malloc.free(inBytesPtr);
      malloc.free(inBlob);
      malloc.free(outBlob);
    }
    return null;
  }

  /// Decrypts ciphertext using Windows DPAPI
  static String? _decrypt(String cipherBase64) {
    _initDpapi();
    if (_cryptUnprotect == null || _localFree == null) {
      try {
        return utf8.decode(base64Decode(cipherBase64));
      } catch (_) {
        return null;
      }
    }

    Uint8List cipherBytes;
    try {
      cipherBytes = base64Decode(cipherBase64);
    } catch (_) {
      return null;
    }

    final inBytesPtr = malloc<Uint8>(cipherBytes.length);
    for (var i = 0; i < cipherBytes.length; i++) {
      inBytesPtr[i] = cipherBytes[i];
    }

    final inBlob = malloc<DataBlob>();
    inBlob.ref.cbData = cipherBytes.length;
    inBlob.ref.pbData = inBytesPtr;

    final outBlob = malloc<DataBlob>();
    outBlob.ref.cbData = 0;
    outBlob.ref.pbData = nullptr;

    try {
      final success = _cryptUnprotect!(
        inBlob,
        nullptr,
        nullptr,
        nullptr,
        nullptr,
        1,
        outBlob,
      );

      if (success != 0 && outBlob.ref.cbData > 0) {
        final length = outBlob.ref.cbData;
        final plainBytes = Uint8List(length);
        for (var i = 0; i < length; i++) {
          plainBytes[i] = outBlob.ref.pbData[i];
        }
        _localFree!(outBlob.ref.pbData.cast());
        return utf8.decode(plainBytes);
      }
    } catch (e) {
      debugPrint('DPAPI decryption error: $e');
    } finally {
      malloc.free(inBytesPtr);
      malloc.free(inBlob);
      malloc.free(outBlob);
    }
    return null;
  }

  // API Key Storage (Encrypted on disk)
  static Future<void> saveApiKey(String providerId, String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = _encrypt(key.trim());
    if (encrypted != null) {
      await prefs.setString(_getStorageKey(providerId), encrypted);
    }
  }

  static Future<String?> getApiKey(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(_getStorageKey(providerId));
    if (encrypted == null || encrypted.isEmpty) return null;
    return _decrypt(encrypted);
  }

  static Future<void> deleteApiKey(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_getStorageKey(providerId));
  }

  static String _getStorageKey(String providerId) {
    return 'khwarizmi_enc_${providerId.toLowerCase()}_api_key';
  }

  // Non-sensitive settings
  static Future<void> setActiveProvider(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProviderKey, providerId);
  }

  static Future<String> getActiveProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeProviderKey) ?? 'gemini';
  }

  static Future<void> setGeminiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_geminiModelKey, model);
  }

  static Future<String> getGeminiModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_geminiModelKey) ?? 'gemini-3.8-flash';
  }

  static Future<void> setProviderModel(String providerId, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('khwarizmi_model_${providerId.toLowerCase()}', model);
  }

  static Future<String?> getProviderModel(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('khwarizmi_model_${providerId.toLowerCase()}');
  }

  static const _customProvidersKey = 'khwarizmi_custom_providers_json';

  static Future<void> saveCustomProvidersJson(String jsonStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customProvidersKey, jsonStr);
  }

  static Future<String?> getCustomProvidersJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customProvidersKey);
  }

  // ── Search Provider Storage ───────────────────────────────────────────────
  // Brave API key is stored encrypted via saveApiKey('brave_search', ...).
  // Custom search URL and display name are non-sensitive → SharedPreferences.

  static const _customSearchUrlKey = 'khwarizmi_custom_search_url';
  static const _customSearchNameKey = 'khwarizmi_custom_search_name';

  static Future<void> saveCustomSearchUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customSearchUrlKey, url);
  }

  static Future<String?> getCustomSearchUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_customSearchUrlKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> saveCustomSearchName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customSearchNameKey, name);
  }

  static Future<String?> getCustomSearchName() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_customSearchNameKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  // ── File System & Browser Storage ──────────────────────────────────────────
  static const _allowedFilesDirKey = 'khwarizmi_allowed_files_dir';

  static Future<void> saveAllowedFilesDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_allowedFilesDirKey, path);
  }

  static Future<String?> getAllowedFilesDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_allowedFilesDirKey);
  }

  static Future<void> saveEncryptedBrowserCredential(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = _encrypt(value);
    if (encrypted != null) {
      await prefs.setString('khwarizmi_browser_cred_$key', encrypted);
    }
  }

  static Future<String?> getEncryptedBrowserCredential(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString('khwarizmi_browser_cred_$key');
    if (encrypted == null || encrypted.isEmpty) return null;
    return _decrypt(encrypted);
  }

  static Future<void> deleteEncryptedBrowserCredential(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('khwarizmi_browser_cred_$key');
  }
}
