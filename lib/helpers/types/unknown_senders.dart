import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get/get.dart';

/// The user's own addresses (iMessage handles), so chats can tell the user apart from the people
/// they're talking to. Loaded once, the first time it's needed.
class MyAddresses {
  static Set<String> _addresses = {};
  static bool _loading = false;

  /// Bumped when the addresses arrive, so lists and counts using [UnknownSender] can update.
  static final RxInt loaded = 0.obs;

  static String _normalize(String address) {
    final a = address.replaceFirst(RegExp(r"^(tel|mailto):"), "").trim().toLowerCase();
    if (a.contains("@")) return a;
    final digits = a.replaceAll(RegExp(r"\D"), "");
    // compare phone numbers by their last 10 digits (with or without the country code)
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  static Set<String> get addresses {
    if (_addresses.isEmpty && !_loading && pushService.state != null) {
      _loading = true;
      api.getHandles(state: pushService.state!.client).then((handles) {
        _addresses = handles.map(_normalize).where((a) => a.isNotEmpty).toSet();
        loaded.value++;
      }).catchError((e) {
        Logger.warn("Couldn't load your own addresses", error: e);
      }).whenComplete(() => _loading = false);
    }
    return _addresses;
  }

  static bool isMine(String address) => addresses.contains(_normalize(address));

  /// The user's own contact card: it lists one of the user's addresses.
  static bool isMyContact(Contact contact) =>
      addresses.isNotEmpty && [...contact.phones, ...contact.emails].any(isMine);
}

extension UnknownSender on Chat {
  /// Nobody in the chat besides the user is in their contacts, like iOS' "Unknown Senders". The
  /// user's own number or contact card (an MMS or a group with a stranger, say) doesn't count.
  bool get isUnknownSender {
    final others = participants.where((h) {
      if (MyAddresses.isMine(h.address)) return false;
      final contact = h.contact;
      return contact == null || !MyAddresses.isMyContact(contact);
    }).toList();
    if (others.isEmpty) return participants.isNotEmpty && !participants.any((h) => h.contact != null);
    return !others.any((h) => h.contact != null);
  }
}
