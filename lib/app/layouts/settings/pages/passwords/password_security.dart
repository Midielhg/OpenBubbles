import 'dart:convert';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Why a saved password is worth changing, most serious first.
enum PasswordIssue { leaked, reused, weak }

/// Security recommendations, like Apple's Passwords app: weak and reused passwords are found on
/// this PC; leaked ones are looked up in Have I Been Pwned's breach list, which only ever receives
/// the first 5 characters of each password's SHA-1 hash (k-anonymity), never the password.
class PasswordSecurity {
  static const _common = {
    "password", "passw0rd", "123456", "1234567", "12345678", "123456789", "1234567890", "qwerty",
    "qwerty123", "abc123", "111111", "123123", "letmein", "iloveyou", "admin", "welcome", "monkey",
    "dragon", "sunshine", "football", "princess", "baseball", "master", "shadow", "superman",
    "trustno1", "000000", "654321", "michael", "password1", "password123", "qwertyuiop",
  };

  static String passwordOf(CredentialEntry entry) {
    final data = entry.passwordRaw?.data;
    if (data == null) return "";
    return utf8.decode(data, allowMalformed: true);
  }

  static bool isWeak(String password) {
    if (password.isEmpty) return false;
    if (password.length < 8) return true;
    final lower = password.toLowerCase();
    if (_common.contains(lower)) return true;
    if (RegExp(r"^(.)\1+$").hasMatch(password)) return true;
    if (RegExp(r"^\d+$").hasMatch(password) && password.length < 12) return true;
    final kinds = [
      RegExp(r"[a-z]"),
      RegExp(r"[A-Z]"),
      RegExp(r"\d"),
      RegExp(r"[^A-Za-z0-9]"),
    ].where((r) => r.hasMatch(password)).length;
    return kinds == 1 && password.length < 12;
  }

  /// Logins (already merged per site) grouped by password, for passwords used on more than one site.
  static Map<String, List<CredentialEntry>> reused(List<CredentialEntry> logins) {
    final byPassword = <String, List<CredentialEntry>>{};
    for (final login in logins) {
      final password = passwordOf(login);
      if (password.isEmpty) continue;
      byPassword.putIfAbsent(password, () => []).add(login);
    }
    byPassword.removeWhere((_, list) {
      final sites = list.map((l) => registrableDomainOf(l.passwordRaw?.srvr ?? "")).toSet();
      return sites.length < 2;
    });
    return byPassword;
  }

  /// Passwords found in data breaches, by password. Network: one request per distinct hash prefix.
  static Future<Set<String>> leaked(Iterable<String> passwords, {void Function(int done, int total)? progress}) async {
    final dio = Dio(BaseOptions(headers: {"Add-Padding": "true"}, responseType: ResponseType.plain));
    final byPrefix = <String, Map<String, String>>{}; // prefix -> suffix -> password
    for (final password in passwords.toSet()) {
      if (password.isEmpty) continue;
      final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
      byPrefix.putIfAbsent(hash.substring(0, 5), () => {})[hash.substring(5)] = password;
    }
    final found = <String>{};
    var done = 0;
    for (final entry in byPrefix.entries) {
      final res = await dio.get<String>("https://api.pwnedpasswords.com/range/${entry.key}");
      for (final line in LineSplitter.split(res.data ?? "")) {
        final parts = line.split(":");
        if (parts.length != 2) continue;
        final password = entry.value[parts[0].trim()];
        if (password != null && (int.tryParse(parts[1].trim()) ?? 0) > 0) found.add(password);
      }
      progress?.call(++done, byPrefix.length);
    }
    return found;
  }

  /// The issues for each login (by id), from the checks that have run.
  static Map<String, List<PasswordIssue>> issues(List<CredentialEntry> logins, {Set<String> leakedPasswords = const {}}) {
    final reusedPasswords = reused(logins);
    final out = <String, List<PasswordIssue>>{};
    for (final login in logins) {
      final password = passwordOf(login);
      if (password.isEmpty) continue;
      final list = <PasswordIssue>[
        if (leakedPasswords.contains(password)) PasswordIssue.leaked,
        if (reusedPasswords.containsKey(password)) PasswordIssue.reused,
        if (isWeak(password)) PasswordIssue.weak,
      ];
      if (list.isNotEmpty) out[login.id] = list;
    }
    return out;
  }

  static String describe(PasswordIssue issue, {int reusedCount = 0}) => switch (issue) {
        PasswordIssue.leaked => "Appeared in a data leak",
        PasswordIssue.reused => reusedCount > 1 ? "Reused on $reusedCount sites" : "Reused on other sites",
        PasswordIssue.weak => "Weak password",
      };
}
