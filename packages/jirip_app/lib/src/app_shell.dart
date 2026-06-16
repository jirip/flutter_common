import 'package:flutter/material.dart';

/// One tab in [AppShell].
class AppShellTab {
  /// Used as the [NavigationDestination] label and, when [AppShell.showAppBar]
  /// is `true`, as the AppBar title for this tab.
  final String label;

  /// Icon shown for the unselected state.
  final IconData icon;

  /// Icon shown when this tab is selected. Defaults to [icon] so callers can
  /// omit it for an unchanged look.
  final IconData? selectedIcon;

  /// Body widget for this tab. Kept alive across tab switches by the
  /// [IndexedStack] inside [AppShell].
  final Widget body;

  const AppShellTab({
    required this.label,
    required this.icon,
    required this.body,
    this.selectedIcon,
  });
}

/// Bottom-tab scaffold shared by Jirip's Flutter apps.
///
/// Renders a [Scaffold] with a Material 3 [NavigationBar] and an
/// [IndexedStack] body so each tab keeps its widget tree (scroll position,
/// in-progress state) across switches.
///
/// The host app controls cross-cutting chrome:
///   * Pass an [AppBar] via [appBar], or set [showAppBar] to let [AppShell]
///     build one with the current tab's [AppShellTab.label].
///   * Pass [bannerAboveBody] (e.g. `UpdateBanner`) to render content between
///     the AppBar and the body.
class AppShell extends StatefulWidget {
  final List<AppShellTab> tabs;

  /// Initial selected index. Defaults to `0`.
  final int initialIndex;

  /// Custom AppBar. Ignored when [showAppBar] is `true`.
  final PreferredSizeWidget? appBar;

  /// When `true` and [appBar] is null, [AppShell] renders an [AppBar] whose
  /// title is the current tab's label. Defaults to `false`.
  final bool showAppBar;

  /// Widget rendered between the AppBar (if any) and the tab body — typical
  /// use is an `UpdateBanner` so the banner sits above every tab.
  final Widget? bannerAboveBody;

  /// Notified with the new index whenever the user switches tabs.
  final ValueChanged<int>? onTabChanged;

  const AppShell({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.appBar,
    this.showAppBar = false,
    this.bannerAboveBody,
    this.onTabChanged,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex.clamp(0, widget.tabs.length - 1);

  void _select(int next) {
    if (next == _index) return;
    setState(() => _index = next);
    widget.onTabChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final current = tabs[_index];

    final PreferredSizeWidget? appBar =
        widget.appBar ??
        (widget.showAppBar ? AppBar(title: Text(current.label)) : null);

    final body = IndexedStack(
      index: _index,
      children: [for (final t in tabs) t.body],
    );

    final banner = widget.bannerAboveBody;
    return Scaffold(
      appBar: appBar,
      body: banner == null
          ? body
          : Column(
              children: [
                banner,
                Expanded(child: body),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon ?? t.icon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
