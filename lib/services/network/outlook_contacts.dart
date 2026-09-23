import 'dart:async';

import 'package:bluebubbles/database/global/structured_name.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';

/// A pending Microsoft device-code sign-in (the user enters [userCode] at [verificationUri]).
class OutlookDeviceCode {
  OutlookDeviceCode(this.deviceCode, this.userCode, this.verificationUri, this.interval, this.expiresAt);

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int interval;
  final DateTime expiresAt;
}

/// Read-only Outlook / Exchange (Microsoft 365) contacts via Microsoft Graph.
///
/// Uses the OAuth device-code flow against the user's own Entra app registration (public client,
/// delegated Contacts.Read + offline_access), so the app never handles the Microsoft password.
class OutlookContacts {
  static const _kClientId = "outlookClientId";
  static const _kTenantId = "outlookTenantId";
  static const _kRefreshToken = "outlookRefreshToken";
  static const _kAccount = "outlookAccount";
  static const _scopes = "offline_access User.Read Contacts.Read";

  static final Dio _dio = Dio(BaseOptions(validateStatus: (_) => true));

  static String get clientId => ss.prefs.getString(_kClientId) ?? "";
  static String get tenantId => ss.prefs.getString(_kTenantId) ?? "organizations";
  static String? get account => ss.prefs.getString(_kAccount);
  /// observable account name for the settings UI (null = not connected)
  static final RxnString accountRx = RxnString(connected ? account : null);
  static bool get connected => (ss.prefs.getString(_kRefreshToken) ?? "").isNotEmpty;

  static String _authority(String tenant) => "https://login.microsoftonline.com/${tenant.isEmpty ? "organizations" : tenant}/oauth2/v2.0";

  static Future<OutlookDeviceCode> startSignIn({required String clientId, required String tenantId}) async {
    await ss.prefs.setString(_kClientId, clientId.trim());
    await ss.prefs.setString(_kTenantId, tenantId.trim());
    final res = await _dio.post(
      "${_authority(tenantId.trim())}/devicecode",
      data: {"client_id": clientId.trim(), "scope": _scopes},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.statusCode != 200) {
      throw Exception("Microsoft sign-in could not start: ${res.data is Map ? res.data["error_description"] ?? res.data["error"] : res.statusCode}");
    }
    final d = res.data as Map;
    return OutlookDeviceCode(
      d["device_code"],
      d["user_code"],
      d["verification_uri"] ?? "https://microsoft.com/devicelogin",
      (d["interval"] as num?)?.toInt() ?? 5,
      DateTime.now().add(Duration(seconds: (d["expires_in"] as num?)?.toInt() ?? 900)),
    );
  }

  /// Polls until the user finishes signing in. Returns the signed-in account name.
  static Future<String> completeSignIn(OutlookDeviceCode code, {bool Function()? cancelled}) async {
    int interval = code.interval;
    while (DateTime.now().isBefore(code.expiresAt)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) throw Exception("Sign-in cancelled");
      final res = await _dio.post(
        "${_authority(tenantId)}/token",
        data: {
          "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
          "client_id": clientId,
          "device_code": code.deviceCode,
        },
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      final d = res.data is Map ? res.data as Map : const {};
      if (res.statusCode == 200) {
        await ss.prefs.setString(_kRefreshToken, d["refresh_token"] ?? "");
        final me = await _dio.get("https://graph.microsoft.com/v1.0/me",
            options: Options(headers: {"Authorization": "Bearer ${d["access_token"]}"}));
        final name = me.data is Map ? (me.data["userPrincipalName"] ?? me.data["mail"] ?? "Microsoft account") : "Microsoft account";
        await ss.prefs.setString(_kAccount, name);
        accountRx.value = name;
        return name;
      }
      switch (d["error"]) {
        case "authorization_pending":
          continue;
        case "slow_down":
          interval += 5;
          continue;
        default:
          throw Exception("Microsoft sign-in failed: ${d["error_description"] ?? d["error"] ?? res.statusCode}");
      }
    }
    throw Exception("The sign-in code expired. Try again.");
  }

  static Future<void> disconnect() async {
    await ss.prefs.remove(_kRefreshToken);
    await ss.prefs.remove(_kAccount);
    accountRx.value = null;
  }

  static Future<String?> _accessToken() async {
    final refresh = ss.prefs.getString(_kRefreshToken);
    if (refresh == null || refresh.isEmpty || clientId.isEmpty) return null;
    final res = await _dio.post(
      "${_authority(tenantId)}/token",
      data: {"grant_type": "refresh_token", "client_id": clientId, "refresh_token": refresh, "scope": _scopes},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    if (res.statusCode != 200) {
      Logger.warn("Outlook contacts: token refresh failed (${res.statusCode}): ${res.data}");
      return null;
    }
    // refresh tokens rotate; keep the newest one
    if (res.data["refresh_token"] != null) await ss.prefs.setString(_kRefreshToken, res.data["refresh_token"]);
    return res.data["access_token"];
  }

  static const _select = "id,displayName,givenName,middleName,surname,title,generation,emailAddresses,mobilePhone,homePhones,businessPhones,companyName";

  static Future<List<Map>> _getAll(String url, String token) async {
    final items = <Map>[];
    String? next = url;
    while (next != null) {
      final res = await _dio.get(next, options: Options(headers: {"Authorization": "Bearer $token"}));
      if (res.statusCode != 200) throw Exception("Graph ${res.statusCode}: ${res.data}");
      items.addAll(((res.data["value"] as List?) ?? []).cast<Map>());
      next = res.data["@odata.nextLink"];
    }
    return items;
  }

  /// All personal contacts (default folder + every contact folder), mapped to app contacts.
  static Future<List<Contact>> fetchContacts() async {
    final token = await _accessToken();
    if (token == null) return [];
    final raw = <String, Map>{};
    for (final c in await _getAll("https://graph.microsoft.com/v1.0/me/contacts?\$select=$_select&\$top=500", token)) {
      raw[c["id"]] = c;
    }
    try {
      for (final f in await _getAll("https://graph.microsoft.com/v1.0/me/contactFolders?\$top=100", token)) {
        for (final c in await _getAll("https://graph.microsoft.com/v1.0/me/contactFolders/${f["id"]}/contacts?\$select=$_select&\$top=500", token)) {
          raw[c["id"]] = c;
        }
      }
    } catch (e) {
      Logger.warn("Outlook contacts: couldn't read contact folders: $e");
    }

    final result = <Contact>[];
    for (final c in raw.values) {
      final phones = <String>{
        if ((c["mobilePhone"] ?? "").toString().isNotEmpty) c["mobilePhone"],
        ...((c["homePhones"] as List?) ?? []).map((e) => e.toString()),
        ...((c["businessPhones"] as List?) ?? []).map((e) => e.toString()),
      }.where((e) => e.trim().isNotEmpty).toList();
      final emails = ((c["emailAddresses"] as List?) ?? [])
          .map((e) => (e is Map ? e["address"] : null)?.toString() ?? "")
          .where((e) => e.trim().isNotEmpty)
          .toList();
      final given = (c["givenName"] ?? "").toString();
      final family = (c["surname"] ?? "").toString();
      var name = (c["displayName"] ?? "").toString().trim();
      if (name.isEmpty) name = [given, family].where((e) => e.isNotEmpty).join(" ");
      if (name.isEmpty) name = (c["companyName"] ?? "").toString();
      if (name.isEmpty || (phones.isEmpty && emails.isEmpty)) continue;
      result.add(Contact(
        id: "outlook:${c["id"]}",
        displayName: name,
        phones: phones,
        emails: emails,
        structuredName: StructuredName(
          namePrefix: (c["title"] ?? "").toString(),
          givenName: given,
          middleName: (c["middleName"] ?? "").toString(),
          familyName: family,
          nameSuffix: (c["generation"] ?? "").toString(),
        ),
      ));
    }
    Logger.info("Outlook contacts: ${result.length} contacts (of ${raw.length} in Outlook)");
    return result;
  }
}
