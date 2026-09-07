/// Entry point for the Flutter-rendered context menu window ("flutter"
/// renderer mode).
///
/// Instead of a native Win32 popup menu, the menu is its own borderless
/// top-level window hosting a dedicated Flutter engine. The main engine
/// sends the fully localized entry tree; this window lays it out, reports
/// its desired size back so the native side can place and clamp it against
/// the monitor work area, and returns the chosen stable item id.
///
/// Submenus expand in place as an additional column (the window grows to
/// the right) rather than in nested popup windows, keeping one engine per
/// menu. Dismissal happens natively when the window loses activation, or
/// here on Escape.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderProxyBox, RenderView;
import 'package:flutter/services.dart';

class FlutterMenuEntry {
  const FlutterMenuEntry.label(this.label, this.id, {this.checked = false})
      : separator = false,
        children = null;

  const FlutterMenuEntry.separator()
      : label = null,
        id = '',
        checked = false,
        separator = true,
        children = null;

  const FlutterMenuEntry.submenu(this.label, this.children, {required this.id})
      : checked = false,
        separator = false;

  final String? label;
  final String id;
  final bool checked;
  final bool separator;
  final List<FlutterMenuEntry>? children;

  bool get hasChildren => children != null && children!.isNotEmpty;
}

Future<void> runContextMenuWindowApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ContextMenuWindowController();
  await controller.start();
  runApp(ContextMenuWindowRoot(controller: controller));
}

class ContextMenuWindowController {
  ContextMenuWindowController();

  static const MethodChannel _channel = MethodChannel('shimeji/context_menu');

  /// null = nothing to show (the native side keeps the window hidden).
  final ValueNotifier<List<FlutterMenuEntry>?> entries =
      ValueNotifier<List<FlutterMenuEntry>?>(null);

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'show') {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        final rawItems = args?['items'];
        entries.value = rawItems is List
            ? rawItems.map(_parseEntry).whereType<FlutterMenuEntry>().toList()
            : null;
      }
      return null;
    });
    // Tell the native side this engine is listening; it (re)sends the
    // entries of a menu that opened while the engine was still booting.
    try {
      await _channel.invokeMethod('ready');
    } on PlatformException {
      // The window may already be gone; nothing else to do.
    }
  }

  static FlutterMenuEntry? _parseEntry(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    if (map['separator'] == true) return const FlutterMenuEntry.separator();
    final label = map['label'] as String?;
    final id = (map['id'] as String?) ?? '';
    final checked = map['checked'] == true;
    final children = map['children'];
    if (children is List) {
      final parsed = children
          .map(_parseEntry)
          .whereType<FlutterMenuEntry>()
          .toList(growable: false);
      return FlutterMenuEntry.submenu(label ?? '', parsed, id: id);
    }
    return FlutterMenuEntry.label(label ?? '', id, checked: checked);
  }

  /// Sends the chosen stable id ('' = dismissed) and clears the menu.
  void select(String id) {
    entries.value = null;
    _channel.invokeMethod('selected', {'id': id}).catchError((_) {});
  }

  /// Reports the laid-out content size (logical) together with the device
  /// pixel ratio the frame was laid out at. The native side sizes the
  /// window with exactly that ratio, so window pixels map 1:1 onto what
  /// the engine rendered -- regardless of which monitor the window idled
  /// on before, or whether its metrics were still settling when the menu
  /// content first arrived.
  void reportSize(Size logicalSize, double devicePixelRatio) {
    _channel.invokeMethod('setMenuSize', {
      'w': logicalSize.width,
      'h': logicalSize.height,
      'dpr': devicePixelRatio,
    }).catchError((_) {});
  }
}

class ContextMenuWindowRoot extends StatefulWidget {
  const ContextMenuWindowRoot({super.key, required this.controller});

  final ContextMenuWindowController controller;

  @override
  State<ContextMenuWindowRoot> createState() => _ContextMenuWindowRootState();
}

class _ContextMenuWindowRootState extends State<ContextMenuWindowRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // The window was moved/resized natively and the view's scale changed
    // (e.g. the freshly shown window still carried the DPI of its previous
    // position): lay out again at the settled device pixel ratio and
    // re-report the menu size so the native side re-fits the window.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape):
            () => controller.select(''),
      },
      child: Focus(
        autofocus: true,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: const Color(0xFFF6F6F6),
            child: ValueListenableBuilder<List<FlutterMenuEntry>?>(
              valueListenable: controller.entries,
              builder: (context, entries, _) {
                if (entries == null || entries.isEmpty) {
                  return const SizedBox.expand();
                }
                // Align loosens the incoming tight window constraints so the
                // panel can shrink-wrap to its content; the reporter then
                // measures the content, which the native side uses to size
                // the window.
                return Align(
                  alignment: Alignment.topLeft,
                  child: _MenuSizeReporter(
                    controller: controller,
                    child: _MenuPanel(controller: controller, entries: entries),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports the laid-out menu size to the native side after every layout in
/// which it changed, so the window can be resized and re-clamped (submenu
/// columns grow the window to the right).
class _MenuSizeReporter extends SingleChildRenderObjectWidget {
  const _MenuSizeReporter({required this.controller, required super.child});

  final ContextMenuWindowController controller;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMenuSizeReporter(controller);
  }
}

class _RenderMenuSizeReporter extends RenderProxyBox {
  _RenderMenuSizeReporter(this.controller);

  final ContextMenuWindowController controller;
  Size _lastReportedSize = Size.zero;
  double _lastReportedDpr = 0;

  /// The device pixel ratio the current frame renders at (this view's own
  /// scale, read from the render tree root at layout time).
  double get _viewDevicePixelRatio {
    RenderObject? node = parent;
    while (node != null) {
      if (node is RenderView) {
        return node.configuration.devicePixelRatio;
      }
      node = node.parent;
    }
    return 1.0;
  }

  @override
  void performLayout() {
    // Lay the menu out UNCONSTRAINED: once the window has shrunk to the
    // menu, the incoming max constraints equal the window size and would
    // clamp a submenu column expansion (the row could never grow beyond
    // the current window, so the window could never widen). The natural
    // size may overflow the window for one frame until the native side
    // applies the reported size.
    if (child != null) {
      child!.layout(const BoxConstraints(), parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.smallest;
    }
    final laidOutSize = size;
    final dpr = _viewDevicePixelRatio;
    if (laidOutSize.width > 0 &&
        laidOutSize.height > 0 &&
        (laidOutSize != _lastReportedSize || dpr != _lastReportedDpr)) {
      _lastReportedSize = laidOutSize;
      _lastReportedDpr = dpr;
      // Report outside layout: the channel call must never re-enter layout.
      scheduleMicrotask(() => controller.reportSize(laidOutSize, dpr));
    }
  }
}

/// The menu panel: a row of columns. Column 0 holds the top-level entries;
/// hovering an entry with children appends the submenu as column 1.
class _MenuPanel extends StatefulWidget {
  const _MenuPanel({required this.controller, required this.entries});

  final ContextMenuWindowController controller;
  final List<FlutterMenuEntry> entries;

  @override
  State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  int? _openSubmenu;

  @override
  Widget build(BuildContext context) {
    final columns = <Widget>[
      _MenuColumn(
        entries: widget.entries,
        onHoverParent: (index) {
          if (_openSubmenu != index) setState(() => _openSubmenu = index);
        },
        onHoverPlainItem: () {
          if (_openSubmenu != null) setState(() => _openSubmenu = null);
        },
        onSelect: widget.controller.select,
      ),
    ];
    final open = _openSubmenu;
    if (open != null && open < widget.entries.length) {
      final children = widget.entries[open].children;
      if (children != null && children.isNotEmpty) {
        columns.add(const VerticalDivider(
            width: 1, thickness: 1, color: Color(0xFFE4E4E4)));
        columns.add(_MenuColumn(
          entries: children,
          onHoverParent: (_) {},
          onHoverPlainItem: () {},
          onSelect: widget.controller.select,
        ));
      }
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: columns,
    );
  }
}

class _MenuColumn extends StatelessWidget {
  const _MenuColumn({
    required this.entries,
    required this.onHoverParent,
    required this.onHoverPlainItem,
    required this.onSelect,
  });

  final List<FlutterMenuEntry> entries;
  final ValueChanged<int> onHoverParent;
  final VoidCallback onHoverPlainItem;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++)
              _MenuItem(
                entry: entries[i],
                onHover: () {
                  if (entries[i].hasChildren) {
                    onHoverParent(i);
                  } else if (!entries[i].separator) {
                    onHoverPlainItem();
                  }
                },
                onSelect: onSelect,
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.entry,
    required this.onHover,
    required this.onSelect,
  });

  final FlutterMenuEntry entry;
  final VoidCallback onHover;
  final ValueChanged<String> onSelect;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    if (entry.separator) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 3, horizontal: 10),
        child: SizedBox(height: 1, child: ColoredBox(color: Color(0xFFE4E4E4))),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelect(entry.id),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFE8E8E8) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: entry.checked
                    ? const Icon(Icons.check, size: 16, color: Color(0xFF3B3B3B))
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'Segoe UI',
                    color: Color(0xFF1B1B1B),
                  ),
                ),
              ),
              if (entry.hasChildren) ...[
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right,
                    size: 16, color: Color(0xFF5F5F5F)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
