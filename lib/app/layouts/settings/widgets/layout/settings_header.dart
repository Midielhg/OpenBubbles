import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

class SettingsHeader extends StatelessWidget {
  final TextStyle? iosSubtitle;
  final TextStyle? materialSubtitle;
  final String text;

  SettingsHeader({
    required this.iosSubtitle,
    required this.materialSubtitle,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (ss.settings.skin.value == Skins.Samsung) return const SizedBox(height: 15);
    if (macLook) {
      return Container(
        height: 44,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.only(bottom: 7, left: 32),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: Theme.of(context).colorScheme.onBackground.withOpacity(0.72),
        )),
      );
    }
    return Container(
      height: ss.settings.skin.value == Skins.iOS ? 60 : 40,
      alignment: Alignment.bottomLeft,
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: 8.0, left: ss.settings.skin.value == Skins.iOS ? 30 : 15),
        child: Text(text.psCapitalize, style: ss.settings.skin.value == Skins.iOS ? iosSubtitle : materialSubtitle),
      ),
    );
  }
}
