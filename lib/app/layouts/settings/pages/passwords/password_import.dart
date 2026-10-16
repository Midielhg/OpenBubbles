import 'dart:convert';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/browser_passwords.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

class ImportedLogin {
  ImportedLogin(this.url, this.username, this.password);
  final String url;
  final String username;
  final String password;
}

/// Imports a password export (CSV) from Chrome, Edge, Firefox, Safari, Bitwarden or 1Password
/// into iCloud Keychain. Logins already saved for the same site and user name are skipped.
class PasswordImport {
  /// RFC 4180 CSV: quoted fields, doubled quotes, commas and line breaks inside quotes.
  static List<List<String>> parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    return rows;
  }

  static int _column(List<String> header, List<String> names) {
    final lower = header.map((h) => h.trim().toLowerCase().replaceAll(RegExp(r"^﻿"), "")).toList();
    for (final name in names) {
      final i = lower.indexOf(name);
      if (i >= 0) return i;
    }
    return -1;
  }

  static List<ImportedLogin> logins(String csv) {
    final rows = parseCsv(csv);
    if (rows.length < 2) return [];
    final header = rows.first;
    final url = _column(header, ["url", "login_uri", "website", "uri", "login url", "web site"]);
    final user = _column(header, ["username", "login_username", "user name", "user", "email", "login"]);
    final pass = _column(header, ["password", "login_password"]);
    if (url < 0 || pass < 0) return [];
    String at(List<String> r, int i) => i >= 0 && i < r.length ? r[i].trim() : "";
    return [
      for (final r in rows.skip(1))
        if (at(r, url).isNotEmpty && at(r, pass).isNotEmpty) ImportedLogin(at(r, url), user >= 0 ? at(r, user) : "", r[pass]),
    ];
  }

  /// Picks a file, confirms, imports. Returns the number of logins added.
  static Future<int> run(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: "Choose a password export (.csv)",
      type: FileType.custom,
      allowedExtensions: ["csv"],
    );
    final path = picked?.files.single.path;
    if (path == null) return 0;
    final list = logins(utf8.decode(await File(path).readAsBytes(), allowMalformed: true));
    if (list.isEmpty) {
      showSnackbar("Import", "No logins found. Use a CSV export with url, username and password columns.");
      return 0;
    }
    if (!context.mounted) return 0;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text("Import ${list.length} Logins?", style: context.theme.textTheme.titleLarge),
        content: Text(
          "They'll be saved to iCloud Keychain and sync to your Apple devices. Logins you already have for the "
          "same site and user name are skipped.",
          style: context.textTheme.bodyLarge,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Import")),
        ],
      ),
    );
    if (go != true) return 0;

    showSnackbar("Importing", "Saving ${list.length} logins...");
    var added = 0, skipped = 0, failed = 0;
    for (final login in list) {
      try {
        if (await BrowserPasswords.importLogin(login.url, login.username, login.password)) {
          added++;
        } else {
          skipped++;
        }
      } catch (_) {
        failed++;
      }
    }
    showSnackbar(
      "Import finished",
      "Added $added, skipped $skipped already saved${failed > 0 ? ", $failed failed" : ""}. "
          "The CSV file has your passwords in plain text, so delete it now.",
    );
    return added;
  }
}
