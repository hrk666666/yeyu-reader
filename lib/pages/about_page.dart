// Upstream source: Wenku8_Flutter rev ebcd7f1
//   lib/updates/update_page.dart (AppUpdatePage: ArchiveFeaturePage shell,
//     ArchiveSection title block, ContentPanel rows, GlassTextButton)
//   lib/feature_pages.dart (FeatureEntry/featurePadding vocabulary)
// Mechanical substitutions:
// - fqapp has no update service or account module: the version line stays the
//   static `AboutPage.versionText` (never bumped here), update checking links
//   to the GitHub release page, and the open-source licence entry keeps
//   `showLicensePage` with the Wenku8 notices registered by
//   `lib/services/third_party_licenses.dart` (assets/licenses/wenku8).
// - `SettingsGroupCard`/`SettingsRow` are replaced by the archive
//   `ContentPanel` + an upstream-styled row. The fqapp-only sponsor card and
//   WeChat reward dialog were dropped in the 页屿 rebrand.
// - Logo plate / heading / intro copy are preserved so the existing About
//   contract (version copy, licence route, e-ink shadow) is unchanged.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';
import '../theme/md3.dart';
import '../widgets/settings/update_check_ui.dart';
import '../widgets/wenku/wenku_ui.dart';

/// About page in the Wenku8 archive shell: centered logo/name header, a short
/// intro paragraph, then archive panel rows (version, updates, licenses,
/// source code, feedback, ...).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// Display version, kept in lockstep with pubspec.yaml's
  /// `version`. Without a package_info dependency the value is
  /// static, so test/about_version_test.dart parses the pubspec and fails the
  /// build check when the two drift apart after a version bump.
  static const versionText = kVersionText;

  /// Pixel width of the bundled logo (assets/images/app_logo.webp). The logo
  /// is displayed at 80dp, so it only needs re-decoding above 4× DPI; clamping
  /// to the asset's real width keeps a high-DPI device from asking the decoder
  /// to upscale a surface the asset does not have. Keep it in sync with
  /// LOGO_SIZE in scripts/generate_app_icons.py.
  static const _logoPixelWidth = 384;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ArchiveFeaturePage(
      title: '关于',
      code: 'SYSTEM / ABOUT',
      child: ListView(
        key: const ValueKey('about-scroll'),
        padding: featurePadding(context),
        children: [
          const _AboutLogo(),
          const SizedBox(height: 12),
          const _AboutHeading(),
          const SizedBox(height: 16),
          Text(
            '页屿把小说、短剧、漫剧、漫画和听书聚到一起。'
            '所有签名与解密都在你的手机本地完成，不依赖第三方服务。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          const ArchiveSection(title: '应用信息', code: 'FQAPP / ABOUT'),
          const SizedBox(height: 14),
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(
                  icon: LucideIcons.badge_check,
                  title: '当前版本',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        label: Text(versionText),
                        backgroundColor: scheme.secondaryContainer,
                        textColor: scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.copy,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  onTap: () => _copyVersion(context),
                ),
                _InfoRow(
                  icon: LucideIcons.user,
                  title: '作者',
                  trailing: Text(
                    'hrk_',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _InfoRow(
                  icon: LucideIcons.square_arrow_out_up_right,
                  title: '检查更新',
                  subtitle: '检查新版本与公告（经 update.json）',
                  onTap: () => checkUpdateNow(context, autoPrompt: false),
                ),
                _InfoRow(
                  icon: LucideIcons.scale,
                  title: '开源许可',
                  subtitle: 'GPL-3.0 与第三方组件许可',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: '页屿',
                    applicationVersion: versionText,
                    applicationLegalese:
                        '页屿基于 GPL-3.0 协议开源，第三方组件遵循其各自的许可协议。'
                        '上游致谢：Wenku8 Flutter（界面来源与许可文本见 '
                        'assets/licenses/wenku8）、fqapp、moye 弦电子书。',
                  ),
                ),
                _InfoRow(
                  icon: LucideIcons.code_xml,
                  title: '源代码',
                  subtitle: 'github.com/hrk666666/yeyu-reader',
                  onTap: () => _launchExternalUrl(
                    context,
                    'https://github.com/hrk666666/yeyu-reader',
                  ),
                ),
                _InfoRow(
                  icon: LucideIcons.message_square,
                  title: '问题反馈',
                  subtitle: '前往 GitHub Issues 提交',
                  onTap: () => _launchExternalUrl(
                    context,
                    'https://github.com/hrk666666/yeyu-reader/issues',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const ArchiveSection(title: '开发说明', code: 'CREDITS / ORIGIN'),
          const SizedBox(height: 12),
          Text(
            '基于 fqapp 1.4.0（GPL-3.0，原作者 ch6vip）二次开发；'
            '界面排版参考 Wenku8 Flutter；'
            '手环传书协议移植自 moye 弦电子书（开源）；'
            '内容数据来自番茄小说官方接口。'
            '二次开发：hrk_',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '仅限个人学习研究使用\n请遵守相关法律法规',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 版本行点按：把版本号写进剪贴板，并用 SnackBar 明示已复制。
  static void _copyVersion(BuildContext context) {
    unawaited(Clipboard.setData(const ClipboardData(text: versionText)));
    md3ShowSnackBar(context, '已复制版本号');
  }
}

/// Archive-style information row: leading icon, title/subtitle and an optional
/// trailing value. The whole row is the tap target.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      leading: Icon(icon, size: 21, color: scheme.onSurfaceVariant),
      title: Text(title, style: theme.textTheme.bodyLarge),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                )),
      onTap: onTap,
    );
  }
}

/// 头部 logo：全幅图片，圆角与投影跟随图版的 15% 板式圆角。
class _AboutLogo extends StatelessWidget {
  const _AboutLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      // M3 不再画自研彩色投影：图版圆角跟随 medium shape，层次由主题表达。
      child: Container(
        key: const ValueKey('about-logo-plate'),
        decoration: BoxDecoration(borderRadius: Md3Shape.mediumRadius),
        child: ClipRRect(
          borderRadius: Md3Shape.mediumRadius,
          child: Image.asset(
            'assets/images/app_logo.webp',
            width: 80,
            height: 80,
            // Decode at the display size rather than the whole 384²
            // surface, which would hold ~590 KB in the image cache for a
            // 80dp logo.
            cacheWidth: (80 * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(80, AboutPage._logoPixelWidth),
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}

/// 头部应用名与一行定位副标题。
class _AboutHeading extends StatelessWidget {
  const _AboutHeading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        AppText(
          '页屿',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
            height: 1.25,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        AppText(
          '小说 / 短剧 / 漫剧 / 漫画 / 听书聚合客户端',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 用外部应用打开 [url]。Android 的包可见性可能让浏览器对 canLaunchUrl
/// 不可见，但仍能处理 ACTION_VIEW，所以这里不做预检查，失败统一走可见提示。
Future<void> _launchExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  var launched = false;
  try {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Report launch failures through the same visible fallback.
  }
  if (!launched && context.mounted) {
    md3ShowSnackBar(context, '无法打开链接');
  }
}
