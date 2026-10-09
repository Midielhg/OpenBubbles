import 'dart:convert';
import 'dart:typed_data';

import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/helpers/types/helpers/date_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cbor/simple.dart';
import 'package:collection/collection.dart';

class CredentialField {
  final String label;
  final String value;

  const CredentialField(this.label, this.value);
}

abstract class CredentialItem {
  String get title;
  String get subtitle;
  IconData get icon;
  Color get color;
  List<CredentialField> get fields;
}

class BasicCredentialItem implements CredentialItem {
  @override
  final String title;
  @override
  final String subtitle;
  @override
  final IconData icon;
  @override
  final Color color;
  @override
  final List<CredentialField> fields;

  const BasicCredentialItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.fields,
  });
}

class CredentialEntry {
  final String id;
  final String? group;
  final String? passwordMetaId;
  final PasswordGroupType groupType;
  final CredentialItem item;
  final api.PasswordManagerMeta? passwordMeta;
  final api.PasswordRawEntry? passwordRaw;
  final api.Passkey? passkey;
  final api.WifiPassword? wifiPassword;

  /// Other saved records of the same login (same user name and password for the same site or its
  /// linked domains, e.g. ring.com and oauth.ring.com). Shown as one item; edits and deletes apply
  /// to all of them.
  final List<CredentialCopy> copies;

  const CredentialEntry({
    required this.id,
    this.group,
    this.passwordMetaId,
    required this.groupType,
    required this.item,
    this.passwordMeta,
    this.passwordRaw,
    this.passkey,
    this.wifiPassword,
    this.copies = const [],
  });

  bool get isEditable =>
      groupType == PasswordGroupType.web || groupType == PasswordGroupType.wifi;
}

class CredentialCopy {
  final String id;
  final String? group;
  final api.PasswordRawEntry raw;

  const CredentialCopy({required this.id, this.group, required this.raw});
}

// ---------- merging duplicate logins ----------

String siteHostOf(String server) {
  var s = server.trim().toLowerCase();
  if (s.contains("://")) s = Uri.tryParse(s)?.host ?? s;
  s = s.split("/").first.split(":").first;
  return s.startsWith("www.") ? s.substring(4) : s;
}

const _twoPartSuffixes = {
  "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "com.br",
  "com.mx", "com.ar", "com.co", "co.in", "co.za", "com.tr", "com.cn", "com.hk", "com.sg", "com.tw",
};

/// The part of a host a site owns ("oauth.ring.com" -> "ring.com"). IP addresses stay whole.
String registrableDomainOf(String host) {
  if (RegExp(r"^[0-9.]+$").hasMatch(host) || host.contains(":")) return host;
  final parts = host.split(".");
  if (parts.length <= 2) return host;
  final lastTwo = parts.sublist(parts.length - 2).join(".");
  if (_twoPartSuffixes.contains(lastTwo)) return parts.sublist(parts.length - 3).join(".");
  return lastTwo;
}

/// Groups records that are really one login: same group, same user name and same password, for
/// the same site or domains linked to it. Keeps the first-seen order.
List<List<T>> groupSameLogins<T>(
  List<T> items, {
  required String Function(T) account,
  required String Function(T) password,
  required String? Function(T) group,
  required Set<String> Function(T) sites,
}) {
  final groups = <List<T>>[];
  final buckets = <String, List<(List<T>, Set<String>)>>{};
  for (final item in items) {
    final key = "${group(item)}\u0000${account(item).trim().toLowerCase()}\u0000${password(item)}";
    final mySites = sites(item);
    final bucket = buckets.putIfAbsent(key, () => []);
    // join every existing login in this bucket that shares a site (can bridge two of them)
    final joined = bucket.where((g) => g.$2.any(mySites.contains)).toList();
    if (joined.isEmpty) {
      final group = <T>[item];
      bucket.add((group, {...mySites}));
      groups.add(group);
      continue;
    }
    final target = joined.first;
    target.$1.add(item);
    target.$2.addAll(mySites);
    for (final other in joined.skip(1)) {
      target.$1.addAll(other.$1);
      target.$2.addAll(other.$2);
      bucket.remove(other);
      groups.remove(other.$1);
    }
  }
  return groups;
}

String _rawPassword(api.PasswordRawEntry raw) {
  try {
    return utf8.decode(raw.data);
  } catch (_) {
    return "";
  }
}

Set<String> _entrySites(CredentialEntry e) {
  final sites = <String>{registrableDomainOf(siteHostOf(e.passwordRaw?.srvr ?? ""))};
  try {
    final data = e.passwordMeta?.getPasswordData();
    for (final d in data?.altDomains ?? const <api.PasswordManagerAltDomain>[]) {
      sites.add(registrableDomainOf(siteHostOf(d.domain)));
    }
  } catch (_) {}
  sites.remove("");
  return sites;
}

/// Shows each login once (see [groupSameLogins]): the record with Passwords app details (title,
/// notes, history) represents the group, the rest become its [CredentialEntry.copies], and its
/// websites are listed together.
List<CredentialEntry> mergeSameLogins(List<CredentialEntry> entries) {
  final logins = entries.where((e) => e.passwordRaw != null).toList();
  final others = entries.where((e) => e.passwordRaw == null);
  final merged = <CredentialEntry>[];
  for (final group in groupSameLogins<CredentialEntry>(
    logins,
    account: (e) => e.passwordRaw!.acct,
    password: (e) => _rawPassword(e.passwordRaw!),
    group: (e) => e.group,
    sites: _entrySites,
  )) {
    if (group.length == 1) {
      merged.add(group.first);
      continue;
    }
    group.sort((a, b) {
      if ((a.passwordMeta == null) != (b.passwordMeta == null)) return a.passwordMeta == null ? 1 : -1;
      return siteHostOf(a.passwordRaw!.srvr).length.compareTo(siteHostOf(b.passwordRaw!.srvr).length);
    });
    final main = group.first;
    final hosts = <String>{
      for (final e in group) siteHostOf(e.passwordRaw!.srvr),
    }..removeWhere((h) => h.isEmpty);
    final mainHost = siteHostOf(main.passwordRaw!.srvr);
    final otherHosts = hosts.where((h) => h != mainHost).toList()..sort();
    final fields = main.item.fields.where((f) => f.label != "Alternate Domains").toList();
    final existingAlt = main.item.fields.firstWhereOrNull((f) => f.label == "Alternate Domains")?.value;
    final alsoUsedOn = {
      ...otherHosts,
      if (existingAlt != null) ...existingAlt.split(", ").where((d) => d.trim().isNotEmpty),
    };
    if (alsoUsedOn.isNotEmpty) fields.add(CredentialField("Alternate Domains", alsoUsedOn.join(", ")));
    merged.add(CredentialEntry(
      id: main.id,
      group: main.group,
      passwordMetaId: main.passwordMetaId,
      groupType: main.groupType,
      item: BasicCredentialItem(
        title: main.item.title,
        subtitle: main.item.subtitle,
        icon: main.item.icon,
        color: main.item.color,
        fields: fields,
      ),
      passwordMeta: main.passwordMeta,
      passwordRaw: main.passwordRaw,
      copies: [
        for (final e in group.skip(1)) CredentialCopy(id: e.id, group: e.group, raw: e.passwordRaw!),
      ],
    ));
  }
  return [...merged, ...others];
}

enum PasswordGroupType {
  web,
  passkeys,
  codes,
  wifi,
}

class PasswordGroupStyle {
  final IconData icon;
  final Color color;

  const PasswordGroupStyle(this.icon, this.color);
}

PasswordGroupStyle styleForPasswordGroup(PasswordGroupType type) {
  switch (type) {
    case PasswordGroupType.web:
      return const PasswordGroupStyle(CupertinoIcons.globe, Colors.blueAccent);
    case PasswordGroupType.passkeys:
      return const PasswordGroupStyle(CupertinoIcons.lock, Colors.deepPurple);
    case PasswordGroupType.codes:
      return const PasswordGroupStyle(CupertinoIcons.lock_shield, Colors.teal);
    case PasswordGroupType.wifi:
      return const PasswordGroupStyle(CupertinoIcons.wifi, Colors.orangeAccent);
  }
}

CredentialItem buildPasswordCredential({
  api.PasswordManagerMeta? meta,
  api.PasswordRawEntry? password,
  api.PasswordManagerMetaData? data,
  String? group,
  required PasswordGroupType groupType,
}) {
  final style = styleForPasswordGroup(groupType);
  final server = (meta?.srvr ?? password?.srvr ?? "").trim();
  final account = (meta?.acct ?? password?.acct ?? "").trim();
  final showServer = server.contains(".");
  final metadataTitle = _decodeOptionalUtf8(data?.title);
  final title = metadataTitle ?? (showServer ? server : account);
  final subtitle = account;

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Saved Password",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      ..._buildGroupField(group),
      ..._buildCommonFields(meta: meta, password: password),
      if (account.isNotEmpty) CredentialField("Account", account),
      if (showServer) CredentialField("Server", server),
      ..._buildPasswordFields(data: data, password: password),
    ],
  );
}

CredentialItem buildPasskeyCredential({
  required api.Passkey passkey,
  String? group,
}) {
  final style = styleForPasswordGroup(PasswordGroupType.passkeys);
  final label = passkey.labl.trim();
  final title = label;
  final subtitle = _extractPasskeyName(passkey);

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Passkey",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      ..._buildGroupField(group),
      if (label.isNotEmpty) CredentialField("Site", label),
      if (passkey.agrp.trim().isNotEmpty)
        CredentialField("Created", _formatPlistDate(passkey.cdat)),
      CredentialField("Modified", _formatPlistDate(passkey.mdat)),
      CredentialField("Account", subtitle),
      // ..._bytesField("Attachment Tag", passkey.atag),
      // ..._bytesField("Key Label", passkey.klbl),
      // ..._bytesField("Data", passkey.data),
    ],
  );
}

CredentialItem buildWifiCredential({
  required api.WifiPassword wifi,
  String? group,
}) {
  final style = styleForPasswordGroup(PasswordGroupType.wifi);
  final ssid = wifi.acct.trim();
  final title = ssid;
  const subtitle = "WPA2 Personal";

  return BasicCredentialItem(
    title: title.isNotEmpty ? title : "Wi-Fi Password",
    subtitle: subtitle,
    icon: style.icon,
    color: style.color,
    fields: [
      ..._buildGroupField(group),
      if (ssid.isNotEmpty) CredentialField("SSID", ssid),
      CredentialField("Created", _formatPlistDate(wifi.cdat)),
      CredentialField("Modified", _formatPlistDate(wifi.mdat)),
      ..._wifiPasswordField(wifi.data),
    ],
  );
}

List<CredentialField> _buildCommonFields({
  api.PasswordManagerMeta? meta,
  api.PasswordRawEntry? password,
}) {
  final created = meta?.cdat ?? password?.cdat ?? 0;
  final modified = meta?.mdat ?? password?.mdat ?? 0;
  return [
    CredentialField("Created", _formatPlistDate(created)),
    CredentialField("Modified", _formatPlistDate(modified)),
  ];
}

List<CredentialField> _buildPasswordFields({
  api.PasswordManagerMetaData? data,
  api.PasswordRawEntry? password,
}) {
  final fields = <CredentialField>[];
  final latestPassword = _currentPassword(data);
  final fallbackPassword = _decodePasswordFromRaw(password);
  final passwordValue = latestPassword ?? fallbackPassword;
  if (passwordValue != null && passwordValue.isNotEmpty) {
    fields.add(CredentialField("Password", passwordValue));
  }
  if (data != null && data.altDomains.isNotEmpty) {
    fields.add(
      CredentialField(
        "Alternate Domains",
        data.altDomains.map((domain) => domain.domain).join(", "),
      ),
    );
  }
  final notes = _decodeOptionalUtf8(data?.notes);
  if (notes != null) {
    fields.add(CredentialField("Notes", notes));
  }
  return fields;
}

String? _currentPassword(api.PasswordManagerMetaData? data) {
  if (data == null || data.history.isEmpty) {
    return null;
  }
  for (final change in data.history.reversed) {
    if (change.password != null) {
      return change.password;
    }
  }
  return null;
}

String? _decodePasswordFromRaw(api.PasswordRawEntry? password) {
  if (password == null || password.data.isEmpty) {
    return null;
  }
  try {
    return utf8.decode(password.data);
  } catch (_) {
    return null;
  }
}

String _formatBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    return "";
  }
  return base64Encode(bytes);
}

String _formatPlistDate(int date) {
  if (date <= 0) return "";
  final dateTime =
      DateTime.fromMillisecondsSinceEpoch(date, isUtc: true).toLocal();
  return buildFullDate(dateTime);
}

List<CredentialField> _bytesField(String label, Uint8List bytes) {
  if (bytes.isEmpty) {
    return const [];
  }
  return [CredentialField(label, _formatBytes(bytes))];
}

List<CredentialField> _wifiPasswordField(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const [];
  }
  final password = _formatUtf8(bytes);
  if (password.isEmpty) {
    return const [];
  }
  return [CredentialField("Password", password)];
}

String _formatUtf8(Uint8List bytes) {
  if (bytes.isEmpty) {
    return "";
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return "";
  }
}

List<CredentialField> _buildGroupField(String? group) {
  final value = group?.trim() ?? "";
  if (value.isEmpty || value == "(none)" || value == "(unknown group)") {
    return const [];
  }
  return [CredentialField("Group", value)];
}

String? _decodeOptionalUtf8(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) {
    return null;
  }
  try {
    final decoded = utf8.decode(bytes).trim();
    if (decoded.isEmpty) {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

String _extractPasskeyName(api.Passkey passkey) {
  try {
    final tag = cbor.decode(passkey.atag) as Map<dynamic, dynamic>;
    return (tag["name"]?.toString() ?? "").trim();
  } catch (_) {
    return "";
  }
}
