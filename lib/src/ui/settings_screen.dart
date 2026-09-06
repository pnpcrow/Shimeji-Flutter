/// The settings screen, shown in the (previously hidden) host window.
///
/// Covers the rendering-mode selection, language, sprite scaling/opacity,
/// the behavior toggles from the original tray and the interactive-window
/// title rules of the Java original's SettingsWindow.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../native/app_window.dart';

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

  @override
  void initState() {
    super.initState();
    final settings = widget.app.settings;
    breeding = settings.breeding;
    transients = settings.transients;
    transformation = settings.transformation;
    throwing = settings.throwing;
    sounds = settings.sounds;
    multiscreen = settings.multiscreen;
    scaling = settings.scaling;
    opacity = settings.opacity;
    // Reflect the language actually in effect: '' when following the system.
    language = settings.language;
    interactiveWindows =
        TextEditingController(text: settings.interactiveWindows.join('/'));
  }

  @override
  void dispose() {
    interactiveWindows.dispose();
    super.dispose();
  }

  /// Applies the language immediately (bundle reload + persistence) and
  /// notifies the tray so both surfaces stay in sync.
  void _changeLanguage(String tag) {
    setState(() => language = tag);
    widget.app.setLanguage(tag);
    widget.app.saveSettings();
    widget.onLanguageChanged?.call();
  }

  void _applyAndClose() {
    final settings = widget.app.settings;
    settings.breeding = breeding;
    settings.transients = transients;
    settings.transformation = transformation;
    settings.throwing = throwing;
    settings.sounds = sounds;
    settings.multiscreen = multiscreen;
    settings.opacity = opacity;
    settings.scaling = scaling;
    settings.language = language;
    settings.interactiveWindows = interactiveWindows.text
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    widget.app.environment.refreshCache();
    widget.app.setLanguage(language);
    widget.app.saveSettings();
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
                value: language,
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
                onChanged: (value) =>
                    setState(() => language = value ?? language),
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
              ),
              const Divider(height: 28),
              Text('Behaviors / 행동',
                  style: Theme.of(context).textTheme.titleMedium),
              _check(lang.getString('Breeding'), breeding,
                  (v) => setState(() => breeding = v ?? breeding)),
              _check(lang.getString('Transients'), transients,
                  (v) => setState(() => transients = v ?? transients)),
              _check(lang.getString('Transformation'), transformation,
                  (v) => setState(() => transformation = v ?? transformation)),
              _check(lang.getString('ThrowingWindows'), throwing,
                  (v) => setState(() => throwing = v ?? throwing)),
              _check(lang.getString('SoundEffects'), sounds,
                  (v) => setState(() => sounds = v ?? sounds)),
              _check(lang.getString('Multiscreen'), multiscreen,
                  (v) => setState(() => multiscreen = v ?? multiscreen)),
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
