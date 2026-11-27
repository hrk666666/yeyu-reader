import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../theme/md3.dart';
import 'glass_morph.dart';

/// 官方 MD3 没有毛玻璃：本组件只提供 `surfaceContainer` + `surfaceTintColor`
/// 的 tonal elevation 分层，state layer 由外层 InkWell 负责。
/// 保留全部构造参数（radius / thickness / blur / refractiveIndex / tint /
/// emission / activation / independent / physicalOptics / morph）以兼容调用方，
/// 但不再创建任何 LiquidGlassLens / BackdropFilter / 折射 / 自定义 blur。
class EasyGlassSurface extends StatelessWidget {
  const EasyGlassSurface({
    super.key,
    required this.child,
    required this.radius,
    required this.thickness,
    required this.blur,
    required this.refractiveIndex,
    required this.tint,
    required this.emission,
    required this.activation,
    this.independent = false,
    this.physicalOptics = false,
    this.morph,
  });

  final Widget child;
  final double radius;
  final double thickness;
  final double blur;
  final double refractiveIndex;
  final ui.Color tint;
  final double emission;
  final double activation;
  final bool independent;
  final bool physicalOptics;

  /// Resolves the material from the originating control to the overlay. Only
  /// the lens is rebuilt per frame; the assembled content keeps its identity.
  final WenkuGlassMorph? morph;

  @override
  Widget build(BuildContext context) {
    // 用官方 MD3 tonal elevation 表达表面层次：surfaceContainer 底色 +
    // surfaceTintColor + level1 elevation + 官方圆角，InkWell 负责 state layer。
    final scheme = Theme.of(context).colorScheme;
    final morph = this.morph;
    final resolvedRadius = morph == null
        ? radius
        : morph.resolve(morph.radius, radius);    return Material(
      color: scheme.surfaceContainer,
      surfaceTintColor: scheme.surfaceTint,
      shadowColor: Colors.transparent, // M3 tonal elevation，不画 BoxShadow
      elevation: Md3Elevation.level1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(resolvedRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 官方 MD3 用 `surfaceContainer` 分层，不绘制滚动边缘 backdrop blur。
/// 保留构造签名（blur / plateau / fromBottom）以兼容调用方，仅透传 child。
class EasyScrollEdge extends StatelessWidget {
  const EasyScrollEdge({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
    required this.child,
  });

  final double blur, plateau;
  final bool fromBottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
