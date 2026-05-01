import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/models/platform_messages.dart';
import 'package:flutter_mcp/src/config/mcp_config.dart';
import 'package:flutter_mcp/src/config/background_config.dart';
import 'package:flutter_mcp/src/config/notification_config.dart';

void main() {
  group('PlatformMessage subclasses', () {
    test('InitializeMessage method/arguments', () {
      final m = InitializeMessage(
        config: MCPConfig(appName: 'app', appVersion: '0.0.1'),
      );
      expect(m.method, 'initialize');
      expect(m.arguments, isNotNull);
      expect(m.arguments!['name'], 'config_placeholder');
    });

    test('StartBackgroundServiceMessage with and without config', () {
      const m1 = StartBackgroundServiceMessage();
      expect(m1.method, 'startBackgroundService');
      expect(m1.arguments, isNull);

      final m2 = StartBackgroundServiceMessage(
        config: BackgroundConfig(),
      );
      expect(m2.arguments, isNotNull);
      expect(m2.arguments!['type'], 'background_config_placeholder');
    });

    test('StopBackgroundServiceMessage', () {
      const m = StopBackgroundServiceMessage();
      expect(m.method, 'stopBackgroundService');
      expect(m.arguments, isNull);
    });

    test('ShowNotificationMessage with and without config', () {
      const m1 = ShowNotificationMessage(id: 'n1', title: 'T', body: 'B');
      expect(m1.method, 'showNotification');
      expect(m1.arguments, {'id': 'n1', 'title': 'T', 'body': 'B'});

      final m2 = ShowNotificationMessage(
        id: 'n2',
        title: 'T2',
        body: 'B2',
        config: NotificationConfig(),
      );
      expect(m2.arguments!['config'], isA<Map>());
    });

    test('CancelNotificationMessage', () {
      const m = CancelNotificationMessage(id: 'n1');
      expect(m.method, 'cancelNotification');
      expect(m.arguments, {'id': 'n1'});
    });

    test('ShowTrayIconMessage with all variants', () {
      const m1 = ShowTrayIconMessage(iconPath: '/p.png');
      expect(m1.method, 'showTrayIcon');
      expect(m1.arguments, {'iconPath': '/p.png'});

      const m2 = ShowTrayIconMessage(
        iconPath: '/p.png',
        tooltip: 'tip',
      );
      expect(m2.arguments, {'iconPath': '/p.png', 'tooltip': 'tip'});

      const m3 = ShowTrayIconMessage(
        iconPath: '/p.png',
        menu: [TrayMenuItem(id: 'a', label: 'A')],
      );
      expect((m3.arguments!['menu'] as List), hasLength(1));
    });

    test('HideTrayIconMessage', () {
      const m = HideTrayIconMessage();
      expect(m.method, 'hideTrayIcon');
      expect(m.arguments, isNull);
    });

    test('UpdateTrayMenuMessage', () {
      const m = UpdateTrayMenuMessage(
        menu: [TrayMenuItem(id: 'a', label: 'A')],
      );
      expect(m.method, 'updateTrayMenu');
      expect((m.arguments!['menu'] as List), hasLength(1));
    });

    test('ExecuteBackgroundTaskMessage', () {
      const m = ExecuteBackgroundTaskMessage(
        taskId: 't1',
        data: {'k': 'v'},
      );
      expect(m.method, 'executeBackgroundTask');
      expect(m.arguments, {'taskId': 't1', 'data': {'k': 'v'}});
    });

    test('RequestPermissionMessage with and without rationale', () {
      const m1 = RequestPermissionMessage(permission: 'notif');
      expect(m1.method, 'requestPermission');
      expect(m1.arguments, {'permission': 'notif'});

      const m2 = RequestPermissionMessage(
        permission: 'cam',
        rationale: 'why',
      );
      expect(m2.arguments, {'permission': 'cam', 'rationale': 'why'});
    });

    test('CheckPermissionMessage', () {
      const m = CheckPermissionMessage(permission: 'notif');
      expect(m.method, 'checkPermission');
      expect(m.arguments, {'permission': 'notif'});
    });

    test('Secure store / retrieve / delete', () {
      const s = SecureStoreMessage(key: 'k', value: 'v');
      expect(s.method, 'secureStore');
      expect(s.arguments, {'key': 'k', 'value': 'v'});

      const r = SecureRetrieveMessage(key: 'k');
      expect(r.method, 'secureRetrieve');
      expect(r.arguments, {'key': 'k'});

      const d = SecureDeleteMessage(key: 'k');
      expect(d.method, 'secureDelete');
      expect(d.arguments, {'key': 'k'});
    });

    test('GetSystemInfoMessage', () {
      const m = GetSystemInfoMessage();
      expect(m.method, 'getSystemInfo');
      expect(m.arguments, isNull);
    });

    test('LogEventMessage with and without parameters', () {
      const m1 = LogEventMessage(event: 'e');
      expect(m1.method, 'logEvent');
      expect(m1.arguments, {'event': 'e'});

      const m2 = LogEventMessage(event: 'e', parameters: {'k': 1});
      expect(m2.arguments, {'event': 'e', 'parameters': {'k': 1}});
    });

    test('PerformHealthCheckMessage with and without components', () {
      const m1 = PerformHealthCheckMessage();
      expect(m1.method, 'performHealthCheck');
      expect(m1.arguments, isNull);

      const m2 = PerformHealthCheckMessage(components: ['a', 'b']);
      expect(m2.arguments, {'components': ['a', 'b']});
    });
  });

  group('PlatformMessage.fromMethodCall', () {
    test('stopBackgroundService returns StopBackgroundServiceMessage', () {
      final m = PlatformMessage.fromMethodCall('stopBackgroundService', null);
      expect(m, isA<StopBackgroundServiceMessage>());
    });

    test('executeBackgroundTask returns ExecuteBackgroundTaskMessage', () {
      final m = PlatformMessage.fromMethodCall(
        'executeBackgroundTask',
        {'taskId': 't1', 'data': {'k': 'v'}},
      );
      expect(m, isA<ExecuteBackgroundTaskMessage>());
      final task = m as ExecuteBackgroundTaskMessage;
      expect(task.taskId, 't1');
      expect(task.data, {'k': 'v'});
    });

    test('unknown method returns null', () {
      expect(PlatformMessage.fromMethodCall('nothing', null), isNull);
    });
  });

  group('PlatformResponse hierarchy', () {
    test('SuccessResponse defaults', () {
      const r = SuccessResponse();
      expect(r.isSuccess, isTrue);
      expect(r.isError, isFalse);
      expect(r.toJson(), {'success': true});
    });

    test('SuccessResponse with data and message', () {
      const r = SuccessResponse(data: {'a': 1}, message: 'ok');
      final json = r.toJson();
      expect(json['success'], isTrue);
      expect(json['data'], {'a': 1});
      expect(json['message'], 'ok');
    });

    test('ErrorResponse', () {
      const r = ErrorResponse(code: 'E1', message: 'bad', details: 'why');
      expect(r.isSuccess, isFalse);
      expect(r.isError, isTrue);
      final json = r.toJson();
      expect(json['success'], isFalse);
      expect(json['error']['code'], 'E1');
      expect(json['error']['message'], 'bad');
      expect(json['error']['details'], 'why');
    });

    test('ErrorResponse without details', () {
      const r = ErrorResponse(code: 'E', message: 'm');
      expect(r.toJson()['error'].containsKey('details'), isFalse);
    });

    test('PermissionResponse with reason', () {
      const r = PermissionResponse(
        permission: 'notif',
        granted: false,
        reason: 'denied by user',
      );
      expect(r.isSuccess, isTrue);
      final json = r.toJson();
      expect(json['permission'], 'notif');
      expect(json['granted'], isFalse);
      expect(json['reason'], 'denied by user');
    });

    test('PermissionResponse without reason', () {
      const r = PermissionResponse(permission: 'p', granted: true);
      expect(r.toJson().containsKey('reason'), isFalse);
    });

    test('SystemInfoResponse', () {
      const r = SystemInfoResponse(
        platform: 'macos',
        version: '14.0',
        capabilities: {'tray': true},
      );
      expect(r.isSuccess, isTrue);
      final json = r.toJson();
      expect(json['platform'], 'macos');
      expect(json['version'], '14.0');
      expect(json['capabilities'], {'tray': true});
    });

    test('HealthCheckResponse', () {
      const r = HealthCheckResponse(
        status: 'healthy',
        components: {'db': 'ok'},
      );
      expect(r.isSuccess, isTrue);
      final json = r.toJson();
      expect(json['status'], 'healthy');
      expect(json['components'], {'db': 'ok'});
    });
  });

  group('PlatformResponse.fromPlatformResponse', () {
    test('null produces SuccessResponse with no data', () {
      final r = PlatformResponse.fromPlatformResponse(null);
      expect(r, isA<SuccessResponse>());
      expect(r.isSuccess, isTrue);
    });

    test('error envelope produces ErrorResponse', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'error': {'code': 'X', 'message': 'm', 'details': 'd'},
      });
      expect(r, isA<ErrorResponse>());
      final err = r as ErrorResponse;
      expect(err.code, 'X');
      expect(err.message, 'm');
      expect(err.details, 'd');
    });

    test('error envelope falls back to defaults when fields missing', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'error': <String, dynamic>{},
      });
      final err = r as ErrorResponse;
      expect(err.code, 'unknown');
      expect(err.message, 'Unknown error');
    });

    test('permission envelope produces PermissionResponse', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'permission': 'notif',
        'granted': true,
      });
      expect(r, isA<PermissionResponse>());
      final p = r as PermissionResponse;
      expect(p.permission, 'notif');
      expect(p.granted, isTrue);
    });

    test('platform envelope produces SystemInfoResponse', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'platform': 'macos',
        'version': '14.0',
        'capabilities': {'tray': true},
      });
      expect(r, isA<SystemInfoResponse>());
    });

    test('status+components envelope produces HealthCheckResponse', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'status': 'healthy',
        'components': <String, dynamic>{},
      });
      expect(r, isA<HealthCheckResponse>());
    });

    test('plain map without keys produces SuccessResponse with data', () {
      final r = PlatformResponse.fromPlatformResponse(<String, dynamic>{
        'arbitrary': 1,
      });
      expect(r, isA<SuccessResponse>());
      expect((r as SuccessResponse).data, {'arbitrary': 1});
    });

    test('non-map response wraps as SuccessResponse with data', () {
      final r = PlatformResponse.fromPlatformResponse('hello');
      expect(r, isA<SuccessResponse>());
      expect((r as SuccessResponse).data, 'hello');
    });
  });

  group('TrayMenuItem', () {
    test('default fields and isSeparator', () {
      const item = TrayMenuItem(id: 'x', label: 'X');
      expect(item.iconPath, isNull);
      expect(item.disabled, isFalse);
      expect(item.checked, isFalse);
      expect(item.submenu, isNull);
      expect(item.shortcut, isNull);
      expect(item.isSeparator, isFalse);
    });

    test('separator factory marks isSeparator true', () {
      final item = TrayMenuItem.separator();
      expect(item.isSeparator, isTrue);
      expect(item.id, 'separator');
      expect(item.label, '-');
    });

    test('toJson preserves all set fields', () {
      const item = TrayMenuItem(
        id: 'x',
        label: 'X',
        iconPath: '/i.png',
        disabled: true,
        checked: true,
        submenu: [TrayMenuItem(id: 's', label: 'Sub')],
        shortcut: 'Cmd+X',
      );
      final json = item.toJson();
      expect(json['id'], 'x');
      expect(json['label'], 'X');
      expect(json['iconPath'], '/i.png');
      expect(json['disabled'], isTrue);
      expect(json['checked'], isTrue);
      expect(json['submenu'], hasLength(1));
      expect(json['shortcut'], 'Cmd+X');
    });

    test('toJson omits null optional fields', () {
      const item = TrayMenuItem(id: 'x', label: 'X');
      final json = item.toJson();
      expect(json.containsKey('iconPath'), isFalse);
      expect(json.containsKey('submenu'), isFalse);
      expect(json.containsKey('shortcut'), isFalse);
    });

    test('fromJson roundtrip with full fields and submenu', () {
      const original = TrayMenuItem(
        id: 'top',
        label: 'Top',
        iconPath: '/i.png',
        disabled: true,
        checked: true,
        shortcut: 'Cmd+T',
        submenu: [
          TrayMenuItem(id: 'a', label: 'A'),
          TrayMenuItem(id: 'b', label: 'B', disabled: true),
        ],
      );
      final restored = TrayMenuItem.fromJson(original.toJson());
      expect(restored.id, 'top');
      expect(restored.label, 'Top');
      expect(restored.iconPath, '/i.png');
      expect(restored.disabled, isTrue);
      expect(restored.checked, isTrue);
      expect(restored.shortcut, 'Cmd+T');
      expect(restored.submenu, hasLength(2));
      expect(restored.submenu!.first.id, 'a');
      expect(restored.submenu!.last.disabled, isTrue);
    });

    test('fromJson minimal payload uses defaults', () {
      final item = TrayMenuItem.fromJson({'id': 'x', 'label': 'X'});
      expect(item.disabled, isFalse);
      expect(item.checked, isFalse);
      expect(item.iconPath, isNull);
      expect(item.submenu, isNull);
      expect(item.shortcut, isNull);
    });
  });
}
