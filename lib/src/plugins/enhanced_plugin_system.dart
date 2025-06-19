import 'dart:async';
import 'dart:isolate';
import 'package:pub_semver/pub_semver.dart';
import 'plugin_system.dart';
import '../utils/logger.dart';
import '../utils/exceptions.dart';
import '../utils/resource_manager.dart';
import '../events/enhanced_typed_event_system.dart';
import '../events/event_models.dart';

/// Plugin version information
class PluginVersion {
  final String name;
  final Version version;
  final Version? minSdkVersion;
  final Version? maxSdkVersion;
  final Map<String, VersionConstraint> dependencies;

  PluginVersion({
    required this.name,
    required this.version,
    this.minSdkVersion,
    this.maxSdkVersion,
    Map<String, VersionConstraint>? dependencies,
  }) : dependencies = dependencies ?? {};

  bool isCompatibleWith(Version sdkVersion) {
    if (minSdkVersion != null && sdkVersion < minSdkVersion!) {
      return false;
    }
    if (maxSdkVersion != null && sdkVersion > maxSdkVersion!) {
      return false;
    }
    return true;
  }

  bool satisfiesDependency(String name, Version version) {
    if (!dependencies.containsKey(name)) return true;
    return dependencies[name]!.allows(version);
  }
}

/// Plugin sandbox configuration
class PluginSandboxConfig {
  final Duration? executionTimeout;
  final int? maxMemoryMB;
  final List<String>? allowedPaths;
  final List<String>? allowedCommands;
  final bool enableNetworkAccess;
  final bool enableFileAccess;

  PluginSandboxConfig({
    this.executionTimeout,
    this.maxMemoryMB,
    this.allowedPaths,
    this.allowedCommands,
    this.enableNetworkAccess = false,
    this.enableFileAccess = false,
  });
}

/// Plugin execution context in sandbox
class PluginExecutionContext {
  final String pluginName;
  final PluginSandboxConfig sandboxConfig;
  final ResourceAllocation? resourceAllocation;
  final Map<String, dynamic> metadata;

  PluginExecutionContext({
    required this.pluginName,
    required this.sandboxConfig,
    this.resourceAllocation,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};
}

/// Enhanced plugin registry with version management and sandboxing
class EnhancedPluginRegistry extends MCPPluginRegistry {
  final Logger _logger = Logger('flutter_mcp.enhanced_plugin_registry');
  final EnhancedTypedEventSystem _eventSystem =
      EnhancedTypedEventSystem.instance;
  final ResourceManager _resourceManager = ResourceManager.instance;

  // SDK version
  static final Version sdkVersion = Version(1, 0, 0);

  // Plugin versions
  final Map<String, PluginVersion> _pluginVersions = {};

  // Plugin sandboxes
  final Map<String, PluginSandboxConfig> _sandboxConfigs = {};

  // Plugin isolates for sandboxing
  final Map<String, Isolate> _pluginIsolates = {};

  // Plugin resource allocations
  final Map<String, ResourceAllocation> _pluginResources = {};

  // Configuration for version checking
  bool strictVersionChecking = true;

  @override
  Future<void> registerPlugin(MCPPlugin plugin,
      [Map<String, dynamic>? config]) async {
    final pluginName = plugin.name;

    // Parse version information
    final versionInfo = _parsePluginVersion(plugin, config);

    // Check SDK compatibility
    if (!versionInfo.isCompatibleWith(sdkVersion)) {
      throw MCPPluginException(
        pluginName,
        'Plugin requires SDK version ${versionInfo.minSdkVersion ?? "any"}-${versionInfo.maxSdkVersion ?? "any"}, but current SDK is $sdkVersion',
      );
    }

    // Check version conflicts if strict checking is enabled
    if (strictVersionChecking) {
      await _checkVersionConflicts(versionInfo);
    }

    // Setup sandbox if configured
    if (config?['sandbox'] != null) {
      final sandboxConfig = _parseSandboxConfig(config!['sandbox']);
      _sandboxConfigs[pluginName] = sandboxConfig;

      // Allocate resources
      if (sandboxConfig.maxMemoryMB != null) {
        final allocation = await _resourceManager.allocateMemory(
          'plugin_$pluginName',
          sandboxConfig.maxMemoryMB!,
        );
        _pluginResources[pluginName] = allocation;
      }
    }

    // Store version info
    _pluginVersions[pluginName] = versionInfo;

    // Register with base class
    await super.registerPlugin(plugin, config);

    // Publish registration event
    await _eventSystem.publish(PluginEvent(
      pluginId: pluginName,
      version: versionInfo.version.toString(),
      state: PluginLifecycleState.initialized,
      message: 'Plugin registered successfully',
      metadata: {
        'sandbox': _sandboxConfigs.containsKey(pluginName),
        'dependencies':
            versionInfo.dependencies.map((k, v) => MapEntry(k, v.toString())),
      },
    ));
  }

  @override
  Future<void> unregisterPlugin(String pluginName) async {
    // Clean up sandbox resources
    if (_pluginIsolates.containsKey(pluginName)) {
      _pluginIsolates[pluginName]!.kill(priority: Isolate.immediate);
      _pluginIsolates.remove(pluginName);
    }

    // Release allocated resources
    if (_pluginResources.containsKey(pluginName)) {
      await _resourceManager.releaseMemory('plugin_$pluginName');
      _pluginResources.remove(pluginName);
    }

    // Remove version and sandbox info
    _pluginVersions.remove(pluginName);
    _sandboxConfigs.remove(pluginName);

    // Unregister with base class
    await super.unregisterPlugin(pluginName);

    // Publish unregistration event
    await _eventSystem.publish(PluginEvent(
      pluginId: pluginName,
      state: PluginLifecycleState.stopped,
      message: 'Plugin unregistered',
    ));
  }

  /// Execute plugin in sandbox
  Future<T> executeInSandbox<T>(
    String pluginName,
    Future<T> Function() operation, {
    Map<String, dynamic>? context,
  }) async {
    final sandboxConfig = _sandboxConfigs[pluginName];
    if (sandboxConfig == null) {
      // No sandbox configured, execute normally
      return await operation();
    }

    // Create execution context (for future use with isolates)
    // final executionContext = PluginExecutionContext(
    //   pluginName: pluginName,
    //   sandboxConfig: sandboxConfig,
    //   resourceAllocation: _pluginResources[pluginName],
    //   metadata: context ?? {},
    // );

    // Execute with timeout if configured
    if (sandboxConfig.executionTimeout != null) {
      try {
        return await operation().timeout(
          sandboxConfig.executionTimeout!,
          onTimeout: () {
            throw MCPPluginException(
              pluginName,
              'Plugin execution timed out after ${sandboxConfig.executionTimeout!.inSeconds} seconds',
            );
          },
        );
      } catch (e) {
        _logger.severe('Plugin execution failed in sandbox', e);
        rethrow;
      }
    }

    return await operation();
  }

  @override
  Future<Map<String, dynamic>> executeTool(
      String name, Map<String, dynamic> arguments) async {
    return await executeInSandbox(
      name,
      () => super.executeTool(name, arguments),
      context: {'operation': 'executeTool', 'arguments': arguments},
    );
  }

  @override
  Future<Map<String, dynamic>> executePrompt(
      String name, Map<String, dynamic> arguments) async {
    return await executeInSandbox(
      name,
      () => super.executePrompt(name, arguments),
      context: {'operation': 'executePrompt', 'arguments': arguments},
    );
  }

  @override
  Future<Map<String, dynamic>> getResource(
    String name,
    String resourceUri,
    Map<String, dynamic> params,
  ) async {
    return await executeInSandbox(
      name,
      () => super.getResource(name, resourceUri, params),
      context: {
        'operation': 'getResource',
        'resourceUri': resourceUri,
        'params': params,
      },
    );
  }

  /// Check for version conflicts
  Future<void> _checkVersionConflicts(PluginVersion newPlugin) async {
    for (final existing in _pluginVersions.entries) {
      final existingName = existing.key;
      final existingVersion = existing.value;

      // Check if new plugin satisfies existing plugin's dependencies
      if (existingVersion.dependencies.containsKey(newPlugin.name)) {
        if (!existingVersion.satisfiesDependency(
            newPlugin.name, newPlugin.version)) {
          throw MCPPluginException(
            newPlugin.name,
            'Version conflict: Plugin "$existingName" requires "${newPlugin.name}" version ${existingVersion.dependencies[newPlugin.name]}, but version ${newPlugin.version} is being registered',
          );
        }
      }

      // Don't check if existing plugins satisfy new plugin's dependencies
      // This allows registering plugins with unmet dependencies
      // The resolveVersionConflicts() method will identify these issues later
    }
  }

  /// Resolve version conflicts by suggesting updates
  List<PluginUpdateSuggestion> resolveVersionConflicts() {
    final suggestions = <PluginUpdateSuggestion>[];

    // Check all plugin dependencies
    for (final plugin in _pluginVersions.entries) {
      for (final dep in plugin.value.dependencies.entries) {
        final depName = dep.key;
        final constraint = dep.value;

        final installedPlugin = _pluginVersions[depName];
        if (installedPlugin != null &&
            !constraint.allows(installedPlugin.version)) {
          suggestions.add(PluginUpdateSuggestion(
            pluginName: depName,
            currentVersion: installedPlugin.version,
            suggestedConstraint: constraint,
            reason: 'Required by ${plugin.key}',
          ));
        }
      }
    }

    return suggestions;
  }

  /// Get plugin version information
  PluginVersion? getPluginVersion(String pluginName) {
    return _pluginVersions[pluginName];
  }

  /// Get all plugin versions
  Map<String, PluginVersion> getAllPluginVersions() {
    return Map.unmodifiable(_pluginVersions);
  }

  /// Get plugin sandbox configuration
  PluginSandboxConfig? getPluginSandboxConfig(String pluginName) {
    return _sandboxConfigs[pluginName];
  }

  /// Update plugin sandbox configuration
  Future<void> updatePluginSandboxConfig(
    String pluginName,
    PluginSandboxConfig config,
  ) async {
    if (!_pluginVersions.containsKey(pluginName)) {
      throw MCPPluginException(pluginName, 'Plugin not registered');
    }

    // Update sandbox config
    _sandboxConfigs[pluginName] = config;

    // Update resource allocation if needed
    if (config.maxMemoryMB != null) {
      if (_pluginResources.containsKey(pluginName)) {
        await _resourceManager.releaseMemory('plugin_$pluginName');
      }

      final allocation = await _resourceManager.allocateMemory(
        'plugin_$pluginName',
        config.maxMemoryMB!,
      );
      _pluginResources[pluginName] = allocation;
    }

    _logger.info('Updated sandbox configuration for plugin: $pluginName');
  }

  /// Parse plugin version from plugin and config
  PluginVersion _parsePluginVersion(
      MCPPlugin plugin, Map<String, dynamic>? config) {
    final versionStr = plugin.version;
    Version version;

    try {
      version = Version.parse(versionStr);
    } catch (e) {
      // Default to 0.0.0 if version parsing fails
      _logger.warning(
          'Failed to parse version "$versionStr" for plugin ${plugin.name}, using 0.0.0');
      version = Version(0, 0, 0);
    }

    Version? minSdk;
    Version? maxSdk;
    final dependencies = <String, VersionConstraint>{};

    if (config != null) {
      // Parse SDK constraints
      if (config['minSdkVersion'] != null) {
        try {
          minSdk = Version.parse(config['minSdkVersion']);
        } catch (e) {
          _logger.warning(
              'Failed to parse minSdkVersion: ${config['minSdkVersion']}');
        }
      }

      if (config['maxSdkVersion'] != null) {
        try {
          maxSdk = Version.parse(config['maxSdkVersion']);
        } catch (e) {
          _logger.warning(
              'Failed to parse maxSdkVersion: ${config['maxSdkVersion']}');
        }
      }

      // Parse dependencies
      if (config['dependencies'] is Map) {
        final deps = config['dependencies'] as Map<String, dynamic>;
        for (final entry in deps.entries) {
          try {
            dependencies[entry.key] =
                VersionConstraint.parse(entry.value.toString());
          } catch (e) {
            _logger.warning(
                'Failed to parse dependency constraint for ${entry.key}: ${entry.value}');
          }
        }
      }
    }

    return PluginVersion(
      name: plugin.name,
      version: version,
      minSdkVersion: minSdk,
      maxSdkVersion: maxSdk,
      dependencies: dependencies,
    );
  }

  /// Parse sandbox configuration
  PluginSandboxConfig _parseSandboxConfig(dynamic sandboxConfig) {
    if (sandboxConfig is PluginSandboxConfig) {
      return sandboxConfig;
    }

    if (sandboxConfig is Map<String, dynamic>) {
      Duration? timeout;
      if (sandboxConfig['executionTimeoutMs'] != null) {
        timeout = Duration(milliseconds: sandboxConfig['executionTimeoutMs']);
      }

      return PluginSandboxConfig(
        executionTimeout: timeout,
        maxMemoryMB: sandboxConfig['maxMemoryMB'],
        allowedPaths: sandboxConfig['allowedPaths'] != null
            ? List<String>.from(sandboxConfig['allowedPaths'])
            : null,
        allowedCommands: sandboxConfig['allowedCommands'] != null
            ? List<String>.from(sandboxConfig['allowedCommands'])
            : null,
        enableNetworkAccess: sandboxConfig['enableNetworkAccess'] ?? false,
        enableFileAccess: sandboxConfig['enableFileAccess'] ?? false,
      );
    }

    return PluginSandboxConfig();
  }
}

/// Plugin update suggestion
class PluginUpdateSuggestion {
  final String pluginName;
  final Version currentVersion;
  final VersionConstraint suggestedConstraint;
  final String reason;

  PluginUpdateSuggestion({
    required this.pluginName,
    required this.currentVersion,
    required this.suggestedConstraint,
    required this.reason,
  });

  @override
  String toString() {
    return 'Update $pluginName from $currentVersion to satisfy $suggestedConstraint ($reason)';
  }
}

/// Plugin isolation helper for running plugins in separate isolates
class PluginIsolationHelper {
  // Removed unused _logger field

  /// Run plugin operation in isolated environment
  static Future<T> runIsolated<T>({
    required String pluginName,
    required Future<T> Function() operation,
    required PluginSandboxConfig sandboxConfig,
    Map<String, dynamic>? context,
  }) async {
    // Note: Full isolate implementation would require serializable plugin interfaces
    // For now, we just apply timeouts and basic constraints

    if (sandboxConfig.executionTimeout != null) {
      return await operation().timeout(
        sandboxConfig.executionTimeout!,
        onTimeout: () {
          throw MCPPluginException(
            pluginName,
            'Plugin operation timed out',
          );
        },
      );
    }

    return await operation();
  }
}
