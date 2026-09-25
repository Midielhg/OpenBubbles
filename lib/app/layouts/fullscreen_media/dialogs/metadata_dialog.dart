import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:intl/intl.dart' as intl;
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// macOS "Get Info" style panel: readable facts about the file, not the raw transport metadata.
void _showMacInfo(Attachment a, BuildContext context) {
  final message = a.message.target;
  final sender = message == null ? null : (message.isFromMe ?? false) ? "You" : (message.handle ?? message.getHandle())?.displayName;
  final ext = (a.transferName ?? "").split(".").last.toUpperCase();
  final kindWord = switch (a.mimeStart) { "image" => "image", "video" => "video", "audio" => "audio", _ => "file" };
  final rows = <(String, String)>[
    if (a.transferName != null) ("Name", a.transferName!),
    ("Kind", ext.isNotEmpty && ext.length <= 5 ? "$ext $kindWord" : (a.mimeType ?? "File")),
    if ((a.totalBytes ?? 0) > 0) ("Size", a.getFriendlySize()),
    if ((a.width ?? 0) > 0 && (a.height ?? 0) > 0) ("Dimensions", "${a.width} × ${a.height}"),
    if (sender != null) ("From", sender),
    if (message?.dateCreated != null) ("Date", intl.DateFormat.yMMMMd().add_jm().format(message!.dateCreated!)),
    // real photo metadata (camera, location...) only: skip transport internals and blobs
    for (final e in (a.metadata ?? {}).entries)
      if (e.value != null && e.key != "rustpush" && e.value.toString().length <= 120 && !e.value.toString().contains("<?xml"))
        (e.key.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => " ${m[1]}").capitalizeFirst ?? e.key, e.value.toString()),
  ];
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.25),
    builder: (context) => Center(
      child: SizedBox(
        width: 380,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(18),
          blur: 30,
          fillOpacity: 0.9,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Info", style: context.theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 96,
                        child: Text(label,
                            textAlign: TextAlign.right,
                            style: context.theme.textTheme.bodyMedium!.copyWith(color: context.theme.colorScheme.outline)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: SelectableText(value, style: context.theme.textTheme.bodyMedium)),
                    ]),
                  ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Done")),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void showMetadataDialog(Attachment a, BuildContext context) {
  if (macLook) return _showMacInfo(a, context);
  List<Widget> metaWidgets = [];
  final metadataMap = <String, dynamic>{
    'filename': a.transferName,
    'mime': a.mimeType,
  }..addAll(a.metadata ?? {});
  for (MapEntry entry in metadataMap.entries.where((element) => element.value != null)) {
    metaWidgets.add(RichText(
      text: TextSpan(
        children: [
          TextSpan(text: "${entry.key}: ", style: context.theme.textTheme.bodyLarge!.apply(fontWeightDelta: 2)),
          TextSpan(text: entry.value.toString(), style: context.theme.textTheme.bodyLarge)
        ],
      ),
    ));
  }

  if (metaWidgets.isEmpty) {
    metaWidgets.add(Text(
      "No metadata available",
      style: context.theme.textTheme.bodyLarge,
      textAlign: TextAlign.center,
    ));
  }

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        "Metadata",
        style: context.theme.textTheme.titleLarge,
      ),
      backgroundColor: context.theme.colorScheme.properSurface,
      content: SizedBox(
        width: ns.width(context) * 3 / 5,
        height: context.height * 1 / 4,
        child: Container(
          padding: const EdgeInsets.all(10.0),
          decoration: BoxDecoration(
            color: context.theme.colorScheme.background,
            borderRadius: BorderRadius.circular(10)
          ),
          child: ListView(
            physics: ThemeSwitcher.getScrollPhysics(),
            children: metaWidgets,
          ),
        ),
      ),
      actions: [
        TextButton(
          child: Text(
            "Close",
            style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}