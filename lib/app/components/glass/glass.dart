import 'dart:ui';

import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/types/helpers/misc_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// The macOS Tahoe design language applies on desktop with the iOS skin.
bool get macLook => kIsDesktop && ss.settings.skin.value == Skins.iOS;

/// macOS System Settings palette: window background and grouped-card fill.
Color macPageColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F7);
Color macCardColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white;

/// Liquid Glass surfaces for the macOS Messages look.
///
/// Glass is always four things together: a translucent fill, blur *with* saturation, a hairline border
/// and one soft shadow. Dropping the saturation turns the backdrop muddy grey; dropping the border
/// makes it stop reading as a pane.
class Glass {
  static const double chromeBlur = 16; // buttons, bars, pills
  static const double panelBlur = 24; // floating sidebar card

  static bool _dark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;

  static Color fill(BuildContext context, {double? opacity}) => _dark(context)
      ? const Color(0xFF2C2C2E).withOpacity(opacity ?? 0.55)
      : Colors.white.withOpacity(opacity ?? 0.62);

  /// One border, never two. A white border is invisible on near-white backgrounds, so light mode uses the
  /// iOS separator instead.
  static Color border(BuildContext context) =>
      _dark(context) ? Colors.white.withOpacity(0.14) : const Color(0x1F3C3C43);

  static List<BoxShadow> shadow(BuildContext context) => [
        BoxShadow(
          color: _dark(context) ? Colors.black.withOpacity(0.32) : const Color(0x1F1E1C3C),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ];

  /// blur(n) saturate(180%)
  static ImageFilter filter(double blur) {
    const s = 1.8;
    const r = 0.2126, g = 0.7152, b = 0.0722;
    return ImageFilter.compose(
      outer: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
      inner: const ColorFilter.matrix(<double>[
        r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0,
        r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0,
        r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0,
        0, 0, 0, 1, 0,
      ]),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.blur = Glass.chromeBlur,
    this.padding,
    this.fillOpacity,
    this.shadow = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final double? fillOpacity;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadow ? Glass.shadow(context) : null),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: Glass.filter(blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Glass.fill(context, opacity: fillOpacity),
              borderRadius: borderRadius,
              border: Border.all(color: Glass.border(context), width: 0.5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Press = dim, never move. Hover is mouse-only.
class GlassPressable extends StatefulWidget {
  const GlassPressable({super.key, required this.child, this.onTap, this.tooltip});

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Widget result = MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.6 : (_hover ? 0.85 : 1),
          duration: const Duration(milliseconds: 60),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) result = Tooltip(message: widget.tooltip!, child: result);
    return result;
  }
}

/// Round glass toolbar button (compose, video call, filter, +, emoji).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({super.key, required this.icon, this.onTap, this.size = 36, this.iconSize, this.tooltip, this.color});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double? iconSize;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GlassPressable(
      onTap: onTap,
      tooltip: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: GlassSurface(
          child: Center(
            child: Icon(icon, size: iconSize ?? size * 0.5, color: color ?? Theme.of(context).colorScheme.onBackground.withOpacity(0.85)),
          ),
        ),
      ),
    );
  }
}
