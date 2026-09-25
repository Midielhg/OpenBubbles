import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/app/components/glass/glass.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart' as intl;
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/dialogs/metadata_dialog.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_image.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_video.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:gesture_x_detector/gesture_x_detector.dart';
import 'package:get/get.dart';

class FullscreenMediaHolder extends StatefulWidget {
  FullscreenMediaHolder({
    super.key,
    required this.attachment,
    required this.showInteractions,
    this.currentChat,
    this.videoController,
    this.mute
  });

  final ChatLifecycleManager? currentChat;
  final Attachment attachment;
  final bool showInteractions;
  final VideoController? videoController;
  final RxBool? mute;

  @override
  FullscreenMediaHolderState createState() => FullscreenMediaHolderState();
}

class FullscreenMediaHolderState extends OptimizedState<FullscreenMediaHolder> {
  final focusNode = FocusNode();
  late final PageController controller;
  late final messageService = widget.currentChat == null ? null : ms(widget.currentChat!.chat.guid);
  late List<Attachment> attachments = widget.currentChat == null
      ? [attachment]
      : messageService!.struct.attachments.where((e) => e.mimeStart == "image" || e.mimeStart == "video").toList();

  int currentIndex = 0;
  ScrollPhysics? physics;
  Attachment get attachment => widget.attachment;
  bool showAppBar = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !widget.showInteractions) {
      controller = PageController(initialPage: 0);
    } else {
      if (widget.currentChat != null) {
        currentIndex = attachments.indexWhere((e) => e.guid == attachment.guid);
        if (currentIndex == -1) {
          attachments.add(attachment);
          currentIndex = attachments.indexWhere((e) => e.guid == attachment.guid);
        }
      }
      controller = PageController(initialPage: currentIndex);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool get _hasPrev => currentIndex > 0;
  bool get _hasNext => currentIndex < attachments.length - 1;

  void _go(int delta) {
    final target = currentIndex + delta;
    if (target < 0 || target >= attachments.length) return;
    controller.animateToPage(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  /// macOS (Quick Look style): floating glass toolbar and edge arrows over the media.
  Widget _macChrome(BuildContext context) {
    final current = attachments[currentIndex.clamp(0, attachments.length - 1)];
    final message = current.message.target;
    final sender = message == null
        ? null
        : (message.isFromMe ?? false)
            ? "You"
            : (message.handle ?? message.getHandle())?.displayName;
    final date = message?.dateCreated == null ? null : intl.DateFormat.yMMMd().add_jm().format(message!.dateCreated!);
    final title = [
      if (widget.showInteractions && widget.currentChat != null && attachments.length > 1) "${currentIndex + 1} of ${attachments.length}",
      if (sender != null) sender,
      if (date != null) date,
    ].join("  \u00b7  ");
    final content = as.getContent(current, path: current.guid == null ? current.sourcePath : null);

    return IgnorePointer(
      ignoring: !showAppBar,
      child: AnimatedOpacity(
        opacity: showAppBar ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Stack(
          children: [
            Positioned(
              top: 34,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  GlassCircleButton(icon: CupertinoIcons.xmark, iconSize: 16, tooltip: "Close", onTap: () => Navigator.of(context).pop()),
                  const Spacer(),
                  if (title.isNotEmpty)
                    GlassSurface(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Text(title, style: context.theme.textTheme.bodyMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  const Spacer(),
                  if (widget.showInteractions) ...[
                    GlassCircleButton(
                      icon: CupertinoIcons.info,
                      iconSize: 17,
                      tooltip: "Info",
                      onTap: () => showMetadataDialog(current, context),
                    ),
                    const SizedBox(width: 8),
                    GlassCircleButton(
                      icon: CupertinoIcons.arrow_down_to_line,
                      iconSize: 17,
                      tooltip: "Save",
                      onTap: content is PlatformFile ? () => as.saveToDisk(content) : null,
                    ),
                  ],
                ],
              ),
            ),
            if (_hasPrev)
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(child: GlassCircleButton(icon: CupertinoIcons.chevron_left, size: 44, iconSize: 18, tooltip: "Previous", onTap: () => _go(-1))),
              ),
            if (_hasNext)
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(child: GlassCircleButton(icon: CupertinoIcons.chevron_right, size: 44, iconSize: 18, tooltip: "Next", onTap: () => _go(1))),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TitleBarWrapper(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: ss.settings.immersiveMode.value
              ? Colors.transparent
              : context.theme.colorScheme.background, // navigation bar color
          systemNavigationBarIconBrightness: context.theme.colorScheme.brightness.opposite,
          statusBarColor: Colors.transparent, // status bar color
          statusBarIconBrightness:
              ss.settings.skin.value != Skins.iOS ? Brightness.light : context.theme.colorScheme.brightness.opposite,
        ),
        child: Actions(
          actions: {
            GoBackIntent: GoBackAction(context),
          },
          child: Scaffold(
            appBar: macLook
                ? null
                : !iOS || !showAppBar
                // AppBar placeholder to prevent shifting of content when toggling the app bar
                ? PreferredSize(preferredSize: const Size.fromHeight(56), child: Container())
                : AppBar(
                    leading: XGestureDetector(
                      supportTouch: true,
                      onTap: !kIsDesktop
                          ? null
                          : (details) {
                              Navigator.of(context).pop();
                            },
                      child: TextButton(
                        child: Text("Done",
                            style:
                                context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                        onPressed: () {
                          if (kIsDesktop) return;
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                    leadingWidth: 75,
                    title: Text(
                        kIsWeb || !widget.showInteractions || widget.currentChat == null
                            ? "Media"
                            : "${currentIndex + 1} of ${attachments.length}",
                        style: context.theme.textTheme.titleLarge!
                            .copyWith(color: context.theme.colorScheme.properOnSurface)),
                    centerTitle: iOS,
                    iconTheme: IconThemeData(color: context.theme.colorScheme.primary),
                    backgroundColor: context.theme.colorScheme.properSurface,
                    systemOverlayStyle: context.theme.colorScheme.brightness == Brightness.dark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark,
                  ),
            backgroundColor: macLook ? const Color(0xFF111113) : Colors.black,
            body: FocusScope(
              child: Focus(
                focusNode: focusNode,
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (macLook) {
                    if (event is KeyUpEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      _go(1);
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _go(-1);
                      return KeyEventResult.handled;
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  }
                  if (event.physicalKey.debugName == "Arrow Right") {
                    if (ss.settings.fullscreenViewerSwipeDir.value == SwipeDirection.RIGHT) {
                      controller.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                    } else {
                      controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                    }
                  } else if (event.physicalKey.debugName == "Arrow Left") {
                    if (ss.settings.fullscreenViewerSwipeDir.value == SwipeDirection.LEFT) {
                      controller.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                    } else {
                      controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeIn);
                    }
                  } else if (event.physicalKey.debugName == "Escape") {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Stack(children: [
                  // mouse and trackpad can drag between items too (Flutter only drags with touch by default)
                  ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  }),
                  child: PageView.builder(
                  physics: physics ??
                      (attachments.length == 1
                          ? const NeverScrollableScrollPhysics()
                          : ThemeSwitcher.getScrollPhysics()),
                  reverse: !macLook && ss.settings.fullscreenViewerSwipeDir.value == SwipeDirection.RIGHT,
                  itemCount: attachments.length,
                  onPageChanged: (int val) {
                    widget.videoController?.player.pause();
                    setState(() {
                      currentIndex = val;
                      // a zoomed page locks paging; the new page starts unzoomed
                      physics = null;
                    });
                  },
                  controller: controller,
                  itemBuilder: (BuildContext context, int index) {
                    final attachment = attachments[index];
                    dynamic content =
                        as.getContent(attachment, path: attachment.guid == null ? attachment.sourcePath : null);
                    final key = attachment.guid ?? attachment.transferName ?? randomString(8);

                    if (content is PlatformFile) {
                      if (attachment.mimeStart == "image") {
                        return FullscreenImage(
                          key: Key(key),
                          attachment: attachment,
                          file: content,
                          showInteractions: widget.showInteractions,
                          updatePhysics: (ScrollPhysics p) {
                            if (physics != p) {
                              setState(() {
                                physics = p;
                              });
                            }
                          },
                          onOverlayToggle: (show) {
                            if (showAppBar != show) {
                              setState(() {
                                showAppBar = show;
                              });
                            }
                          },
                        );
                      } else if (attachment.mimeStart == "video") {
                        return FullscreenVideo(
                          key: Key(key),
                          file: content,
                          attachment: attachment,
                          showInteractions: widget.showInteractions,
                          videoController: widget.videoController,
                          mute: widget.mute,
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    } else if (content is Attachment) {
                      final Attachment _content = content;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            content = attachmentDownloader.startDownload(content, onComplete: (file) {
                              setState(() {
                                content = file;
                              });
                            });
                          });
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            SizedBox(
                              height: 40,
                              width: 40,
                              child: Center(
                                  child: Icon(iOS ? CupertinoIcons.cloud_download : Icons.cloud_download_outlined,
                                      size: 30)),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              (_content.mimeType ?? ""),
                              style: context.theme.textTheme.bodyLarge!
                                  .copyWith(color: context.theme.colorScheme.properOnSurface),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _content.getFriendlySize(),
                              style: context.theme.textTheme.bodyMedium!
                                  .copyWith(color: context.theme.colorScheme.properOnSurface),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      );
                    } else if (content is AttachmentDownloadController) {
                      final AttachmentDownloadController _content = content;
                      return InkWell(
                        onTap: () {
                          final AttachmentDownloadController _content = content;
                          if (!_content.error.value) return;
                          Get.delete<AttachmentDownloadController>(tag: _content.attachment.guid);
                          content = attachmentDownloader.startDownload(_content.attachment, onComplete: (file) {
                            setState(() {
                              content = file;
                            });
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Obx(() {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  height: 40,
                                  width: 40,
                                  child: Center(
                                    child: _content.error.value
                                        ? Icon(iOS ? CupertinoIcons.arrow_clockwise : Icons.refresh, size: 30)
                                        : CircleProgressBar(
                                            value: _content.progress.value?.toDouble() ?? 0,
                                            backgroundColor: context.theme.colorScheme.outline,
                                            foregroundColor: context.theme.colorScheme.properOnSurface,
                                          ),
                                  ),
                                ),
                                _content.error.value ? const SizedBox(height: 10) : const SizedBox(height: 5),
                                Text(
                                  _content.error.value ? "Failed to download!" : (_content.attachment.mimeType ?? ""),
                                  style: context.theme.textTheme.bodyLarge!
                                      .copyWith(color: context.theme.colorScheme.properOnSurface),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              ],
                            );
                          }),
                        ),
                      );
                    } else {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Error loading attachment",
                            style: context.theme.textTheme.bodyLarge,
                          ),
                        ],
                      );
                    }
                  },
                ),
                  ),
                  if (macLook) _macChrome(context),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
