import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import 'src/app_text.dart';
import 'src/archive_motion.dart';

export 'src/archive_motion.dart';

/// The archive vocabulary is foreground geometry, not another filter layer.
/// Codes, rules and registration marks are static and carry no idle ticker.
///
/// 配色全部取自官方 MD3 tonal role 的静态标准取样（surface /
/// surfaceContainerLow / surfaceContainer* / onSurface* / outlineVariant）。
/// 这些字段必须是 `const`：其它文件（含 wenku_theme.dart 的 `canvas`、
/// 各 CustomPainter 的默认参数）以 const 方式引用，无法在运行时读取
/// `Theme.of(context).colorScheme`。实际页面配色由 WenkuTheme →
/// `ColorScheme.fromSeed` 动态派生（见 WenkuTonalColors），此处仅作无主题
/// 时的回退取样。原先的牛奶 / 石头纸色已废弃。
abstract final class ArchiveDesign {
  // 浅色取样：surface(98) / surfaceContainerLow(96) / Lowest(100)
  static const background = Color(0xFFFDF8F6); // surface
  static const surface = Color(0xFFFBF4F1); // surfaceContainerLow
  static const milk = Color(0xFFFFFFFF); // surfaceContainerLowest
  // 深色取样：surface(6) / surfaceContainerLow(10) / High(17) / Highest(22)
  static const darkBackground = Color(0xFF141311); // surface
  static const darkSurface = Color(0xFF1C1B19); // surfaceContainerLow
  static const darkRaised = Color(0xFF2B2926); // surfaceContainerHigh
  static const darkRaisedHigh = Color(0xFF363330); // surfaceContainerHighest
  static const darkOutline = Color(0xFF4A4542); // outlineVariant
  static const darkInk = Color(0xFFE9E2DF); // onSurface
  static const darkMuted = Color(0xFFCFC4BF); // onSurfaceVariant
  static const darkMilk = Color(0xFFF5F4F1); // 浅色 thumb（inverseSurface 取样）
  // 官方 M3 shape scale：面板 medium(12)、封面 small(8)。
  static const panelRadius = Md3Shape.medium;
  static const coverRadius = Md3Shape.small;

  /// 官方 MD3 没有毛玻璃：返回 `surfaceContainer` 语义的分层取样，不再
  /// 表示任何 backdrop blur / 折射。保留方法签名以兼容调用方。
  static Color glassTint(Brightness brightness, {required double opacity}) =>
      brightness == Brightness.dark
      ? Color.lerp(darkMilk, darkSurface, opacity.clamp(0.0, 1.0))!
      : milk;

  static TextStyle codeStyle(BuildContext context, {Color? color}) => TextStyle(
    fontFamily: 'monospace',
    fontSize: 9,
    height: 1.35,
    letterSpacing: 1.05,
    fontWeight: FontWeight.w500,
    color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
  );

  static String fileCode(int id) => 'WK-${id.toString().padLeft(5, '0')}';
}

class ArchiveMasthead extends StatelessWidget {
  const ArchiveMasthead({
    super.key,
    required this.title,
    required this.code,
    this.brand = false,
  });
  final String title;
  final String code;
  final bool brand;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (brand) ...[
        ExcludeSemantics(
          child: SizedBox(
            width: 30,
            height: 34,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Image.asset(
                  'assets/images/app_logo.webp',
                  key: const ValueKey('discovery-app-icon'),
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                  cacheWidth: (30 * MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        // Keep the fixed 56 px toolbar usable with large system text, without
        // shrinking any reading content or enlarging its pinned hitbox plane.
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Keep the navigation landmark immediately readable; the
                // archive address below it performs the terminal assembly.
                AppText(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.7,
                    shadows: [],
                  ),
                ),
                const SizedBox(height: 3),
                ArchivePart(start: .16, end: .88, child: ArchiveCode(code)),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class ArchiveCode extends StatelessWidget {
  const ArchiveCode(this.text, {super.key, this.inverse = false, this.color});
  final String text;
  final bool inverse;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = AppText(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: ArchiveDesign.codeStyle(
        context,
        color: color ?? (inverse ? scheme.surface : null),
      ),
    );
    return ExcludeSemantics(
      child: inverse
          ? ColoredBox(
              color: scheme.onSurface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: label,
              ),
            )
          : label,
    );
  }
}

class ArchiveSection extends StatelessWidget {
  const ArchiveSection({
    super.key,
    required this.title,
    required this.code,
    this.subtitle = '',
  });
  final String title;
  final String code;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(0, constraints.maxWidth - 17),
              ),
              child: ArchivePart(start: .1, end: .68, child: ArchiveCode(code)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: ArchivePart(
                start: 0,
                end: .46,
                child: ExcludeSemantics(
                  // 官方 MD3 分割线：outlineVariant / 1dp，去掉自研 0.6px 发丝。
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            ExcludeSemantics(
              child: SizedBox(
                width: 3,
                height: 3,
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      ArchivePart(
        start: .16,
        end: .82,
        child: AppText(
          title,
          style: const TextStyle(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
          ),
        ),
      ),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 5),
        AppText(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );
}

/// Readable route title plus a restrained archive address below it.
class ArchiveRouteTitle extends StatelessWidget {
  const ArchiveRouteTitle({super.key, required this.title, required this.code});
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => FittedBox(
      fit: BoxFit.scaleDown,
      child: SizedBox(
        width: constraints.maxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 3),
            ArchiveCode(code),
          ],
        ),
      ),
    ),
  );
}

class ArchiveRegistration extends StatelessWidget {
  const ArchiveRegistration({super.key, required this.child, this.inset = 0});
  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _RegistrationPainter(
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .5),
      inset: inset,
    ),
    child: child,
  );
}

class _RegistrationPainter extends CustomPainter {
  const _RegistrationPainter({required this.color, required this.inset});
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;
    final r = (Offset.zero & size).deflate(inset + .5);
    final length = math.min(7.0, math.min(r.width, r.height) / 3);
    if (length <= 0) return;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx + dx * length, corner.dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx, corner.dy + dy * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RegistrationPainter oldDelegate) =>
      color != oldDelegate.color || inset != oldDelegate.inset;
}

/// The diagram is limited to the header margin. The reading canvas stays plain.
class ArchiveBackdrop extends StatelessWidget {
  const ArchiveBackdrop({super.key, this.filmColor = ArchiveDesign.milk});
  final Color filmColor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Align(
        alignment: Alignment.topCenter,
        // Bound the raster-cache candidate to the diagram itself, rather than
        // allocating a full-screen layer for an almost empty static painter.
        child: SizedBox(
          width: double.infinity,
          height: MediaQuery.viewPaddingOf(context).top + 240,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ArchiveBackdropPainter(
                color: Theme.of(context).colorScheme.onSurface,
                filmColor: filmColor,
                top: MediaQuery.viewPaddingOf(context).top,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ArchiveBackdropPainter extends CustomPainter {
  const _ArchiveBackdropPainter({
    required this.color,
    required this.top,
    required this.filmColor,
  });
  final Color color;
  final Color filmColor;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = math.min(size.height, top + 240);
    final dark = color.computeLuminance() > .5;
    final film = Paint()
      ..color = filmColor.withValues(alpha: dark ? .018 : .42);
    // Two restrained frosted file planes in the existing small header raster.
    // They are paint geometry: no backdrop filter, full-screen layer or ticker.
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .42, top)
        ..lineTo(size.width, top)
        ..lineTo(size.width, bottom * .82)
        ..lineTo(size.width * .78, bottom * .82)
        ..close(),
      film,
    );
    film.color = filmColor.withValues(alpha: dark ? .012 : .28);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * .60, top + 18)
        ..lineTo(size.width, top + 18)
        ..lineTo(size.width, bottom)
        ..lineTo(size.width * .92, bottom)
        ..close(),
      film,
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .045)
      ..strokeWidth = .5;
    for (var x = 24.0; x < size.width; x += 48) {
      canvas.drawLine(Offset(x, 0), Offset(x, bottom), paint);
    }
    for (var y = top + 4; y < bottom; y += 48) {
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), paint);
    }
    paint.color = color.withValues(alpha: .15);
    final y = top + 60;
    for (final x in [24.0, size.width - 24]) {
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), paint);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_ArchiveBackdropPainter oldDelegate) =>
      color != oldDelegate.color ||
      top != oldDelegate.top ||
      filmColor != oldDelegate.filmColor;
}
