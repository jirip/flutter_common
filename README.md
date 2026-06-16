# flutter_common

Shared infrastructure for Jirip's Flutter Android side-projects (voicer,
darts-score, pdf2jpg, kombucha-calculator, …).

The goal: stop copy-pasting the same in-app updater, the same release
workflow, and the same release-publisher dispatch step into every repo.

## What lives here

| Path | Purpose |
| --- | --- |
| `packages/jirip_app/` | Dart package: in-app self-updater (`Updater`), global update banner (`UpdateBanner`), bottom-tab scaffold (`AppShell`). |
| `actions/flutter-android-release/` | (Planned.) Composite GitHub Action that wraps the standard build → sign → release → dispatch steps. |
| `AGENTS.md` | Terse usage rules for AI coding agents (what to import, how to wire it). |

## Status

| Component | Version | First consumer |
| --- | --- | --- |
| `jirip_app` Dart package | 0.4.0 | voicer |
| `flutter-android-release` action | not yet built | — |

## Quick start: add the updater to a new Flutter Android app

1. **Depend on the package** in your app's `pubspec.yaml`:

    ```yaml
    dependencies:
      jirip_app:
        git:
          url: https://github.com/jirip/flutter_common.git
          ref: jirip_app-v0.1.0
          path: packages/jirip_app
    ```

2. **Construct `Updater` once** at app startup with your app's key. The
   key must match the `app:` value the source repo sends to
   release-publisher's dispatch action.

    ```dart
    final updater = Updater(appKey: 'myapp');
    unawaited(updater.checkForUpdate());
    ```

3. **Add the banner** above your `Scaffold`'s body. The style is supplied
   by the consumer so the banner colour matches the app's theme.

    ```dart
    Scaffold(
      body: Column(
        children: [
          UpdateBanner(
            updater: updater,
            style: const UpdateBannerStyle(
              background: Color(0xFFE63946),
              foreground: Colors.white,
            ),
          ),
          Expanded(child: yourTabs[index]),
        ],
      ),
    )
    ```

4. **Drive it from a Settings row** if you want a "Check for updates"
   button that's always visible. Pattern-match `updater.state` against
   the sealed `UpdateState` family.

## How the updater talks to release-publisher

The updater pulls a manifest from
<https://jirip.github.io/release-publisher/releases.json>, looks for
`apps[<appKey>]`, and compares the top entry's `version` against the
running app's `PackageInfo.version`. If a newer APK is published, the
banner offers to download and hand off to the system installer.

The cache stores the downloaded APK under
`getTemporaryDirectory()/jirip_app_updates/<appKey>-<version>.apk`. On
the next check the cache wins, so users who backed out of the Android
installer screen can press Install again without redownloading.

## Versioning policy

The `jirip_app` package is git-only, never published to pub.dev. Tag
releases as `jirip_app-vX.Y.Z`; bump the version field in
`packages/jirip_app/pubspec.yaml` and tag a matching commit. Consumers
pin via `ref:`.

## Repo

<https://github.com/jirip/flutter_common>
