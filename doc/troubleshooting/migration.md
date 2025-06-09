# Migration Guide

Comprehensive guide for migrating between Flutter MCP versions and from other solutions.

## Version Migration

### Migrating from 0.x to 1.0

#### Breaking Changes

1. **Configuration Structure**
```dart
// Old (0.x)
final config = Config(
  serverUrl: 'ws://localhost:8080',
  timeout: 30,
);

// New (1.0)
final config = McpConfig(
  servers: [
    ServerConfig(
      id: 'main',
      url: 'ws://localhost:8080',
      connectionTimeout: Duration(seconds: 30),
    ),
  ],
);
```

2. **Client API Changes**
```dart
// Old (0.x)
final result = await mcp.execute('tool_name', {'arg': 'value'});

// New (1.0)
final result = await mcp.client.callTool(
  serverId: 'main',
  name: 'tool_name',
  arguments: {'arg': 'value'},
);
```

3. **Error Handling**
```dart
// Old (0.x)
try {
  await mcp.connect();
} on ConnectionError catch (e) {
  print(e.message);
}

// New (1.0)
try {
  await mcp.initialize(config: config);
} on MCPConnectionException catch (e) {
  print('Error ${e.code}: ${e.message}');
}
```

#### Migration Steps

1. **Update Dependencies**
```yaml
# pubspec.yaml
dependencies:
  flutter_mcp: ^1.0.0
```

2. **Update Configuration**
```dart
// migration_helper.dart
McpConfig migrateConfig(OldConfig oldConfig) {
  return McpConfig(
    servers: [
      ServerConfig(
        id: 'default',
        url: oldConfig.serverUrl,
        connectionTimeout: Duration(seconds: oldConfig.timeout),
        reconnectDelay: Duration(seconds: oldConfig.reconnectDelay ?? 5),
      ),
    ],
    debugOptions: oldConfig.debug ? DebugOptions(
      logLevel: LogLevel.debug,
      enableNetworkLogging: true,
    ) : null,
  );
}
```

3. **Update Client Usage**
```dart
// Before
class OldService {
  final MCP mcp;
  
  Future<String> getData() async {
    final result = await mcp.execute('getData', {});
    return result['data'];
  }
}

// After
class NewService {
  final FlutterMCP mcp;
  
  Future<String> getData() async {
    final result = await mcp.client.callTool(
      serverId: 'default',
      name: 'getData',
      arguments: {},
    );
    return result.content['data'];
  }
}
```

4. **Update Error Handling**
```dart
// Error migration helper
class ErrorMigrator {
  static MCPException migrateError(dynamic oldError) {
    if (oldError is ConnectionError) {
      return MCPConnectionException(
        message: oldError.message,
        code: 'MCP-CONN-001',
      );
    } else if (oldError is TimeoutError) {
      return MCPTimeoutException(
        message: oldError.message,
        code: 'MCP-CONN-001',
      );
    }
    
    return MCPException(
      message: oldError.toString(),
      code: 'MCP-UNKNOWN',
    );
  }
}
```

### Migrating from 1.0 to 2.0

#### Breaking Changes

1. **Async Initialization**
```dart
// Old (1.0)
final mcp = FlutterMCP(config: config);
await mcp.connect();

// New (2.0)
final mcp = FlutterMCP();
await mcp.initialize(config: config);
```

2. **Stream API Changes**
```dart
// Old (1.0)
mcp.messages.listen((message) {
  print(message);
});

// New (2.0)
mcp.client.onMessage.listen((message) {
  print(message);
});
```

3. **Plugin Architecture**
```dart
// Old (1.0)
mcp.registerExtension(MyExtension());

// New (2.0)
mcp.plugins.register(MyPlugin());
```

#### Automated Migration Tool

```dart
// lib/migration/auto_migrator.dart
class AutoMigrator {
  static Future<void> migrateProject({
    required String projectPath,
    required String fromVersion,
    required String toVersion,
  }) async {
    final migrator = _getMigrator(fromVersion, toVersion);
    
    if (migrator == null) {
      throw Exception('No migrator available for $fromVersion to $toVersion');
    }
    
    // Backup project
    await _backupProject(projectPath);
    
    try {
      // Run migration
      await migrator.migrate(projectPath);
      
      // Update pubspec
      await _updatePubspec(projectPath, toVersion);
      
      // Run tests
      await _runTests(projectPath);
      
      print('Migration completed successfully');
    } catch (e) {
      // Restore backup
      await _restoreBackup(projectPath);
      rethrow;
    }
  }
  
  static Migrator? _getMigrator(String from, String to) {
    final key = '$from->$to';
    
    return {
      '0.9->1.0': Migrator_0_9_to_1_0(),
      '1.0->1.1': Migrator_1_0_to_1_1(),
      '1.1->2.0': Migrator_1_1_to_2_0(),
    }[key];
  }
}

abstract class Migrator {
  Future<void> migrate(String projectPath);
}

class Migrator_1_0_to_2_0 extends Migrator {
  @override
  Future<void> migrate(String projectPath) async {
    // Update imports
    await _updateImports(projectPath);
    
    // Update configuration
    await _updateConfiguration(projectPath);
    
    // Update API usage
    await _updateApiUsage(projectPath);
    
    // Update error handling
    await _updateErrorHandling(projectPath);
  }
  
  Future<void> _updateImports(String projectPath) async {
    final dartFiles = await _findDartFiles(projectPath);
    
    for (final file in dartFiles) {
      var content = await file.readAsString();
      
      // Update imports
      content = content.replaceAll(
        'package:flutter_mcp/mcp.dart',
        'package:flutter_mcp/flutter_mcp.dart',
      );
      
      await file.writeAsString(content);
    }
  }
  
  Future<void> _updateConfiguration(String projectPath) async {
    final configFiles = await _findConfigFiles(projectPath);
    
    for (final file in configFiles) {
      var content = await file.readAsString();
      
      // Update configuration syntax
      content = _migrateConfigSyntax(content);
      
      await file.writeAsString(content);
    }
  }
  
  String _migrateConfigSyntax(String content) {
    // Implement AST-based code transformation
    return content
        .replaceAll('Config(', 'McpConfig(')
        .replaceAll('serverUrl:', 'servers: [ServerConfig(url:')
        .replaceAll('timeout:', 'connectionTimeout: Duration(seconds:');
  }
}
```

## Platform Migration

### Migrating from Other MCP Libraries

#### From Node.js MCP

```javascript
// Node.js MCP
const mcp = new MCPClient({
  serverUrl: 'ws://localhost:8080',
  onMessage: (message) => console.log(message),
});

await mcp.connect();
const result = await mcp.call('tool', { param: 'value' });
```

```dart
// Flutter MCP equivalent
final mcp = FlutterMCP();

await mcp.initialize(
  config: McpConfig(
    servers: [
      ServerConfig(
        id: 'main',
        url: 'ws://localhost:8080',
      ),
    ],
  ),
);

mcp.client.onMessage.listen((message) => print(message));

final result = await mcp.client.callTool(
  serverId: 'main',
  name: 'tool',
  arguments: {'param': 'value'},
);
```

#### From Python MCP

```python
# Python MCP
from mcp import MCPClient

client = MCPClient(server_url='ws://localhost:8080')
client.connect()

result = client.execute_tool('tool', {'param': 'value'})
```

```dart
// Flutter MCP equivalent
final mcp = FlutterMCP();

await mcp.initialize(
  config: McpConfig(
    servers: [
      ServerConfig(
        id: 'main',
        url: 'ws://localhost:8080',
      ),
    ],
  ),
);

final result = await mcp.client.callTool(
  serverId: 'main',
  name: 'tool',
  arguments: {'param': 'value'},
);
```

### Platform-Specific Considerations

#### Android Migration

```xml
<!-- Old permissions -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- New permissions (Android 12+) -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

```kotlin
// Old implementation
class MCPService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Old service implementation
        return START_STICKY
    }
}

// New implementation
class MCPService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Create notification channel for Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            createNotificationChannel()
        }
        
        // Start foreground service for Android 12+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            startForeground(NOTIFICATION_ID, createNotification())
        }
        
        return START_STICKY
    }
}
```

#### iOS Migration

```swift
// Old implementation
class MCPManager: NSObject {
    func startService() {
        // Basic service start
    }
}

// New implementation  
class MCPManager: NSObject {
    func startService() {
        // Request permissions
        requestNotificationPermissions()
        
        // Configure background modes
        configureBackgroundModes()
        
        // Start service with iOS 14+ considerations
        if #available(iOS 14.0, *) {
            startModernService()
        } else {
            startLegacyService()
        }
    }
    
    @available(iOS 14.0, *)
    private func startModernService() {
        // Use BGTaskScheduler for background tasks
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.example.mcp.refresh",
            using: nil
        ) { task in
            self.handleBackgroundTask(task: task)
        }
    }
}
```

## Feature Migration

### Migrating Authentication

```dart
// Old authentication
class OldAuth {
  final MCP mcp;
  
  Future<void> authenticate(String token) async {
    mcp.setHeader('Authorization', 'Bearer $token');
  }
}

// New authentication
class NewAuth {
  final FlutterMCP mcp;
  
  Future<void> authenticate(String token) async {
    // Use auth provider
    await mcp.setAuthProvider(
      AuthProvider(
        getCredentials: () async => Credentials(
          token: token,
          type: CredentialType.bearer,
        ),
        onAuthError: (error) async {
          // Handle auth errors
          await refreshToken();
        },
      ),
    );
  }
}
```

### Migrating Custom Plugins

```dart
// Old plugin system
class OldPlugin extends MCPExtension {
  @override
  void register(MCP mcp) {
    mcp.registerTool('custom_tool', (args) async {
      return {'result': 'value'};
    });
  }
}

// New plugin system
class NewPlugin extends MCPPlugin {
  @override
  String get id => 'my_plugin';
  
  @override
  String get version => '1.0.0';
  
  @override
  Future<void> initialize(MCPPluginContext context) async {
    // Register tools
    context.registerTool(
      ToolDefinition(
        name: 'custom_tool',
        description: 'My custom tool',
        parameters: {
          'param': ParameterDefinition(
            type: ParameterType.string,
            required: true,
          ),
        },
        handler: (arguments) async {
          return ToolResult(
            content: {'result': 'value'},
          );
        },
      ),
    );
  }
}
```

### Migrating Error Handling

```dart
// Old error handling
try {
  await mcp.connect();
} catch (e) {
  if (e.toString().contains('timeout')) {
    // Handle timeout
  } else if (e.toString().contains('auth')) {
    // Handle auth error
  }
}

// New error handling
try {
  await mcp.initialize(config: config);
} on MCPTimeoutException catch (e) {
  // Handle timeout with specific error code
  print('Timeout: ${e.code}');
} on MCPAuthException catch (e) {
  // Handle auth error
  print('Auth error: ${e.code}');
} on MCPException catch (e) {
  // Handle general MCP errors
  print('MCP error: ${e.code} - ${e.message}');
}
```

## Migration Validation

### Automated Testing

```dart
// lib/migration/validation_test.dart
class MigrationValidator {
  static Future<ValidationResult> validate({
    required String projectPath,
    required String targetVersion,
  }) async {
    final results = <ValidationCheck>[];
    
    // Check dependencies
    results.add(await _validateDependencies(projectPath, targetVersion));
    
    // Check configuration
    results.add(await _validateConfiguration(projectPath));
    
    // Check API usage
    results.add(await _validateApiUsage(projectPath));
    
    // Run tests
    results.add(await _validateTests(projectPath));
    
    return ValidationResult(
      passed: results.every((r) => r.passed),
      checks: results,
    );
  }
  
  static Future<ValidationCheck> _validateDependencies(
    String projectPath,
    String targetVersion,
  ) async {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    final pubspec = loadYaml(await pubspecFile.readAsString());
    
    final mcpVersion = pubspec['dependencies']['flutter_mcp'];
    final isValidVersion = mcpVersion == '^$targetVersion';
    
    return ValidationCheck(
      name: 'Dependencies',
      passed: isValidVersion,
      message: isValidVersion 
          ? 'Dependencies are correct'
          : 'flutter_mcp version should be ^$targetVersion',
    );
  }
  
  static Future<ValidationCheck> _validateConfiguration(
    String projectPath,
  ) async {
    final configFiles = await _findFiles(
      projectPath,
      pattern: RegExp(r'McpConfig\('),
    );
    
    final errors = <String>[];
    
    for (final file in configFiles) {
      final content = await file.readAsString();
      
      // Check for old configuration patterns
      if (content.contains('Config(')) {
        errors.add('${file.path}: Old Config class found');
      }
      
      if (content.contains('serverUrl:')) {
        errors.add('${file.path}: Old serverUrl property found');
      }
    }
    
    return ValidationCheck(
      name: 'Configuration',
      passed: errors.isEmpty,
      message: errors.isEmpty 
          ? 'Configuration is valid'
          : errors.join('\n'),
    );
  }
  
  static Future<ValidationCheck> _validateTests(String projectPath) async {
    final result = await Process.run(
      'flutter',
      ['test'],
      workingDirectory: projectPath,
    );
    
    return ValidationCheck(
      name: 'Tests',
      passed: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'All tests passed'
          : 'Test failures:\n${result.stderr}',
    );
  }
}

class ValidationResult {
  final bool passed;
  final List<ValidationCheck> checks;
  
  ValidationResult({
    required this.passed,
    required this.checks,
  });
  
  void printReport() {
    print('Migration Validation Report');
    print('=' * 30);
    
    for (final check in checks) {
      final status = check.passed ? '✓' : '✗';
      print('$status ${check.name}: ${check.message}');
    }
    
    print('\nResult: ${passed ? 'PASSED' : 'FAILED'}');
  }
}

class ValidationCheck {
  final String name;
  final bool passed;
  final String message;
  
  ValidationCheck({
    required this.name,
    required this.passed,
    required this.message,
  });
}
```

## Migration Tools

### Command-Line Tool

```dart
// bin/mcp_migrate.dart
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('from', abbr: 'f', help: 'Source version')
    ..addOption('to', abbr: 't', help: 'Target version')
    ..addOption('project', abbr: 'p', help: 'Project path')
    ..addFlag('validate', abbr: 'v', help: 'Validate only')
    ..addFlag('backup', abbr: 'b', help: 'Create backup', defaultsTo: true);
  
  final results = parser.parse(args);
  
  final fromVersion = results['from'];
  final toVersion = results['to'];
  final projectPath = results['project'] ?? Directory.current.path;
  final validateOnly = results['validate'];
  final createBackup = results['backup'];
  
  if (validateOnly) {
    // Validate migration
    final validation = await MigrationValidator.validate(
      projectPath: projectPath,
      targetVersion: toVersion,
    );
    
    validation.printReport();
    exit(validation.passed ? 0 : 1);
  } else {
    // Perform migration
    try {
      await AutoMigrator.migrateProject(
        projectPath: projectPath,
        fromVersion: fromVersion,
        toVersion: toVersion,
      );
      
      print('Migration completed successfully');
      exit(0);
    } catch (e) {
      print('Migration failed: $e');
      exit(1);
    }
  }
}
```

### IDE Plugin

```dart
// lib/migration/ide_plugin.dart
class MCPMigrationPlugin {
  static void registerWithIDE() {
    // Register with VS Code
    vscode.commands.registerCommand('flutter-mcp.migrate', () async {
      final fromVersion = await vscode.showInputBox(
        prompt: 'Enter current version',
        placeHolder: '1.0.0',
      );
      
      final toVersion = await vscode.showInputBox(
        prompt: 'Enter target version',
        placeHolder: '2.0.0',
      );
      
      final progress = vscode.showProgress(
        title: 'Migrating Flutter MCP',
        cancellable: true,
      );
      
      try {
        await AutoMigrator.migrateProject(
          projectPath: vscode.workspace.rootPath,
          fromVersion: fromVersion,
          toVersion: toVersion,
        );
        
        vscode.showInformationMessage('Migration completed successfully');
      } catch (e) {
        vscode.showErrorMessage('Migration failed: $e');
      } finally {
        progress.dispose();
      }
    });
  }
}
```

## Best Practices

### 1. Pre-Migration Checklist

```dart
class PreMigrationChecklist {
  static Future<ChecklistResult> run(String projectPath) async {
    final checks = <Check>[];
    
    // Version control
    checks.add(await _checkVersionControl(projectPath));
    
    // Tests passing
    checks.add(await _checkTestsPassing(projectPath));
    
    // No uncommitted changes
    checks.add(await _checkCleanWorkingTree(projectPath));
    
    // Dependencies up to date
    checks.add(await _checkDependencies(projectPath));
    
    // Backup exists
    checks.add(await _checkBackup(projectPath));
    
    return ChecklistResult(checks: checks);
  }
  
  static Future<Check> _checkVersionControl(String projectPath) async {
    final gitDir = Directory('$projectPath/.git');
    return Check(
      name: 'Version Control',
      passed: await gitDir.exists(),
      message: 'Project should be under version control',
    );
  }
  
  static Future<Check> _checkTestsPassing(String projectPath) async {
    final result = await Process.run(
      'flutter',
      ['test'],
      workingDirectory: projectPath,
    );
    
    return Check(
      name: 'Tests',
      passed: result.exitCode == 0,
      message: 'All tests should pass before migration',
    );
  }
}
```

### 2. Safe Migration Process

```dart
class SafeMigrationProcess {
  static Future<void> migrate({
    required String projectPath,
    required String fromVersion,
    required String toVersion,
  }) async {
    // 1. Pre-migration checks
    final checklist = await PreMigrationChecklist.run(projectPath);
    if (!checklist.allPassed) {
      throw Exception('Pre-migration checks failed');
    }
    
    // 2. Create backup
    final backupPath = await createBackup(projectPath);
    print('Backup created at: $backupPath');
    
    // 3. Create migration branch
    await Process.run('git', ['checkout', '-b', 'migrate-to-$toVersion']);
    
    try {
      // 4. Run migration
      await AutoMigrator.migrateProject(
        projectPath: projectPath,
        fromVersion: fromVersion,
        toVersion: toVersion,
      );
      
      // 5. Validate migration
      final validation = await MigrationValidator.validate(
        projectPath: projectPath,
        targetVersion: toVersion,
      );
      
      if (!validation.passed) {
        throw Exception('Migration validation failed');
      }
      
      // 6. Commit changes
      await Process.run('git', ['add', '.']);
      await Process.run('git', ['commit', '-m', 'Migrate to Flutter MCP $toVersion']);
      
      print('Migration completed successfully');
    } catch (e) {
      // Rollback on failure
      await rollback(projectPath, backupPath);
      rethrow;
    }
  }
  
  static Future<String> createBackup(String projectPath) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$projectPath/../backup_$timestamp';
    
    await Process.run('cp', ['-r', projectPath, backupPath]);
    
    return backupPath;
  }
  
  static Future<void> rollback(String projectPath, String backupPath) async {
    print('Rolling back migration...');
    
    // Reset git changes
    await Process.run('git', ['reset', '--hard']);
    await Process.run('git', ['checkout', 'main']);
    
    // Restore backup if needed
    if (await Directory(backupPath).exists()) {
      await Process.run('rm', ['-rf', projectPath]);
      await Process.run('mv', [backupPath, projectPath]);
    }
    
    print('Rollback completed');
  }
}
```

### 3. Post-Migration Verification

```dart
class PostMigrationVerification {
  static Future<VerificationResult> verify({
    required String projectPath,
    required String targetVersion,
  }) async {
    final checks = <VerificationCheck>[];
    
    // Build succeeds
    checks.add(await _verifyBuild(projectPath));
    
    // Tests pass
    checks.add(await _verifyTests(projectPath));
    
    // Integration tests pass
    checks.add(await _verifyIntegrationTests(projectPath));
    
    // Performance benchmarks
    checks.add(await _verifyPerformance(projectPath));
    
    // API compatibility
    checks.add(await _verifyApiCompatibility(projectPath, targetVersion));
    
    return VerificationResult(checks: checks);
  }
  
  static Future<VerificationCheck> _verifyBuild(String projectPath) async {
    final platforms = ['apk', 'ios', 'web'];
    final errors = <String>[];
    
    for (final platform in platforms) {
      final result = await Process.run(
        'flutter',
        ['build', platform, '--release'],
        workingDirectory: projectPath,
      );
      
      if (result.exitCode != 0) {
        errors.add('$platform build failed');
      }
    }
    
    return VerificationCheck(
      name: 'Build',
      passed: errors.isEmpty,
      errors: errors,
    );
  }
  
  static Future<VerificationCheck> _verifyPerformance(
    String projectPath,
  ) async {
    // Run performance benchmarks
    final result = await Process.run(
      'flutter',
      ['test', 'test/performance'],
      workingDirectory: projectPath,
    );
    
    return VerificationCheck(
      name: 'Performance',
      passed: result.exitCode == 0,
      errors: result.exitCode != 0 ? [result.stderr.toString()] : [],
    );
  }
}
```

## Rollback Procedures

### Emergency Rollback

```dart
class EmergencyRollback {
  static Future<void> rollback({
    required String projectPath,
    required String previousVersion,
    String? backupPath,
  }) async {
    print('Starting emergency rollback...');
    
    try {
      // 1. Stop all services
      await stopServices();
      
      // 2. Restore from backup if available
      if (backupPath != null && await Directory(backupPath).exists()) {
        await restoreFromBackup(projectPath, backupPath);
      } else {
        // 3. Revert using git
        await revertUsingGit(projectPath, previousVersion);
      }
      
      // 4. Downgrade dependencies
      await downgradeDependencies(projectPath, previousVersion);
      
      // 5. Clear caches
      await clearCaches(projectPath);
      
      // 6. Restart services
      await restartServices();
      
      print('Rollback completed successfully');
    } catch (e) {
      print('Rollback failed: $e');
      print('Manual intervention required');
      throw RollbackException('Emergency rollback failed', cause: e);
    }
  }
  
  static Future<void> stopServices() async {
    // Stop any running MCP services
    await Process.run('pkill', ['-f', 'flutter_mcp']);
  }
  
  static Future<void> restoreFromBackup(
    String projectPath,
    String backupPath,
  ) async {
    // Remove current project
    await Directory(projectPath).delete(recursive: true);
    
    // Copy backup
    await Process.run('cp', ['-r', backupPath, projectPath]);
  }
  
  static Future<void> revertUsingGit(
    String projectPath,
    String previousVersion,
  ) async {
    await Process.run(
      'git',
      ['checkout', 'tags/v$previousVersion'],
      workingDirectory: projectPath,
    );
  }
  
  static Future<void> downgradeDependencies(
    String projectPath,
    String previousVersion,
  ) async {
    // Update pubspec.yaml
    final pubspecFile = File('$projectPath/pubspec.yaml');
    var content = await pubspecFile.readAsString();
    
    content = content.replaceAll(
      RegExp(r'flutter_mcp:\s*\^[\d.]+'),
      'flutter_mcp: ^$previousVersion',
    );
    
    await pubspecFile.writeAsString(content);
    
    // Run pub get
    await Process.run(
      'flutter',
      ['pub', 'get'],
      workingDirectory: projectPath,
    );
  }
  
  static Future<void> clearCaches(String projectPath) async {
    await Process.run(
      'flutter',
      ['clean'],
      workingDirectory: projectPath,
    );
  }
  
  static Future<void> restartServices() async {
    // Restart any MCP services
    // Implementation depends on your setup
  }
}

class RollbackException implements Exception {
  final String message;
  final dynamic cause;
  
  RollbackException(this.message, {this.cause});
  
  @override
  String toString() => 'RollbackException: $message${cause != null ? '\nCause: $cause' : ''}';
}
```

## Troubleshooting

### Common Migration Issues

```dart
class MigrationTroubleshooter {
  static final Map<String, TroubleshootingSolution> solutions = {
    'dependency_conflict': TroubleshootingSolution(
      description: 'Dependency version conflicts',
      solution: '''
1. Clear pub cache: flutter pub cache clean
2. Delete pubspec.lock
3. Run: flutter pub get
4. If persists, check for incompatible dependencies
''',
      code: '''
# Check for conflicts
flutter pub deps
''',
    ),
    
    'api_not_found': TroubleshootingSolution(
      description: 'API method not found after migration',
      solution: '''
1. Check migration guide for API changes
2. Update method calls to new API
3. Use migration helper methods if available
''',
      code: '''
// Old API
mcp.execute('tool', args);

// New API
mcp.client.callTool(
  serverId: 'default',
  name: 'tool',
  arguments: args,
);
''',
    ),
    
    'configuration_error': TroubleshootingSolution(
      description: 'Configuration format error',
      solution: '''
1. Update configuration to new format
2. Check for required fields
3. Validate with schema
''',
      code: '''
// Validate configuration
final validator = ConfigValidator();
final result = validator.validate(config);
if (!result.isValid) {
  print(result.errors);
}
''',
    ),
  };
  
  static void diagnose(String error) {
    print('Diagnosing migration error...');
    
    // Check against known issues
    for (final entry in solutions.entries) {
      if (error.toLowerCase().contains(entry.key)) {
        print('\nPossible issue: ${entry.value.description}');
        print('\nSolution:');
        print(entry.value.solution);
        
        if (entry.value.code != null) {
          print('\nExample:');
          print(entry.value.code);
        }
        
        return;
      }
    }
    
    print('Unknown error. Please check the migration guide or file an issue.');
  }
}

class TroubleshootingSolution {
  final String description;
  final String solution;
  final String? code;
  
  TroubleshootingSolution({
    required this.description,
    required this.solution,
    this.code,
  });
}
```

### Migration Support

```dart
class MigrationSupport {
  static const String supportEmail = 'support@flutter-mcp.dev';
  static const String documentationUrl = 'https://flutter-mcp.dev/migration';
  static const String issuesUrl = 'https://github.com/flutter-mcp/issues';
  
  static Future<void> reportIssue({
    required String version,
    required String error,
    String? projectInfo,
  }) async {
    final report = {
      'version': version,
      'error': error,
      'platform': Platform.operatingSystem,
      'dart_version': Platform.version,
      'project_info': projectInfo,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    // Submit to issue tracker
    await http.post(
      Uri.parse('$issuesUrl/migration-report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(report),
    );
  }
  
  static void showHelp() {
    print('''
Flutter MCP Migration Help
========================

Documentation: $documentationUrl
Support Email: $supportEmail
Issue Tracker: $issuesUrl

Common Commands:
- flutter pub run flutter_mcp:migrate --from 1.0 --to 2.0
- flutter pub run flutter_mcp:validate
- flutter pub run flutter_mcp:rollback

For interactive help, run:
flutter pub run flutter_mcp:doctor
''');
  }
}
```

## See Also

- [Installation Guide](/doc/getting-started/installation.md)
- [Configuration Guide](/doc/getting-started/configuration.md)
- [API Reference](/doc/api/client.md)
- [Release Notes](/CHANGELOG.md)