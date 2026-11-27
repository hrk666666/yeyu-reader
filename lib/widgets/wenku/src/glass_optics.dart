/// 官方 MD3 没有折射 / 毛玻璃。保留常量名（wenku_glass.dart 仍引用）以兼容
/// 调用方，但值改为 1.0（无折射），实际渲染已由 EasyGlassSurface 的
/// `surfaceContainer` + `surfaceTintColor` 分层取代。
abstract final class GlassOptics {
  static const refractiveIndex = 1.0;
}
