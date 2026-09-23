import 'dart:math' as math;
import 'dart:ui';

import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/types/helpers/misc_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// The macOS Tahoe design language applies on desktop with the iOS skin.
bool get macLook => kIsDesktop && ss.settings.skin.value == Skins.iOS;

/// macOS System Settings palette: window background and grouped-card fill.
Color macPageColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F7);
/// Neutral ink for icon-only chrome (toolbar buttons): macOS secondaryLabel / label. Muted: systemGray.
Color macChromeInk(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFFE5E5EA) : const Color(0xFF3C3C43);
const Color macMutedInk = Color(0xFF8E8E93);

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
            child: Icon(icon, size: iconSize ?? size * 0.5, color: color ?? macChromeInk(context)),
          ),
        ),
      ),
    );
  }
}

/// Damped overshoot shared by everything that moves (peaks at 1.05 and settles), sampled from the
/// liquid-glass --spring curve.
class GlassSpring extends Curve {
  const GlassSpring();
  static const _points = [0, .04, .16, .36, .6, .82, .97, 1.04, 1.05, 1.04, 1.02, 1.007, 1.0];

  @override
  double transformInternal(double t) {
    final x = t * (_points.length - 1);
    final i = x.floor().clamp(0, _points.length - 2);
    return _points[i] + (_points[i + 1] - _points[i]) * (x - i);
  }
}

/// macOS segmented control (Find My's People / Devices / Items): a grey capsule track with one white
/// pill that travels to the selected segment. One moving object, not a crossfade per segment.
class GlassSegmented extends StatelessWidget {
  const GlassSegmented({super.key, required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).colorScheme.onBackground;
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.10) : const Color(0x1F787880), // quaternary system fill
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final segment = constraints.maxWidth / labels.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: const GlassSpring(),
              left: segment * selected,
              top: 0,
              bottom: 0,
              width: segment,
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF636366) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Glass.border(context), width: 0.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(dark ? 0.3 : 0.12), blurRadius: 4, offset: const Offset(0, 1))],
                ),
              ),
            ),
            Row(
              children: [
                for (int i = 0; i < labels.length; i++)
                  Expanded(
                    child: GlassPressable(
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: text.withOpacity(i == selected ? 0.9 : 0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

/// A Liquid Glass popover opening upward from the widget at [anchorContext] (the + and emoji buttons):
/// left edges aligned, or right edges with [alignRight]. Dismissed by clicking outside or Esc; the
/// builder can pop a result with Navigator.of(context).pop(value).
Future<T?> showGlassPopover<T>({
  required BuildContext anchorContext,
  required double width,
  required WidgetBuilder builder,
  bool alignRight = false,
  EdgeInsets padding = const EdgeInsets.all(6),
  double radius = 18,
}) {
  final box = anchorContext.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  return showGeneralDialog<T>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: "Dismiss",
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) {
      final screen = MediaQuery.of(context).size;
      final left = (alignRight ? origin.dx + box.size.width - width : origin.dx).clamp(8.0, screen.width - width - 8);
      return Stack(
        children: [
          Positioned(
            left: left,
            bottom: screen.height - origin.dy + 8,
            width: width,
            child: GlassSurface(
              borderRadius: BorderRadius.circular(radius),
              blur: 24,
              fillOpacity: 0.78,
              padding: padding,
              child: Material(type: MaterialType.transparency, child: builder(context)),
            ),
          ),
        ],
      );
    },
    // geometry springs, opacity is a plain fade
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: animation, curve: const GlassSpring())),
        alignment: alignRight ? Alignment.bottomRight : Alignment.bottomLeft,
        child: child,
      ),
    ),
  );
}

/// A blur that fades out downward instead of ending in a hard line (the scroll-edge effect under
/// floating toolbars). Built from [steps] stacked backdrop blurs anchored at the top, each shorter than
/// the last: blurs compose, so strength accumulates toward the top edge. Per-layer strengths are chosen
/// so the combined blur follows a smooth curve from ~0 at the bottom to [sigma] at the top, which keeps
/// every band edge below what the eye can see. (A gradient-masked single blur would be simpler, but on
/// this renderer a blur inside a mask layer only sees that empty layer and blurs nothing.)
/// [colorFilter] (e.g. saturation) is applied once, on the full-height layer.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({super.key, required this.sigma, this.color, this.colorFilter, this.steps = 8});

  final double sigma;
  final Color? color;
  final ColorFilter? colorFilter;
  final int steps;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      double target(int k) => sigma * math.pow(k / steps, 1.5).toDouble();
      final layers = <Widget>[];
      for (int k = 1; k <= steps; k++) {
        // layer k covers the top (steps - k + 1)/steps of the height and adds enough blur that the region
        // covered by k layers reaches target(k)
        final layerSigma = math.sqrt(math.max(0.0, target(k) * target(k) - target(k - 1) * target(k - 1)));
        ImageFilter filter = ImageFilter.blur(sigmaX: layerSigma, sigmaY: layerSigma);
        if (k == 1 && colorFilter != null) filter = ImageFilter.compose(outer: filter, inner: colorFilter!);
        layers.add(Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height * (steps - k + 1) / steps,
          child: ClipRect(child: BackdropFilter(filter: filter, child: const SizedBox.expand())),
        ));
      }
      return Stack(children: [
        ...layers,
        if (color != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color!, color!.withOpacity(0)],
                ),
              ),
            ),
          ),
      ]);
    });
  }
}
