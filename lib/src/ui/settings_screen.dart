/// The settings screen, shown in the chromeless host window.
///
/// Every control applies its change immediately — state, persistence and the
/// [SettingsChangeNotifier] broadcast happen on the spot, so mascots, the
/// tray and every other surface pick the change up without a Save action.
/// There is no Save button; the window is closed from its own header.
///
/// Sync contract: every option change applies immediately and broadcasts
/// through [SettingsChangeNotifier]; the tray rebuilds from the same signal,
/// and changes made in the tray refresh this screen via the same notifier.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../settings.dart' show Settings;
import '../native/app_window.dart';

class SettingsScreen extends StatefulWidget {
  final ShimejiApp app;
  final VoidCallback onClose;

  const SettingsScreen({
    super.key,
    required this.app,
    required this.onClose,
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
  late String renderingMode;
  late String language;
  late TextEditingController interactiveWindows;
  Timer? _interactiveDebounce;
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
    _interactiveDebounce?.cancel();
    // Flush an uncommitted interactive-window edit (window closed while the
    // debounce was still pending) so closing never loses input.
    final parsed = interactiveWindows.text
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (widget.app.settings.interactiveWindows.join('/') != parsed.join('/')) {
      widget.app.settings.interactiveWindows = parsed;
      widget.app.saveSettings();
    }
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
    renderingMode = settings.renderingMode;
  }

  /// Applies one option immediately: mutates settings, persists to disk and
  /// broadcasts so the tray and mascots pick the change up at once. Runtime
  /// side effects (Sounds.enabled, environment caches) are applied centrally
  /// by [ShimejiApp.saveSettings].
  void _apply(void Function(Settings s) apply) {
    apply(widget.app.settings);
    widget.app.saveSettings();
  }

  /// Applies the language immediately (bundle reload + persistence) and
  /// broadcasts so the tray and other surfaces stay in sync.
  void _changeLanguage(String tag) {
    setState(() => language = tag);
    widget.app.setLanguage(tag);
    widget.app.saveSettings();
  }

  /// Switches the screen presentation mode; every mascot respawns under
  /// the new presenter (see [ShimejiApp.switchRenderingMode]).
  Future<void> _changeRenderingMode(String mode) async {
    setState(() => renderingMode = mode);
    await widget.app.switchRenderingMode(mode);
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
  }

  /// Commits the interactive-window field live (debounced while typing) so
  /// mascots start interacting with matching windows without a save action.
  void _onInteractiveWindowsChanged() {
    _interactiveDebounce?.cancel();
    _interactiveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      widget.app.settings.interactiveWindows = interactiveWindows.text
          .split('/')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      widget.app.saveSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.app.languageBundle;
    final languages = widget.app.availableLanguages();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFFFAF9F7),
          body: Column(
            children: [
              _buildHeader(lang),
              const Divider(height: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        _section(lang.getString('Language')),
                        DropdownButtonFormField<String>(
                          // Re-keyed on language switches (own or from the
                          // tray) so the rebuilt field shows the new choice.
                          key: ValueKey(language),
                          initialValue: language.isEmpty ? '' : language,
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(widget.app.systemLanguageLabel),
                            ),
                            for (final tag in languages)
                              DropdownMenuItem(
                                value: tag,
                                child:
                                    Text(widget.app.languageDisplayName(tag)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null || value == language) return;
                            _changeLanguage(value);
                          },
                        ),
                        _section(lang.getString('ImageSets')),
                        if (imageSets.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(lang.getString('NoImageSetsFound'),
                                style: _mutedStyle),
                          ),
                        for (final set in imageSets)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            value:
                                widget.app.settings.activeImageSets.contains(set),
                            title: Text(set, style: _rowStyle),
                            onChanged: (_) => _toggleImageSet(set),
                          ),
                        _section(lang.getString('Scaling')),
                        _sliderValueRow(lang.getString('Scaling'),
                            '${scaling.toStringAsFixed(2)}x'),
                        Slider(
                          min: 0.25,
                          max: 4,
                          divisions: 15,
                          value: scaling,
                          onChanged: (v) => setState(() => scaling = v),
                          // Scaling is baked into the decoded sprites: on
                          // release, re-decode and respawn every active set.
                          onChangeEnd: (v) async {
                            if ((v - widget.app.settings.scaling).abs() <
                                0.0005) {
                              return;
                            }
                            await widget.app.applyScaling(v);
                          },
                        ),
                        _sliderValueRow(lang.getString('Opacity'),
                            '${(opacity * 100).round()}%'),
                        Slider(
                          min: 0.1,
                          max: 1,
                          divisions: 9,
                          value: opacity,
                          onChanged: (v) => setState(() => opacity = v),
                          onChangeEnd: (v) => _apply((s) => s.opacity = v),
                        ),
                        _section(lang.getString('RenderingMode')),
                        DropdownButtonFormField<String>(
                          // Re-keyed on mode switches so the field always
                          // shows the freshly applied value.
                          key: ValueKey('renderer-$renderingMode'),
                          initialValue: renderingMode,
                          isDense: true,
                          borderRadius: BorderRadius.circular(10),
                          items: [
                            DropdownMenuItem(
                              value: 'legacy',
                              child: Text(lang.getString('RendererLegacy'),
                                  style: _rowStyle),
                            ),
                            DropdownMenuItem(
                              value: 'flutter',
                              child: Text(lang.getString('RendererFlutter'),
                                  style: _rowStyle),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null || value == renderingMode) {
                              return;
                            }
                            _changeRenderingMode(value);
                          },
                        ),
                        _section(lang.getString('General')),
                        _switch(lang.getString('Breeding'), breeding,
                            (v) => _apply((s) => s.breeding = v)),
                        _switch(lang.getString('Transients'), transients,
                            (v) => _apply((s) => s.transients = v)),
                        _switch(lang.getString('Transformation'), transformation,
                            (v) => _apply((s) => s.transformation = v)),
                        _switch(lang.getString('ThrowingWindows'), throwing,
                            (v) => _apply((s) => s.throwing = v)),
                        _switch(lang.getString('SoundEffects'), sounds,
                            (v) => _apply((s) => s.sounds = v)),
                        _switch(lang.getString('Multiscreen'), multiscreen,
                            (v) => _apply((s) => s.multiscreen = v)),
                        _section(lang.getString('InteractiveWindows')),
                        TextField(
                          controller: interactiveWindows,
                          onChanged: (_) => _onInteractiveWindowsChanged(),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText:
                                lang.getString('InteractiveWindowsHint'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _rowStyle = TextStyle(fontSize: 14);
  static const _mutedStyle =
      TextStyle(fontSize: 13, color: Colors.black38);

  /// Chromeless title bar: draggable everywhere except the close button,
  /// which is the only window chrome the screen needs.
  Widget _buildHeader(LanguageBundle lang) {
    return GestureDetector(
      onPanStart: (_) => AppWindow.beginWindowDrag(),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            const SizedBox(width: 20),
            Text(
              lang.getString('Settings'),
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: lang.getString('Close'),
              onPressed: widget.onClose,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.black45,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _sliderValueRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: _rowStyle),
        Text(value, style: _mutedStyle),
      ],
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      value: value,
      title: Text(label, style: _rowStyle),
      onChanged: onChanged,
    );
  }
}
