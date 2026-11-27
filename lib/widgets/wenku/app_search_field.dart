import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/md3.dart';
import 'src/app_text.dart';
import 'wenku_glass.dart';
import 'wenku_icons.dart';

/// One borderless input inside the shared glass plate. Embedded header searches
/// keep their animated outer plate, rather than nesting a filled Material field.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.inputKey,
    this.controller,
    this.focusNode,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.embedded = false,
    this.showLeading = true,
    this.trailing,
    this.autofocus = false,
    this.clearTooltip = '清空搜索',
  });

  final Key? inputKey;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool embedded;
  final bool showLeading;
  final Widget? trailing;
  final bool autofocus;
  final String clearTooltip;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _owned;
  TextEditingController get _text =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Md3Dimens.minTouchTarget),
      child: Row(
        children: [
          if (widget.showLeading)
            SizedBox(
              width: 44,
              child: ArchiveIcon(
                CupertinoIcons.search,
                size: 19,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          Expanded(
            child: TextField(
              key: widget.inputKey,
              controller: _text,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              // 官方 MD3 typescale（bodyMedium），去掉自研 14px 字号。
              style: Theme.of(context).textTheme.bodyMedium,
              onTap: () => AppHaptics.play(context, HapticCue.selection),
              onTapAlwaysCalled: true,
              onChanged: widget.onChanged,
              onSubmitted: (value) {
                AppHaptics.play(context, HapticCue.action);
                widget.onSubmitted?.call(value);
              },
              decoration: InputDecoration(
                hintText: appText(context, widget.hint),
                hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _text,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : SizedBox(
                    width: Md3Dimens.minTouchTarget,
                    height: Md3Dimens.minTouchTarget,
                    child: ArchiveIconButton(
                      tooltip: appText(context, widget.clearTooltip),
                      onPressed: () {
                        _text.clear();
                        widget.onChanged?.call('');
                      },
                      icon: const ArchiveIcon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 16,
                      ),
                    ),
                  ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
    // 官方 MD3 SearchBar 为全圆角胶囊（StadiumBorder）：用 Md3Shape.full。
    return widget.embedded
        ? child
        : LiquidGlass(radius: Md3Shape.full, elevated: false, child: child);
  }
}
