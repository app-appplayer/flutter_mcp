// Targeted serialization coverage for the config classes in
// lib/src/config/mcp_config.dart. The existing tests focus on parsing /
// validation; this file drives toJson() and copyWith() through every
// optional branch.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/config/mcp_config.dart';
import 'package:mcp_llm/mcp_llm.dart' show LlmConfiguration;

void main() {
  group('MCPClientConfig.toJson', () {
    test('minimal config emits the three required keys', () {
      final c = MCPClientConfig(
        name: 'c',
        version: '1.0.0',
        transportType: 'stdio',
      );
      final json = c.toJson();
      expect(json['name'], 'c');
      expect(json['version'], '1.0.0');
      expect(json['transportType'], 'stdio');
      expect(json.containsKey('serverUrl'), isFalse);
      expect(json.containsKey('headers'), isFalse);
    });

    test('all-optional config emits every branch', () {
      final c = MCPClientConfig(
        name: 'c',
        version: '1.0.0',
        transportType: 'streamablehttp',
        transportCommand: '/usr/bin/x',
        transportArgs: ['--flag'],
        serverUrl: 'https://example.test',
        authToken: 'tok',
        endpoint: '/mcp',
        timeout: const Duration(seconds: 30),
        sseReadTimeout: const Duration(minutes: 5),
        maxConcurrentRequests: 3,
        useHttp2: true,
        terminateOnClose: false,
        headers: {'X-Foo': 'Bar'},
      );
      final json = c.toJson();
      expect(json['transportCommand'], '/usr/bin/x');
      expect(json['transportArgs'], ['--flag']);
      expect(json['serverUrl'], 'https://example.test');
      expect(json['authToken'], 'tok');
      expect(json['endpoint'], '/mcp');
      expect(json['timeout'], 30000);
      expect(json['sseReadTimeout'], 300000);
      expect(json['maxConcurrentRequests'], 3);
      expect(json['useHttp2'], true);
      expect(json['terminateOnClose'], false);
      expect(json['headers'], {'X-Foo': 'Bar'});
    });

    test('throws ArgumentError when transportType is omitted', () {
      expect(
        () => MCPClientConfig(name: 'c', version: '1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('autoBridgeSampling defaults to true', () {
      final c = MCPClientConfig(
        name: 'c',
        version: '1.0.0',
        transportType: 'stdio',
      );
      expect(c.autoBridgeSampling, isTrue);
    });
  });

  group('MCPServerConfig.toJson', () {
    test('minimal stdio config', () {
      final s = MCPServerConfig(
        name: 's',
        version: '1.0.0',
        transportType: 'stdio',
      );
      final json = s.toJson();
      expect(json['name'], 's');
      expect(json['version'], '1.0.0');
      expect(json['transportType'], 'stdio');
    });

    // ignore: deprecated_member_use_from_same_package
    test('deprecated useStdioTransport flag picks transportType=stdio', () {
      final s = MCPServerConfig(
        name: 's',
        version: '1',
        useStdioTransport: true,
      );
      expect(s.transportType, 'stdio');
      // ignore: deprecated_member_use_from_same_package
      expect(s.useStdioTransport, isTrue);
    });

    test('throws when neither transportType nor useStdioTransport set', () {
      expect(
        () => MCPServerConfig(name: 's', version: '1'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('all-optional config emits every branch', () {
      final s = MCPServerConfig(
        name: 's',
        version: '1.0.0',
        transportType: 'sse',
        ssePort: 8080,
        streamableHttpPort: 8443,
        fallbackPorts: [8081, 8082],
        authToken: 'tok',
        host: '0.0.0.0',
        endpoint: '/sse',
        messagesEndpoint: '/messages',
        corsConfig: {'origin': '*'},
        maxRequestSize: 2 << 20,
        requestTimeout: const Duration(seconds: 10),
        isJsonResponseEnabled: true,
        jsonResponseMode: 'async',
        middleware: ['logger'],
      );
      final json = s.toJson();
      expect(json['ssePort'], 8080);
      expect(json['streamableHttpPort'], 8443);
      expect(json['fallbackPorts'], [8081, 8082]);
      expect(json['authToken'], 'tok');
      expect(json['host'], '0.0.0.0');
      expect(json['endpoint'], '/sse');
      expect(json['messagesEndpoint'], '/messages');
      expect(json['corsConfig'], {'origin': '*'});
      expect(json['maxRequestSize'], 2 << 20);
      expect(json['requestTimeout'], 10000);
      expect(json['isJsonResponseEnabled'], true);
      expect(json['jsonResponseMode'], 'async');
      expect(json['middleware'], ['logger']);
    });
  });

  group('MCPLlmClientConfig.toJson', () {
    test('round-trips required + optional fields', () {
      final c = MCPLlmClientConfig(
        providerName: 'openai',
        config: LlmConfiguration(apiKey: 'k', model: 'gpt-4'),
        isDefault: true,
        mcpClientIds: ['c1', 'c2'],
      );
      final json = c.toJson();
      expect(json['providerName'], 'openai');
      expect(json['isDefault'], true);
      expect(json['mcpClientIds'], ['c1', 'c2']);
      expect(json['config'], isA<Map>());
    });
  });

  group('MCPLlmServerConfig.toJson', () {
    test('round-trips required + optional fields', () {
      final s = MCPLlmServerConfig(
        providerName: 'claude',
        config: LlmConfiguration(apiKey: 'k', model: 'sonnet'),
        isDefault: false,
        mcpServerIds: ['s0'],
      );
      final json = s.toJson();
      expect(json['providerName'], 'claude');
      expect(json['isDefault'], false);
      expect(json['mcpServerIds'], ['s0']);
    });
  });

  group('MCPConfig.toJson', () {
    test('emits required fields with defaults', () {
      final c = MCPConfig(appName: 'app', appVersion: '1.0.0');
      final json = c.toJson();
      expect(json['appName'], 'app');
      expect(json['appVersion'], '1.0.0');
      expect(json['useBackgroundService'], false);
      expect(json['useNotification'], false);
      expect(json['useTray'], false);
      expect(json['secure'], true);
      expect(json['lifecycleManaged'], true);
      expect(json['autoStart'], true);
      // Optional fields are still emitted because they have non-null defaults.
      expect(json['autoRegisterLlmPlugins'], false);
      expect(json['registerMcpPluginsWithLlm'], false);
      expect(json['registerCoreLlmPlugins'], false);
      expect(json['enableRetrieval'], false);
    });

    test('emits optional numeric/string knobs when set', () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        enablePerformanceMonitoring: true,
        enableMetricsExport: true,
        metricsExportPath: '/tmp/m.json',
        autoLoadPlugins: true,
        highMemoryThresholdMB: 512,
        lowBatteryWarningThreshold: 15,
        maxConnectionRetries: 5,
        llmRequestTimeoutMs: 12000,
      );
      final json = c.toJson();
      expect(json['enablePerformanceMonitoring'], true);
      expect(json['enableMetricsExport'], true);
      expect(json['metricsExportPath'], '/tmp/m.json');
      expect(json['autoLoadPlugins'], true);
      expect(json['highMemoryThresholdMB'], 512);
      expect(json['lowBatteryWarningThreshold'], 15);
      expect(json['maxConnectionRetries'], 5);
      expect(json['llmRequestTimeoutMs'], 12000);
    });

    test('serialises background config block', () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        background: BackgroundConfig(
          notificationChannelId: 'ch',
          notificationChannelName: 'name',
          notificationDescription: 'desc',
          notificationIcon: 'ic',
          autoStartOnBoot: true,
          intervalMs: 1000,
          keepAlive: true,
        ),
      );
      final bg = c.toJson()['background'] as Map<String, dynamic>;
      expect(bg['notificationChannelId'], 'ch');
      expect(bg['intervalMs'], 1000);
      expect(bg['keepAlive'], true);
      expect(bg['autoStartOnBoot'], true);
    });

    test('serialises notification config block', () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        notification: NotificationConfig(
          channelId: 'cid',
          channelName: 'cn',
          channelDescription: 'cd',
          icon: 'ic',
          enableSound: true,
          enableVibration: false,
        ),
      );
      final n = c.toJson()['notification'] as Map<String, dynamic>;
      expect(n['channelId'], 'cid');
      expect(n['channelName'], 'cn');
      expect(n['enableSound'], true);
      expect(n['enableVibration'], false);
      expect(n['priority'], isNotNull);
    });

    test('serialises tray config including menu items + separator', () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        tray: TrayConfig(
          iconPath: '/i.png',
          tooltip: 'tt',
          menuItems: [
            TrayMenuItem(label: 'Open'),
            TrayMenuItem.separator(),
            TrayMenuItem(label: 'Quit', disabled: true),
          ],
        ),
      );
      final tray = c.toJson()['tray'] as Map<String, dynamic>;
      expect(tray['iconPath'], '/i.png');
      expect(tray['tooltip'], 'tt');
      final items = tray['menuItems'] as List;
      expect(items, hasLength(3));
      expect(items[1], {'separator': true});
      expect(items[2], {'label': 'Quit', 'disabled': true});
    });

    test('serialises schedule + autoStart{Server,Client,LlmClient,LlmServer}',
        () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        schedule: [
          MCPJob(id: 'j', interval: const Duration(seconds: 5), task: () {}),
        ],
        autoStartServer: [
          MCPServerConfig(name: 's', version: '1', transportType: 'stdio'),
        ],
        autoStartClient: [
          MCPClientConfig(name: 'c', version: '1', transportType: 'stdio'),
        ],
        autoStartLlmClient: [
          MCPLlmClientConfig(
            providerName: 'p',
            config: LlmConfiguration(apiKey: 'k', model: 'm'),
          ),
        ],
        autoStartLlmServer: [
          MCPLlmServerConfig(
            providerName: 'p',
            config: LlmConfiguration(apiKey: 'k', model: 'm'),
          ),
        ],
      );
      final json = c.toJson();
      expect(json['schedule'], hasLength(1));
      expect(json['autoStartServer'], hasLength(1));
      expect(json['autoStartClient'], hasLength(1));
      expect(json['autoStartLlmClient'], hasLength(1));
      expect(json['autoStartLlmServer'], hasLength(1));
    });

    test('extraOptions are merged but never overwrite reserved keys', () {
      final c = MCPConfig(
        appName: 'app',
        appVersion: '1',
        extraOptions: {
          'custom': 'value',
          'appName': 'should-not-overwrite',
        },
      );
      final json = c.toJson();
      expect(json['custom'], 'value');
      expect(json['appName'], 'app'); // reserved key untouched
    });
  });

  group('MCPConfig.copyWith', () {
    test('copyWith with no args returns equivalent shape', () {
      final c = MCPConfig(appName: 'app', appVersion: '1.0.0');
      final c2 = c.copyWith();
      expect(c2.appName, 'app');
      expect(c2.appVersion, '1.0.0');
      expect(c2.useNotification, c.useNotification);
    });

    test('copyWith replaces individual fields', () {
      final c = MCPConfig(appName: 'app', appVersion: '1.0.0');
      final c2 = c.copyWith(
        appName: 'new',
        useNotification: true,
        useTray: true,
        autoStart: false,
      );
      expect(c2.appName, 'new');
      expect(c2.appVersion, '1.0.0');
      expect(c2.useNotification, isTrue);
      expect(c2.useTray, isTrue);
      expect(c2.autoStart, isFalse);
    });
  });

  group('MCPProtectedResourceConfig', () {
    test('stores all fields', () {
      const cfg = MCPProtectedResourceConfig(
        resource: 'https://r.test',
        authorizationServers: ['https://as.test'],
        scopesSupported: ['read', 'write'],
        bearerMethodsSupported: ['header'],
        resourceDocumentation: 'https://r.test/docs',
      );
      expect(cfg.resource, 'https://r.test');
      expect(cfg.authorizationServers, ['https://as.test']);
      expect(cfg.scopesSupported, ['read', 'write']);
      expect(cfg.bearerMethodsSupported, ['header']);
      expect(cfg.resourceDocumentation, 'https://r.test/docs');
    });

    test('optional fields default to null', () {
      const cfg = MCPProtectedResourceConfig(
        resource: 'https://r.test',
        authorizationServers: ['https://as.test'],
      );
      expect(cfg.scopesSupported, isNull);
      expect(cfg.bearerMethodsSupported, isNull);
      expect(cfg.resourceDocumentation, isNull);
    });
  });
}
