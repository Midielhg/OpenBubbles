import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/src/rust/lib.dart' as lib;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';
import 'package:win32/win32.dart';

/// A login deleted in OpenBubbles, kept so it can be restored.
class DeletedLogin {
  DeletedLogin({required this.deletedAt, required this.title, required this.username, required this.group,
      required this.passwords, this.metaId, this.meta});

  final DateTime deletedAt;
  final String title;
  final String username;
  final String? group;
  // every keychain record of the login (one per website), by id
  final Map<String, api.PasswordRawEntry> passwords;
  final String? metaId;
  final api.PasswordManagerMeta? meta;

  String get key => "${deletedAt.microsecondsSinceEpoch}:${passwords.keys.firstOrNull ?? ""}";
  int get daysLeft => (RecentlyDeletedStore.keepFor - DateTime.now().difference(deletedAt)).inDays.clamp(0, 30);

  static Map<String, dynamic> _raw(api.PasswordRawEntry e) => {
        "cdat": e.cdat, "mdat": e.mdat, "srvr": e.srvr, "acct": e.acct, "agrp": e.agrp, "data": base64Encode(e.data),
      };

  static api.PasswordRawEntry _rawFrom(Map m) => api.PasswordRawEntry(
        cdat: m["cdat"], mdat: m["mdat"], srvr: m["srvr"], acct: m["acct"], agrp: m["agrp"], data: base64Decode(m["data"]));

  Map<String, dynamic> toJson() => {
        "deletedAt": deletedAt.millisecondsSinceEpoch,
        "title": title,
        "username": username,
        "group": group,
        "passwords": {for (final e in passwords.entries) e.key: _raw(e.value)},
        if (metaId != null && meta != null) "metaId": metaId,
        if (metaId != null && meta != null)
          "meta": {
            "cdat": meta!.cdat, "mdat": meta!.mdat, "srvr": meta!.srvr, "acct": meta!.acct, "agrp": meta!.agrp,
            "data": base64Encode(meta!.data),
          },
      };

  static DeletedLogin fromJson(Map m) => DeletedLogin(
        deletedAt: DateTime.fromMillisecondsSinceEpoch(m["deletedAt"]),
        title: m["title"] ?? "",
        username: m["username"] ?? "",
        group: m["group"],
        passwords: {for (final e in (m["passwords"] as Map).entries) e.key as String: _rawFrom(e.value)},
        metaId: m["metaId"],
        meta: m["meta"] == null
            ? null
            : api.PasswordManagerMeta(
                cdat: m["meta"]["cdat"], mdat: m["meta"]["mdat"], srvr: m["meta"]["srvr"], acct: m["meta"]["acct"],
                agrp: m["meta"]["agrp"], data: base64Decode(m["meta"]["data"])),
      );
}

/// Recently Deleted, like Apple's Passwords app: logins deleted here are kept on this PC for 30
/// days. The file is encrypted with Windows' per-user data protection (DPAPI), so only this Windows
/// account on this PC can read it. Restoring saves the login back to iCloud Keychain.
class RecentlyDeletedStore {
  static const keepFor = Duration(days: 30);

  static bool get supported => Platform.isWindows;

  static File get _file =>
      File(p.join(Platform.environment["LOCALAPPDATA"] ?? "", "OpenBubbles", "recently-deleted-passwords.bin"));

  static Future<List<DeletedLogin>> load() async {
    if (!supported) return [];
    try {
      if (!await _file.exists()) return [];
      final clear = _unprotect(await _file.readAsBytes());
      final list = (jsonDecode(utf8.decode(clear)) as List).map((e) => DeletedLogin.fromJson(e as Map)).toList();
      final cutoff = DateTime.now().subtract(keepFor);
      return list.where((d) => d.deletedAt.isAfter(cutoff)).toList()
        ..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    } catch (e, s) {
      Logger.warn("Couldn't read Recently Deleted", error: e, trace: s);
      return [];
    }
  }

  static Future<void> _save(List<DeletedLogin> items) async {
    await _file.parent.create(recursive: true);
    final clear = utf8.encode(jsonEncode(items.map((e) => e.toJson()).toList()));
    await _file.writeAsBytes(_protect(Uint8List.fromList(clear)), flush: true);
  }

  /// Keeps a copy of a login (and its copies for other websites) before it's deleted.
  static Future<void> remember({
    required String id,
    required api.PasswordRawEntry raw,
    List<CredentialCopy> copies = const [],
    String? group,
    String? metaId,
    api.PasswordManagerMeta? meta,
  }) async {
    if (!supported) return;
    try {
      final items = await load();
      items.insert(
        0,
        DeletedLogin(
          deletedAt: DateTime.now(),
          title: siteHostOf(raw.srvr),
          username: raw.acct,
          group: group,
          passwords: {id: raw, for (final copy in copies) copy.id: copy.raw},
          metaId: metaId,
          meta: meta,
        ),
      );
      await _save(items);
    } catch (e, s) {
      Logger.warn("Couldn't keep the deleted login", error: e, trace: s);
    }
  }

  static Future<void> restore(lib.ArcPasswordManagerDefaultAnisetteProvider provider, DeletedLogin item) async {
    await Future.wait([
      for (final e in item.passwords.entries) api.savePassword(passwords: provider, id: e.key, entry: e.value, group: item.group),
      if (item.metaId != null && item.meta != null)
        api.savePasswordMeta(passwords: provider, id: item.metaId!, entry: item.meta!, group: item.group),
    ]);
    await forget(item);
  }

  static Future<void> forget(DeletedLogin item) async {
    final items = await load();
    items.removeWhere((d) => d.key == item.key);
    await _save(items);
  }

  // ---------- DPAPI ----------

  static Uint8List _protect(Uint8List data) => _crypt(data, protect: true);
  static Uint8List _unprotect(Uint8List data) => _crypt(data, protect: false);

  static Uint8List _crypt(Uint8List data, {required bool protect}) {
    final input = calloc<CRYPT_INTEGER_BLOB>();
    final output = calloc<CRYPT_INTEGER_BLOB>();
    final buffer = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buffer;
      const uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN
      final ok = protect
          ? CryptProtectData(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output)
          : CryptUnprotectData(input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output);
      if (ok == 0) throw Exception("Windows data protection failed (${GetLastError()})");
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      LocalFree(output.ref.pbData);
      return result;
    } finally {
      calloc.free(buffer);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
