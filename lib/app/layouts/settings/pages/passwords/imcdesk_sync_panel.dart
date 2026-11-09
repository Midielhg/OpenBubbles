import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/imcdesk_sync.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Windows: two-way password sync with IMCDesk for @imcequitygroup.com logins.
class ImcDeskSyncPanel extends StatefulWidget {
  const ImcDeskSyncPanel({super.key});

  @override
  State<StatefulWidget> createState() => _ImcDeskSyncPanelState();
}

class _ImcDeskSyncPanelState extends OptimizedState<ImcDeskSyncPanel> {
  final TextEditingController _code = TextEditingController();
  bool _connecting = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    final error = await ImcDeskSync.connect(_code.text);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (error != null) {
      showSnackbar("IMCDesk Sync", error);
    } else {
      _code.clear();
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text("Stop Syncing?", style: context.theme.textTheme.titleLarge),
        content: Text(
          "Passwords stay where they are in both places; changes just stop being copied. To revoke access "
          "completely, also disconnect OpenBubbles in IMCDesk (Personal settings → Security).",
          style: context.textTheme.bodyLarge,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Stop Syncing")),
        ],
      ),
    );
    if (ok == true) await ImcDeskSync.disconnect();
  }

  Widget _text(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Text(text, style: context.theme.textTheme.bodyMedium),
      );

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: "IMCDesk Sync",
      initialHeader: null,
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            Obx(() {
              if (!ImcDeskSync.connected.value) return _connectSection();
              return _syncSection();
            }),
          ]),
        ),
      ],
    );
  }

  Widget _connectSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          backgroundColor: tileColor,
          children: [
            _text("Keeps your @${ImcDeskSync.domain} logins the same in iCloud Keychain and in IMCDesk. A password "
                "changed or deleted in either place changes in the other, and the newer change wins if both "
                "changed. Personal logins never leave Keychain."),
            _text("In IMCDesk, open Personal settings → Security → Connect OpenBubbles, copy the connection code "
                "and paste it here."),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: "Connection code", border: OutlineInputBorder()),
                      onSubmitted: (_) => _connect(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _connecting ? null : _connect,
                    child: Text(_connecting ? "Connecting..." : "Connect"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _syncSection() {
    final last = ImcDeskSync.lastSync.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          backgroundColor: tileColor,
          children: [
            SettingsTile(
              backgroundColor: tileColor,
              title: "Connected to ${ImcDeskSync.server.value}",
              subtitle: "${ImcDeskSync.linkedCount.value} linked logins · "
                  "${last == null ? "not synced yet" : "last synced ${TimeOfDay.fromDateTime(last).format(context)}"}",
              leading: const SettingsLeadingIcon(
                iosIcon: CupertinoIcons.arrow_2_circlepath,
                materialIcon: Icons.sync,
                containerColor: Colors.teal,
              ),
            ),
            if (ImcDeskSync.status.value.isNotEmpty) _text(ImcDeskSync.status.value),
            const SettingsDivider(),
            SettingsTile(
              backgroundColor: tileColor,
              title: ImcDeskSync.running.value ? "Syncing..." : "Sync Now",
              subtitle: "Also syncs on its own every 5 minutes while OpenBubbles is open",
              onTap: ImcDeskSync.running.value ? null : ImcDeskSync.syncNow,
            ),
          ],
        ),
        if (ImcDeskSync.heldDeletes.isNotEmpty) ...[
          SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Deletions Waiting"),
          SettingsSection(
            backgroundColor: tileColor,
            children: [
              _text("These logins were deleted on one side. Because there are several at once, they weren't "
                  "deleted on the other side yet:\n\n${ImcDeskSync.heldDeleteNames.join("\n")}"),
              SettingsTile(
                backgroundColor: tileColor,
                title: "Delete Them Everywhere",
                subtitle: "Deleted logins in Keychain stay in Recently Deleted for 30 days",
                onTap: () => ImcDeskSync.resolveHeldDeletes(true),
              ),
              const SettingsDivider(),
              SettingsTile(
                backgroundColor: tileColor,
                title: "Keep Them",
                subtitle: "Adds them back where they were deleted",
                onTap: () => ImcDeskSync.resolveHeldDeletes(false),
              ),
            ],
          ),
        ],
        if (ImcDeskSync.activity.isNotEmpty) ...[
          SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Recent Activity"),
          SettingsSection(
            backgroundColor: tileColor,
            children: [_text(ImcDeskSync.activity.join("\n"))],
          ),
        ],
        SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Connection"),
        SettingsSection(
          backgroundColor: tileColor,
          children: [
            SettingsTile(
              backgroundColor: tileColor,
              title: "Stop Syncing",
              onTap: _disconnect,
              leading: const SettingsLeadingIcon(
                iosIcon: CupertinoIcons.xmark_circle,
                materialIcon: Icons.link_off,
                containerColor: Colors.redAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
