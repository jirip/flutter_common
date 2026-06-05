sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateAvailable extends UpdateState {
  final String version;
  final String assetUrl;
  final String? notes;
  const UpdateAvailable({
    required this.version,
    required this.assetUrl,
    this.notes,
  });
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateDownloading extends UpdateState {
  final String version;
  final double progress;
  const UpdateDownloading({required this.version, required this.progress});
}

/// The APK is on disk and the system installer has been launched at least
/// once. Tapping Install again should re-open the installer, not redownload.
class UpdateReadyToInstall extends UpdateState {
  final String version;
  final String apkPath;
  final String? notes;
  const UpdateReadyToInstall({
    required this.version,
    required this.apkPath,
    this.notes,
  });
}

class UpdateError extends UpdateState {
  final String message;
  const UpdateError(this.message);
}
