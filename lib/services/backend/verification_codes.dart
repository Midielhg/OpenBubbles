import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';

/// Verification codes in incoming texts (bank, Plaid, Google, ...): finding them, and "Delete After
/// Use" like iOS, where a code's text goes to Recently Deleted once the code has been filled by the
/// browser extension or copied from its notification.
class VerificationCodes {
  // Codes for signing in to an Apple Account stay in OpenBubbles (and on the user's devices); they're
  // never offered to websites or copied from notifications.
  static final _appleCode = RegExp(r"apple\s*(account|id)|@apple\.com|#apple\.com|appleid", caseSensitive: false);
  static final _codeHint = RegExp(
      r"code|c[oó]digo|otp|passcode|password|pin\b|verif|one[- ]?time|2fa|mfa|security|login|sign[- ]?in|token|clave",
      caseSensitive: false);
  // 4-8 digits, optionally written with a dash or space in the middle (123-456), or a G-123456 style prefix
  static final _codePattern = RegExp(r"(?<![\w-])(?:[A-Z]{1,3}-)?(\d{3,4}[- ]\d{3,4}|\d{4,8})(?![\w-])");

  /// The verification code in a message's text, if it has one.
  static String? codeIn(String text) {
    if (text.trim().isEmpty || _appleCode.hasMatch(text) || !_codeHint.hasMatch(text)) return null;
    final match = _codePattern.firstMatch(text);
    return match?.group(1)!.replaceAll(RegExp(r"[- ]"), "");
  }

  static String? codeInMessage(Message message) {
    if (message.isFromMe ?? true) return null;
    return codeIn("${message.subject ?? ""} ${message.text ?? ""}");
  }

  /// The code in this message was used: move its text to Recently Deleted (a little later, so the
  /// site has the code before the text disappears), when "Delete After Use" is on.
  static void used(String messageGuid) {
    if (!ss.settings.deleteCodesAfterUse.value) return;
    Future.delayed(const Duration(seconds: 3), () {
      try {
        final message = Message.findOne(guid: messageGuid);
        if (message == null || message.dateDeleted != null || codeInMessage(message) == null) return;
        Message.softDelete(messageGuid);
        Logger.info("Deleted a used verification code's message");
      } catch (e, s) {
        Logger.warn("Couldn't delete the used verification code's message", error: e, trace: s);
      }
    });
  }
}
