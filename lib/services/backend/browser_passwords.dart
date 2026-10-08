import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:win32/win32.dart';

/// Windows: lets the OpenBubbles Passwords browser extension (browser_extension/) fill iCloud
/// passwords on websites.
///
/// Chrome/Edge start openbubbles_password_host.exe for that extension only (the host manifest
/// written here allows just its fixed ID). The host relays the extension's messages to the loopback
/// server below, first proving itself with a random per-launch token stored in
/// %LOCALAPPDATA%\OpenBubbles\browser-bridge.txt, which only this Windows user can read.
///
/// The page address comes from the browser, not the page, and a password is only handed out for
/// the site it was saved for.
class BrowserPasswords {
  static const extensionId = "odfmlmhmmoamgcgboaclpookgfjnehin";
  static const hostName = "com.openbubbles.passwords";
  static const _authWindow = Duration(minutes: 10);
  static const _maxFrame = 1024 * 1024;

  static ServerSocket? _server;
  static String? _token;
  static DateTime? _authorizedUntil;
  static Future<bool>? _authInFlight;

  static bool get supported => !kIsWeb && Platform.isWindows;

  /// Folder users pick in the browser's "Load unpacked".
  static String get extensionDir => p.join(p.dirname(Platform.resolvedExecutable), "browser_extension");
  static String get _hostExe => p.join(p.dirname(Platform.resolvedExecutable), "openbubbles_password_host.exe");
  static String get _dataDir => p.join(Platform.environment["LOCALAPPDATA"] ?? "", "OpenBubbles");
  static File get _bridgeFile => File(p.join(_dataDir, "browser-bridge.txt"));

  static bool get running => _server != null;

  static Future<void> start() async {
    if (!supported || _server != null || !ss.settings.browserPasswordFill.value) return;
    if ((Platform.environment["LOCALAPPDATA"] ?? "").isEmpty) return;
    try {
      final random = Random.secure();
      _token = List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, "0")).join();
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _server!.listen(_handleClient);
      await Directory(_dataDir).create(recursive: true);
      await _bridgeFile.writeAsString("${_server!.port}\n$_token\n", flush: true);
      await _registerHost();
      Logger.info("Browser password bridge listening on ${_server!.port}");
    } catch (e, s) {
      Logger.error("Couldn't start the browser password bridge", error: e, trace: s);
      await stop();
    }
  }

  static Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _authorizedUntil = null;
    await server?.close();
    try {
      if (await _bridgeFile.exists()) await _bridgeFile.delete();
    } catch (_) {}
  }

  static Future<void> setEnabled(bool enabled) async {
    ss.settings.browserPasswordFill.value = enabled;
    await ss.saveSettings();
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  // ---------- native messaging host registration ----------

  static Future<void> _registerHost() async {
    final manifest = File(p.join(_dataDir, "$hostName.json"));
    await manifest.writeAsString(jsonEncode({
      "name": hostName,
      "description": "OpenBubbles Passwords",
      "path": _hostExe,
      "type": "stdio",
      "allowed_origins": ["chrome-extension://$extensionId/"],
    }));
    for (final browserKey in const [
      r"Software\Google\Chrome\NativeMessagingHosts",
      r"Software\Microsoft\Edge\NativeMessagingHosts",
      r"Software\BraveSoftware\Brave-Browser\NativeMessagingHosts",
    ]) {
      _setRegistryDefault("$browserKey\\$hostName", manifest.path);
    }
  }

  static void _setRegistryDefault(String subKey, String value) {
    final key = calloc<IntPtr>();
    final subKeyPtr = subKey.toNativeUtf16();
    final valuePtr = value.toNativeUtf16();
    try {
      final created = RegCreateKeyEx(HKEY_CURRENT_USER, subKeyPtr, 0, nullptr,
          REG_OPEN_CREATE_OPTIONS.REG_OPTION_NON_VOLATILE, REG_SAM_FLAGS.KEY_SET_VALUE, nullptr, key, nullptr);
      if (created != ERROR_SUCCESS) {
        Logger.warn("Couldn't register browser host at $subKey ($created)");
        return;
      }
      RegSetValueEx(key.value, nullptr, 0, REG_VALUE_TYPE.REG_SZ, valuePtr.cast<Uint8>(), (value.length + 1) * 2);
      RegCloseKey(key.value);
    } finally {
      calloc.free(key);
      calloc.free(subKeyPtr);
      calloc.free(valuePtr);
    }
  }

  // ---------- connection handling ----------

  static void _handleClient(Socket socket) {
    var buffer = BytesBuilder(copy: false);
    var authenticated = false;

    void send(Map<String, dynamic> message) {
      final body = utf8.encode(jsonEncode(message));
      final header = ByteData(4)..setUint32(0, body.length, Endian.little);
      socket.add(header.buffer.asUint8List());
      socket.add(body);
    }

    Future<void> handle(Map<String, dynamic> message) async {
      if (!authenticated) {
        if (message["type"] == "hello" &&
            _token != null &&
            _constantTimeEquals(message["token"]?.toString() ?? "", _token!) &&
            message["origin"] == "chrome-extension://$extensionId/") {
          authenticated = true;
        } else {
          socket.destroy();
        }
        return;
      }
      final id = message["id"];
      try {
        final result = await _handleRequest(message);
        send({"id": id, "result": result});
      } on _BridgeError catch (e) {
        send({"id": id, "error": e.code});
      } catch (e, s) {
        Logger.error("Browser password request failed", error: e, trace: s);
        send({"id": id, "error": "failed"});
      }
    }

    socket.listen((data) {
      buffer.add(data);
      var bytes = buffer.takeBytes();
      while (bytes.length >= 4) {
        final length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
        if (length > _maxFrame) {
          socket.destroy();
          return;
        }
        if (bytes.length < 4 + length) break;
        final frame = bytes.sublist(4, 4 + length);
        bytes = bytes.sublist(4 + length);
        try {
          final decoded = jsonDecode(utf8.decode(frame));
          if (decoded is Map<String, dynamic>) handle(decoded);
        } catch (_) {
          socket.destroy();
          return;
        }
      }
      buffer = BytesBuilder(copy: false)..add(bytes);
    }, onError: (_) => socket.destroy(), cancelOnError: true);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ---------- requests ----------

  static Future<Map<String, dynamic>> _handleRequest(Map<String, dynamic> message) async {
    if (!ss.settings.browserPasswordFill.value) throw _BridgeError("disabled");
    switch (message["type"]) {
      case "status":
        final passwords = await _passwords();
        return {"count": passwords.length};
      case "lookup":
        final host = _pageHost(message["url"]);
        if (host == null) return {"accounts": []};
        final matches = await _matches(host);
        return {
          "accounts": matches
              .take(8)
              .map((m) => {"id": m.id, "username": m.entry.acct, "site": _siteHost(m.entry.srvr)})
              .toList(),
        };
      case "fill":
        final host = _pageHost(message["url"]);
        final credentialId = message["credentialId"]?.toString();
        if (host == null || credentialId == null) throw _BridgeError("not_found");
        final match = (await _matches(host)).firstWhereOrNull((m) => m.id == credentialId);
        // only hand out a password for the site it was saved for
        if (match == null) throw _BridgeError("not_found");
        if (!await _authorize(host)) throw _BridgeError("denied");
        return {
          "username": match.entry.acct,
          "password": utf8.decode(match.entry.data, allowMalformed: true),
        };
      default:
        throw _BridgeError("unknown");
    }
  }

  static Future<Map<String, (String?, api.PasswordRawEntry)>> _passwords() async {
    final manager = pushService.state?.icloudServices?.passwords;
    if (manager == null || !pushService.cachedInClique) throw _BridgeError("not_ready");
    return await api.getPasswords(passwords: manager);
  }

  static Future<List<_Match>> _matches(String pageHost) async {
    final passwords = await _passwords();
    final pageSite = _registrable(pageHost);
    final manager = pushService.state!.icloudServices!.passwords!;

    // extra domains a password was saved for ("Also used on ...")
    final altDomains = <String, Set<String>>{};
    try {
      final metas = await api.getPasswordsMeta(passwords: manager);
      for (final meta in metas.values) {
        final data = meta.$2.getPasswordData();
        if (data.altDomains.isEmpty) continue;
        altDomains
            .putIfAbsent("${_registrable(_siteHost(meta.$2.srvr))}|${meta.$2.acct}", () => {})
            .addAll(data.altDomains.map((d) => _registrable(_siteHost(d.domain))));
      }
    } catch (_) {}

    final matches = <_Match>[];
    for (final entry in passwords.entries) {
      final password = entry.value.$2;
      final host = _siteHost(password.srvr);
      if (host.isEmpty) continue;
      final site = _registrable(host);
      int score;
      if (host == pageHost) {
        score = 3;
      } else if (site == pageSite) {
        score = 2;
      } else if (altDomains["$site|${password.acct}"]?.contains(pageSite) ?? false) {
        score = 1;
      } else {
        continue;
      }
      matches.add(_Match(entry.key, password, score));
    }
    matches.sort((a, b) => a.score != b.score ? b.score - a.score : b.entry.mdat - a.entry.mdat);
    return matches;
  }

  /// Optional Windows Hello check, remembered for a few minutes.
  static Future<bool> _authorize(String host) async {
    if (!ss.settings.browserPasswordFillRequireAuth.value) return true;
    final until = _authorizedUntil;
    if (until != null && DateTime.now().isBefore(until)) return true;
    _authInFlight ??= () async {
      try {
        final auth = LocalAuthentication();
        if (!await auth.isDeviceSupported()) return true;
        return await auth.authenticate(localizedReason: "Fill your password for $host");
      } catch (e) {
        Logger.warn("Windows Hello failed: $e");
        return false;
      }
    }();
    final ok = await _authInFlight!;
    _authInFlight = null;
    if (ok) _authorizedUntil = DateTime.now().add(_authWindow);
    return ok;
  }

  // ---------- site matching ----------

  static String? _pageHost(dynamic url) {
    final uri = Uri.tryParse(url?.toString() ?? "");
    if (uri == null || (uri.scheme != "https" && uri.scheme != "http") || uri.host.isEmpty) return null;
    return _stripWww(uri.host.toLowerCase());
  }

  static String _siteHost(String server) {
    var s = server.trim().toLowerCase();
    if (s.contains("://")) s = Uri.tryParse(s)?.host ?? s;
    s = s.split("/").first.split(":").first;
    return _stripWww(s);
  }

  static String _stripWww(String host) => host.startsWith("www.") ? host.substring(4) : host;

  static const _twoPartSuffixes = {
    "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "com.br",
    "com.mx", "com.ar", "com.co", "co.in", "co.za", "com.tr", "com.cn", "com.hk", "com.sg", "com.tw",
  };

  /// The part of a host name a site owns (e.g. "accounts.google.com" -> "google.com").
  static String _registrable(String host) {
    if (InternetAddress.tryParse(host) != null) return host;
    final parts = host.split(".");
    if (parts.length <= 2) return host;
    final lastTwo = parts.sublist(parts.length - 2).join(".");
    if (_twoPartSuffixes.contains(lastTwo)) return parts.sublist(parts.length - 3).join(".");
    return lastTwo;
  }
}

class _Match {
  _Match(this.id, this.entry, this.score);
  final String id;
  final api.PasswordRawEntry entry;
  final int score;
}

class _BridgeError implements Exception {
  _BridgeError(this.code);
  final String code;
}
