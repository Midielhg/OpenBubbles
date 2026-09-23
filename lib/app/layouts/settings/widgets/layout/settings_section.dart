import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  final List<Widget> children;
  final Color backgroundColor;

  SettingsSection({required this.children, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    if (macLook) {
      // macOS grouped card: 12px radius, one hairline edge, no drop shadow
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Glass.border(context), width: 0.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
    }
    return Padding(
      padding: ss.settings.skin.value == Skins.iOS
          ? const EdgeInsets.symmetric(horizontal: 20)
          : ss.settings.skin.value == Skins.Samsung
          ? const EdgeInsets.symmetric(vertical: 5)
          : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius:
        ss.settings.skin.value == Skins.Samsung ? BorderRadius.circular(25) :
        ss.settings.skin.value == Skins.iOS ? BorderRadius.circular(10) : BorderRadius.circular(0),
        clipBehavior: ss.settings.skin.value != Skins.Material ? Clip.antiAlias : Clip.none,
        child: Container(
          color: ss.settings.skin.value == Skins.iOS ? null : backgroundColor,
          decoration: ss.settings.skin.value == Skins.iOS ? BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.darkenAmount(0.1).withOpacity(0.25),
                spreadRadius: 5,
                blurRadius: 7,
                offset: const Offset(0, 3), // changes position of shadow
              ),
            ],
          ) : null, 
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}