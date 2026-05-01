import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/platform/lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LifecycleManager — initialization & disposal', () {
    test('initialize sets observer and is idempotent', () {
      final m = LifecycleManager();
      m.initialize();
      m.initialize(); // Second call logs a warning but doesn't throw.
      m.dispose();
    });

    test('dispose without initialize is a no-op', () {
      final m = LifecycleManager();
      m.dispose();
    });
  });

  group('LifecycleManager — state queries', () {
    test('currentState is null before any lifecycle change', () {
      final m = LifecycleManager();
      expect(m.currentState, isNull);
      expect(m.isInForeground, isFalse);
      expect(m.isInBackground, isFalse);
    });
  });

  group('LifecycleManager — didChangeAppLifecycleState dispatches', () {
    test('records state and updates foreground/background flags', () {
      final m = LifecycleManager();

      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(m.currentState, AppLifecycleState.resumed);
      expect(m.isInForeground, isTrue);
      expect(m.isInBackground, isFalse);

      m.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(m.currentState, AppLifecycleState.inactive);
      expect(m.isInForeground, isFalse);
      expect(m.isInBackground, isFalse);

      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(m.isInBackground, isTrue);

      m.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(m.isInBackground, isTrue);
    });

    test('lifecycle change listener fires for every state', () {
      final m = LifecycleManager();
      final received = <AppLifecycleState>[];
      m.setLifecycleChangeListener(received.add);

      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      m.didChangeAppLifecycleState(AppLifecycleState.inactive);
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      m.didChangeAppLifecycleState(AppLifecycleState.detached);

      expect(received, [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]);
    });

    test('foreground/background transitions trigger transition handlers', () {
      final m = LifecycleManager();
      // paused → resumed: foreground transition
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      m.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(m.isInForeground, isTrue);

      // inactive → paused: background transition
      m.didChangeAppLifecycleState(AppLifecycleState.inactive);
      m.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(m.isInBackground, isTrue);
    });
  });

  group('LifecycleManager — pub/sub helpers', () {
    test('onForeground / onBackground / onInactive / onDetached return tokens',
        () async {
      final m = LifecycleManager();
      final t1 = await m.onForeground(() {});
      final t2 = await m.onBackground(() {});
      final t3 = await m.onInactive(() {});
      final t4 = await m.onDetached(() {});
      final t5 = await m.onLifecycleChange((_) {});

      expect(t1, isA<String>());
      expect(t2, isA<String>());
      expect(t3, isA<String>());
      expect(t4, isA<String>());
      expect(t5, isA<String>());

      // Cleanup — exercise unsubscribe.
      m.unsubscribe(t1);
      m.unsubscribe(t2);
      m.unsubscribe(t3);
      m.unsubscribe(t4);
      m.unsubscribe(t5);
    });

    test('onForeground callback fires when state becomes resumed', () async {
      final m = LifecycleManager();
      var calls = 0;
      final token = await m.onForeground(() => calls++);
      addTearDown(() => m.unsubscribe(token));

      m.didChangeAppLifecycleState(AppLifecycleState.resumed);

      // Allow async event delivery to settle.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(calls, greaterThanOrEqualTo(1));
    });

    test('onLifecycleChange callback receives the lifecycle state', () async {
      final m = LifecycleManager();
      AppLifecycleState? received;
      final token = await m.onLifecycleChange((state) => received = state);
      addTearDown(() => m.unsubscribe(token));

      m.didChangeAppLifecycleState(AppLifecycleState.paused);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, AppLifecycleState.paused);
    });
  });
}
