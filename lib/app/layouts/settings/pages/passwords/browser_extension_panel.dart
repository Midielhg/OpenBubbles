import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/browser_passwords.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

/// Windows: settings and one-time setup for the Passwords browser extension.
class BrowserExtensionPanel extends StatefulWidget {
  const BrowserExtensionPanel({super.key});

  @override
  State<StatefulWidget> createState() => _BrowserExtensionPanelState();
}

class _BrowserExtensionPanelState extends OptimizedState<BrowserExtensionPanel> {
  Future<void> copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    showSnackbar("Copied", "$what copied. Paste it into your browser's address bar.");
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: "Browser Extension",
      initialHeader: "Filling",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate(
            <Widget>[
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  Obx(() => SettingsSwitch(
                        initialVal: ss.settings.browserPasswordFill.value,
                        onChanged: (val) => BrowserPasswords.setEnabled(val),
                        title: "Fill Passwords in Chrome and Edge",
                        subtitle: "Shows your iCloud passwords under login boxes on websites. OpenBubbles needs to be running.",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.lock_fill,
                          materialIcon: Icons.password,
                          containerColor: Colors.green,
                        ),
                      )),
                  const SettingsDivider(),
                  Obx(() => SettingsSwitch(
                        initialVal: ss.settings.browserPasswordFillRequireAuth.value,
                        onChanged: (val) async {
                          ss.settings.browserPasswordFillRequireAuth.value = val;
                          await ss.saveSettings();
                        },
                        title: "Ask for Windows Hello",
                        subtitle: "Confirm with your PIN or fingerprint before filling, at most once every 10 minutes.",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.person_crop_circle_badge_checkmark,
                          materialIcon: Icons.fingerprint,
                          containerColor: Colors.blueAccent,
                        ),
                      )),
                  Obx(() => SettingsSwitch(
                        initialVal: ss.settings.deleteCodesAfterUse.value,
                        onChanged: (val) async {
                          ss.settings.deleteCodesAfterUse.value = val;
                          await ss.saveSettings();
                        },
                        title: "Delete Verification Codes After Use",
                        subtitle: "Once a texted code is filled on a website or copied from its notification, move the text to Recently Deleted.",
                        backgroundColor: tileColor,
                        isThreeLine: true,
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.trash,
                          materialIcon: Icons.auto_delete_outlined,
                          containerColor: Colors.grey,
                        ),
                      )),
                ],
              ),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Set Up (One Time)",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "1. Open the extensions page",
                    subtitle: "Chrome: chrome://extensions   Edge: edge://extensions\nClick to copy the Chrome address.",
                    isThreeLine: true,
                    onTap: () => copy("chrome://extensions", "Address"),
                    trailing: Icon(iOS ? CupertinoIcons.doc_on_clipboard : Icons.copy, size: 18),
                  ),
                  const SettingsDivider(),
                  const SettingsTile(
                    title: "2. Turn on Developer mode",
                    subtitle: "Use the switch in the top-right corner (in Edge, it's on the left).",
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "3. Click \"Load unpacked\" and choose this folder",
                    subtitle: "${BrowserPasswords.extensionDir}\nClick to copy the folder path.",
                    isThreeLine: true,
                    onTap: () => copy(BrowserPasswords.extensionDir, "Folder path"),
                    trailing: Icon(iOS ? CupertinoIcons.doc_on_clipboard : Icons.copy, size: 18),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "Show the folder in File Explorer",
                    onTap: () => Process.run("explorer.exe", [BrowserPasswords.extensionDir]),
                    trailing: const NextButton(),
                  ),
                ],
              ),
              const SettingsSubtitle(
                subtitle: "After an OpenBubbles update, click \"Update\" in the extension's menu (or the reload arrow on its card) to get the newest version.",
                unlimitedSpace: true,
              ),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Firefox (128 or Newer)",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "1. Open about:debugging#/runtime/this-firefox",
                    subtitle: "Click to copy the address, then paste it into Firefox's address bar.",
                    onTap: () => copy("about:debugging#/runtime/this-firefox", "Address"),
                    trailing: Icon(iOS ? CupertinoIcons.doc_on_clipboard : Icons.copy, size: 18),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "2. \"Load Temporary Add-on\", then choose manifest.json in this folder",
                    subtitle: "${BrowserPasswords.firefoxExtensionDir}\nClick to copy the folder path.",
                    isThreeLine: true,
                    onTap: () => copy(BrowserPasswords.firefoxExtensionDir, "Folder path"),
                    trailing: Icon(iOS ? CupertinoIcons.doc_on_clipboard : Icons.copy, size: 18),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "Show the Firefox folder in File Explorer",
                    onTap: () => Process.run("explorer.exe", [BrowserPasswords.firefoxExtensionDir]),
                    trailing: const NextButton(),
                  ),
                ],
              ),
              const SettingsSubtitle(
                subtitle: "Regular Firefox removes extensions loaded this way when it restarts, because it only keeps "
                    "extensions signed by Mozilla. To keep it, sign it for yourself (free, unlisted) at "
                    "addons.mozilla.org, or use Firefox Developer Edition with xpinstall.signatures.required "
                    "set to false in about:config.",
                unlimitedSpace: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
