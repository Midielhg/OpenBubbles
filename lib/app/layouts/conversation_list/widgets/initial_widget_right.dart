import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/navigator/navigator_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/window_effect.dart';
import 'package:get/get.dart';

class InitialWidgetRight extends StatefulWidget {
  const InitialWidgetRight({super.key});

  @override
  State<StatefulWidget> createState() => _InitialWidgetRightState();
}

class _InitialWidgetRightState extends OptimizedState<InitialWidgetRight> {
  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Scaffold(
        backgroundColor: ss.settings.windowEffect.value != WindowEffect.disabled ? Colors.transparent : context.theme.colorScheme.background,
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            Center(
              child: Text("Select a chat from the list",
                  style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.outline)),
            ),
            // same floating compose button as the conversation toolbar, so it's always in one place
            Positioned(
              top: 8,
              left: 20,
              child: GlassCircleButton(
                icon: CupertinoIcons.square_pencil,
                iconSize: 19,
                tooltip: "New Message",
                onTap: () => ns.pushAndRemoveUntil(
                  context,
                  ChatCreator(initialAttachments: const []),
                  (route) => route.isFirst,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
