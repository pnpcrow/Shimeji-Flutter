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

  // Screen geometry of the current menu, in PHYSICAL pixels (sent by the
  // native side with 'show'); used to decide the submenu direction.
  int anchorX = 0;
  int workLeft = 0;
  int workRight = 0;
  bool get hasWorkArea => workRight > workLeft;

  /// The device pixel ratio of the last size report (reporter feedback).
  double lastDpr = 0;

  /// Increments on every 'show'; the size reporter re-reports once per
  /// epoch even when the content lays out to an identical size.
  int showEpoch = 0;

  /// Width of the main column alone (logical), tracked from the collapsed
  /// reports; lets the window keep the main column under the cursor when
  /// the submenu expands to the left.
  double mainColumnWidth = 0;

  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'show') {
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        final rawItems = args?['items'];
        anchorX = ((args?['anchorX'] as num?) ?? 0).toInt();
        workLeft = ((args?['workLeft'] as num?) ?? 0).toInt();
        workRight = ((args?['workRight'] as num?) ?? 0).toInt();
        // Bumped per open: re-showing the SAME mascot produces an
        // identical entry tree, which would lay out to the exact same size
        // and never send a new size report -- the window would stay
        // work-area sized. The epoch forces one report per open.
        showEpoch++;
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
  ///
  /// [submenuOpen]/[expandLeft] describe the layout: when the submenu
  /// expands to the left, [originOffsetX] shifts the window origin left by
  /// the submenu's share of the width so the main column stays under the
  /// cursor.
  void reportSize(Size logicalSize, double devicePixelRatio,
      {required bool submenuOpen, required bool expandLeft}) {
    lastDpr = devicePixelRatio;
    var originOffset = 0.0;
    if (!submenuOpen) {
      mainColumnWidth = logicalSize.width;
    } else if (expandLeft && mainColumnWidth > 0) {
      originOffset = mainColumnWidth - logicalSize.width;
    }
    _channel.invokeMethod('setMenuSize', {
      'w': logicalSize.width,
      'h': logicalSize.height,
      'dpr': devicePixelRatio,
      'originOffsetX': originOffset,
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
          // No window-wide background: the window briefly spans the whole
          // work area while the menu measures itself, and anything painted
          // here would flash across the entire screen. The menu panel
          // paints its own background.
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
                child: _MenuPanel(controller: controller, entries: entries),
              );
            },
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
  const _MenuSizeReporter({
    required this.controller,
    required this.submenuOpen,
    required this.expandLeft,
    required this.epoch,
    required super.child,
  });

  final ContextMenuWindowController controller;
  final bool submenuOpen;
  final bool expandLeft;
  final int epoch;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMenuSizeReporter(
        controller, submenuOpen, expandLeft, epoch);
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderMenuSizeReporter renderObject) {
    renderObject
      ..controller = controller
      ..submenuOpen = submenuOpen
      ..expandLeft = expandLeft
      ..epoch = epoch;
  }
}

class _RenderMenuSizeReporter extends RenderProxyBox {
  _RenderMenuSizeReporter(
      this.controller, this.submenuOpen, this.expandLeft, int epoch)
      : _epoch = epoch;

  ContextMenuWindowController controller;
  bool submenuOpen;
  bool expandLeft;
  Size _lastReportedSize = Size.zero;
  double _lastReportedDpr = 0;
  int _lastReportedEpoch = -1;

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

  int get epoch => _epoch;

  set epoch(int value) {
    if (_epoch != value) {
      _epoch = value;
      // A new open must produce a report even when the identical content
      // would otherwise lay out to a no-op.
      markNeedsLayout();
    }
  }

  int _epoch;

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
        (laidOutSize != _lastReportedSize ||
            dpr != _lastReportedDpr ||
            _epoch != _lastReportedEpoch)) {
      _lastReportedSize = laidOutSize;
      _lastReportedDpr = dpr;
      _lastReportedEpoch = _epoch;
      // Report outside layout: the channel call must never re-enter layout.
      final submenuOpen = this.submenuOpen;
      final expandLeft = this.expandLeft;
      scheduleMicrotask(() =>
          controller.reportSize(laidOutSize, dpr,
              submenuOpen: submenuOpen, expandLeft: expandLeft));
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

class _MenuPanelState extends State<_MenuPanel>
    with SingleTickerProviderStateMixin {
  int? _openSubmenu;

  late final AnimationController _openController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );

  /// One-shot settle pass shortly after the menu opened. The open
  /// animation's ticker drives frames while it runs; this timer forces one
  /// more layout/report afterwards so the window size converges even if an
  /// early report raced the resize -- no user input needed.
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _openController.forward();
    _settleTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _openController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entries, oldWidget.entries)) {
      // The menu re-opened while the panel stayed mounted (native-side
      // dismissal keeps the old tree): replay the open animation.
      _openController.forward(from: 0);
    }
  }

  /// Whether the open submenu column should be laid out to the LEFT of the
  /// main column: near the right edge of the work area there is no room to
  /// expand rightward without the window being clamped sideways.
  bool get _expandLeft {
    final controller = widget.controller;
    final dpr = controller.lastDpr;
    if (!controller.hasWorkArea || dpr <= 0) return false;
    final spaceRightLogical = (controller.workRight - controller.anchorX) / dpr;
    // The submenu column is roughly as wide as the main column.
    final needed = controller.mainColumnWidth * 2.2;
    return spaceRightLogical < needed;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final expandLeft = _openSubmenu != null && _expandLeft;
    final mainColumn = _MenuColumn(
      entries: widget.entries,
      onHoverParent: (index) {
        if (_openSubmenu != index) setState(() => _openSubmenu = index);
      },
      onHoverPlainItem: () {
        if (_openSubmenu != null) setState(() => _openSubmenu = null);
      },
      onSelect: controller.select,
    );

    Widget panel = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (expandLeft) ..._submenuColumns(),
        mainColumn,
        if (!expandLeft) ..._submenuColumns(),
      ],
    );

    // The panel paints its own surface: the window itself must stay fully
    // transparent outside the menu (it spans the work area while the menu
    // measures itself).
    panel = DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF6F6F6)),
      child: FadeTransition(
        opacity: CurvedAnimation(
            parent: _openController, curve: Curves.easeOutCubic),
        child: panel,
      ),
    );

    return _MenuSizeReporter(
      controller: controller,
      submenuOpen: _openSubmenu != null,
      expandLeft: expandLeft,
      epoch: controller.showEpoch,
      child: panel,
    );
  }

  List<Widget> _submenuColumns() {
    final open = _openSubmenu;
    if (open == null || open >= widget.entries.length) return const [];
    final children = widget.entries[open].children;
    if (children == null || children.isEmpty) return const [];
    return [
      const VerticalDivider(
          width: 1, thickness: 1, color: Color(0xFFE4E4E4)),
      _MenuColumn(
        entries: children,
        onHoverParent: (_) {},
        onHoverPlainItem: () {},
        onSelect: widget.controller.select,
      ),
    ];
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
