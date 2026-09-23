import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/outlook_contacts.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings entry point for Outlook / Exchange contacts: connect (device-code sign-in) or disconnect.
Future<void> showOutlookContactsFlow(BuildContext context) async {
  if (OutlookContacts.connected) {
    final disconnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text("Outlook / Exchange", style: context.theme.textTheme.titleLarge),
        content: Text("Connected as ${OutlookContacts.account ?? "your Microsoft account"}. Disconnect? Outlook contacts stay until the next sync.",
            style: context.theme.textTheme.bodyLarge),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Disconnect")),
        ],
      ),
    );
    if (disconnect == true) await OutlookContacts.disconnect();
    return;
  }

  // 1. app registration ids (not secrets)
  final clientCtrl = TextEditingController(text: OutlookContacts.clientId);
  final tenantCtrl = TextEditingController(text: OutlookContacts.tenantId == "organizations" ? "" : OutlookContacts.tenantId);
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.theme.colorScheme.properSurface,
      title: Text("Connect Outlook / Exchange", style: context.theme.textTheme.titleLarge),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Enter the IDs from your Entra app registration. Contacts are read-only.", style: context.theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        TextField(controller: clientCtrl, decoration: const InputDecoration(labelText: "Application (client) ID")),
        TextField(controller: tenantCtrl, decoration: const InputDecoration(labelText: "Directory (tenant) ID")),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Continue")),
      ],
    ),
  );
  if (proceed != true || clientCtrl.text.trim().isEmpty) return;

  final OutlookDeviceCode code;
  try {
    code = await OutlookContacts.startSignIn(clientId: clientCtrl.text, tenantId: tenantCtrl.text.isEmpty ? "organizations" : tenantCtrl.text);
  } catch (e) {
    showSnackbar("Outlook", e.toString().replaceFirst("Exception: ", ""));
    return;
  }

  // 2. device code: user signs in on Microsoft's page (their MFA applies there)
  bool cancelled = false;
  final result = OutlookContacts.completeSignIn(code, cancelled: () => cancelled);
  if (!context.mounted) return;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      result.then((_) {
        if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
      }, onError: (_) {
        if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
      });
      return AlertDialog(
        backgroundColor: dialogContext.theme.colorScheme.properSurface,
        title: Text("Sign in with Microsoft", style: dialogContext.theme.textTheme.titleLarge),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text("Enter this code on the Microsoft sign-in page:", style: dialogContext.theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          SelectableText(code.userCode,
              style: dialogContext.theme.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w700, letterSpacing: 3)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code.userCode));
              await launchUrl(Uri.parse(code.verificationUri), mode: LaunchMode.externalApplication);
            },
            child: const Text("Copy code & open sign-in page"),
          ),
          const SizedBox(height: 16),
          const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text("Waiting for you to finish signing in…"),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.of(dialogContext).pop();
            },
            child: const Text("Cancel"),
          ),
        ],
      );
    },
  );

  try {
    final account = await result;
    await dialog;
    showSnackbar("Outlook connected", "Syncing contacts for $account…");
    await cs.refreshContacts();
  } catch (e) {
    await dialog;
    if (!cancelled) showSnackbar("Outlook", e.toString().replaceFirst("Exception: ", ""));
  }
}
