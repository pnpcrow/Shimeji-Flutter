/// Overlay UI: context menu, image set chooser, settings and stats panels.
///
/// The Java original used Swing dialogs; here everything renders on the
/// transparent overlay window.
library;

import 'package:flutter/material.dart';

import '../app.dart';
import '../mascot.dart';
import 'app_ui_state.dart';

/// Renders the open context menu.
class ContextMenuWidget extends StatelessWidget {
  final MenuModel model;
  final double left;
  final double top;
  final VoidCallback onClose;

  const ContextMenuWidget({
    super.key,
    required this.model,
    required this.left,
    required this.top,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: IntrinsicWidth(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500, maxWidth: 320),
            decoration: BoxDecoration(
              color: const Color(0xFFFDFDFD),
              border: Border.all(color: const Color(0xFFB0B0B0)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in model.items)
                    if (item.isSeparator)
                      const Divider(height: 9, thickness: 1)
                    else
                      _MenuRow(
                        label: item.label!,
                        checked: item.checked,
                        onTap: () {
                          onClose();
                          item.onTap?.call();
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onTap;

  const _MenuRow({required this.label, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: checked
                  ? const Icon(Icons.check, size: 15, color: Color(0xFF333333))
                  : null,
            ),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The image set chooser panel (port of ImageSetChooser).
class ImageSetChooser extends StatefulWidget {
  final ShimejiApp app;
  const ImageSetChooser({super.key, required this.app});

  @override
  State<ImageSetChooser> createState() => _ImageSetChooserState();
}

class _ImageSetChooserState extends State<ImageSetChooser> {
  late Future<List<String>> _setsFuture;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _setsFuture = widget.app.availableImageSets();
    _selected.addAll(widget.app.settings.activeImageSets);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          border: Border.all(color: const Color(0xFF9A9A9A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.app.languageBundle.getString('ChooseShimeji'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FutureBuilder<List<String>>(
              future: _setsFuture,
              builder: (context, snapshot) {
                final sets = snapshot.data ?? const <String>[];
                if (sets.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('No image sets found in the img directory.'),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final set in sets)
                          CheckboxListTile(
                            dense: true,
                            value: _selected.contains(set),
                            title: Text(set),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(set);
                                } else {
                                  _selected.remove(set);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      AppUiState.instance.closePanels(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final selected = _selected.toList()..sort();
                    AppUiState.instance.closePanels();
                    await widget.app.switchImageSets(selected);
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The settings panel (port of SettingsWindow, simplified).
class SettingsPanel extends StatefulWidget {
  final ShimejiApp app;
  const SettingsPanel({super.key, required this.app});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late bool breeding;
  late bool transients;
  late bool transformation;
  late bool throwing;
  late bool sounds;
  late bool multiscreen;
  late double scaling;
  late double opacity;
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
    interactiveWindows =
        TextEditingController(text: settings.interactiveWindows.join('/'));
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.app.languageBundle;
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          border: Border.all(color: const Color(0xFF9A9A9A)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(lang.getString('Settings'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              Text('Scaling: ${scaling.toStringAsFixed(2)}x'),
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
              const SizedBox(height: 8),
              const Text('Interactive windows (title substrings, / separated):'),
              TextField(controller: interactiveWindows),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => AppUiState.instance.closePanels(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      final settings = widget.app.settings;
                      settings.breeding = breeding;
                      settings.transients = transients;
                      settings.transformation = transformation;
                      settings.throwing = throwing;
                      settings.sounds = sounds;
                      settings.multiscreen = multiscreen;
                      settings.scaling = scaling;
                      settings.opacity = opacity;
                      settings.interactiveWindows = interactiveWindows.text
                          .split('/')
                          .where((s) => s.trim().isNotEmpty)
                          .toList();
                      widget.app.environment.refreshCache();
                      AppUiState.instance.closePanels();
                    },
                    child: const Text('OK'),
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

/// The statistics panel (port of DebugWindow).
class StatsPanel extends StatelessWidget {
  final ShimejiApp app;
  const StatsPanel({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final mascots = app.manager.mascots;
    return Align(
      alignment: Alignment.topLeft,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(12),
        width: 380,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: const Color(0xFF9A9A9A)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Statistics',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  iconSize: 16,
                  onPressed: () => AppUiState.instance.closePanels(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            if (mascots.isEmpty) const Text('No shimeji'),
            for (final mascot in mascots)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${mascot.imageSet} #${mascot.id}: '
                  'anchor=(${mascot.anchor.x}, ${mascot.anchor.y}) '
                  'behavior=${_behaviorName(mascot)}',
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            const Divider(),
            Text(
              'workArea: ${app.environment.getWorkAreaAt(_firstAnchor(mascots)).toRect()}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }

  String _behaviorName(Mascot mascot) {
    final behavior = mascot.behavior;
    try {
      final name = (behavior as dynamic).name;
      return name?.toString() ?? '?';
    } catch (_) {
      return '?';
    }
  }

  dynamic _firstAnchor(Iterable<Mascot> mascots) =>
      mascots.isEmpty ? null : mascots.first.anchor;
}
