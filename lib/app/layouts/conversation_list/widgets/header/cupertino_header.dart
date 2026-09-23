import 'dart:ui';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/search/search_view.dart';
import 'package:bluebubbles/app/wrappers/fade_on_scroll.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class CupertinoHeader extends StatelessWidget {
  const CupertinoHeader({Key? key, required this.controller});

  final ConversationListController controller;

  @override
  Widget build(BuildContext context) {
    if (kIsDesktop && !ns.isAvatarOnly(context)) {
      return SliverPersistentHeader(pinned: true, delegate: _MacListHeaderDelegate(controller));
    }
    final double topMargin = context.orientation == Orientation.landscape && context.isPhone
        ? 20
        : kIsDesktop || kIsWeb
            ? 40
            : kToolbarHeight + 30;

    return SliverToBoxAdapter(
      child: FadeOnScroll(
        scrollController: controller.iosScrollController,
        zeroOpacityOffset: topMargin + 15,
        child: Container(
          margin: EdgeInsets.only(
            top: topMargin,
            left: 20,
            right: 20,
            bottom: 5,
          ),
          child: Obx(() {
            ns.listener.value;
            return Row(
              mainAxisAlignment: ns.isAvatarOnly(context) ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: <Widget>[
                if (!ns.isAvatarOnly(context))
                  Expanded(
                    child: HeaderText(controller: controller),
                  ),
                if (ns.isAvatarOnly(context))
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: OverflowMenu(extraItems: true, controller: controller),
                  ),
                if (!ns.isAvatarOnly(context))
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SyncIndicator(size: 16),
                      const SizedBox(width: 10.0),
                      ClipOval(
                        child: Material(
                          color: context.theme.colorScheme.properSurface, // button color
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: InkWell(
                              child: Icon(CupertinoIcons.search, color: context.theme.colorScheme.properOnSurface, size: 18),
                              onTap: () {
                                ns.pushLeft(context, SearchView());
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10.0),
                      if (ss.settings.moveChatCreatorToHeader.value)
                        ClipOval(
                          child: Material(
                            color: context.theme.colorScheme.properSurface, // button color
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                                  if (!FocusScope.of(context).focusInDirection(TraversalDirection.left)) {
                                    FocusScope.of(context).previousFocus();
                                  }
                                },
                                const SingleActivator(LogicalKeyboardKey.enter): () => controller.openNewChatCreator(context),
                                const SingleActivator(LogicalKeyboardKey.select): () => controller.openNewChatCreator(context),
                                const SingleActivator(LogicalKeyboardKey.space): () => controller.openNewChatCreator(context),
                              },
                              child: InkWell(
                                focusNode: controller.newMessageFocusNode,
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: Icon(
                                    CupertinoIcons.pencil,
                                    color: context.theme.colorScheme.properOnSurface,
                                    size: 20,
                                  ),
                                ),
                                onTap: () => controller.openNewChatCreator(context),
                              ),
                            ),
                          ),
                        ),
                      if (ss.settings.moveChatCreatorToHeader.value && ss.settings.cameraFAB.value && !kIsWeb && !kIsDesktop)
                        const SizedBox(width: 10.0),
                      if (ss.settings.moveChatCreatorToHeader.value && ss.settings.cameraFAB.value && !kIsWeb && !kIsDesktop)
                        ClipOval(
                          child: Material(
                            color: context.theme.colorScheme.properSurface, // button color
                            child: InkWell(
                                child: SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: Icon(CupertinoIcons.camera, color: context.theme.colorScheme.properOnSurface, size: 20),
                                ),
                                onTap: () => controller.openCamera(context)),
                          ),
                        ),
                      if (ss.settings.moveChatCreatorToHeader.value) const SizedBox(width: 10.0),
                      const Material(
                        color: Colors.transparent,
                        shape: CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: OverflowMenu(),
                      ),
                    ],
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class CupertinoMiniHeader extends StatelessWidget {
  const CupertinoMiniHeader({Key? key, required this.controller});

  final ConversationListController controller;

  @override
  Widget build(BuildContext context) {
    // the macOS header is pinned, so there's no collapsed title bar to fade in
    if (kIsDesktop && !ns.isAvatarOnly(context)) return const SizedBox.shrink();
    final double topMargin = context.orientation == Orientation.landscape && context.isPhone
        ? 20
        : kIsDesktop || kIsWeb
            ? 60
            : kToolbarHeight + 30;

    return IgnorePointer(
      child: FadeOnScroll(
        scrollController: controller.iosScrollController,
        fullOpacityOffset: topMargin + 15,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Obx(() {
              ns.listener.value;
              return Container(
                width: ns.width(context),
                height: (topMargin - 20).clamp(kIsDesktop ? 65 : 40, double.infinity),
                color: context.theme.colorScheme.properSurface.withOpacity(0.5),
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: kIsDesktop ? 10 : 5),
                  child: Text(
                    controller.showArchivedChats
                        ? "Archive"
                        : controller.showUnknownSenders
                        ? "Unknown Senders"
                        : "Messages",
                    style: context.textTheme.titleMedium!.copyWith(color: context.theme.colorScheme.properOnSurface),
                  ),
                ),
              );
            })
          ),
        ),
      ),
    );
  }
}

/// macOS Tahoe sidebar header: a slim toolbar row and a search pill, pinned while the list scrolls under it.
class _MacListHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MacListHeaderDelegate(this.controller);

  final ConversationListController controller;
  // 28 top (+8 card inset) puts the 34px row's centre at 52px, the same line as the conversation toolbar
  static const double _height = 74;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  bool shouldRebuild(covariant _MacListHeaderDelegate oldDelegate) => oldDelegate.controller != controller;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final scrolled = shrinkOffset > 0 || overlapsContent;
    return ClipRect(
      child: Stack(
        children: [
          // fades from full blur at the top edge to none at the bottom, instead of a hard line
          if (scrolled)
            Positioned.fill(
              child: ProgressiveBlur(sigma: 12, color: Glass.fill(context, opacity: 0.6)),
            ),
          Container(
          padding: const EdgeInsets.fromLTRB(14, 28, 14, 12),
          // macOS Tahoe: the search field and the toolbar button share one row
          child: Row(
            children: [
              Expanded(child: _MacSearchField(controller: controller)),
              const SizedBox(width: 8),
              SyncIndicator(size: 16),
              const Material(
                color: Colors.transparent,
                shape: CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: OverflowMenu(),
              ),
            ],
          ),
          ),
        ],
      ),
    );
  }
}

class _MacSearchField extends StatefulWidget {
  const _MacSearchField({required this.controller});

  final ConversationListController controller;

  @override
  State<_MacSearchField> createState() => _MacSearchFieldState();
}

class _MacSearchFieldState extends State<_MacSearchField> {
  late final TextEditingController text = TextEditingController(text: widget.controller.searchQuery.value);
  final FocusNode focus = FocusNode();

  @override
  void dispose() {
    text.dispose();
    focus.dispose();
    super.dispose();
  }

  void _clear() {
    text.clear();
    widget.controller.searchQuery.value = "";
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final outline = context.theme.colorScheme.outline;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () { _clear(); focus.unfocus(); }},
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : const Color(0x14767680), // Apple tertiary system fill
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.search, size: 16, color: outline),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: text,
                focusNode: focus,
                style: context.textTheme.bodyLarge,
                cursorColor: context.theme.colorScheme.primary,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: "Search",
                  hintStyle: context.textTheme.bodyLarge!.copyWith(color: outline),
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) {
                  widget.controller.searchQuery.value = v;
                  setState(() {});
                },
              ),
            ),
            if (text.text.isNotEmpty)
              GlassPressable(
                onTap: _clear,
                tooltip: "Clear",
                child: Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: outline),
              ),
          ],
        ),
      ),
    );
  }
}
