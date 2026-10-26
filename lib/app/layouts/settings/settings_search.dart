import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/notification_providers_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/private_api_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/redacted_mode_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/tasker_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/conversation_list/chat_list_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/desktop/desktop_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/attachment_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/conversation_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/about_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/misc_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/troubleshoot_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/browser_extension_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/profile_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/scheduling/message_reminders_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/scheduling/scheduled_messages_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/server/backup_restore_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/server/server_management_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/system/device_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/system/notification_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/system/status_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/theming_panel.dart';
import 'package:bluebubbles/app/layouts/settings/settings_search_index.g.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

/// Search over every option on the Settings pages (index: settings_search_index.g.dart, built by
/// tool/gen_settings_search_index.py). Picking a result opens the page that has the option.
class SettingsSearch {
  /// Pages that exist on this device and setup, matching what the Settings page shows.
  static bool available(String page) {
    switch (page) {
      case "server":
        return backend.getRemoteService() != null;
      case "scheduled":
        return ss.serverDetailsSync().item4 >= 205;
      case "reminders":
      case "tasker":
        return !kIsWeb && Platform.isAndroid;
      case "desktop":
        return kIsDesktop;
      case "privateApi":
      case "redacted":
      case "notificationProviders":
        return !usingRustPush;
      case "device":
        return !kIsWeb && usingRustPush;
      case "passwords":
        return pushService.state?.icloudServices?.keychain != null;
      case "browserExtension":
        return !kIsWeb && Platform.isWindows;
      default:
        return true;
    }
  }

  static Widget? _panel(String page) => switch (page) {
        "profile" => ProfilePanel(),
        "status" => const StatusPanel(),
        "server" => ServerManagementPanel(),
        "scheduled" => ScheduledMessagesPanel(),
        "reminders" => MessageRemindersPanel(),
        "device" => DevicePanel(),
        "theming" => ThemingPanel(),
        "media" => AttachmentPanel(),
        "notifications" => NotificationPanel(),
        "chatList" => ChatListPanel(),
        "conversation" => ConversationPanel(),
        "desktop" => DesktopPanel(),
        "misc" => MiscPanel(),
        "privateApi" => PrivateAPIPanel(),
        "redacted" => RedactedModePanel(),
        "tasker" => TaskerPanel(),
        "notificationProviders" => NotificationProvidersPanel(),
        "troubleshoot" => TroubleshootPanel(),
        "backup" => BackupRestorePanel(),
        "about" => AboutPanel(),
        "browserExtension" => const BrowserExtensionPanel(),
        _ => null,
      };

  static void open(BuildContext context, String page) {
    if (page == "passwords") {
      goToPasswords(context);
      return;
    }
    final panel = _panel(page);
    if (panel == null) return;
    ns.pushAndRemoveSettingsUntil(context, panel, (route) => route.isFirst);
  }

  /// Entries containing every word of [query] (in the option, its description or its page), best
  /// matches first: title starts with the query, then title contains it, then the rest.
  static List<SettingsSearchEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final words = q.split(RegExp(r"\s+"));
    final scored = <(int, SettingsSearchEntry)>[];
    for (final e in settingsSearchIndex) {
      if (!available(e.page)) continue;
      final title = e.title.toLowerCase();
      final haystack =
          "$title ${e.subtitle.toLowerCase()} ${(settingsPageNames[e.page] ?? "").toLowerCase()} ${e.keywords.toLowerCase()}";
      if (!words.every(haystack.contains)) continue;
      final score = title.startsWith(q)
          ? 0
          : title.contains(q)
              ? 1
              : words.every(title.contains)
                  ? 2
                  : 3;
      scored.add((score * 2 + (e.section ? 0 : 1), e));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return scored.map((s) => s.$2).take(60).toList();
  }
}

/// The search field shown at the top of the Settings page.
class SettingsSearchField extends StatefulWidget {
  const SettingsSearchField({super.key, required this.query});

  final RxString query;

  @override
  State<SettingsSearchField> createState() => _SettingsSearchFieldState();
}

class _SettingsSearchFieldState extends State<SettingsSearchField> {
  late final TextEditingController controller = TextEditingController(text: widget.query.value);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CupertinoSearchTextField(
        controller: controller,
        placeholder: "Search Settings",
        style: context.theme.textTheme.bodyLarge,
        backgroundColor: context.theme.colorScheme.properSurface,
        onChanged: (value) => widget.query.value = value,
        onSuffixTap: () {
          controller.clear();
          widget.query.value = "";
        },
      ),
    );
  }
}

/// Results for the Settings search, as a sliver for the Settings page.
class SettingsSearchResults extends StatelessWidget {
  const SettingsSearchResults({super.key, required this.query, required this.tileColor});

  final String query;
  final Color tileColor;

  @override
  Widget build(BuildContext context) {
    final results = SettingsSearch.search(query);
    return SliverList(
      delegate: SliverChildListDelegate([
        SettingsSection(
          backgroundColor: tileColor,
          children: results.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text("No settings match \"${query.trim()}\"", style: context.theme.textTheme.bodyMedium),
                  ),
                ]
              : [
                  for (final (i, e) in results.indexed) ...[
                    if (i > 0) const SettingsDivider(),
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: e.title,
                      subtitle: [
                        settingsPageNames[e.page] ?? "",
                        if (e.subtitle.isNotEmpty) e.subtitle,
                      ].join(" · "),
                      onTap: () => SettingsSearch.open(context, e.page),
                      trailing: Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: context.theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ],
        ),
      ]),
    );
  }
}
