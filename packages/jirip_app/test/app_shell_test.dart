import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jirip_app/jirip_app.dart';

void main() {
  group('AppShell', () {
    testWidgets('renders initial tab body and switches on destination tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(
            tabs: [
              AppShellTab(
                label: 'One',
                icon: Icons.looks_one,
                body: Text('body-one'),
              ),
              AppShellTab(
                label: 'Two',
                icon: Icons.looks_two,
                body: Text('body-two'),
              ),
            ],
          ),
        ),
      );

      expect(find.text('body-one'), findsOneWidget);
      // IndexedStack only paints the active child.
      expect(find.text('body-two'), findsNothing);

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
      expect(find.text('body-two'), findsOneWidget);
    });

    testWidgets('preserves tab state across switches', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(
            tabs: [
              AppShellTab(
                label: 'Counter',
                icon: Icons.add,
                body: _Counter(key: ValueKey('counter')),
              ),
              AppShellTab(
                label: 'Other',
                icon: Icons.circle,
                body: Text('other'),
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('+'));
      await tester.tap(find.text('+'));
      await tester.pump();
      expect(find.text('count:2'), findsOneWidget);

      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Counter'));
      await tester.pumpAndSettle();

      expect(find.text('count:2'), findsOneWidget);
    });

    testWidgets('showAppBar renders the default app-name AppBar', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppShell(
            showAppBar: true,
            tabs: [
              AppShellTab(label: 'Alpha', icon: Icons.abc, body: SizedBox()),
              AppShellTab(label: 'Beta', icon: Icons.abc, body: SizedBox()),
            ],
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
      // Tab label is NOT used as the title — the default header shows the
      // app name + version (from PackageInfo) instead.
      expect(find.widgetWithText(AppBar, 'Alpha'), findsNothing);
      expect(find.widgetWithText(AppBar, 'Beta'), findsNothing);
    });

    testWidgets('custom appBar overrides the default app-name header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            showAppBar: true, // ignored when appBar is supplied
            appBar: AppBar(title: const Text('Custom')),
            tabs: const [
              AppShellTab(label: 'One', icon: Icons.abc, body: SizedBox()),
              AppShellTab(label: 'Two', icon: Icons.abc, body: SizedBox()),
            ],
          ),
        ),
      );

      expect(find.widgetWithText(AppBar, 'Custom'), findsOneWidget);
    });

    testWidgets('bannerAboveBody renders above the tab body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            bannerAboveBody: Container(
              key: const ValueKey('banner'),
              height: 24,
              color: const Color(0xFFAABBCC),
            ),
            tabs: const [
              AppShellTab(
                label: 'One',
                icon: Icons.looks_one,
                body: Text('body'),
              ),
              AppShellTab(
                label: 'Two',
                icon: Icons.looks_two,
                body: SizedBox(),
              ),
            ],
          ),
        ),
      );

      final bannerTop = tester
          .getTopLeft(find.byKey(const ValueKey('banner')))
          .dy;
      final bodyTop = tester.getTopLeft(find.text('body')).dy;
      expect(bannerTop, lessThan(bodyTop));
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _n = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('count:$_n'),
        TextButton(
          onPressed: () => setState(() => _n++),
          child: const Text('+'),
        ),
      ],
    );
  }
}
