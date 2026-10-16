import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/backend/browser_passwords.dart';
import 'package:bluebubbles/services/network/app_updater.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

enum _Health { ok, warning, error, checking }

class _Check {
  _Check(this.title);
  final String title;
  _Health health = _Health.checking;
  String detail = "Checking...";
  String? actionLabel;
  Future<void> Function()? action;
}

/// One place to see whether everything OpenBubbles depends on is working: iMessage registration,
/// the Mac relay, iCloud Keychain, the browser extension and updates, with a fix for each problem.
class StatusPanel extends StatefulWidget {
  const StatusPanel({super.key});

  @override
  State<StatefulWidget> createState() => _StatusPanelState();
}

class _StatusPanelState extends OptimizedState<StatusPanel> {
  final imessage = _Check("iMessage");
  final relay = _Check("Mac Relay");
  final keychain = _Check("iCloud Keychain");
  final browser = _Check("Browser Extension");
  final updates = _Check("Updates");
  final sync = _Check("Message Sync");
  bool refreshing = false;

  List<_Check> get checks => [imessage, relay, keychain, if (Platform.isWindows) browser, if (Platform.isWindows) updates, sync];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  void set(_Check check, _Health health, String detail, {String? actionLabel, Future<void> Function()? action}) {
    if (!mounted) return;
    setState(() {
      check.health = health;
      check.detail = detail;
      check.actionLabel = actionLabel;
      check.action = action;
    });
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      for (final c in checks) {
        c.health = _Health.checking;
        c.detail = "Checking...";
        c.actionLabel = null;
        c.action = null;
      }
    });
    await Future.wait([checkIMessage(), checkRelay(), checkKeychain(), checkBrowser(), checkUpdates(), checkSync()]);
    if (mounted) setState(() => refreshing = false);
  }

  Future<void> checkIMessage() async {
    try {
      final info = await backend.getAccountInfo();
      final status = (info["login_status_message"] ?? "").toString();
      if (status.startsWith("Connected")) {
        set(imessage, _Health.ok, status);
      } else if (status.startsWith("Reregistering")) {
        set(imessage, _Health.warning, "Registering with Apple...");
      } else {
        set(imessage, _Health.error, status.isEmpty ? "Not registered" : status,
            actionLabel: "Retry", action: () async {
          await api.doReregister(state: pushService.state!.client);
          await checkIMessage();
        });
      }
    } catch (e) {
      set(imessage, _Health.error, "Couldn't check: $e");
    }
  }

  Future<void> checkRelay() async {
    try {
      final config = pushService.state?.osConfig;
      if (config == null) return set(relay, _Health.warning, "Not set up");
      final device = await api.getDeviceInfo(config: config);
      // only relay setups depend on a Mac being online; a saved hardware snapshot doesn't
      if (device.encodedData != null) return set(relay, _Health.ok, "Not needed (${device.name})");
      final online = await api.validateRelay(configRef: config);
      if (online != null) {
        set(relay, _Health.ok, "Online (${device.name})");
      } else {
        set(relay, _Health.error, "Offline. Make sure the Mac is on, awake and connected to the internet.",
            actionLabel: "Check Again", action: checkRelay);
      }
    } catch (e) {
      set(relay, _Health.error, "Couldn't reach the relay: $e", actionLabel: "Check Again", action: checkRelay);
    }
  }

  Future<void> checkKeychain() async {
    if (pushService.state?.icloudServices?.keychain == null) {
      return set(keychain, _Health.warning, "Not available for this account");
    }
    if (pushService.cachedInClique) {
      set(keychain, _Health.ok, "Joined. Passwords are syncing.");
    } else {
      set(keychain, _Health.warning, "Not joined yet. Passwords can't be read.",
          actionLabel: "Open Passwords", action: () => goToPasswords(context));
    }
  }

  Future<void> checkBrowser() async {
    if (!Platform.isWindows) return;
    if (!ss.settings.browserPasswordFill.value) {
      return set(browser, _Health.warning, "Turned off in Passwords > Browser Extension");
    }
    if (BrowserPasswords.running) {
      set(browser, _Health.ok, "Ready for the extension",
          actionLabel: "Restart", action: () async {
        await BrowserPasswords.restart();
        await checkBrowser();
      });
    } else {
      set(browser, _Health.error, "Not running", actionLabel: "Start", action: () async {
        await BrowserPasswords.restart();
        await checkBrowser();
      });
    }
  }

  Future<void> checkUpdates() async {
    if (!Platform.isWindows) return;
    final update = await AppUpdater.check();
    if (update != null) {
      set(updates, _Health.warning, "Version ${update.version} is available",
          actionLabel: "Update", action: () => AppUpdater.install(update));
    } else {
      set(updates, _Health.ok, "Up to date", actionLabel: "Check", action: checkUpdates);
    }
  }

  Future<void> checkSync() async {
    final last = ss.prefs.getInt("lastSynced");
    if (last == null) return set(sync, _Health.warning, "Hasn't synced from iCloud on this PC yet");
    final ago = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last));
    final text = ago.inMinutes < 1
        ? "just now"
        : ago.inHours < 1
            ? "${ago.inMinutes} min ago"
            : ago.inDays < 1
                ? "${ago.inHours} h ago"
                : "${ago.inDays} days ago";
    set(sync, ago.inDays >= 2 ? _Health.warning : _Health.ok, "Last synced $text");
  }

  Color colorFor(_Health health) => switch (health) {
        _Health.ok => const Color(0xFF34C759),
        _Health.warning => const Color(0xFFFF9F0A),
        _Health.error => const Color(0xFFFF3B30),
        _Health.checking => context.theme.colorScheme.outline,
      };

  Widget row(_Check check) {
    return SettingsTile(
      backgroundColor: tileColor,
      title: check.title,
      subtitle: check.detail,
      leading: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: check.health == _Health.checking
            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            : Container(width: 12, height: 12, decoration: BoxDecoration(color: colorFor(check.health), shape: BoxShape.circle)),
      ),
      trailing: check.actionLabel == null
          ? null
          : TextButton(
              onPressed: () async {
                final action = check.action;
                if (action == null) return;
                setState(() {
                  check.health = _Health.checking;
                  check.detail = "Working...";
                });
                try {
                  await action();
                } catch (e) {
                  set(check, _Health.error, "Didn't work: $e");
                }
              },
              child: Text(check.actionLabel!, style: TextStyle(color: context.theme.colorScheme.primary)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: "Status",
      initialHeader: "Connections",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      actions: [
        IconButton(
          tooltip: "Check again",
          icon: Icon(iOS ? CupertinoIcons.refresh : Icons.refresh, color: context.theme.colorScheme.primary),
          onPressed: refreshing ? null : refresh,
        ),
      ],
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            <Widget>[
              SettingsSection(
                backgroundColor: tileColor,
                children: [for (final c in checks) row(c)],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
