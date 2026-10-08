import 'package:bluebubbles/app/layouts/settings/pages/passwords/password_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Rounded-square site tile in the style of Apple's Passwords app: the site's initial on a color
/// derived from its name, or a symbol for items that aren't websites.
class SiteIcon extends StatelessWidget {
  const SiteIcon({super.key, required this.name, this.icon, this.size = 36});

  final String name;
  final IconData? icon;
  final double size;

  static const _palette = <List<Color>>[
    [Color(0xFF5AC8FA), Color(0xFF007AFF)],
    [Color(0xFF64D2FF), Color(0xFF0A84FF)],
    [Color(0xFF34C759), Color(0xFF248A3D)],
    [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
    [Color(0xFFFF6482), Color(0xFFFF2D55)],
    [Color(0xFFBF5AF2), Color(0xFF8944AB)],
    [Color(0xFF5E5CE6), Color(0xFF3634A3)],
    [Color(0xFFFFD60A), Color(0xFFF2A900)],
    [Color(0xFF30D5C8), Color(0xFF0C8B80)],
    [Color(0xFFAC8E68), Color(0xFF7F6545)],
  ];

  static String _key(String name) {
    var s = name.trim().toLowerCase();
    if (s.contains("://")) s = Uri.tryParse(s)?.host ?? s;
    if (s.startsWith("www.")) s = s.substring(4);
    return s;
  }

  static String initialOf(String name) {
    final match = RegExp(r"[\p{L}\p{N}]", unicode: true).firstMatch(_key(name));
    return match == null ? "?" : match.group(0)!.toUpperCase();
  }

  static List<Color> colorsFor(String name) {
    final key = _key(name);
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsFor(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(color: colors.last.withOpacity(0.25), blurRadius: size * 0.12, offset: Offset(0, size * 0.04)),
        ],
      ),
      child: icon != null
          ? Icon(icon, color: Colors.white, size: size * 0.52)
          : Text(
              initialOf(name),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.46,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
    );
  }
}

/// Avatar for a saved item in lists and headers.
class CredentialAvatar extends StatelessWidget {
  final CredentialItem credential;
  final double size;

  const CredentialAvatar({super.key, required this.credential, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final isWifi = credential.icon == CupertinoIcons.wifi;
    return SiteIcon(
      name: isWifi ? "wifi" : credential.title,
      icon: isWifi ? CupertinoIcons.wifi : null,
      size: size,
    );
  }
}

/// A category card on the Passwords home screen (icon, count and title).
class PasswordCategoryCard extends StatelessWidget {
  const PasswordCategoryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    this.count,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: Colors.white, size: 18),
                  ),
                  const Spacer(),
                  Text(
                    count?.toString() ?? "",
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays out [PasswordCategoryCard]s two per row (four on wide windows).
class PasswordCategoryGrid extends StatelessWidget {
  const PasswordCategoryGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 4 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    });
  }
}

/// Large centered header on a saved item's page.
class CredentialHeader extends StatelessWidget {
  const CredentialHeader({super.key, required this.credential, this.caption});

  final CredentialItem credential;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        children: [
          CredentialAvatar(credential: credential, size: 72),
          const SizedBox(height: 12),
          Text(
            credential.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labeled value on a saved item's page, with optional copy and reveal controls.
class CredentialFieldRow extends StatelessWidget {
  const CredentialFieldRow({
    super.key,
    required this.label,
    required this.value,
    this.obscured = false,
    this.monospace = false,
    this.onCopy,
    this.onToggleObscured,
    this.inline = false,
  });

  final String label;
  final String value;
  final bool obscured;
  final bool monospace;
  final VoidCallback? onCopy;
  final VoidCallback? onToggleObscured;

  /// Label and value on one line (for short details like dates).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: monospace && !obscured ? "monospace" : null,
      letterSpacing: obscured ? 2 : null,
    );
    final shown = obscured ? "•" * value.length.clamp(8, 16) : value;

    if (inline) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Text(label, style: theme.textTheme.bodyLarge),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: labelStyle),
                  const SizedBox(height: 2),
                  Text(shown, style: valueStyle),
                ],
              ),
            ),
            if (onToggleObscured != null)
              IconButton(
                tooltip: obscured ? "Show" : "Hide",
                icon: Icon(obscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 20),
                color: theme.colorScheme.outline,
                onPressed: onToggleObscured,
              ),
            if (onCopy != null)
              IconButton(
                tooltip: "Copy",
                icon: const Icon(CupertinoIcons.doc_on_doc, size: 19),
                color: theme.colorScheme.primary,
                onPressed: onCopy,
              ),
          ],
        ),
      ),
    );
  }
}

/// Search bar on the Passwords home screen; opens the search screen when tapped.
class PasswordSearchField extends StatelessWidget {
  const PasswordSearchField({super.key, required this.backgroundColor, required this.onTap});

  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(CupertinoIcons.search, size: 18, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Text("Search", style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}
