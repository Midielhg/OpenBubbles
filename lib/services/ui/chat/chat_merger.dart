import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/objectbox.g.dart';
import 'package:bluebubbles/utils/logger/logger.dart';

/// One conversation per person, like Apple Messages: someone who messages from their phone number and
/// from an email (or whose chat got re-created under a new id) otherwise ends up with several separate
/// 1:1 chats. Only iMessage 1:1 chats are merged; group chats, SMS and routing stubs are left alone.
class DirectChatMerger {
  static bool _mergeable(Chat c) =>
      !c.isRoutingStub && !c.isRpSms && c.isIMessage && c.dateDeleted == null && c.handles.length == 1;

  /// The person a 1:1 chat is with: their contact when linked, else the address itself.
  static String? _personKey(Handle h) {
    final contact = h.contact;
    if (contact != null && !contact.isShared && contact.dbId != null) return "contact:${contact.dbId}";
    return "address:${h.address.toLowerCase()}";
  }

  static DateTime _latest(Chat c) {
    final query = (Database.messages.query(Message_.dateDeleted.isNull())
          ..link(Message_.chat, Chat_.id.equals(c.id!))
          ..order(Message_.dateCreated, flags: Order.descending))
        .build()
      ..limit = 1;
    final latest = query.findFirst();
    query.close();
    return latest?.dateCreated ?? c.dbOnlyLatestMessageDate ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Merges duplicate 1:1 chats in the database. Returns how many chats were folded into another.
  static int mergeDuplicates() {
    final groups = <String, List<Chat>>{};
    for (final c in Database.chats.getAll()) {
      if (!_mergeable(c)) continue;
      final key = _personKey(c.handles.first);
      if (key != null) groups.putIfAbsent(key, () => []).add(c);
    }

    var merged = 0;
    for (final group in groups.values.where((g) => g.length > 1)) {
      // keep the chat with the most recent message: its address is the one they last used
      final dated = {for (final c in group) c: _latest(c)};
      group.sort((a, b) => dated[b]!.compareTo(dated[a]!));
      final primary = group.first;
      Database.runInTransaction(TxMode.write, () {
        for (final other in group.skip(1)) {
          final query = (Database.messages.query()..link(Message_.chat, Chat_.id.equals(other.id!))).build();
          final moved = query.find();
          query.close();
          for (final m in moved) {
            m.chat.target = primary;
          }
          Database.messages.putMany(moved);

          // messages that still reference the old conversation id route here from now on
          for (final ref in [other.guid, ...other.guidRefs]) {
            if (!primary.guidRefs.contains(ref)) primary.guidRefs.add(ref);
          }
          if ((other.isPinned ?? false) && !(primary.isPinned ?? false)) {
            primary.isPinned = true;
            primary.pinIndex = other.pinIndex;
          }
          if ((other.hasUnreadMessage ?? false)) primary.hasUnreadMessage = true;
          Database.chats.remove(other.id!);
          merged++;
          Logger.info("Merged chat ${other.guid} (${moved.length} messages) into ${primary.guid}");
        }
        primary.dbOnlyLatestMessageDate = dated[primary];
        Database.chats.put(primary);
      });
    }
    if (merged > 0) Logger.info("Chat merge: folded $merged duplicate 1:1 chats");
    return merged;
  }

  /// For an incoming message whose 1:1 participant has no chat yet: the existing chat with the same
  /// person under another address, so it lands in their conversation instead of starting a new one.
  static Chat? existingChatForPerson(Handle participant) {
    final key = _personKey(participant);
    if (key == null || key.startsWith("address:")) return null; // same address would have matched already
    for (final c in Database.chats.getAll()) {
      if (_mergeable(c) && _personKey(c.handles.first) == key) return c;
    }
    return null;
  }
}
