import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

/// Opens Passwords straight to search from anywhere: the Ctrl+Alt+P shortcut (registered by the
/// Windows runner), the "Passwords" Start menu shortcut and openbubbles://passwords links, the tray
/// menu, and the browser extension's popup.
class PasswordsQuickOpen {
  static const _channel = MethodChannel("openbubbles/shortcuts");
  static bool _showing = false;

  /// Listens for the global shortcut from the Windows runner.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == "openPasswords") await open();
    });
  }

  static bool handlesLink(String link) => link.toLowerCase().startsWith("openbubbles://passwords");

  static Future<void> open() async {
    try {
      if (kIsDesktop) {
        await windowManager.show();
        await windowManager.focus();
      }
      final context = Get.context;
      // already open (the route stays pushed until closed): just bring the window forward
      if (context == null || !ss.settings.finishedSetup.value || _showing) return;
      _showing = true;
      try {
        await goToPasswords(context, openSearch: true);
      } finally {
        _showing = false;
      }
    } catch (e, s) {
      Logger.error("Couldn't open Passwords", error: e, trace: s);
    }
  }
}
