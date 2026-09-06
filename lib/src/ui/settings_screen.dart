/// The settings screen, shown in the (previously hidden) host window.
///
/// Covers the rendering-mode selection, language, sprite scaling/opacity,
/// the behavior toggles from the original tray and the interactive-window
/// title rules of the Java original's SettingsWindow.
///
/// Sync contract: every option change applies immediately and broadcasts
/// through [SettingsChangeNotifier]; the tray rebuilds from the same signal,
/// and changes made in the tray refresh this screen via the same notifier.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../settings.dart' show Settings;
import '../native/mascot_windows.dart';

class SettingsScreen extends StatefulWidget {
  final ShimejiApp app;
  final VoidCallback onClose;

  /// Fired right after the language is changed inside this screen, so the
  /// tray menu and other surfaces rebuild in sync.
  final VoidCallback? onLanguageChanged;

  const SettingsScreen({
    super.key,
    required this.app,
    required this.onClose,
    this.onLanguageChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool breeding;
  late bool transients;
  late bool transformation;
  late bool throwing;
  late bool sounds;
  late bool multiscreen;
  late double scaling;
  late double opacity;
  late String language;
  late TextEditingController interactiveWindows;
  List<String> imageSets = [];

  @override
  void initState() {
    super.initState();
    _refreshFromSettings();
    // Reflect the stored choice ('' = follow the system language) so the
    // dropdown matches its "System language" item.
    language = widget.app.settings.language;
    interactiveWindows = TextEditingController(
        text: widget.app.settings.interactiveWindows.join('/'));
    _loadImageSets();
    // External changes (tray, context menu) refresh this screen live.
    SettingsChangeNotifier.instance.addListener(_onSettingsBroadcast);
  }

  @override
  void dispose() {
    SettingsChangeNotifier.instance.removeListener(_onSettingsBroadcast);
    interactiveWindows.dispose();
    super.dispose();
  }

  /// Called when settings changed on another surface (tray, context menu):
  /// refresh every field and the localized labels.
  void _onSettingsBroadcast() {
    if (!mounted) return;
    setState(() {
      language = widget.app.settings.language;
      _refreshFromSettings();
    });
    _loadImageSets();
  }

  Future<void> _loadImageSets() async {
    final sets = await widget.app.availableImageSets();
    if (!mounted) return;
    setState(() => imageSets = sets);
  }

  void _refreshFromSettings() {
    final settings = widget.app.settings;
    breeding = settings.breeding;
    transients = settings.transients;
    transformation = settings.transformation;
    throwing = settings.throwing;
    sounds = settings.sounds;
    multiscreen = settings.multiscreen;
    scaling = settings.scaling;
    opacity = settings.opacity;
  }

  /// Applies a boolean option immediately (state + persist + broadcast) so
  /// the tray and mascots pick it up without pressing Save. Runtime side
  /// effects (Sounds.enabled, environment caches) are applied centrally by
  /// [ShimejiApp.saveSettings].
  void _applyToggle(
      void Function(Settings s) apply, void Function() updateLocal) {
    apply(widget.app.settings);
    updateLocal();
    widget.app.saveSettings();
  }

  /// Applies the language immediately (bundle reload + persistence) and
  /// broadcasts so the tray and other surfaces stay in sync.
  void _changeLanguage(String tag) {
    setState(() => language = tag);
    widget.app.setLanguage(tag);
    widget.app.saveSettings();
    widget.onLanguageChanged?.call();
  }

  /// Chooser: adds/removes an image set and respawns the mascots. The
  /// broadcast from switchImageSets refreshes this screen and the tray.
  Future<void> _toggleImageSet(String set) async {
    final settings = widget.app.settings;
    final next = <String>[...settings.activeImageSets];
    if (next.contains(set)) {
      next.remove(set);
    } else {
      next.add(set);
    }
    if (next.isEmpty) return;
    await widget.app.switchImageSets(next..sort());
    MascotNativeWindows.clearCache();
  }

  /// Commits the text field and the scaling slider (the only Save-only
  /// controls; everything else already applied itself) and closes.
  void _applyAndClose() {
    widget.app.settings.scaling = scaling;
    widget.app.settings.interactiveWindows = interactiveWindows.text
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    widget.app.setLanguage(language);
    widget.app.saveSettings();
    widget.onLanguageChanged?.call();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.app.languageBundle;
    final languages = widget.app.availableLanguages();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(lang.getString('Settings')),
        actions: [
          TextButton(
            onPressed: _applyAndClose,
            child: const Text('Save'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Rendering mode',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              RadioListTile<String>(
                dense: true,
                value: 'legacy',
                groupValue: widget.app.settings.renderingMode,
                onChanged: (_) {},
                title: const Text('Legacy (레거시)'),
                subtitle: const Text(
                    '마스코트마다 네이티브 픽셀 알파 윈도우 (원본 Java 아키텍처)'),
              ),
              const Divider(height: 28),
              Text('Language / 언어',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: language.isEmpty ? '' : language,
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(widget.app.systemLanguageLabel),
                  ),
                  for (final tag in languages)
                    DropdownMenuItem(
                      value: tag,
                      child: Text(widget.app.languageDisplayName(tag)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null || value == language) return;
                  _changeLanguage(value);
                },
              ),
              const Divider(height: 28),
              Text('Image sets / 이미지 세트',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (imageSets.isEmpty)
                const Text('No image sets found.'),
              for (final set in imageSets)
                CheckboxListTile(
                  dense: true,
                  value: widget.app.settings.activeImageSets.contains(set),
                  title: Text(set),
                  onChanged: (_) => _toggleImageSet(set),
                ),
              const Divider(height: 28),
              Text('Sprites / 스프라이트',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('Scaling: ${scaling.toStringAsFixed(2)}x  (새 이미지 로딩 시 적용)'),
              Slider(
                min: 0.25,
                max: 4,
                divisions: 15,
                value: scaling,
                onChanged: (v) => setState(() => scaling = v),
              ),
              Text('Opacity: ${(opacity * 100).round()}%'),
              Slider(
                min: 0.1,
                max: 1,
                divisions: 9,
                value: opacity,
                onChanged: (v) => setState(() => opacity = v),
                onChangeEnd: (v) => _applyToggle(
                    (s) => s.opacity = v, () => opacity = v),
              ),
              const Divider(height: 28),
              Text('Behaviors / 행동',
                  style: Theme.of(context).textTheme.titleMedium),
              _check(lang.getString('Breeding'), breeding, (v) {
                final next = v ?? breeding;
                _applyToggle((s) => s.breeding = next,
                    () => breeding = next);
              }),
              _check(lang.getString('Transients'), transients, (v) {
                final next = v ?? transients;
                _applyToggle((s) => s.transients = next,
                    () => transients = next);
              }),
              _check(lang.getString('Transformation'), transformation, (v) {
                final next = v ?? transformation;
                _applyToggle((s) => s.transformation = next,
                    () => transformation = next);
              }),
              _check(lang.getString('ThrowingWindows'), throwing, (v) {
                final next = v ?? throwing;
                _applyToggle((s) => s.throwing = next,
                    () => throwing = next);
              }),
              _check(lang.getString('SoundEffects'), sounds, (v) {
                final next = v ?? sounds;
                _applyToggle((s) => s.sounds = next, () => sounds = next);
              }),
              _check(lang.getString('Multiscreen'), multiscreen, (v) {
                final next = v ?? multiscreen;
                _applyToggle((s) => s.multiscreen = next,
                    () => multiscreen = next);
              }),
              const Divider(height: 28),
              Text('Interactive windows (title substrings, / separated)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              TextField(controller: interactiveWindows),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: widget.onClose,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _applyAndClose,
                    child: const Text('Save & Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      dense: true,
      value: value,
      title: Text(label),
      onChanged: onChanged,
    );
  }
}
