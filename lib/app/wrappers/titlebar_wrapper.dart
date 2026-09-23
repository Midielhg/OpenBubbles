import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/header/header_widgets.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_obx_widget.dart';
import 'package:get/get_utils/src/extensions/context_extensions.dart';
import 'package:window_manager/window_manager.dart';

class TitleBarWrapper extends StatelessWidget {
  TitleBarWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsDesktop) {
      return Stack(
        children: <Widget>[
          child,
          if (ss.settings.showConnectionIndicator.value) const ConnectionIndicator(),
        ],
      );
    }

    return Obx(() => (ss.settings.useCustomTitleBar.value && Platform.isLinux) || (kIsDesktop && !Platform.isLinux) ? WindowBorder(
        color: Colors.transparent,
        width: 0,
        child: Stack(
          children: <Widget>[
            child,
            const TitleBar(),
            if (ss.settings.showConnectionIndicator.value)
              const ConnectionIndicator(),
          ]
        ),
      ) : Stack(
        children: <Widget>[
          child,
          if (ss.settings.showConnectionIndicator.value)
            const ConnectionIndicator(),
        ],
      ),
    );
  }
}

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(),
          ),
          const _HoverReveal(child: WindowButtons())
        ],
      ),
    );
  }
}

/// Keeps the caption buttons out of sight until the pointer is over them. They stay hit-testable
/// while hidden, so a click in that corner still works.
class _HoverReveal extends StatefulWidget {
  const _HoverReveal({required this.child});
  final Widget child;

  @override
  State<_HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<_HoverReveal> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        opacity: _hover ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) {
    // neutral Windows 11 caption buttons: text-colored glyphs, faint grey hover, red close
    final dark = context.theme.brightness == Brightness.dark;
    final icon = dark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8);
    WindowButtonColors buttonColors = WindowButtonColors(
        iconNormal: icon,
        mouseOver: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
        mouseDown: dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
        iconMouseOver: icon,
        iconMouseDown: icon.withOpacity(0.6));

    WindowButtonColors closeButtonColors = WindowButtonColors(
        iconNormal: icon,
        mouseOver: const Color(0xFFC42B1C),
        mouseDown: const Color(0xFFC42B1C).withOpacity(0.9),
        iconMouseOver: Colors.white,
        iconMouseDown: Colors.white.withOpacity(0.7));
    return Row(
      children: [
        MinimizeWindowButton(
          colors: buttonColors,
          onPressed: () async => ss.settings.minimizeToTray.value ? await windowManager.hide() : await windowManager.minimize(),
          animate: true,
        ),
        MaximizeWindowButton(
          colors: buttonColors,
          animate: true,
        ),
        CloseWindowButton(
          colors: closeButtonColors,
          onPressed: () async => await windowManager.close(),
          animate: true,
        ),
      ],
    );
  }
}
