import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// One tab in [AppShell].
class AppShellTab {
  /// Used as the [NavigationDestination] label.
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
/// Renders a [Scaffold] with a custom bottom-nav bar and an [IndexedStack]
/// body so each tab keeps its widget tree (scroll position, in-progress
/// state) across switches.
///
/// The bar deliberately departs from the stock Material 3 [NavigationBar]:
/// no pill behind the selected icon, the selected icon scales up, the ripple
/// covers the entire tab slot, and the bar is a compact 70 dp tall. Toggle
/// the text labels per app with [showLabels].
///
/// AppBar choices:
///   * [appBar] — caller-supplied [PreferredSizeWidget]; used as-is.
///   * [showAppBar] — when `true` and [appBar] is null, renders the default
///     `<appName> v<version>` header pulled from [PackageInfo]. The version
///     is the clean semver (no build number).
///   * neither — no AppBar.
///
/// Colours come from the surrounding [Theme]; [AppShell] never paints its own.
class AppShell extends StatefulWidget {
  final List<AppShellTab> tabs;

  /// Initial selected index. Defaults to `0`.
  final int initialIndex;

  /// Custom AppBar. Takes precedence over [showAppBar].
  final PreferredSizeWidget? appBar;

  /// When `true` and [appBar] is null, [AppShell] renders an [AppBar] showing
  /// `<appName> v<version>` pulled from [PackageInfo]. Defaults to `false`.
  final bool showAppBar;

  /// Widget rendered between the AppBar (if any) and the tab body — typical
  /// use is an `UpdateBanner` so the banner sits above every tab.
  final Widget? bannerAboveBody;

  /// When `true`, each tab shows its [AppShellTab.label] under the icon.
  /// When `false`, the bar is icon-only. Defaults to `true`.
  final bool showLabels;

  /// Notified with the new index whenever the user switches tabs.
  final ValueChanged<int>? onTabChanged;

  const AppShell({
    super.key,
    required this.tabs,
    this.initialIndex = 0,
    this.appBar,
    this.showAppBar = false,
    this.bannerAboveBody,
    this.showLabels = true,
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

    final PreferredSizeWidget? appBar =
        widget.appBar ??
        (widget.showAppBar ? const _AppNameVersionAppBar() : null);

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
      bottomNavigationBar: _BottomNav(
        tabs: tabs,
        selectedIndex: _index,
        showLabels: widget.showLabels,
        onSelected: _select,
      ),
    );
  }
}

/// Custom bottom-nav bar — full-slot ripple, primary-tint selection,
/// icon scale-up on selection, optional text labels, 70 dp tall.
class _BottomNav extends StatelessWidget {
  static const double _height = 70;
  static const double _iconSize = 24;
  static const double _selectedIconSize = 28;
  static const double _labelFontSize = 11;

  final List<AppShellTab> tabs;
  final int selectedIndex;
  final bool showLabels;
  final ValueChanged<int> onSelected;

  const _BottomNav({
    required this.tabs,
    required this.selectedIndex,
    required this.showLabels,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _height,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _BottomNavItem(
                    tab: tabs[i],
                    selected: i == selectedIndex,
                    showLabel: showLabels,
                    iconSize: _iconSize,
                    selectedIconSize: _selectedIconSize,
                    labelFontSize: _labelFontSize,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final AppShellTab tab;
  final bool selected;
  final bool showLabel;
  final double iconSize;
  final double selectedIconSize;
  final double labelFontSize;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.tab,
    required this.selected,
    required this.showLabel,
    required this.iconSize,
    required this.selectedIconSize,
    required this.labelFontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final icon = selected ? (tab.selectedIcon ?? tab.icon) : tab.icon;
    final size = selected ? selectedIconSize : iconSize;

    return InkWell(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: size),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  color: color,
                  fontSize: labelFontSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Default AppBar used when `showAppBar: true` and no custom [AppBar] is
/// supplied. Title is `<appName> v<version>`, with the version rendered
/// smaller than the name. Values come from [PackageInfo].
class _AppNameVersionAppBar extends StatefulWidget
    implements PreferredSizeWidget {
  const _AppNameVersionAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<_AppNameVersionAppBar> createState() => _AppNameVersionAppBarState();
}

class _AppNameVersionAppBarState extends State<_AppNameVersionAppBar> {
  String? _appName;
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (!mounted) return;
      setState(() {
        _appName = info.appName;
        _version = info.version;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _appName ?? '';
    final version = _version;
    return AppBar(
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: name),
            if (version != null && version.isNotEmpty) ...[
              const TextSpan(text: '  '),
              TextSpan(
                text: 'v$version',
                style: TextStyle(
                  fontSize:
                      (DefaultTextStyle.of(context).style.fontSize ?? 16) * 0.7,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
