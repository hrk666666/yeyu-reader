// 系统朗读设置页。
//
// Chrome ported from Wenku8_Flutter (revision ebcd7f1)
// `lib/listening/system_tts_page.dart`: ArchiveFeaturePage-style header,
// engine rows and the archive action vocabulary. The upstream page is a
// sheet panel; fqapp keeps a full route because it is linked from Settings.
//
// Mechanical substitutions:
// - The upstream engine/voice sheet (`SystemSpeechEnginesPanel`, GlassTextButton
//   rows) maps to this page's engine selector and rate slider; fqapp's engine
//   and preference services (`SystemTts`, `SystemTtsPreferences`) are kept.
// - `AppControls.toggle/slider` -> `GlassControls`
//   (`lib/widgets/wenku/glass_controls.dart`).
// - `showNovelFeedback` -> the existing SnackBar messages (same text).
// - Empty/error states use `ContentNotice`, the shared archive state widget.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/audio_floating_routes.dart';
import '../services/system_tts.dart';
import '../theme/md3.dart';
import '../widgets/settings/settings_archive_rows.dart';
import '../widgets/wenku/wenku_ui.dart';

class SystemTtsSettingsPage extends StatefulWidget {
  const SystemTtsSettingsPage({super.key});

  @override
  State<SystemTtsSettingsPage> createState() => _SystemTtsSettingsPageState();
}

class _SystemTtsSettingsPageState extends State<SystemTtsSettingsPage>
    with WidgetsBindingObserver {
  List<SystemTtsEngine> _engines = const [];
  String? _defaultEngine;
  SystemTtsPreferences _prefs = const SystemTtsPreferences();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _generation = 0;

  // Official AudioPlaySettingActivity hides the capsule.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AudioFloatingRouteScope.configure(context, hidden: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_saving) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SystemTtsPreferences.load();
      final data = await SystemTts.engines();
      if (!mounted || generation != _generation) return;
      setState(() {
        _prefs = prefs;
        _engines = data.engines;
        _defaultEngine = data.defaultEngine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = SystemTts.errorMessage(e);
      });
    }
  }

  Future<void> _save(SystemTtsPreferences prefs) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await prefs.save();
      if (mounted) setState(() => _prefs = prefs);
    } catch (_) {
      if (mounted) {
        md3ShowSnackBar(context, '设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      await SystemTts.openSettings();
    } catch (e) {
      if (mounted) {
        md3ShowSnackBar(context, SystemTts.errorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMissing =
        _prefs.engine != null &&
        !_engines.any((e) => e.package == _prefs.engine);
    final defaultLabel = _engines
        .where((e) => e.package == _defaultEngine)
        .firstOrNull
        ?.label;
    return ArchiveFeaturePage(
      title: '系统朗读',
      code: 'AUDIO / SYSTEM ENGINES',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: featurePadding(context),
                  children: [
                    const SettingsHint(
                      '从小说或本地书阅读页点“听书”即可使用。支持已安装的系统 TTS '
                      '引擎，例如 MultiTTS；音色和联网需求由引擎管理。',
                    ),
                    const SizedBox(height: 16),
                    if (_error case final error?)
                      ContentNotice(
                        icon: CupertinoIcons.wifi_exclamationmark,
                        title: '无法读取朗读引擎',
                        message: error,
                        actionLabel: '重试',
                        onRetry: _load,
                      )
                    else if (_engines.isEmpty)
                      const ContentNotice(
                        icon: CupertinoIcons.volume_off,
                        title: '没有找到朗读引擎',
                        message: '请先安装并在引擎应用中配置中文语音。',
                      )
                    else ...[
                      SettingsPanel(
                        children: [
                          if (selectedMissing)
                            AppText(
                              '之前选择的引擎已不可用，请重新选择。',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          _enginePicker(selectedMissing, defaultLabel),
                          _ratePicker(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const SettingsHint(
                        '引擎和语速修改在关闭当前系统朗读、重新开始后生效。'
                        '部分引擎暂停后会从当前短句重读。',
                      ),
                    ],
                    const SizedBox(height: 20),
                    Center(
                      child: TextButton.icon(
                        onPressed: _openSettings,
                        icon: const Icon(CupertinoIcons.settings, size: 17),
                        label: const Text('打开系统语音设置'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _enginePicker(bool selectedMissing, String? defaultLabel) {
    final missingEngine = selectedMissing ? _prefs.engine : null;
    final options = <String, String>{
      '': '系统默认${defaultLabel == null ? '' : ' · $defaultLabel'}',
      for (final engine in _engines) engine.package: engine.label,
      ?missingEngine: '已不可用 · $missingEngine',
    };
    return DropdownMenu<String>(
      expandedInsets: EdgeInsets.zero,
      initialSelection: _prefs.engine ?? '',
      label: const Text('朗读引擎'),
      leadingIcon: const Icon(CupertinoIcons.waveform),
      dropdownMenuEntries: [
        for (final option in options.entries)
          DropdownMenuEntry<String>(value: option.key, label: option.value),
      ],
      onSelected: _saving
          ? null
          : (value) {
              if (value == null) return;
              _save(
                SystemTtsPreferences(
                  engine: value.isEmpty ? null : value,
                  rate: _prefs.rate,
                ),
              );
            },
    );
  }

  Widget _ratePicker() {
    final rate = _prefs.rate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '语速',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${rate.toStringAsFixed(1)}×',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Slider(
          value: rate,
          min: .5,
          max: 3,
          divisions: 25,
          label: '${rate.toStringAsFixed(1)}×',
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _prefs = SystemTtsPreferences(
                    engine: _prefs.engine,
                    rate: value,
                  );
                }),
          onChangeEnd: _saving
              ? null
              : (value) => _save(
                  SystemTtsPreferences(engine: _prefs.engine, rate: value),
                ),
        ),
      ],
    );
  }
}
