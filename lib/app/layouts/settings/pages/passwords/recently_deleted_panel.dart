import 'package:bluebubbles/app/layouts/settings/pages/passwords/recently_deleted_store.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/src/rust/lib.dart' as lib;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Logins deleted in the last 30 days, with Recover and Delete Now.
class RecentlyDeletedPanel extends StatefulWidget {
  const RecentlyDeletedPanel({super.key, required this.provider});

  final lib.ArcPasswordManagerDefaultAnisetteProvider provider;

  @override
  State<StatefulWidget> createState() => _RecentlyDeletedPanelState();
}

class _RecentlyDeletedPanelState extends OptimizedState<RecentlyDeletedPanel> {
  List<DeletedLogin>? items;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final loaded = await RecentlyDeletedStore.load();
    if (mounted) setState(() => items = loaded);
  }

  Future<void> recover(DeletedLogin item) async {
    try {
      await RecentlyDeletedStore.restore(widget.provider, item);
      showSnackbar("Recovered", "${item.title} is back in your passwords.");
    } catch (e) {
      showSnackbar("Error", "Couldn't recover the login: $e");
    }
    await reload();
  }

  Future<void> deleteNow(DeletedLogin item) async {
    await RecentlyDeletedStore.forget(item);
    await reload();
  }

  void options(DeletedLogin item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text(item.title, style: context.theme.textTheme.titleLarge),
        content: Text(
          "${item.username}\nDeleted ${item.deletedAt.toLocal().toString().substring(0, 16)}. "
          "It will be removed for good in ${item.daysLeft} days.",
          style: context.textTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              deleteNow(item);
            },
            child: Text("Delete Now", style: TextStyle(color: context.theme.colorScheme.error)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              recover(item);
            },
            child: Text("Recover", style: TextStyle(color: context.theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    return SettingsScaffold(
      title: "Recently Deleted",
      initialHeader: "Deleted in the last 30 days",
      iosSubtitle: iosSubtitle,
      materialSubtitle: materialSubtitle,
      tileColor: tileColor,
      headerColor: headerColor,
      bodySlivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            SettingsSection(
              backgroundColor: tileColor,
              children: list == null
                  ? [const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))]
                  : list.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text("No recently deleted logins.", style: context.theme.textTheme.bodyMedium),
                          ),
                        ]
                      : [
                          for (final item in list)
                            SettingsTile(
                              backgroundColor: tileColor,
                              title: item.title,
                              subtitle: "${item.username} · ${item.daysLeft} days left",
                              onTap: () => options(item),
                              trailing: TextButton(
                                onPressed: () => recover(item),
                                child: Text("Recover", style: TextStyle(color: context.theme.colorScheme.primary)),
                              ),
                            ),
                        ],
            ),
          ]),
        ),
      ],
    );
  }
}
