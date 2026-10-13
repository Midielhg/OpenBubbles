import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

/// A release on GitHub newer than the running app.
class AppUpdate {
  AppUpdate({required this.version, required this.url, required this.size, required this.sha256, required this.pageUrl});
  final String version;
  final String url;
  final int size;
  final String? sha256;
  final String pageUrl;
}

/// Self-update for the Windows build: checks this fork's GitHub Releases (built by
/// .github/workflows/windows-release.yml), asks before doing anything, then downloads the installer,
/// verifies it, and runs it silently. The installer reopens the app when it's done.
class AppUpdater {
  static const _repo = "Midielhg/OpenBubbles";
  static const _kSnoozed = "updateSnoozedVersion";
  static final _dio = Dio(BaseOptions(validateStatus: (_) => true, headers: {"Accept": "application/vnd.github+json"}));

  static final Rxn<AppUpdate> available = Rxn<AppUpdate>();
  static final RxnDouble progress = RxnDouble();
  static Timer? _timer;
  static LocalNotification? _toast;

  static bool get supported => Platform.isWindows && !kDebugMode;

  /// Starts background checks: shortly after launch, then every 6 hours.
  static void start() {
    if (!supported || _timer != null) return;
    Future.delayed(const Duration(seconds: 30), () => check());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => check());
  }

  /// [userInitiated] also reports "up to date" and ignores a snoozed version.
  static Future<AppUpdate?> check({bool userInitiated = false}) async {
    if (!Platform.isWindows) return null;
    try {
      final current = (await PackageInfo.fromPlatform()).version;
      final res = await _dio.get("https://api.github.com/repos/$_repo/releases/latest");
      ({String version, AppUpdate? update})? latest;
      if (res.statusCode == 200 && res.data is Map) {
        latest = _fromApi(res.data as Map);
      } else {
        // GitHub's API allows ~60 unauthenticated requests an hour per network (403 once used up,
        // e.g. on an office connection); the regular releases pages have no such limit
        Logger.warn("GitHub API returned ${res.statusCode}; checking the releases page instead");
        latest = await _fromWebsite();
      }
      if (latest == null) {
        if (userInitiated) showSnackbar("Updates", "Couldn't check for updates (${res.statusCode})");
        return null;
      }
      if (!_isNewer(latest.version, current)) {
        available.value = null;
        if (userInitiated) showSnackbar("Updates", "You're on the latest version ($current)");
        return null;
      }
      final update = latest.update;
      if (update == null) return null;
      available.value = update;
      if (userInitiated || ss.prefs.getString(_kSnoozed) != update.version) _notify(update);
      return update;
    } catch (e, s) {
      Logger.warn("Update check failed", error: e, trace: s);
      if (userInitiated) showSnackbar("Updates", "Couldn't check for updates");
      return null;
    }
  }

  static bool _isSetup(String name) => name.startsWith("OpenBubbles-Desktop-Setup") && name.endsWith(".exe");

  static ({String version, AppUpdate? update}) _fromApi(Map data) {
    final latest = (data["tag_name"] ?? "").toString().replaceFirst(RegExp(r'^v'), "");
    final asset = ((data["assets"] as List?) ?? []).cast<Map>().firstWhereOrNull((a) => _isSetup((a["name"] ?? "").toString()));
    if (asset == null) return (version: latest, update: null);
    final digest = asset["digest"]?.toString();
    return (
      version: latest,
      update: AppUpdate(
        version: latest,
        url: asset["browser_download_url"].toString(),
        size: (asset["size"] as num?)?.toInt() ?? 0,
        sha256: digest != null && digest.startsWith("sha256:") ? digest.substring(7).toLowerCase() : null,
        pageUrl: (data["html_url"] ?? "https://github.com/$_repo/releases").toString(),
      ),
    );
  }

  /// The same details from github.com: /releases/latest redirects to the newest tag, and the
  /// release's asset list names the installer with its SHA-256.
  static Future<({String version, AppUpdate? update})?> _fromWebsite() async {
    final web = Dio(BaseOptions(validateStatus: (_) => true, followRedirects: false));
    final redirect = await web.get("https://github.com/$_repo/releases/latest");
    final location = redirect.headers.value("location") ?? "";
    final tag = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location)?.group(1);
    if (tag == null) return null;
    final latest = Uri.decodeComponent(tag).replaceFirst(RegExp(r'^v'), "");
    final assets = await web.get<String>("https://github.com/$_repo/releases/expanded_assets/$tag",
        options: Options(responseType: ResponseType.plain));
    final html = assets.statusCode == 200 ? assets.data ?? "" : "";
    final name = RegExp(r'OpenBubbles-Desktop-Setup-[\w.\-]+?\.exe').firstMatch(html)?.group(0);
    if (name == null || !_isSetup(name)) return (version: latest, update: null);
    // the digest listed after the installer's name
    final after = html.substring(html.indexOf(name));
    final digest = RegExp(r'sha256:([0-9a-f]{64})').firstMatch(after)?.group(1);
    return (
      version: latest,
      update: AppUpdate(
        version: latest,
        url: "https://github.com/$_repo/releases/download/$tag/$name",
        size: 0,
        sha256: digest,
        pageUrl: "https://github.com/$_repo/releases/tag/$tag",
      ),
    );
  }

  /// "1.15.12" vs "1.15.3": numeric per part; tags with extra suffixes (v1.15.0-desktop.1) compare by
  /// their numeric prefix.
  static bool _isNewer(String latest, String current) {
    List<int> parts(String v) => RegExp(r'\d+').allMatches(v.split(RegExp(r'[-+]')).first).map((m) => int.parse(m[0]!)).toList();
    final a = parts(latest), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static void _notify(AppUpdate update) {
    _toast?.close();
    _toast = LocalNotification(
      title: "OpenBubbles update available",
      body: "Version ${update.version} is ready to install.",
      duration: LocalNotificationDuration.long,
      actions: [LocalNotificationAction(text: "Update now"), LocalNotificationAction(text: "Later")],
    );
    _toast!.onClickAction = (i) => i == 0 ? install(update) : snooze(update);
    _toast!.show();
  }

  /// "Later": don't notify again for this version (the Settings banner stays).
  static Future<void> snooze(AppUpdate update) => ss.prefs.setString(_kSnoozed, update.version);

  static Future<void> install(AppUpdate update) async {
    if (progress.value != null) return;
    final file = File(p.join((await Directory.systemTemp.createTemp("openbubbles-update")).path, "OpenBubbles-Desktop-Setup-${update.version}.exe"));
    try {
      progress.value = 0;
      showSnackbar("Updating", "Downloading OpenBubbles ${update.version}...");
      final res = await Dio().download(update.url, file.path,
          onReceiveProgress: (got, total) => progress.value = total > 0 ? got / total : null);
      if (res.statusCode != 200) throw "download returned ${res.statusCode}";
      final bytes = await file.readAsBytes();
      if (update.size > 0 && bytes.length != update.size) throw "incomplete download (${bytes.length} of ${update.size} bytes)";
      if (update.sha256 != null && sha256.convert(bytes).toString() != update.sha256) throw "checksum mismatch";

      Logger.info("Installing update ${update.version}");
      // silent install into the existing install folder; the installer closes this app and reopens it
      await Process.start(file.path, ["/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/CLOSEAPPLICATIONS"],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } catch (e) {
      Logger.error("Update failed: $e");
      progress.value = null;
      showSnackbar("Update failed", "$e. You can download it from GitHub Releases instead.");
    }
  }
}
