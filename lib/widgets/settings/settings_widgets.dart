import 'package:flutter/material.dart';

import '../../services/app_theme.dart';
import '../../theme/md3.dart';
import '../home/home_back_button.dart';
import '../home/home_design.dart';
import '../home/home_shelf.dart';

/// 设置类页面的共享骨架。
///
/// 收敛点（审查结论）：4 套设置行 / 3 套卡片（20+0.6、18+1.0、16+0.6）/
/// 2 套开关（Material Switch、SwitchListTile）/ 5 种空错态。这里给出唯一
/// 一套：卡片圆角 [SettingsGroupCard.radius]、行高 52/64、行内标题 15sp、
/// 副标题 12.5sp，开关统一走 [SettingsSwitch]。颜色一律 `HomePalette`，
/// 墨水屏自动退化为纯黑白。

/// 设置页统一的 AppBar：画布色、无 elevation / surface tint、Lucide 返回。
///
/// 背景取 [HomePalette.canvas]，与 SettingsScaffold 的 body 同色；只设 body
/// 色的旧页面在 AppBar 与 body 之间不会再出现两色拼接。
AppBar settingsAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
}) {
  final theme = Theme.of(context);
  return AppBar(
    centerTitle: true,
    leadingWidth: 56,
    leading: const Padding(
      padding: EdgeInsets.only(left: 10),
      child: Center(child: HomeBackButton()),
    ),
    title: Text(title, style: theme.textTheme.titleLarge),
    actions: actions,
    bottom: bottom,
  );
}

/// 设置页外壳：画布底色 + [settingsAppBar]。
class SettingsScaffold extends StatelessWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottom,
    this.resizeToAvoidBottomInset,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: settingsAppBar(
        context,
        title: title,
        actions: actions,
        bottom: bottom,
      ),
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: body,
    );
  }
}

/// 设置分组卡片：surface 底 + 0.6dp line 描边 + 唯一圆角 token。
///
/// [children] 之间自动插入一条缩进 68dp 的分隔线（与 38dp 图标砖 +
/// 12dp 间距后的文字起点对齐）；放自定义内容时可用 [showDividers] 关掉。
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.children,
    this.showDividers = true,
  });

  /// 设置卡片的唯一圆角（M3 large）。
  static const double radius = Md3Shape.large;

  /// 行间分隔线的左侧缩进。
  static const double dividerIndent = 68;

  final List<Widget> children;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0 && showDividers)
              Divider(
                height: 1,
                indent: dividerIndent,
                color: scheme.outlineVariant,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 一行设置：可选图标 / 38dp 图标砖 + 标题 + 副标题 + 尾部控件。
///
/// 尾部三选一：
/// * [trailing] 自定义（开关、按钮）；
/// * [value] + 自动 chevron（导航行）；
/// * 只给 [onTap] 时 auto chevron，用 [showChevron] 可关掉。
///
/// 最小高度 52dp（有副标题 64dp），大字号下随内容增高不裁切。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconTile = false,
    this.trailing,
    this.value,
    this.onTap,
    this.enabled = true,
    this.showChevron,
  }) : assert(value == null || trailing == null, 'value 与 trailing 只能二选一');

  static const double minHeight = 52;
  static const double minHeightWithSubtitle = 64;

  final String title;
  final String? subtitle;

  /// 19dp 行内图标；[iconTile] 为 true 时改用 38dp soft 图标砖。
  final IconData? icon;
  final bool iconTile;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;

  /// 缺省：有 [onTap] 时显示 chevron。
  final bool? showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final trailing = this.trailing ?? _defaultTrailing(scheme);
    return Semantics(
      label: subtitle == null ? title : '$title，$subtitle',
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: icon == null ? null : _icon(scheme),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        trailing: trailing,
      ),
    );
  }

  Widget _icon(ColorScheme scheme) {
    final icon = this.icon!;
    if (!iconTile) {
      return Icon(icon, size: 19, color: scheme.onSurfaceVariant);
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Md3Shape.smallRadius,
      ),
      child: Icon(icon, size: 20, color: scheme.primary),
    );
  }

  Widget? _defaultTrailing(ColorScheme scheme) {
    final chevron = (showChevron ?? onTap != null)
        ? Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant)
        : null;
    if (value == null && chevron == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          Text(
            value!,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        if (value != null && chevron != null) const SizedBox(width: 4),
        ?chevron,
      ],
    );
  }
}

/// 设置页分区头：与 [HomeSectionHeader] 同一版式。
///
/// 设置页的 ListView 通常已经给了 16dp 水平内边距，[gutter] 默认 0，避免
/// 分区头再缩进一次；放在无内边距容器里时传 `homeGutter`。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    this.gutter = 0,
  });

  final String title;
  final double gutter;

  @override
  Widget build(BuildContext context) =>
      HomeSectionHeader(title: title, gutter: gutter);
}

/// 设置页开关：直接使用官方 [Switch]，选中 / 未选中 / 禁用态全部由
/// 主题（含墨水屏、OLED 的 ColorScheme 变体）接管，不再自绘轨道与滑块。
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// 设置页确认框：取消 + 确认（破坏性操作确认键用书架同款删除红）。
///
/// 墨水屏下删除红不进入主题（纯黑白要求），改用 [HomePalette.ink] 黑字
/// 并给按钮加 1dp 黑描边：`secondaryContainer` 与对话框底色都是白色，
/// 没有描边按钮边界会和对话框融为一体。
/// 返回 true 仅当用户点了确认；点遮罩 / 返回键关闭按取消处理。
Future<bool> showSettingsConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        shape: Md3Shape.dialogShape,
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: destructive
                ? FilledButton.styleFrom(foregroundColor: scheme.error)
                : einkModeNotifier.value
                    // 墨水屏：secondaryContainer 与对话框底同为白色，
                    // 1dp 黑描边保证按钮边界可辨（见上方注释）。
                    ? FilledButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.black,
                          width: 1,
                        ),
                      )
                    : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}
