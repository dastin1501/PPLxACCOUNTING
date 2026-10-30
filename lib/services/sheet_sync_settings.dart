import 'package:shared_preferences/shared_preferences.dart';

/// Web app URL and shared secret, kept on this device only.
class SheetSyncConfig {
  const SheetSyncConfig({required this.webAppUrl, required this.secret});

  final String webAppUrl;
  final String secret;

  bool get isReady => webAppUrl.trim().isNotEmpty && secret.trim().isNotEmpty;
}

class SheetSyncSettings {
  static const _urlKey = 'sheet_web_app_url';
  static const _secretKey = 'sheet_secret';
  static const _lastSyncKey = 'sheet_last_sync';
  static const _lastMessageKey = 'sheet_last_message';

  static Future<SheetSyncConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SheetSyncConfig(
      webAppUrl: prefs.getString(_urlKey) ?? '',
      secret: prefs.getString(_secretKey) ?? '',
    );
  }

  static Future<void> save({required String webAppUrl, required String secret}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, webAppUrl.trim());
    await prefs.setString(_secretKey, secret.trim());
  }

  static Future<String?> lastSyncIso() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  static Future<String?> lastMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastMessageKey);
  }

  static Future<void> remember(String message, {required bool ok}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastMessageKey, message);
    if (ok) {
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
    }
  }
}
