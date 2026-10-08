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

/// Windows: settings and one-time setup for the OpenBubbles Passwords browser extension.
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
                subtitle: "After an OpenBubbles update, click the reload arrow on the extension's card (or restart the browser) to get the newest version.",
                unlimitedSpace: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
