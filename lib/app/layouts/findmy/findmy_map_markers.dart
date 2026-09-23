import 'package:flutter/material.dart';

/// Map chrome matching DealFinder's Apple Maps-style map (apps/web/public/app.css there): a teardrop
/// pin with a soft drop shadow, a pulsing blue "you are here" dot, and white 14px popup cards with no
/// tip.
class FindMapColors {
  static const pin = Color(0xFF1F3D5C); // DealFinder --accent
  static const you = Color(0xFF3B82F6); // DealFinder --pin-highlight
  static const shadow = Color(0x5914120F); // drop-shadow(0 2px 3px rgba(20,18,15,.35))
  static const land = Color(0xFFF4F1EA); // style background, shown while tiles load
}

/// DealFinder's PROPERTY_PIN_SVG (26x34) path, scaled to the widget size.
class _TeardropPainter extends CustomPainter {
  const _TeardropPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 34);
    final path = Path()
      ..moveTo(13, 0)
      ..cubicTo(5.8, 0, 0, 5.8, 0, 13)
      ..cubicTo(0, 22.2, 9.6, 31.8, 12, 34)
      ..cubicTo(12.3, 34.3, 12.7, 34.3, 13, 34)
      ..cubicTo(15.4, 31.8, 26, 22.2, 26, 13)
      ..cubicTo(26, 5.8, 20.2, 0, 13, 0)
      ..close();
    canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()
          ..color = FindMapColors.shadow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TeardropPainter old) => old.color != color;
}

/// Pin for a device or item; [child] (icon or emoji) sits in the round head.
class FindMyTeardropPin extends StatelessWidget {
  const FindMyTeardropPin({super.key, required this.child, this.color = FindMapColors.pin});
  static const size = Size(32, 42);

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _TeardropPainter(color),
      child: SizedBox.fromSize(
        size: size,
        child: Align(
          alignment: const Alignment(0, -0.6),
          child: SizedBox(width: 22, height: 22, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// Friend avatar in a white ring with the pin shadow.
class FindMyAvatarPin extends StatelessWidget {
  const FindMyAvatarPin({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: FindMapColors.shadow, blurRadius: 3, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Blue dot with a white ring and an expanding pulse (DealFinder .user-location-pulse: 2.2s, scale
/// 0.6 → 2.6, fading out by 70%). The pulse stops when the OS asks for reduced motion.
class FindMyYouAreHere extends StatefulWidget {
  const FindMyYouAreHere({super.key});

  @override
  State<FindMyYouAreHere> createState() => _FindMyYouAreHereState();
}

class _FindMyYouAreHereState extends State<FindMyYouAreHere> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = Curves.easeOut.transform((_pulse.value / 0.7).clamp(0.0, 1.0));
            if (!_pulse.isAnimating) return const SizedBox();
            return Transform.scale(
              scale: 0.6 + 2.0 * t,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(shape: BoxShape.circle, color: FindMapColors.you.withOpacity(0.55 * (1 - t))),
              ),
            );
          },
        ),
        Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(color: FindMapColors.shadow, blurRadius: 3, offset: Offset(0, 1))],
          ),
          padding: const EdgeInsets.all(3),
          child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: FindMapColors.you)),
        ),
      ],
    );
  }
}

/// Popup card: surface color, 14px radius, one soft shadow, no tip.
class FindMyPopupCard extends StatelessWidget {
  const FindMyPopupCard({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: padding,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x2E14120F), blurRadius: 28, offset: Offset(0, 12))],
        ),
        child: child,
      ),
    );
  }
}
