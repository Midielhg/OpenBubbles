import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_editor_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/passwords_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/src/rust/lib.dart' as lib;
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

class CredentialDetailPanel extends StatefulWidget {
  final CredentialEntry credential;
  final lib.ArcPasswordManagerDefaultAnisetteProvider provider;
  final Map<String, String> groupNamesById;
  final String? groupUserId;

  const CredentialDetailPanel({
    super.key,
    required this.credential,
    required this.provider,
    required this.groupNamesById,
    required this.groupUserId,
  });

  @override
  State<CredentialDetailPanel> createState() => _CredentialDetailPanelState();
}

class _CredentialDetailPanelState
    extends OptimizedState<CredentialDetailPanel> {
  bool get _canEdit => widget.credential.isEditable;
  bool _showPassword = false;
  // websites added on this page (saved already; the item itself refreshes when the list reloads)
  final List<String> _addedDomains = [];
  bool get _isApplePasskey {
    if (widget.credential.groupType != PasswordGroupType.passkeys) {
      return false;
    }

    String? rawSite;
    for (final field in widget.credential.item.fields) {
      if (field.label.toLowerCase() == "site") {
        rawSite = field.value.trim();
        break;
      }
    }

    if (rawSite == null || rawSite.isEmpty) {
      return false;
    }

    final normalized = _normalizeHost(rawSite);
    return normalized == "apple.com" || normalized.endsWith(".apple.com");
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: widget.credential.item.title,
      initialHeader: "Credential",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      headerColor: headerColor,
      tileColor: tileColor,
      fab: _canEdit
          ? FloatingActionButton(
              backgroundColor: context.theme.colorScheme.primary,
              child: Icon(
                Icons.edit,
                color: context.theme.colorScheme.onPrimary,
                size: 22,
              ),
              onPressed: () async {
                final result = await ns.pushSettings(
                  context,
                  PasswordEditorPanel(
                    provider: widget.provider,
                    groupType: widget.credential.groupType,
                    id: widget.credential.id,
                    group: widget.credential.group,
                    passwordMetaId: widget.credential.passwordMetaId,
                    passwordMeta: widget.credential.passwordMeta,
                    passwordRaw: widget.credential.passwordRaw,
                    wifiPassword: widget.credential.wifiPassword,
                    copies: widget.credential.copies,
                    availableGroups: widget.groupNamesById,
                    groupUserId: widget.groupUserId,
                  ),
                );
                if (result == true && mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            )
          : null,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            [
              CredentialHeader(
                credential: widget.credential.item,
                caption: _field("Modified") == null
                    ? null
                    : "Last edited ${_field("Modified")}",
              ),
              if (_primaryRows().isNotEmpty)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: _withDividers(_primaryRows()),
                ),
              if (_field("Notes") != null) ...[
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Notes",
                ),
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _field("Notes")!,
                        style: context.theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ],
              if (_detailRows().isNotEmpty) ...[
                const SizedBox(height: 20),
                SettingsSection(
                  backgroundColor: tileColor,
                  children: _withDividers(_detailRows()),
                ),
              ],
              if (_actionTiles().isNotEmpty) ...[
                const SizedBox(height: 20),
                SettingsSection(
                  backgroundColor: tileColor,
                  children: _withDividers(_actionTiles()),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  String? _field(String label) {
    for (final field in widget.credential.item.fields) {
      if (field.label == label && field.value.trim().isNotEmpty) {
        return field.value;
      }
    }
    return null;
  }

  List<Widget> _withDividers(List<Widget> rows) => [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const SettingsDivider(),
        ],
      ];

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    showSnackbar("Copied", "$label copied to clipboard.");
  }

  // shown with a copy button, in this order, under these names
  static const _primaryLabels = {
    "Account": "User Name",
    "SSID": "Network",
    "Password": "Password",
    "Server": "Website",
    "Site": "Website",
    "Alternate Domains": "Also Used On",
  };

  List<Widget> _primaryRows() {
    final rows = <Widget>[];
    for (final entry in _primaryLabels.entries) {
      var value = _field(entry.key);
      if (entry.key == "Alternate Domains" && _addedDomains.isNotEmpty) {
        value = [if (value != null) value, ..._addedDomains].join(", ");
      }
      if (value == null) continue;
      final shown = value;
      final isPassword = entry.key == "Password";
      rows.add(CredentialFieldRow(
        label: entry.value,
        value: shown,
        obscured: isPassword && !_showPassword,
        monospace: isPassword,
        onCopy: () => _copy(entry.value, shown),
        onToggleObscured: isPassword
            ? () => setState(() => _showPassword = !_showPassword)
            : null,
      ));
    }
    final totp = widget.credential.passwordMeta?.getPasswordData().totp;
    if (totp != null) rows.add(TotpCodeTile(totp: totp, tileColor: tileColor));
    return rows;
  }

  List<Widget> _detailRows() => [
        for (final label in const ["Group", "Created", "Modified"])
          if (_field(label) != null)
            CredentialFieldRow(label: label, value: _field(label)!, inline: true),
      ];

  bool get _canAddWebsite =>
      widget.credential.isEditable && widget.credential.passwordRaw != null;

  /// Adds a website this login also works on. Like Apple's Passwords app, every website of a login is
  /// its own keychain record (same user name and password), so this saves one for the new site, which
  /// Safari, the iPhone and the browser extension all use. The site is also noted in the login's
  /// Passwords-app details ("also used on"), which keeps OpenBubbles showing them as one login.
  Future<void> _addWebsite() async {
    final raw = widget.credential.passwordRaw;
    if (raw == null) return;
    final controller = TextEditingController();
    final domain = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Website"),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: "example.com"),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text("Add")),
        ],
      ),
    );
    final host = siteHostOf(domain ?? "");
    if (host.isEmpty || !host.contains(".")) return;
    final existingHosts = {
      siteHostOf(raw.srvr),
      for (final copy in widget.credential.copies) siteHostOf(copy.raw.srvr),
    };
    if (existingHosts.contains(host)) {
      showSnackbar("Already added", "This login is already saved for $host.");
      return;
    }
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      // the keychain record for the new website
      await api.savePassword(
        passwords: widget.provider,
        id: const Uuid().v4().toUpperCase(),
        group: widget.credential.group,
        entry: api.PasswordRawEntry(
          cdat: now,
          mdat: now,
          srvr: host,
          acct: raw.acct,
          agrp: raw.agrp,
          data: raw.data,
        ),
      );
      // and the note in the login's details
      final meta = widget.credential.passwordMeta;
      final metaId = widget.credential.passwordMetaId;
      if (meta != null && metaId != null) {
        final data = meta.getPasswordData();
        if (!data.altDomains.any((d) => siteHostOf(d.domain) == host)) {
          await api.savePasswordMeta(
            passwords: widget.provider,
            id: metaId,
            group: widget.credential.group,
            entry: api.PasswordManagerMeta(
              cdat: meta.cdat,
              mdat: now,
              srvr: meta.srvr,
              acct: meta.acct,
              agrp: meta.agrp,
              data: api.PasswordManagerMeta.getData(
                data: api.PasswordManagerMetaData(
                  history: data.history,
                  altDomains: [...data.altDomains, api.PasswordManagerAltDomain(domain: host)],
                  totp: data.totp,
                  ctxt: data.ctxt,
                  title: data.title,
                  notes: data.notes,
                  formerlyShared: data.formerlyShared,
                  ocpid: data.ocpid,
                ),
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() => _addedDomains.add(host));
      showSnackbar("Added", "This login is now saved for $host too.");
    } catch (e) {
      showSnackbar("Error", "Couldn't add the website: $e");
    }
  }

  List<Widget> _actionTiles() {
    final tiles = <Widget>[];
    if (_canAddWebsite) {
      tiles.add(
        SettingsTile(
          backgroundColor: tileColor,
          title: "Add Website",
          subtitle: "Use this login on another website too",
          onTap: _addWebsite,
          trailing: Icon(
            iOS ? CupertinoIcons.add_circled : Icons.add_circle_outline,
            color: context.theme.colorScheme.primary,
          ),
        ),
      );
    }
    if (widget.credential.wifiPassword != null) {
      tiles.add(
        SettingsTile(
          backgroundColor: tileColor,
          title: "Show Wi-Fi QR Code",
          onTap: _showWifiQr,
          trailing: Icon(
            iOS ? CupertinoIcons.qrcode : Icons.qr_code,
            color: context.theme.colorScheme.onBackground,
          ),
        ),
      );
    }
    if (widget.credential.groupType == PasswordGroupType.passkeys &&
        !_isApplePasskey) {
      tiles.add(
        SettingsTile(
          backgroundColor: tileColor,
          title: "Delete Passkey",
          trailing: Icon(
            iOS ? CupertinoIcons.trash : Icons.delete_outline,
            color: context.theme.colorScheme.error,
          ),
          onTap: _confirmDeletePasskey,
        ),
      );
    }
    return tiles;
  }

  String _normalizeHost(String value) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host.toLowerCase();
    }
    return value
        .toLowerCase()
        .replaceFirst(RegExp(r"^https?://"), "")
        .split("/")
        .first;
  }

  void _showWifiQr() {
    final wifi = widget.credential.wifiPassword;
    if (wifi == null) return;
    final ssid = wifi.acct.trim();
    final password = _decodeWifiPassword(wifi);
    if (ssid.isEmpty || password.isEmpty) {
      showSnackbar("Error", "Wi-Fi credentials are incomplete.");
      return;
    }
    final data = _buildWifiQrPayload(ssid, password);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Wi‑Fi QR Code"),
        backgroundColor: context.theme.colorScheme.properSurface,
        content: AspectRatio(
          aspectRatio: 1,
          child: BarcodeWidget(
            barcode: Barcode.qrCode(
              errorCorrectLevel: BarcodeQRCorrectionLevel.medium,
            ),
            data: data,
            backgroundColor: const Color(0),
            color: context.theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  String _decodeWifiPassword(api.WifiPassword entry) {
    try {
      return utf8.decode(entry.data);
    } catch (_) {
      return "";
    }
  }

  String _buildWifiQrPayload(String ssid, String password) {
    final escapedSsid = ssid
        .replaceAll(r"\", r"\\")
        .replaceAll(";", r"\;")
        .replaceAll(",", r"\,")
        .replaceAll(":", r"\:");
    final escapedPassword = password
        .replaceAll(r"\", r"\\")
        .replaceAll(";", r"\;")
        .replaceAll(",", r"\,")
        .replaceAll(":", r"\:");
    return "WIFI:T:WPA;S:$escapedSsid;P:$escapedPassword;;";
  }

  void _confirmDeletePasskey() {
    showDialog(
      context: context,
      builder: (context) => areYouSure(
        context,
        title: "Delete Passkey?",
        content: const Text("Are you sure you want to delete this passkey?"),
        onNo: () => Navigator.of(context).pop(),
        onYes: () async {
          Navigator.of(context).pop();
          await _deletePasskey();
        },
      ),
    );
  }

  Future<void> _deletePasskey() async {
    try {
      await Future.wait([
        api.deletePasskey(
          passwords: widget.provider,
          id: widget.credential.id,
          group: widget.credential.group,
        ),
        if (widget.credential.passwordMetaId != null)
          api.deletePasswordMeta(
            passwords: widget.provider,
            id: widget.credential.passwordMetaId!,
            group: widget.credential.group,
          ),
      ]);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      showSnackbar("Error", "Unable to delete passkey.");
    }
  }
}

class TotpCodeTile extends StatefulWidget {
  final api.PasswordManagerTotp totp;
  final Color tileColor;

  const TotpCodeTile({
    super.key,
    required this.totp,
    required this.tileColor,
  });

  @override
  State<TotpCodeTile> createState() => _TotpCodeTileState();
}

class _TotpCodeTileState extends State<TotpCodeTile>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _expiryMicros = 0;
  String _code = "";

  @override
  void initState() {
    super.initState();
    _refreshCode();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _refreshCode() {
    final (code, expiry) = widget.totp.generateOtp();
    _expiryMicros = expiry.toInt() * 1000000;
    _code = code.toString().padLeft(widget.totp.digits, '0');
  }

  void _tick() {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    if (nowMicros >= _expiryMicros) {
      _refreshCode();
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _copyCode() async {
    if (_code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _code));
    showSnackbar("Copied", "Verification code copied to clipboard.");
  }

  @override
  Widget build(BuildContext context) {
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final periodMicros = widget.totp.period * 1000000;
    final remainingMicros = (_expiryMicros - nowMicros).clamp(0, periodMicros);
    final progress = widget.totp.period == 0
        ? 0.0
        : (1.0 - (remainingMicros / periodMicros)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsTile(
            backgroundColor: widget.tileColor,
            title: "Verification Code",
            subtitle: _code.length == 6
                ? "${_code.substring(0, 3)} ${_code.substring(3)}"
                : _code,
            trailing: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 4.5,
                strokeCap: StrokeCap.round,
                backgroundColor:
                    context.theme.colorScheme.outline.withOpacity(0.3),
              ),
            ),
            onTap: _copyCode,
          ),
        ],
      ),
    );
  }
}
