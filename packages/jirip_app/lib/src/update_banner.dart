import 'package:flutter/material.dart';

import 'update_state.dart';
import 'updater.dart';

/// Colour pair used to paint the [UpdateBanner]. Each consuming app
/// provides its own (typically pulled from its `Theme` extensions) so the
/// shared widget doesn't carry app-specific palettes.
class UpdateBannerStyle {
  final Color background;
  final Color foreground;
  const UpdateBannerStyle({
    required this.background,
    required this.foreground,
  });
}

/// Inline update banner. Renders at most one of:
///   * "Update available — Install / Dismiss"
///   * "Downloaded vX.Y — tap Install to finish — Install / Dismiss"
///   * "Downloading vX.Y… NN%" (with progress)
///
/// All other [UpdateState]s collapse to a zero-size widget so the consumer
/// can drop this above a [Scaffold]'s body without conditional layout.
class UpdateBanner extends StatefulWidget {
  final Updater updater;
  final UpdateBannerStyle style;
  const UpdateBanner({
    super.key,
    required this.updater,
    required this.style,
  });

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  @override
  void initState() {
    super.initState();
    widget.updater.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.updater.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.updater.shouldShowBanner) return const SizedBox.shrink();
    final state = widget.updater.state;

    final Widget content;
    switch (state) {
      case UpdateAvailable():
        content = _AvailableContent(
          updater: widget.updater,
          state: state,
          style: widget.style,
        );
      case UpdateDownloading():
        content = _DownloadingContent(state: state, style: widget.style);
      case UpdateReadyToInstall():
        content = _ReadyContent(
          updater: widget.updater,
          state: state,
          style: widget.style,
        );
      case UpdateIdle() ||
            UpdateChecking() ||
            UpdateUpToDate() ||
            UpdateError():
        return const SizedBox.shrink();
    }

    return Material(
      color: widget.style.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: widget.style.foreground),
            child: IconTheme.merge(
              data: IconThemeData(color: widget.style.foreground),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvailableContent extends StatelessWidget {
  final Updater updater;
  final UpdateAvailable state;
  final UpdateBannerStyle style;
  const _AvailableContent({
    required this.updater,
    required this.state,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.download_for_offline_outlined),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Update available: v${state.version}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () => updater.downloadAndInstall(state),
          style: TextButton.styleFrom(foregroundColor: style.foreground),
          child: const Text('Install'),
        ),
        TextButton(
          onPressed: updater.dismissCurrent,
          style: TextButton.styleFrom(foregroundColor: style.foreground),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

class _ReadyContent extends StatelessWidget {
  final Updater updater;
  final UpdateReadyToInstall state;
  final UpdateBannerStyle style;
  const _ReadyContent({
    required this.updater,
    required this.state,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Downloaded v${state.version} — tap Install to finish',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () => updater.launchInstaller(state),
          style: TextButton.styleFrom(foregroundColor: style.foreground),
          child: const Text('Install'),
        ),
        TextButton(
          onPressed: updater.dismissCurrent,
          style: TextButton.styleFrom(foregroundColor: style.foreground),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}

class _DownloadingContent extends StatelessWidget {
  final UpdateDownloading state;
  final UpdateBannerStyle style;
  const _DownloadingContent({required this.state, required this.style});

  @override
  Widget build(BuildContext context) {
    final percent = (state.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: style.foreground,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Downloading v${state.version}… $percent%'),
        ),
      ],
    );
  }
}
