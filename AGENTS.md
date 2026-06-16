# AGENTS.md — flutter_common

Terse, deterministic instructions for AI coding agents working on
Jirip's Flutter Android side-projects. Read top-to-bottom.

## Rules

1. **Never copy `updater.dart` or `update_banner.dart` into a consuming
   repo.** Always depend on `jirip_app` via the `git` ref pattern in
   that app's `pubspec.yaml`. If you find a hand-rolled copy in a
   consumer, treat it as a regression and migrate to the package.

2. **One `appKey` per app, stable forever.** It is the dispatch payload
   sent to release-publisher and the key under `apps[]` in the
   manifest. Voicer's key is `voicer`. Darts is `darts-score`. PDF→JPG
   is `pdf2jpg`. Do not rename these.

3. **Pin to a tag**, never `ref: master`. Tags are
   `jirip_app-vX.Y.Z`. Bumping the version is a deliberate action: edit
   the consuming app's `pubspec.yaml`, run `flutter pub upgrade
   jirip_app`, run tests, commit.

4. **Banner style is host-supplied.** The widget does not consult the
   ambient `Theme` — pass an `UpdateBannerStyle` whose colours come
   from the consuming app's theme file.

5. **Sealed `UpdateState` is exhaustive.** Use Dart 3 switch
   expressions. Do not add a fallback `_` case.

## Adding the updater to a new app

```dart
import 'package:jirip_app/jirip_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final updater = Updater(appKey: '<your-app-key>');
  unawaited(updater.checkForUpdate());
  runApp(MyApp(updater: updater));
}
```

In your root shell:

```dart
Scaffold(
  body: Column(
    children: [
      UpdateBanner(updater: updater, style: AppTheme.bannerStyle),
      Expanded(child: currentTab),
    ],
  ),
)
```

In a settings screen, drive a row off `updater.state`:

```dart
switch (updater.state) {
  UpdateIdle()           => /* "Check for updates" */
  UpdateChecking()       => /* spinner */
  UpdateUpToDate()       => /* "You are up to date" */
  UpdateAvailable()      => /* "Update available — install" */
  UpdateReadyToInstall() => /* "Downloaded — tap to install" */
  UpdateDownloading()    => /* progress */
  UpdateError(:final message) => /* show message */
}
```

## Wiring the bottom-tab shell (`AppShell`)

`AppShell` is the shared bottom-navigation scaffold. It owns the
`NavigationBar` and an `IndexedStack` body so each tab keeps its state
across switches. The host app keeps full control of the AppBar and the
update banner.

```dart
Scaffold(
  // …or just return AppShell directly if you don't need an outer Scaffold.
)
AppShell(
  showAppBar: true, // optional — uses the current tab's label as title
  bannerAboveBody: UpdateBanner(updater: updater, style: AppTheme.bannerStyle),
  tabs: const [
    AppShellTab(
      label: 'Live',
      icon: Icons.mic_none,
      selectedIcon: Icons.mic,
      body: LiveScreen(),
    ),
    AppShellTab(
      label: 'Recordings',
      icon: Icons.fiber_manual_record_outlined,
      selectedIcon: Icons.fiber_manual_record,
      body: RecordingsScreen(),
    ),
  ],
)
```

Rules:

- **Always set `selectedIcon`** unless the unselected and selected glyphs
  are identical. Material 3 expects the visual hint.
- **Tab bodies are kept alive** via `IndexedStack`. Do not put expensive
  `initState` work inside a body that the user may not visit — it still
  runs on first mount, but it survives every switch after that.
- **Do not nest a second `Scaffold` inside an `AppShellTab.body`.** Use
  a plain widget (or a custom AppBar on the body if you really need a
  per-tab one — but prefer `AppShell.showAppBar`).
- **The banner slot is for one persistent widget**, typically
  `UpdateBanner`. If you need to show a snackbar/dialog, route it
  through the surrounding `Scaffold`/`Overlay`, not the shell.

## Bumping `jirip_app`

1. Edit `packages/jirip_app/pubspec.yaml` → `version:`.
2. `cd packages/jirip_app && flutter test`.
3. Commit, tag `jirip_app-vX.Y.Z`, push the tag.
4. In each consumer, bump the `ref:` in `pubspec.yaml` and run
   `flutter pub upgrade jirip_app`.

## Migration checklist (from hand-rolled `updater.dart`)

When migrating an existing app:

- [ ] Delete `lib/updater.dart` and `lib/widgets/update_banner.dart`
      from the consumer.
- [ ] Add `jirip_app` dep with the git/ref/path triple.
- [ ] Replace `Updater()` constructor with `Updater(appKey: '<key>')`.
- [ ] Add `UpdateBannerStyle` to the app's theme file.
- [ ] Wrap the root scaffold body with the banner.
- [ ] Run `flutter analyze` and `flutter test` — no findings.
- [ ] Build and install a debug APK. Confirm the banner appears when
      a newer version is mocked in `apps[<appKey>].releases[0]`.

## Out of scope (for now)

- iOS / web / desktop. The updater calls `Platform.isAndroid` and
  no-ops elsewhere. Don't add platform handling here.
- Pub.dev publishing. Stay git-only.
- Auto-update timing policy beyond the 30-minute cool-off. The host
  app schedules `checkForUpdate()`; the package doesn't.
