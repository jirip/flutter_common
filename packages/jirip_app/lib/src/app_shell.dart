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
/// Renders a [Scaffold] with a Material 3 [NavigationBar] and an
/// [IndexedStack] body so each tab keeps its widget tree (scroll position,
/// in-progress state) across switches.
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
