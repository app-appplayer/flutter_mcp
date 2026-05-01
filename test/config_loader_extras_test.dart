// Targeted extras for ConfigLoader — covers loadFromYamlString, file
// loading (success + error), exportToJson, saveToJsonFile, autoStart*
// section parsing, and the log/priority enum branches that the existing
// config_task_execution_test does not exercise.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import 'package:flutter_mcp/src/config/config_loader.dart';
import 'package:flutter_mcp/src/config/notification_config.dart' as notif;
import 'package:flutter_mcp/src/utils/exceptions.dart';

void main() {
  group('ConfigLoader.loadFromString — JSON', () {
    test('parses minimal JSON config', () {
      final c = ConfigLoader.loadFromString(
        '{"appName": "x", "appVersion": "1.0.0"}',
      );
      expect(c.appName, 'x');
      expect(c.appVersion, '1.0.0');
    });

    test('throws MCPConfigurationException on invalid JSON', () {
      expect(
        () => ConfigLoader.loadFromString('{not json'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigLoader.loadFromString — YAML', () {
    test('parses YAML when format=yaml', () {
      final c = ConfigLoader.loadFromString(
        '''
appName: y
appVersion: 1.0.0
useNotification: true
''',
        format: ConfigFormat.yaml,
      );
      expect(c.appName, 'y');
      expect(c.useNotification, isTrue);
    });

    test('throws MCPConfigurationException on invalid YAML', () {
      expect(
        () => ConfigLoader.loadFromString(
          '{:\n  bad', // intentionally malformed
          format: ConfigFormat.yaml,
        ),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigLoader file IO', () {
    test('loadFromJsonFile reads a real file', () async {
      final tmp = await Directory.systemTemp.createTemp('cfg_loader_test');
      try {
        final f = File('${tmp.path}/c.json');
        await f.writeAsString(
          '{"appName": "f", "appVersion": "1.0.0"}',
        );
        final c = await ConfigLoader.loadFromJsonFile(f.path);
        expect(c.appName, 'f');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('loadFromJsonFile throws when file is missing', () async {
      await expectLater(
        ConfigLoader.loadFromJsonFile('/no/such/path.json'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });

    test('loadFromYamlFile reads a real file', () async {
      final tmp = await Directory.systemTemp.createTemp('cfg_loader_test');
      try {
        final f = File('${tmp.path}/c.yaml');
        await f.writeAsString('''
appName: yf
appVersion: 1.0.0
''');
        final c = await ConfigLoader.loadFromYamlFile(f.path);
        expect(c.appName, 'yf');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('loadFromYamlFile throws when file is missing', () async {
      await expectLater(
        ConfigLoader.loadFromYamlFile('/no/such/path.yaml'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigLoader.exportToJson + saveToJsonFile', () {
    test('exportToJson roundtrips through MCPConfig.toJson', () {
      final c = MCPConfig(appName: 'r', appVersion: '1.0.0');
      final j = ConfigLoader.exportToJson(c);
      expect(j['appName'], 'r');
      expect(j['appVersion'], '1.0.0');
    });

    test('saveToJsonFile writes file content that re-parses', () async {
      final tmp = await Directory.systemTemp.createTemp('cfg_save_test');
      try {
        final c = MCPConfig(appName: 's', appVersion: '1.0.0');
        final p = '${tmp.path}/saved.json';
        await ConfigLoader.saveToJsonFile(c, p);
        expect(await File(p).exists(), isTrue);
        final reread = await ConfigLoader.loadFromJsonFile(p);
        expect(reread.appName, 's');
        expect(reread.appVersion, '1.0.0');
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('saveToJsonFile wraps IO errors', () async {
      final c = MCPConfig(appName: 's', appVersion: '1.0.0');
      // Path under /no/such — write fails.
      await expectLater(
        ConfigLoader.saveToJsonFile(c, '/no/such/dir/saved.json'),
        throwsA(isA<MCPConfigurationException>()),
      );
    });
  });

  group('ConfigLoader autoStart parsing', () {
    test('autoStartServer parses capabilities + ports', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "autoStartServer": [
    {
      "name": "srv",
      "version": "1",
      "transportType": "sse",
      "capabilities": {"tools": true, "resources": true, "prompts": true, "logging": true},
      "ssePort": 8080,
      "fallbackPorts": [8081, 8082]
    }
  ]
}
''');
      expect(c.autoStartServer, hasLength(1));
      final s = c.autoStartServer!.first;
      expect(s.name, 'srv');
      expect(s.transportType, 'sse');
      expect(s.ssePort, 8080);
      expect(s.fallbackPorts, [8081, 8082]);
      expect(s.capabilities, isNotNull);
    });

    test('autoStartClient parses capabilities + transport', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "autoStartClient": [
    {
      "name": "cli",
      "version": "1",
      "transportType": "stdio",
      "transportCommand": "/usr/bin/x",
      "transportArgs": ["--y"],
      "capabilities": {"roots": true, "rootsListChanged": true, "sampling": true}
    }
  ]
}
''');
      expect(c.autoStartClient, hasLength(1));
      final cli = c.autoStartClient!.first;
      expect(cli.name, 'cli');
      expect(cli.transportType, 'stdio');
      expect(cli.transportCommand, '/usr/bin/x');
      expect(cli.transportArgs, ['--y']);
      expect(cli.capabilities, isNotNull);
    });

    test('autoStartLlmClient parses provider + ids', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "autoStartLlmClient": [
    {
      "providerName": "openai",
      "config": {"apiKey": "k", "model": "m"},
      "isDefault": true,
      "mcpClientIds": ["c1", "c2"]
    }
  ]
}
''');
      expect(c.autoStartLlmClient, hasLength(1));
      final l = c.autoStartLlmClient!.first;
      expect(l.providerName, 'openai');
      expect(l.isDefault, isTrue);
      expect(l.mcpClientIds, ['c1', 'c2']);
    });

    test('autoStartLlmServer parses provider + ids', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "autoStartLlmServer": [
    {
      "providerName": "claude",
      "config": {"apiKey": "k", "model": "m"},
      "mcpServerIds": ["s0"]
    }
  ]
}
''');
      expect(c.autoStartLlmServer, hasLength(1));
      final l = c.autoStartLlmServer!.first;
      expect(l.providerName, 'claude');
      expect(l.mcpServerIds, ['s0']);
    });
  });

  group('ConfigLoader notification + tray + background blocks', () {
    test('parses background block', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "background": {
    "notificationChannelId": "ch",
    "notificationChannelName": "name",
    "intervalMs": 1000,
    "keepAlive": true,
    "autoStartOnBoot": true
  }
}
''');
      expect(c.background, isNotNull);
      expect(c.background!.notificationChannelId, 'ch');
      expect(c.background!.intervalMs, 1000);
    });

    test('parses notification block with priority + flags', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "notification": {
    "channelId": "cid",
    "channelName": "cn",
    "enableSound": false,
    "enableVibration": false,
    "priority": "high"
  }
}
''');
      expect(c.notification, isNotNull);
      expect(c.notification!.channelId, 'cid');
      expect(c.notification!.priority, notif.NotificationPriority.high);
    });

    test('priority defaults to normal when missing', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "notification": {"channelId": "cid"}
}
''');
      expect(c.notification!.priority, notif.NotificationPriority.normal);
    });

    test('priority falls back to normal on unknown value', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "notification": {"channelId": "cid", "priority": "totallyUnknown"}
}
''');
      expect(c.notification!.priority, notif.NotificationPriority.normal);
    });

    test('parses tray block with menu items + separators', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "tray": {
    "iconPath": "/i.png",
    "tooltip": "tt",
    "menuItems": [
      {"label": "Open"},
      {"separator": true},
      {"label": "Quit", "disabled": true}
    ]
  }
}
''');
      expect(c.tray, isNotNull);
      expect(c.tray!.iconPath, '/i.png');
      expect(c.tray!.menuItems, hasLength(3));
      expect(c.tray!.menuItems![1].isSeparator, isTrue);
      expect(c.tray!.menuItems![2].disabled, isTrue);
    });
  });

  group('ConfigLoader logging level branches', () {
    Future<MCPConfig> withLevel(String level) async {
      return ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "logging": {"enabled": true, "level": "$level"}
}
''');
    }

    test('all known levels produce non-null loggingLevel', () async {
      for (final lvl in [
        'trace',
        'finest',
        'debug',
        'fine',
        'info',
        'warning',
        'error',
        'severe',
        'none',
        'off',
      ]) {
        final c = await withLevel(lvl);
        expect(c.loggingLevel, isNotNull, reason: 'level=$lvl');
      }
    });

    test('logging.enabled=false leaves loggingLevel null', () {
      final c = ConfigLoader.loadFromString('''
{
  "appName": "a", "appVersion": "1",
  "logging": {"enabled": false}
}
''');
      expect(c.loggingLevel, isNull);
    });
  });
}
