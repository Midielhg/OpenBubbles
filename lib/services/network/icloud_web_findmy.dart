import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/database/global/findmy_device.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:uuid/uuid.dart';

/// Find My devices through an icloud.com web session: the fallback for when the relay Mac is offline.
///
/// The normal Find My path signs in to iCloud like an Apple device, which needs validation data from
/// the relay Mac. icloud.com's own Find Devices page only needs an Apple ID session, so the user signs
/// in on Apple's page in a WebView (the app never sees the password or code) and this reads devices
/// with that session's cookies. The WebView profile lives in app data, so "Keep me signed in" keeps
/// working across restarts and reinstalls. Web Find My has no People tab, so friends aren't covered.
class ICloudWebFindMy {
  static const _kConnected = "icloudWebFindMyConnected";
  static const _setup = "https://setup.icloud.com/setup/ws/1";
  static const _origin = "https://www.icloud.com";
  static const _findUrl = "https://www.icloud.com/find/";
  static const _build = "2420Hotfix12";
  static final _clientId = const Uuid().v4().toUpperCase();

  static bool get supported => Platform.isWindows;
  static bool get connected => supported && (ss.prefs.getBool(_kConnected) ?? false);
  static final RxBool connectedRx = RxBool(connected);

  static WebViewEnvironment? _env;
  static Future<WebViewEnvironment> environment() async =>
      _env ??= await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(userDataFolder: p.join(fs.appDocDir.path, "icloud_web")));

  static List<FindMyDevice>? _cache;
  static DateTime? _cacheTime;

  static Future<void> _setConnected(bool value) async {
    await ss.prefs.setBool(_kConnected, value);
    connectedRx.value = value;
  }

  static Future<void> signOut() async {
    await _setConnected(false);
    _cache = null;
    try {
      await CookieManager.instance(webViewEnvironment: await environment()).deleteAllCookies();
    } catch (e) {
      Logger.warn("Failed to clear icloud.com cookies: $e");
    }
  }

  /// Opens Apple's icloud.com sign-in. Resolves true once a Find My device list could be read.
  static Future<bool> signIn(BuildContext context) async {
    final env = await environment();
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _SignInPage(env: env)));
    return ok ?? false;
  }

  /// Devices from icloud.com, or null if there's no usable session. Results are reused for a minute,
  /// since the Find My page polls every few seconds.
  static Future<List<FindMyDevice>?> fetchDevices({bool allowReauth = true}) async {
    if (!connected) return null;
    if (_cache != null && _cacheTime != null && DateTime.now().difference(_cacheTime!) < const Duration(minutes: 1)) {
      return _cache;
    }
    var devices = await _tryFetch();
    if (devices == null && allowReauth) {
      // let icloud.com renew its own session from the saved "Keep me signed in" state
      await _silentReauth();
      devices = await _tryFetch();
    }
    if (devices != null) {
      _cache = devices;
      _cacheTime = DateTime.now();
    }
    return devices;
  }

  static Future<List<FindMyDevice>?> _tryFetch() async {
    try {
      final account = await _post("$_setup/validate?clientBuildNumber=$_build&clientMasteringNumber=$_build&clientId=$_clientId", "null");
      if (account == null) return null;
      final findme = account["webservices"]?["findme"]?["url"] as String?;
      final dsid = account["dsInfo"]?["dsid"]?.toString();
      if (findme == null || dsid == null) {
        Logger.warn("icloud.com session has no Find My service");
        return null;
      }
      final result = await _post(
        "$findme/fmipservice/client/web/refreshClient?clientBuildNumber=$_build&clientMasteringNumber=$_build&clientId=$_clientId&dsid=$dsid",
        jsonEncode({
          "clientContext": {
            "appName": "iCloud Find (Web)",
            "appVersion": "2.0",
            "apiVersion": "3.0",
            "deviceListVersion": 1,
            "fmly": true,
            "shouldLocate": true,
            "selectedDevice": "all"
          }
        }),
      );
      final content = result?["content"];
      if (content is! List) return null;
      return content.whereType<Map>().map((e) => FindMyDevice.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e, s) {
      Logger.error("icloud.com Find My request failed", error: e, trace: s);
      return null;
    }
  }

  /// POST with the WebView session's cookies. Returns the decoded JSON, or null when the session isn't
  /// accepted. Cookies Apple rotates are written back so the WebView profile stays current.
  static Future<Map<String, dynamic>?> _post(String url, String body) async {
    final uri = Uri.parse(url);
    final cookieManager = CookieManager.instance(webViewEnvironment: await environment());
    final cookies = await cookieManager.getCookies(url: WebUri(url));
    if (cookies.isEmpty) return null;

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..set("Origin", _origin)
        ..set("Referer", "$_origin/")
        ..set("Content-Type", "text/plain")
        ..set("Accept", "*/*")
        ..set("Cookie", cookies.map((c) => "${c.name}=${c.value}").join("; "));
      request.write(body);
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

      for (final c in response.cookies) {
        await cookieManager.setCookie(
          url: WebUri("https://${uri.host}/"),
          name: c.name,
          value: c.value,
          domain: c.domain ?? uri.host,
          path: c.path ?? "/",
          expiresDate: c.expires?.millisecondsSinceEpoch,
          isSecure: c.secure,
          isHttpOnly: c.httpOnly,
        );
      }

      if (response.statusCode != 200) {
        Logger.info("icloud.com ${uri.path} returned ${response.statusCode}");
        return null;
      }
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } finally {
      client.close();
    }
  }

  static Future<void> _silentReauth() async {
    final done = Completer<void>();
    final webView = HeadlessInAppWebView(
      webViewEnvironment: await environment(),
      initialUrlRequest: URLRequest(url: WebUri(_findUrl)),
      onLoadStop: (controller, url) {
        // the page validates or renews its session with XHRs right after loading
        Future.delayed(const Duration(seconds: 6), () {
          if (!done.isCompleted) done.complete();
        });
      },
    );
    try {
      await webView.run();
      await done.future.timeout(const Duration(seconds: 25), onTimeout: () {});
    } catch (e) {
      Logger.warn("icloud.com silent re-auth failed: $e");
    } finally {
      await webView.dispose();
    }
  }
}

class _SignInPage extends StatefulWidget {
  const _SignInPage({required this.env});
  final WebViewEnvironment env;

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // done once the session can actually read Find My, not merely once a cookie shows up
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final cookies = await CookieManager.instance(webViewEnvironment: widget.env).getCookies(url: WebUri("https://setup.icloud.com/"));
      if (!cookies.any((c) => c.name == "X-APPLE-WEBAUTH-TOKEN")) return;
      await ICloudWebFindMy._setConnected(true);
      final devices = await ICloudWebFindMy.fetchDevices(allowReauth: false);
      if (devices == null) {
        await ICloudWebFindMy._setConnected(false);
        return;
      }
      _poll?.cancel();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sign in with iCloud.com"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              "Sign in on Apple's page and check \"Keep me signed in\". This window closes by itself once your devices can be read.",
              style: context.theme.textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: InAppWebView(
        webViewEnvironment: widget.env,
        initialUrlRequest: URLRequest(url: WebUri(ICloudWebFindMy._findUrl)),
      ),
    );
  }
}
