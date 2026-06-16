import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_state.dart';

/// Default manifest URL served by the `jirip/release-publisher` GitHub Pages
/// site. Apps that publish through a different host can pass `manifestUrl`.
const String kDefaultManifestUrl =
    'https://jirip.github.io/release-publisher/releases.json';

/// Pulls a release manifest from a public URL, compares the latest entry
/// against the running app's version, and downloads + hands off the APK to
/// the system installer.
///
/// Dismissals are session-only — they live only in the current process and
/// clear on the next app launch.
class Updater extends ChangeNotifier {
  /// `apps[appKey]` is the entry consulted in the manifest. Must match the
  /// key the source repo passes to release-publisher's dispatch action.
  final String appKey;
  final String manifestUrl;

  /// Minimum interval between automatic checks. Manual `force: true` calls
  /// bypass this.
  final Duration coolOff;

  Updater({
    required this.appKey,
    this.manifestUrl = kDefaultManifestUrl,
    this.coolOff = const Duration(minutes: 30),
  });

  UpdateState _state = const UpdateIdle();
  UpdateState get state => _state;

  final Set<String> _dismissedVersions = {};

  DateTime _lastNetworkCheck = DateTime.fromMillisecondsSinceEpoch(0);
  String? _currentVersion;

  /// `true` when an update is available (and not dismissed this session),
  /// currently downloading, or sitting on disk waiting to be installed.
  /// [UpdateError] stays out because transient network failures are better
  /// surfaced inside a Settings row than on a global banner.
  bool get shouldShowBanner {
    final dismissible = _dismissibleVersion;
    if (dismissible != null) return !_dismissedVersions.contains(dismissible);
    return _state is UpdateDownloading;
  }

  /// Suppress the banner for the current process. The user can still open
  /// Settings and explicitly install the same version.
  void dismissCurrent() {
    final dismissible = _dismissibleVersion;
    if (dismissible == null) return;
    _dismissedVersions.add(dismissible);
    notifyListeners();
  }

  String? get _dismissibleVersion => switch (_state) {
    UpdateAvailable(:final version) => version,
    UpdateReadyToInstall(:final version) => version,
    _ => null,
  };

  Future<String> currentVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    final info = await PackageInfo.fromPlatform();
    _currentVersion = info.version;
    return _currentVersion!;
  }

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> checkForUpdate({bool force = false}) async {
    if (!isSupported) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastNetworkCheck) < coolOff &&
        _state is! UpdateIdle &&
        _state is! UpdateError) {
      return;
    }
    _lastNetworkCheck = now;
    _set(const UpdateChecking());
    try {
      final response = await http.get(Uri.parse(manifestUrl));
      if (response.statusCode != HttpStatus.ok) {
        _set(UpdateError('Manifest HTTP ${response.statusCode}'));
        return;
      }
      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final apps = manifest['apps'] as Map<String, dynamic>?;
      final app = apps?[appKey] as Map<String, dynamic>?;
      final releases = app?['releases'] as List?;
      if (releases == null || releases.isEmpty) {
        _set(const UpdateUpToDate());
        return;
      }
      final latest = releases.first as Map<String, dynamic>;
      final latestVersion = latest['version'] as String? ?? '';
      final notes = latest['notes'] as String?;
      final assets = (latest['assets'] as List?) ?? const [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
        orElse: () => const <String, dynamic>{},
      );
      if (apkAsset.isEmpty) {
        _set(const UpdateUpToDate());
        return;
      }
      final url = apkAsset['url'] as String;
      final current = await currentVersion();
      if (_compareVersions(latestVersion, current) > 0) {
        final cached = await _apkFileFor(latestVersion);
        if (cached.existsSync() && cached.lengthSync() > 0) {
          _set(
            UpdateReadyToInstall(
              version: latestVersion,
              apkPath: cached.path,
              notes: notes,
            ),
          );
        } else {
          _set(
            UpdateAvailable(
              version: latestVersion,
              assetUrl: url,
              notes: notes,
            ),
          );
        }
      } else {
        _set(const UpdateUpToDate());
      }
    } catch (e) {
      _set(UpdateError(e.toString()));
    }
  }

  Future<void> downloadAndInstall(UpdateAvailable available) async {
    if (!isSupported) {
      _set(const UpdateError('Updater not available on this platform'));
      return;
    }
    final apkFile = await _apkFileFor(available.version);

    if (apkFile.existsSync() && apkFile.lengthSync() > 0) {
      await _launchInstallerFor(
        available.version,
        apkFile.path,
        available.notes,
      );
      return;
    }

    _set(UpdateDownloading(version: available.version, progress: 0));
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(available.assetUrl));
      final response = await client.send(request);
      if (response.statusCode != HttpStatus.ok) {
        _set(UpdateError('Download HTTP ${response.statusCode}'));
        return;
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = apkFile.openWrite();
      await response.stream.listen((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _set(
            UpdateDownloading(
              version: available.version,
              progress: received / total,
            ),
          );
        }
      }).asFuture<void>();
      await sink.close();

      await _launchInstallerFor(
        available.version,
        apkFile.path,
        available.notes,
      );
    } catch (e) {
      _set(UpdateError(e.toString()));
    }
  }

  /// Re-open the system installer for an already-downloaded APK.
  Future<void> launchInstaller(UpdateReadyToInstall ready) async {
    if (!isSupported) return;
    await _launchInstallerFor(ready.version, ready.apkPath, ready.notes);
  }

  Future<File> _apkFileFor(String version) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/jirip_app_updates/$appKey-$version.apk');
    await file.parent.create(recursive: true);
    return file;
  }

  Future<void> _launchInstallerFor(
    String version,
    String apkPath,
    String? notes,
  ) async {
    final result = await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      _set(UpdateError('Install handoff: ${result.message}'));
      return;
    }
    _set(
      UpdateReadyToInstall(version: version, apkPath: apkPath, notes: notes),
    );
  }

  void _set(UpdateState next) {
    _state = next;
    notifyListeners();
  }
}

int _compareVersions(String a, String b) {
  final pa = _semverParts(a);
  final pb = _semverParts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final av = i < pa.length ? pa[i] : 0;
    final bv = i < pb.length ? pb[i] : 0;
    if (av != bv) return av.compareTo(bv);
  }
  return 0;
}

List<int> _semverParts(String v) {
  return v
      .split(RegExp(r'[.+-]'))
      .where((p) => p.isNotEmpty)
      .map(int.tryParse)
      .whereType<int>()
      .toList();
}
