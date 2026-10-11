import 'dart:convert';

import 'package:bluebubbles/app/layouts/settings/pages/passwords/browser_extension_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/group_credentials_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/credential_detail_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/passwords_group_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/passwords/passwords_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/src/rust/lib.dart' as lib;
import 'package:get/get.dart';

class PasswordsPanel extends StatefulWidget {
  const PasswordsPanel({super.key, this.openSearch = false});

  /// Go straight to search once the passwords are loaded (quick-open shortcuts).
  final bool openSearch;

  @override
  State<PasswordsPanel> createState() => _PasswordsPanelState();
}

class _PasswordsPanelState extends OptimizedState<PasswordsPanel> {
  lib.ArcPasswordManagerDefaultAnisetteProvider? manager;
  bool _isCheckingClique = true;
  bool _isInClique = false;
  bool _isJoiningClique = false;
  bool _isCreatingGroup = false;
  Map<String, String> _groupNamesById = const {};
  Map<String, api.GroupSummary> _groupsById = const {};
  String? _groupsUserId;
  Map<String, api.ShareInviteContentData> _invitesById = const {};
  final Set<String> _pendingInviteActions = <String>{};
  Map<PasswordGroupType, int> _counts = const {};
  // Apple verification codes need Apple's closed-source ADI component (ClearADI), which only
  // official builds include; this build's placeholder reports "Missing Libraries".
  bool _appleCodesAvailable = false;

  @override
  void initState() {
    super.initState();
    _refreshCliqueStatus();
  }

  Future<void> _refreshCliqueStatus() async {
    final keychain = pushService.state?.icloudServices?.keychain;
    if (keychain == null) {
      if (!mounted) return;
      setState(() {
        _isInClique = false;
        _isCheckingClique = false;
      });
      return;
    }

    await pushService.initFuture;
    final inClique = pushService.cachedInClique;
    if (inClique && manager == null) {
      manager = pushService.state!.icloudServices!.passwords!;
    }
    _checkAppleCodes();
    if (inClique && manager != null) {
      if (widget.openSearch) WidgetsBinding.instance.addPostFrameCallback((_) => _openSearch());
      await _loadCredentialCaches();
      await _loadGroups();
    }
    pushService.checkClique().then((inclique) {
      if (!inclique) return;
      api.syncWifiPasswords(manager: manager!, userApprove: true);
    });
    if (!mounted) return;
    setState(() {
      _isInClique = inClique;
      _isCheckingClique = false;
    });
  }

  Future<void> _loadGroups() async {
    if (manager == null) return;
    try {
      final groups = await api.getGroups(passwords: manager!);
      print("groups ${groups.$2.length} ${groups.$3.length}");
      if (!mounted) return;
      setState(() {
        _groupsUserId = groups.$1;
        _groupNamesById = {
          for (final entry in groups.$2.entries)
            entry.key: entry.value.displayName.trim().isEmpty
                ? "(unknown group)"
                : entry.value.displayName,
        };
        _groupsById = groups.$2;
        _invitesById = groups.$3;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groupsUserId = null;
        _groupNamesById = const {};
        _groupsById = const {};
        _invitesById = const {};
      });
    }
  }

  Future<void> _loadCredentialCaches() async {
    if (manager == null) return;
    final counts = <PasswordGroupType, int>{};
    try {
      // logins, not records: copies for a site's other addresses count once
      final passwords = (await api.getPasswords(passwords: manager!)).values.toList();
      counts[PasswordGroupType.web] = groupSameLogins<(String?, api.PasswordRawEntry)>(
        passwords,
        account: (p) => p.$2.acct,
        password: (p) => utf8.decode(p.$2.data, allowMalformed: true),
        group: (p) => p.$1,
        sites: (p) => {registrableDomainOf(siteHostOf(p.$2.srvr))},
      ).length;
    } catch (_) {}
    try {
      counts[PasswordGroupType.passkeys] =
          (await api.getPasskeys(passwords: manager!)).length;
    } catch (_) {}
    try {
      counts[PasswordGroupType.wifi] =
          (await api.getWifiPasswords(passwords: manager!)).length;
    } catch (_) {}
    try {
      final metas = await api.getPasswordsMeta(passwords: manager!);
      counts[PasswordGroupType.codes] = metas.values.where((meta) {
        try {
          return meta.$2.getPasswordData().totp != null;
        } catch (_) {
          return false;
        }
      }).length;
    } catch (_) {}
    if (mounted) setState(() => _counts = counts);
  }

  Future<void> _handleInviteAction(
    String inviteId, {
    required bool accept,
  }) async {
    if (manager == null || _pendingInviteActions.contains(inviteId)) return;
    setState(() => _pendingInviteActions.add(inviteId));
    try {
      if (accept) {
        await api.acceptInvite(passwords: manager!, inviteId: inviteId);
      } else {
        await api.declineInvite(passwords: manager!, inviteId: inviteId);
      }
      await api.syncPasswords(
          passwords: manager!, conn: pushService.state!.conn);
      await _loadGroups();
    } catch (error) {
      showSnackbar(
        "Error",
        "Unable to ${accept ? "accept" : "decline"} invite. $error",
      );
    } finally {
      if (mounted) {
        setState(() => _pendingInviteActions.remove(inviteId));
      }
    }
  }

  Future<void> _handlePullToRefresh() async {
    if (manager == null) return;
    try {
      await api.syncPasswords(
        passwords: manager!,
        conn: pushService.state!.conn,
      );
      await _loadCredentialCaches();
      await _loadGroups();
    } catch (error) {
      showSnackbar("Error", "Unable to refresh passwords. $error");
    }
  }

  Future<void> _joinClique() async {
    if (_isJoiningClique) return;
    final keychain = pushService.state?.icloudServices?.keychain;
    if (keychain == null) {
      showSnackbar(
        "Relog required!",
        "Relog required to use Passwords! Relog in Settings -> Reconfigure",
      );
      return;
    }

    setState(() => _isJoiningClique = true);
    try {
      if (await pushService.joinClique()) {
        await api.syncPasswords(passwords: pushService.state!.icloudServices!.passwords!, conn: pushService.state!.conn);
      }
      await _refreshCliqueStatus();
    } finally {
      if (mounted) {
        setState(() => _isJoiningClique = false);
      }
    }
  }

  Future<void> _promptCreateGroup() async {
    if (manager == null || _isCreatingGroup) return;
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Group"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "Group Name",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                showSnackbar("Error", "Please enter a group name.");
                return;
              }
              Navigator.of(context).pop();
              setState(() => _isCreatingGroup = true);
              try {
                await api.createGroup(passwords: manager!, name: name);
                await _loadGroups();
                showSnackbar("Created", "Group created.");
              } catch (error) {
                showSnackbar("Error", "Unable to create group. $error");
              } finally {
                if (mounted) {
                  setState(() => _isCreatingGroup = false);
                }
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;

    if (_isCheckingClique) {
      return SettingsScaffold(
        title: "Passwords",
        initialHeader: null,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        headerColor: headerColor,
        tileColor: tileColor,
        bodySlivers: [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (!_isInClique) {
      return SettingsScaffold(
        title: "Passwords",
        initialHeader: null,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        headerColor: headerColor,
        tileColor: tileColor,
        bodySlivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              [
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "iCloud Keychain",
                ),
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Join iCloud Keychain Clique",
                      subtitle:
                          "Join this device to iCloud Keychain to view passwords, passkeys, codes, and Wi-Fi credentials.",
                      onTap: _isJoiningClique ? null : _joinClique,
                      trailing: _isJoiningClique
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.theme.colorScheme.primary,
                              ),
                            )
                          : const NextButton(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SettingsScaffold(
      title: "Passwords",
      initialHeader: null,
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      headerColor: headerColor,
      tileColor: tileColor,
      actions: [
        IconButton(
          tooltip: "Search",
          icon: Icon(iOS ? CupertinoIcons.search : Icons.search),
          onPressed: _openSearch,
        ),
      ],
      bodySlivers: [
        CupertinoSliverRefreshControl(
          onRefresh: _handlePullToRefresh,
        ),
        SliverList(
          delegate: SliverChildListDelegate(
            [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: PasswordSearchField(
                  backgroundColor: tileColor,
                  onTap: _openSearch,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PasswordCategoryGrid(
                  children: [
                    _buildCategoryCard(
                      title: "Passwords",
                      icon: CupertinoIcons.person_fill,
                      color: const Color(0xFF0A84FF),
                      groupType: PasswordGroupType.web,
                    ),
                    _buildCategoryCard(
                      title: "Passkeys",
                      icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                      color: const Color(0xFF5E5CE6),
                      groupType: PasswordGroupType.passkeys,
                    ),
                    _buildCategoryCard(
                      title: "Codes",
                      icon: CupertinoIcons.lock_shield_fill,
                      color: const Color(0xFFFF9F0A),
                      groupType: PasswordGroupType.codes,
                    ),
                    _buildCategoryCard(
                      title: "Wi-Fi",
                      icon: CupertinoIcons.wifi,
                      color: const Color(0xFF30B0C7),
                      groupType: PasswordGroupType.wifi,
                    ),
                  ],
                ),
              ),
              if (_appleCodesAvailable)
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Apple Account",
                ),
              if (_appleCodesAvailable)
                SettingsSection(
                backgroundColor: tileColor,
                children: [
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "Apple Verification Code",
                    subtitle: "Sign in to your Apple Account on another device or website",
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.lock_shield_fill,
                      materialIcon: Icons.verified_user,
                      containerColor: Colors.blueGrey,
                    ),
                    onTap: _showAppleCode,
                    trailing: const NextButton(),
                  ),
                ],
              ),
              if (isAndroid || (!kIsWeb && Platform.isWindows))
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "AutoFill",
                ),
              if (isAndroid)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Configure device password and passkey providers",
                      subtitle:
                          "Enable to use iCloud Passkeys and Passwords on this device. To autofill passwords, set to preferred provider.",
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.settings,
                        materialIcon: Icons.settings,
                        containerColor: Colors.indigo,
                      ),
                      onTap: () async {
                        await mcs
                            .invokeMethod("open-autofill-provider-settings");
                      },
                      trailing: const NextButton(),
                    ),
                  ],
                ),
              if (!kIsWeb && Platform.isWindows)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    SettingsTile(
                      backgroundColor: tileColor,
                      title: "Browser Extension",
                      subtitle: "Fill these passwords on websites in Chrome and Edge",
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.globe,
                        materialIcon: Icons.extension,
                        containerColor: Colors.green,
                      ),
                      onTap: () => ns.pushSettings(context, const BrowserExtensionPanel()),
                      trailing: const NextButton(),
                    ),
                  ],
                ),
              if (_invitesById.isNotEmpty)
                SettingsHeader(
                  iosSubtitle: iosSubtitle,
                  materialSubtitle: materialSubtitle,
                  text: "Invites",
                ),
              if (_invitesById.isNotEmpty)
                SettingsSection(
                  backgroundColor: tileColor,
                  children: _buildInviteTiles(),
                ),
              SettingsHeader(
                iosSubtitle: iosSubtitle,
                materialSubtitle: materialSubtitle,
                text: "Shared Groups",
              ),
              SettingsSection(
                backgroundColor: tileColor,
                children: [
                  ..._buildGroupsListTiles(),
                  SettingsTile(
                    backgroundColor: tileColor,
                    title: "New Group",
                    onTap: _isCreatingGroup ? null : _promptCreateGroup,
                    leading: _isCreatingGroup
                        ? SizedBox(
                            width: 36,
                            height: 36,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.theme.colorScheme.primary,
                              ),
                            ),
                          )
                        : SizedBox(
                            width: 36,
                            child: Icon(
                              CupertinoIcons.add_circled_solid,
                              size: 30,
                              color: context.theme.colorScheme.primary,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _checkAppleCodes() async {
    try {
      await api.get2FaCode(anisette: pushService.state!.anisette);
      if (mounted) setState(() => _appleCodesAvailable = true);
    } catch (_) {}
  }

  /// The six-digit code a trusted Apple device shows when signing in to the Apple Account
  /// elsewhere; OpenBubbles is one of the account's trusted devices.
  Future<void> _showAppleCode() async {
    String code;
    try {
      code = (await api.get2FaCode(anisette: pushService.state!.anisette)).toString().padLeft(6, "0");
    } catch (e) {
      showSnackbar("Error", "Couldn't get a verification code: $e");
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Apple Verification Code"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Enter this code where your Apple Account asks for one.", style: context.textTheme.bodyLarge),
            const SizedBox(height: 24),
            SelectableText(
              "${code.substring(0, 3)} ${code.substring(3)}",
              style: context.textTheme.displaySmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              showSnackbar("Copied", "Verification code copied to clipboard.");
            },
            child: const Text("Copy"),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Done")),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required Color color,
    required PasswordGroupType groupType,
  }) {
    return PasswordCategoryCard(
      title: title,
      icon: icon,
      color: color,
      backgroundColor: tileColor,
      count: _counts[groupType],
      onTap: () async {
        if (manager == null) return;
        await ns.pushSettings(
          context,
          PasswordsGroupPanel(
            title: title,
            groupType: groupType,
            provider: manager!,
            groupNamesById: _groupNamesById,
            groupUserId: _groupsUserId,
          ),
        );
        // items may have been added, edited or deleted
        await _loadCredentialCaches();
      },
    );
  }

  List<Widget> _buildGroupsListTiles() {
    if (_groupsById.isEmpty) {
      return [];
    }

    final entries = _groupsById.entries.toList()
      ..sort((a, b) => a.value.displayName
          .toLowerCase()
          .compareTo(b.value.displayName.toLowerCase()));

    final tiles = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final groupId = entries[i].key;
      final summary = entries[i].value;
      final groupName = summary.displayName.trim().isEmpty
          ? "(unknown group)"
          : summary.displayName;
      tiles.add(
        SettingsTile(
          backgroundColor: tileColor,
          title: groupName,
          leading: SiteIcon(name: groupName, icon: CupertinoIcons.person_2_fill),
          onTap: () async {
            if (manager == null) return;
            final result = await ns.pushSettings(
              context,
              GroupCredentialsPanel(
                groupId: groupId,
                groupName: groupName,
                provider: manager!,
                groupNamesById: _groupNamesById,
                groupUserId: _groupsUserId,
                initialSummary: summary,
              ),
            );
            if (result == true) {
              await _loadGroups();
            }
          },
          trailing: const NextButton(),
        ),
      );
      tiles.add(const SettingsDivider());
    }
    return tiles;
  }

  List<Widget> _buildInviteTiles() {
    final entries = _invitesById.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final tiles = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      final inviteId = entries[i].key;
      final invite = entries[i].value;
      final pending = _pendingInviteActions.contains(inviteId);
      final groupName = invite.groupName.trim().isEmpty
          ? "(unknown group)"
          : invite.groupName;
      tiles.add(
        SettingsTile(
          backgroundColor: tileColor,
          title: groupName,
          subtitle: _displayHandle(invite.inviteeHandle),
          trailing: pending
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.theme.colorScheme.primary,
                  ),
                )
              : Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => _handleInviteAction(
                        inviteId,
                        accept: false,
                      ),
                      child: const Text("Decline"),
                    ),
                    TextButton(
                      onPressed: () => _handleInviteAction(
                        inviteId,
                        accept: true,
                      ),
                      child: const Text("Accept"),
                    ),
                  ],
                ),
        ),
      );
      if (i != entries.length - 1) {
        tiles.add(const SettingsDivider());
      }
    }
    return tiles;
  }

  String _displayHandle(String handle) {
    try {
      return RustPushBBUtils.rustHandleToBB(handle).displayName;
    } catch (_) {
      return "Contact";
    }
  }

  Future<void> _openSearch() async {
    if (manager == null) return;
    final items = await _loadSearchItems();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<_PasswordSearchItem?>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: animation,
          child: _PasswordSearchPage(items: items),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final result = await ns.pushSettings(
      context,
      CredentialDetailPanel(
        credential: selected.entry,
        provider: manager!,
        groupNamesById: _groupNamesById,
        groupUserId: _groupsUserId,
      ),
    );
    if (result == true) {
      await api.syncPasswords(
          passwords: manager!, conn: pushService.state!.conn);
      await _loadGroups();
    }
  }

  /// Searched word by word: "ring seascape" finds ring.com / seascapepm@... Covers the title, user
  /// name, every website of the login, group, other domains and notes.
  _PasswordSearchItem _searchItemFor(CredentialEntry credential) {
    final raw = credential.passwordRaw!;
    final website = siteHostOf(raw.srvr);
    const skip = {"Password", "Created", "Modified"};
    return _PasswordSearchItem(
      entry: credential,
      queryText: [
        credential.item.title,
        credential.item.subtitle,
        raw.srvr,
        for (final copy in credential.copies) copy.raw.srvr,
        for (final f in credential.item.fields)
          if (!skip.contains(f.label)) f.value,
      ].join(" ").toLowerCase(),
      subtitle: [
        if (raw.acct.trim().isNotEmpty) raw.acct.trim(),
        if (website.isNotEmpty && website != credential.item.title)
          credential.copies.isEmpty ? website : "$website +${credential.copies.length}",
      ].join(" · "),
    );
  }

  Future<List<_PasswordSearchItem>> _loadSearchItems() async {
    if (manager == null) return const [];
    final passwords = await api.getPasswords(passwords: manager!);
    final wifi = await api.getWifiPasswords(passwords: manager!);
    final metas = await api.getPasswordsMeta(passwords: manager!);
    final metasBySiteUser = _indexMetasBySiteAndUser(metas);
    final items = <_PasswordSearchItem>[];
    final webEntries = <CredentialEntry>[];

    for (final entry in passwords.entries) {
      final passwordGroup = entry.value.$1;
      final password = entry.value.$2;
      final match = _takeMatchingMeta(
        metasBySiteUser,
        site: password.srvr,
        user: password.acct,
        group: passwordGroup,
      );
      final meta = match?.$2;
      final data = meta?.getPasswordData();
      final groupName = _resolveGroupName(passwordGroup);
      final credential = CredentialEntry(
        id: entry.key,
        group: passwordGroup,
        passwordMetaId: match?.$1,
        groupType: PasswordGroupType.web,
        item: buildPasswordCredential(
          meta: meta,
          password: password,
          data: data,
          group: groupName,
          groupType: PasswordGroupType.web,
        ),
        passwordMeta: meta,
        passwordRaw: password,
      );
      webEntries.add(credential);
    }
    // one result per login (copies for a site's other addresses are merged)
    for (final credential in mergeSameLogins(webEntries)) {
      items.add(_searchItemFor(credential));
    }

    for (final entry in wifi.entries) {
      final wifiGroup = entry.value.$1;
      final wifiEntry = entry.value.$2;
      final ssid = wifiEntry.acct.trim();
      final groupName = _resolveGroupName(wifiGroup);
      final credential = CredentialEntry(
        id: entry.key,
        group: wifiGroup,
        groupType: PasswordGroupType.wifi,
        item: buildWifiCredential(
          wifi: wifiEntry,
          group: groupName,
        ),
        wifiPassword: wifiEntry,
      );
      items.add(
        _PasswordSearchItem(
          entry: credential,
          queryText: "$ssid wi-fi wifi".toLowerCase(),
          subtitle: "Wi-Fi network",
        ),
      );
    }

    // passkeys too, so a search finds every way to sign in to a site
    try {
      final passkeys = await api.getPasskeys(passwords: manager!);
      for (final entry in passkeys.entries) {
        final passkeyGroup = entry.value.$1;
        final passkey = entry.value.$2;
        final groupName = _resolveGroupName(passkeyGroup);
        final item = buildPasskeyCredential(passkey: passkey, group: groupName);
        items.add(
          _PasswordSearchItem(
            entry: CredentialEntry(
              id: entry.key,
              group: passkeyGroup,
              groupType: PasswordGroupType.passkeys,
              item: item,
              passkey: passkey,
            ),
            queryText: [passkey.labl, item.title, item.subtitle, if (passkeyGroup != null) groupName, "passkey"]
                .join(" ")
                .toLowerCase(),
            subtitle: [if (item.subtitle.trim().isNotEmpty) item.subtitle.trim(), "Passkey"].join(" · "),
          ),
        );
      }
    } catch (_) {}

    items.sort((a, b) => a.entry.item.title.toLowerCase().compareTo(b.entry.item.title.toLowerCase()));

    return items;
  }

  Map<String, List<(String, String?, api.PasswordManagerMeta)>>
      _indexMetasBySiteAndUser(
    Map<String, (String?, api.PasswordManagerMeta)> metas,
  ) {
    final result = <String, List<(String, String?, api.PasswordManagerMeta)>>{};
    for (final entry in metas.entries) {
      final group = entry.value.$1;
      final meta = entry.value.$2;
      final key = _siteUserKey(site: meta.srvr, user: meta.acct);
      result.putIfAbsent(
          key, () => <(String, String?, api.PasswordManagerMeta)>[]);
      result[key]!.add((entry.key, group, meta));
    }
    return result;
  }

  (String, api.PasswordManagerMeta)? _takeMatchingMeta(
    Map<String, List<(String, String?, api.PasswordManagerMeta)>>
        metasBySiteUser, {
    required String site,
    required String user,
    required String? group,
  }) {
    final key = _siteUserKey(site: site, user: user);
    final bucket = metasBySiteUser[key];
    if (bucket == null || bucket.isEmpty) {
      return null;
    }
    for (var i = 0; i < bucket.length; i++) {
      final candidate = bucket[i];
      if (_sameGroup(candidate.$2, group)) {
        bucket.removeAt(i);
        return (candidate.$1, candidate.$3);
      }
    }
    return null;
  }

  String _siteUserKey({required String site, required String user}) {
    final normalizedSite = site.trim().toLowerCase();
    final normalizedUser = user.trim().toLowerCase();
    return "$normalizedSite::$normalizedUser";
  }

  bool _sameGroup(String? a, String? b) {
    final normalizedA = a?.trim() ?? "";
    final normalizedB = b?.trim() ?? "";
    return normalizedA == normalizedB;
  }

  String _resolveGroupName(String? groupId) {
    if (groupId == null || groupId.trim().isEmpty) {
      return "(unknown group)";
    }
    return _groupNamesById[groupId] ?? "(unknown group)";
  }
}

class _PasswordSearchItem {
  final CredentialEntry entry;
  final String queryText;
  final String subtitle;

  const _PasswordSearchItem({
    required this.entry,
    required this.queryText,
    required this.subtitle,
  });
}

/// Searches saved passwords and Wi-Fi networks word by word. Its own page rather than
/// showSearch(), so the search box sits below the Windows title bar's drag strip and can be
/// clicked into and selected normally.
class _PasswordSearchPage extends StatefulWidget {
  const _PasswordSearchPage({required this.items});

  final List<_PasswordSearchItem> items;

  @override
  State<_PasswordSearchPage> createState() => _PasswordSearchPageState();
}

class _PasswordSearchPageState extends OptimizedState<_PasswordSearchPage> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_PasswordSearchItem> get _results {
    final words = _controller.text.trim().toLowerCase().split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
    // every word has to match somewhere (site, user name, title, group, other domains)
    if (words.isEmpty) return widget.items;
    return widget.items.where((item) => words.every(item.queryText.contains)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      backgroundColor: headerColor,
      body: SafeArea(
        child: Column(
          children: [
            // clear of the custom title bar's drag strip on desktop
            SizedBox(height: kIsDesktop ? 36 : 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "Back",
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.arrow_left),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        if (results.length == 1) Navigator.of(context).pop(results.first);
                      },
                      decoration: InputDecoration(
                        hintText: "Search sites, user names, notes, groups",
                        prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: "Clear",
                                onPressed: _controller.clear,
                                icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 18),
                              ),
                        filled: true,
                        fillColor: tileColor,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text("No matching passwords, passkeys or Wi-Fi networks."))
                  // the same rows as the Passwords lists: site tile, name, user name
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        final first = index == 0;
                        final last = index == results.length - 1;
                        return ClipRRect(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(first ? 12 : 0),
                            bottom: Radius.circular(last ? 12 : 0),
                          ),
                          child: Container(
                            color: tileColor,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SettingsTile(
                                  backgroundColor: tileColor,
                                  title: item.entry.item.title,
                                  subtitle: item.subtitle,
                                  leading: CredentialAvatar(credential: item.entry.item),
                                  trailing: const NextButton(),
                                  onTap: () => Navigator.of(context).pop(item),
                                ),
                                if (!last) const SettingsDivider(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
