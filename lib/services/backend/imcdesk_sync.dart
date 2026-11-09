import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/recently_deleted_store.dart';
import 'package:bluebubbles/services/backend/browser_passwords.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

/// A login on the IMCDesk side, as its sync API lists it (no password, only a fingerprint).
class ImcAccount {
  ImcAccount(Map m)
      : id = m["id"].toString(),
        username = (m["username"] ?? "").toString(),
        url = (m["url"] ?? "").toString(),
        host = (m["host"] ?? "").toString(),
        provider = (m["provider"] ?? "").toString(),
        changedAt = DateTime.tryParse((m["changedAt"] ?? "").toString()),
        fingerprint = (m["fingerprint"] ?? "").toString(),
        addedBySync = m["addedBySync"] == true;

  final String id;
  final String username;
  final String url;
  final String host;
  final String provider;
  final DateTime? changedAt;
  final String fingerprint;
  final bool addedBySync;
}

/// Two-way password sync with IMCDesk (Asset Management → Passwords), for logins whose user name ends in
/// @imcequitygroup.com. A password change on either side is copied to the other; when both sides changed
/// since the last sync, the newer change wins. Personal logins never leave Keychain.
///
/// Deletions only go ONE way: a login deleted in IMCDesk is deleted here (kept in Recently Deleted), but a
/// login removed from Keychain (iPhone, Apple account, OpenBubbles) is NEVER deleted from IMCDesk — IMCDesk
/// is the company's record, and its sync API has no delete at all. The link is just paused until the login
/// comes back to Keychain, and it isn't re-added to Keychain on its own.
///
/// Each linked pair remembers the password fingerprint both sides had at the last sync, so a sync can tell
/// which side changed. Deletions only follow for logins that were already linked, never on a run where
/// either side couldn't be read, and a run that would delete more than a few is held for the user to
/// confirm in Settings.
class ImcDeskSync {
  static const domain = "imcequitygroup.com";
  static const _every = Duration(minutes: 5);
  static const _microsoftSites = {"microsoftonline.com", "microsoft.com", "office.com", "office365.com", "live.com", "outlook.com", "azure.com"};

  static bool get supported => Platform.isWindows;

  static final RxBool connected = false.obs;
  static final RxString server = "".obs;
  static final RxBool running = false.obs;
  static final RxString status = "".obs;
  static final Rxn<DateTime> lastSync = Rxn<DateTime>();
  static final RxInt linkedCount = 0.obs;
  static final RxList<String> activity = <String>[].obs;

  /// Deletions from IMCDesk held back for the user to confirm: "kc:<imc id>".
  static final RxList<String> heldDeletes = <String>[].obs;
  static final RxList<String> heldDeleteNames = <String>[].obs;

  static Map<String, dynamic> _state = {};
  static Timer? _timer;
  static bool _approveHeld = false;

  static File get _file =>
      File(p.join(Platform.environment["LOCALAPPDATA"] ?? "", "OpenBubbles", "imcdesk-sync.bin"));

  static bool inScope(String username) {
    final u = username.trim().toLowerCase();
    return u.endsWith("@$domain") && u.indexOf("@") > 0;
  }

  static String fingerprint(String key, String password) =>
      password.isEmpty ? "" : Hmac(sha256, utf8.encode(key)).convert(utf8.encode(password)).toString();

  // ---------- setup ----------

  static Future<void> start() async {
    if (!supported) return;
    await _load();
    if (!connected.value) return;
    _timer?.cancel();
    _timer = Timer.periodic(_every, (_) => syncNow());
    Future.delayed(const Duration(seconds: 45), syncNow);
  }

  /// Connects with the code IMCDesk shows (key@host). Returns an error message, or null.
  static Future<String?> connect(String code) async {
    final match = RegExp(r"^\s*(obsync_[a-f0-9]{64})@([a-z0-9.-]+(?::\d+)?)\s*$", caseSensitive: false).firstMatch(code);
    if (match == null) return "That isn't a connection code. Copy it again from IMCDesk.";
    final key = match.group(1)!, host = match.group(2)!.toLowerCase();
    try {
      await _get(host, key);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return "IMCDesk didn't accept that code. Create a new one.";
      return "Couldn't reach $host.";
    }
    _state = {"key": key, "host": host, "v": 2, "pairs": <String, dynamic>{}};
    await _save();
    connected.value = true;
    server.value = host;
    activity.clear();
    _note("Connected to $host");
    await start();
    unawaited(syncNow());
    return null;
  }

  static Future<void> disconnect() async {
    _timer?.cancel();
    _state = {};
    connected.value = false;
    server.value = "";
    status.value = "";
    linkedCount.value = 0;
    heldDeletes.clear();
    heldDeleteNames.clear();
    try {
      if (await _file.exists()) await _file.delete();
    } catch (_) {}
  }

  /// Applies (or cancels) the deletions held back by the last sync.
  static Future<void> resolveHeldDeletes(bool apply) async {
    if (apply) {
      _approveHeld = true;
    } else {
      // keep both: forget the links, so the missing side is added back on the next sync
      final pairs = _pairs;
      for (final d in heldDeletes) {
        pairs.remove(d.substring(d.indexOf(":") + 1));
      }
      await _save();
    }
    heldDeletes.clear();
    heldDeleteNames.clear();
    await syncNow();
  }

  // ---------- the sync ----------

  static Future<void> syncNow() async {
    if (!connected.value || running.value) return;
    running.value = true;
    try {
      final summary = await _run();
      status.value = summary;
      lastSync.value = DateTime.now();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        status.value = "IMCDesk revoked this connection. Connect again from Settings.";
      } else {
        status.value = "Couldn't reach IMCDesk. Will try again.";
      }
    } catch (e, s) {
      Logger.warn("IMCDesk password sync failed", error: e, trace: s);
      status.value = "Sync failed: $e";
    } finally {
      running.value = false;
      _approveHeld = false;
    }
  }

  static Map<String, dynamic> get _pairs => (_state["pairs"] as Map<String, dynamic>?) ?? (_state["pairs"] = <String, dynamic>{});

  static Future<String> _run() async {
    final manager = pushService.state?.icloudServices?.passwords;
    if (manager == null || !pushService.cachedInClique) return "Waiting for iCloud Keychain";
    final key = _state["key"] as String, host = _state["host"] as String;

    final all = await api.getPasswords(passwords: manager);
    final keychain = {
      for (final e in all.entries)
        if (inScope(e.value.$2.acct) && e.value.$2.srvr.isNotEmpty && e.value.$2.data.isNotEmpty) e.key: e.value.$2,
    };
    final imcList = (await _get(host, key))["accounts"] as List;
    final imc = {for (final a in imcList.map((m) => ImcAccount(m as Map))) if (inScope(a.username)) a.id: a};

    final pairs = _pairs;
    var pushed = 0, pulled = 0, created = 0, deleted = 0;

    // 1. logins linked before: copy changes, or follow a deletion
    final deleteInKeychain = <String>[];
    for (final imcId in pairs.keys.toList()) {
      final pair = pairs[imcId] as Map<String, dynamic>;
      final a = imc[imcId];
      var k = keychain[pair["kc"]];
      if (k == null && a != null) {
        // edited in a way that gave it a new id (moved to a shared group, say): link to it again
        final moved = _movedLogin(keychain, pairs, a.username, pair);
        if (moved != null) {
          pair["kc"] = moved;
          k = keychain[moved];
        }
      }
      if (a == null && k == null) {
        pairs.remove(imcId);
      } else if (a != null && k != null) {
        pair["seen"] = true;
        pair.remove("removedHere");
        final r = await _reconcile(host, key, pair, a, pair["kc"] as String, k);
        if (r == 1) pushed++;
        if (r == 2) pulled++;
      } else if (pair["seen"] != true) {
        // linked on the last run and not visible on one side yet (iCloud can take a moment): wait
      } else if (a == null && pair["added"] == true) {
        // a record the sync itself added, removed in IMCDesk (the duplicates clean-up): the login stays here
        pairs.remove(imcId);
      } else if (a == null) {
        deleteInKeychain.add(imcId);
      } else if (pair["removedHere"] != true) {
        // removed from Keychain: IMCDesk keeps it (see the class comment)
        pair["removedHere"] = true;
        _note("${pair["name"] ?? "A login"} was removed from your devices; it stays in IMCDesk");
      }
    }

    // deletions: never when a side came back empty (a failed read looks exactly like "everything deleted"),
    // and more than a few at once wait for the user
    final deletes = deleteInKeychain.length;
    if (deletes > 0) {
      if (all.isEmpty || imcList.isEmpty) {
        // skip this run
      } else if (deletes > 3 && !_approveHeld) {
        heldDeletes.assignAll(deleteInKeychain.map((id) => "kc:$id"));
        heldDeleteNames.assignAll([for (final id in deleteInKeychain) "${(pairs[id] as Map)["name"] ?? id}"]);
      } else {
        for (final imcId in deleteInKeychain) {
          final pair = pairs[imcId] as Map<String, dynamic>;
          await BrowserPasswords.syncDelete(pair["kc"] as String);
          pairs.remove(imcId);
          deleted++;
          _note("Deleted ${pair["name"] ?? "a login"} (deleted in IMCDesk; kept in Recently Deleted)");
        }
        heldDeletes.clear();
        heldDeleteNames.clear();
      }
    }

    // 2. logins not linked yet: link to the matching login on the other side, or add it there
    final linkedKc = {for (final pair in pairs.values) (pair as Map)["kc"] as String};
    final linkedImc = pairs.keys.toSet();
    final freeImc = imc.values.where((a) => !linkedImc.contains(a.id)).toList();

    // the oldest keychain record of a login first, so its copies for other addresses link to it
    final freeKc = keychain.entries.where((e) => !linkedKc.contains(e.key)).toList()
      ..sort((x, y) => x.value.cdat.compareTo(y.value.cdat));
    for (final e in freeKc) {
      final k = e.value;
      final site = _site(k.srvr);
      final password = utf8.decode(k.data, allowMalformed: true);
      // a copy of a login already linked (same user, site and password): nothing to do
      final isCopy = pairs.values.any((pair) {
        final other = keychain[(pair as Map)["kc"]];
        return other != null &&
            other.acct.toLowerCase() == k.acct.toLowerCase() &&
            _site(other.srvr) == site &&
            const ListEquality().equals(other.data, k.data);
      });
      if (isCopy) continue;

      final kcFp = fingerprint(key, password);
      bool sameLogin(ImcAccount a) =>
          a.username.toLowerCase() == k.acct.toLowerCase() &&
          (a.host.isNotEmpty
              ? _site(a.host) == site
              : _providerMatches(a.provider, site) || (a.fingerprint.isNotEmpty && a.fingerprint == kcFp));
      // the IMCDesk record of this login is already linked to another copy of it: nothing to add
      if (imc.values.any((a) => pairs.containsKey(a.id) && sameLogin(a))) continue;
      // the original record before one the sync added
      final match = freeImc.where(sameLogin).sortedBy<num>((a) => a.addedBySync ? 1 : 0).firstOrNull;
      if (match != null) {
        freeImc.remove(match);
        final pair = <String, dynamic>{"kc": e.key, "name": _name(k.acct, k.srvr), "site": site, "added": match.addedBySync};
        pairs[match.id] = pair;
        final r = await _reconcile(host, key, pair, match, e.key, k);
        if (r == 1) pushed++;
        if (r == 2) pulled++;
        continue;
      }
      final res = await _post(host, key, "/upsert", {
        "username": k.acct,
        "url": "https://${BrowserPasswords.siteHostOf(k.srvr)}",
        "password": password,
        "changedAt": DateTime.fromMillisecondsSinceEpoch(k.mdat).toUtc().toIso8601String(),
      });
      if (res["existed"] == true) {
        // IMCDesk already had it (its own duplicate check): link, and let the next sync settle the password
        pairs[res["id"].toString()] = {"kc": e.key, "name": _name(k.acct, k.srvr), "site": site};
        continue;
      }
      pairs[res["id"].toString()] = {"kc": e.key, "name": _name(k.acct, k.srvr), "site": site, "fp": kcFp, "added": true};
      created++;
      _note("Added ${_name(k.acct, k.srvr)} to IMCDesk");
    }

    var noWebsite = 0;
    for (final a in freeImc) {
      // came from Keychain in the first place (a duplicate waiting for the clean-up)
      if (a.addedBySync) continue;
      final site = a.host.isNotEmpty ? a.host : (_isMicrosoft(a) ? "login.microsoftonline.com" : "");
      if (site.isEmpty) {
        noWebsite++;
        continue;
      }
      // Keychain already has a login for this user and site (linked to another IMCDesk record): don't add another
      if (keychain.values.any((k) => k.acct.toLowerCase() == a.username.toLowerCase() && _site(k.srvr) == _site(site))) {
        continue;
      }
      final password = (await _post(host, key, "/reveal", {"id": a.id}))["password"]?.toString() ?? "";
      if (password.isEmpty) continue;
      final kcId = await BrowserPasswords.syncCreate(site, a.username, password);
      pairs[a.id] = {"kc": kcId, "name": _name(a.username, site), "site": _site(site), "fp": a.fingerprint};
      created++;
      _note("Added ${_name(a.username, site)} from IMCDesk");
    }

    await _save();
    linkedCount.value = pairs.length;
    final changes = [
      if (pulled > 0) "$pulled updated here",
      if (pushed > 0) "$pushed updated in IMCDesk",
      if (created > 0) "$created added",
      if (deleted > 0) "$deleted deleted",
    ];
    final tail = [
      if (heldDeletes.isNotEmpty) "${heldDeletes.length} deletions waiting for you",
      if (noWebsite > 0) "$noWebsite IMCDesk logins have no website, so they stay in IMCDesk only",
    ];
    return [changes.isEmpty ? "Up to date" : changes.join(", "), ...tail].join(". ");
  }

  /// Makes both sides of a linked login have the same password. Returns 1 when IMCDesk was updated,
  /// 2 when the keychain was, 0 when nothing changed.
  static Future<int> _reconcile(
      String host, String key, Map<String, dynamic> pair, ImcAccount a, String kcId, api.PasswordRawEntry k) async {
    final password = utf8.decode(k.data, allowMalformed: true);
    final kcFp = fingerprint(key, password);
    if (kcFp == a.fingerprint) {
      pair["fp"] = kcFp;
      return 0;
    }
    final last = pair["fp"] as String?;
    final kcChanged = last == null || kcFp != last;
    final imcChanged = last == null || a.fingerprint != last;
    var keychainWins = kcChanged && !imcChanged;
    if (kcChanged && imcChanged) {
      // both changed (or never synced): the newer change wins
      final kcTime = DateTime.fromMillisecondsSinceEpoch(k.mdat);
      keychainWins = a.changedAt == null || kcTime.isAfter(a.changedAt!);
      if (last != null) {
        _note("${pair["name"]} was changed in both places; kept the newer password from "
            "${keychainWins ? "your devices" : "IMCDesk"}");
      }
    }
    if (keychainWins) {
      await _post(host, key, "/upsert", {
        "id": a.id,
        "username": a.username,
        "url": "https://${BrowserPasswords.siteHostOf(k.srvr)}",
        "password": password,
        "changedAt": DateTime.fromMillisecondsSinceEpoch(k.mdat).toUtc().toIso8601String(),
      });
      pair["fp"] = kcFp;
      _note("Updated ${pair["name"]} in IMCDesk");
      return 1;
    }
    final fresh = (await _post(host, key, "/reveal", {"id": a.id}))["password"]?.toString() ?? "";
    if (fresh.isEmpty) return 0;
    await BrowserPasswords.syncUpdate(kcId, fresh);
    pair["fp"] = fingerprint(key, fresh);
    _note("Updated ${pair["name"]} from IMCDesk");
    return 2;
  }

  /// An unlinked keychain login that is the linked one under a new id: same user name, and the same
  /// site or the password it had at the last sync.
  static String? _movedLogin(
      Map<String, api.PasswordRawEntry> keychain, Map<String, dynamic> pairs, String username, Map<String, dynamic> pair) {
    final linked = {for (final p in pairs.values) (p as Map)["kc"]};
    final key = _state["key"] as String;
    final site = (pair["site"] ?? "").toString();
    for (final e in keychain.entries) {
      if (linked.contains(e.key) || e.value.acct.toLowerCase() != username.toLowerCase()) continue;
      final sameSite = site.isNotEmpty && _site(e.value.srvr) == site;
      final samePassword = pair["fp"] != null && fingerprint(key, utf8.decode(e.value.data, allowMalformed: true)) == pair["fp"];
      if (sameSite || samePassword) return e.key;
    }
    return null;
  }

  static String _site(String server) => BrowserPasswords.registrableOf(BrowserPasswords.siteHostOf(server));

  /// A provider name ("Wells Fargo") naming a site ("wellsfargo.com"); same rules as IMCDesk's
  /// providerMatchesHost.
  static bool _providerMatches(String provider, String site) {
    final p = provider.toLowerCase().replaceAll(RegExp(r"[^a-z0-9]"), "");
    final labels = site.toLowerCase().split(".").where((l) => l.isNotEmpty).toList();
    if (p.length < 3 || labels.length < 2) return false;
    final name = labels[labels.length - 2].replaceAll(RegExp(r"[^a-z0-9]"), "");
    if (name.length < 3) return false;
    if (RegExp(r"microsoft|office|m365|outlook|azure|entra").hasMatch(p) &&
        _microsoftSites.contains(labels.sublist(labels.length - 2).join("."))) return true;
    return p.contains(name) || (p.length >= 4 && name.contains(p));
  }

  static bool _isMicrosoft(ImcAccount a) {
    final p = a.provider.toLowerCase();
    return p.isEmpty || p.contains("microsoft") || p.contains("m365") || p.contains("office 365") || p.contains("outlook");
  }

  static String _name(String username, String server) => "$username on ${BrowserPasswords.siteHostOf(server)}";

  static void _note(String text) {
    Logger.info("IMCDesk sync: $text");
    activity.insert(0, "${_time(DateTime.now())}  $text");
    if (activity.length > 30) activity.removeRange(30, activity.length);
  }

  static String _time(DateTime t) =>
      "${t.month}/${t.day} ${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, "0")} ${t.hour < 12 ? "AM" : "PM"}";

  // ---------- IMCDesk API ----------

  static final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  static Options _auth(String key) => Options(headers: {"Authorization": "Bearer $key"});

  static Future<Map<String, dynamic>> _get(String host, String key) async =>
      Map<String, dynamic>.from((await _dio.get("https://$host/api/sync/passwords", options: _auth(key))).data as Map);

  static Future<Map<String, dynamic>> _post(String host, String key, String path, Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
          (await _dio.post("https://$host/api/sync/passwords$path", data: body, options: _auth(key))).data as Map);

  // ---------- state (encrypted with Windows data protection, like Recently Deleted) ----------

  static Future<void> _load() async {
    try {
      if (!await _file.exists()) return;
      _state = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(RecentlyDeletedStore.unprotect(await _file.readAsBytes()))) as Map);
      connected.value = _state["key"] != null;
      // links made before matching was fixed (v1 duplicated logins): start over and link again
      if (_state["v"] != 2) {
        _state["pairs"] = <String, dynamic>{};
        _state["v"] = 2;
      }
      server.value = (_state["host"] ?? "").toString();
      linkedCount.value = _pairs.length;
    } catch (e, s) {
      Logger.warn("Couldn't read the IMCDesk sync settings", error: e, trace: s);
    }
  }

  static Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsBytes(RecentlyDeletedStore.protect(Uint8List.fromList(utf8.encode(jsonEncode(_state)))), flush: true);
  }
}
