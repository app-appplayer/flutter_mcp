import '../config/mcp_config.dart';
import '../config/background_config.dart';
import '../config/notification_config.dart';

/// Base class for all platform messages
abstract class PlatformMessage {
  const PlatformMessage();

  /// Convert to method name and arguments for MethodChannel
  String get method;
  Map<String, dynamic>? get arguments => null;

  /// Factory method to create from method call
  static PlatformMessage? fromMethodCall(String method, dynamic arguments) {
    // This is a placeholder for when proper JSON deserialization is implemented
    // Currently, we don't have fromJson methods in config classes
    switch (method) {
      case 'stopBackgroundService':
        return const StopBackgroundServiceMessage();
      case 'executeBackgroundTask':
        final args = arguments as Map<String, dynamic>;
        return ExecuteBackgroundTaskMessage(
          taskId: args['taskId'] as String,
          data: args['data'] as Map<String, dynamic>,
        );
      default:
        return null;
    }
  }
}

/// Initialize platform services
class InitializeMessage extends PlatformMessage {
  final MCPConfig config;

  const InitializeMessage({required this.config});

  @override
  String get method => 'initialize';

  @override
  Map<String, dynamic> get arguments => {
        // Placeholder - config.toJson() doesn't exist yet
        'name': 'config_placeholder',
      };
}

/// Start background service
class StartBackgroundServiceMessage extends PlatformMessage {
  final BackgroundConfig? config;

  const StartBackgroundServiceMessage({this.config});

  @override
  String get method => 'startBackgroundService';

  @override
  Map<String, dynamic>? get arguments => config != null
      ? {
          // Placeholder - config.toJson() doesn't exist yet
          'type': 'background_config_placeholder',
        }
      : null;
}

/// Stop background service
class StopBackgroundServiceMessage extends PlatformMessage {
  const StopBackgroundServiceMessage();

  @override
  String get method => 'stopBackgroundService';
}

/// Show notification
class ShowNotificationMessage extends PlatformMessage {
  final String id;
  final String title;
  final String body;
  final NotificationConfig? config;

  const ShowNotificationMessage({
    required this.id,
    required this.title,
    required this.body,
    this.config,
  });

  @override
  String get method => 'showNotification';

  @override
  Map<String, dynamic> get arguments => {
        'id': id,
        'title': title,
        'body': body,
        if (config != null)
          'config': {'type': 'notification_config_placeholder'},
      };
}

/// Cancel notification
class CancelNotificationMessage extends PlatformMessage {
  final String id;

  const CancelNotificationMessage({required this.id});

  @override
  String get method => 'cancelNotification';

  @override
  Map<String, dynamic> get arguments => {'id': id};
}

/// Show tray icon
class ShowTrayIconMessage extends PlatformMessage {
  final String iconPath;
  final String? tooltip;
  final List<TrayMenuItem>? menu;

  const ShowTrayIconMessage({
    required this.iconPath,
    this.tooltip,
    this.menu,
  });

  @override
  String get method => 'showTrayIcon';

  @override
  Map<String, dynamic> get arguments => {
        'iconPath': iconPath,
        if (tooltip != null) 'tooltip': tooltip,
        if (menu != null) 'menu': menu!.map((item) => item.toJson()).toList(),
      };
}

/// Hide tray icon
class HideTrayIconMessage extends PlatformMessage {
  const HideTrayIconMessage();

  @override
  String get method => 'hideTrayIcon';
}

/// Update tray menu
class UpdateTrayMenuMessage extends PlatformMessage {
  final List<TrayMenuItem> menu;

  const UpdateTrayMenuMessage({required this.menu});

  @override
  String get method => 'updateTrayMenu';

  @override
  Map<String, dynamic> get arguments => {
        'menu': menu.map((item) => item.toJson()).toList(),
      };
}

/// Execute background task
class ExecuteBackgroundTaskMessage extends PlatformMessage {
  final String taskId;
  final Map<String, dynamic> data;

  const ExecuteBackgroundTaskMessage({
    required this.taskId,
    required this.data,
  });

  @override
  String get method => 'executeBackgroundTask';

  @override
  Map<String, dynamic> get arguments => {
        'taskId': taskId,
        'data': data,
      };
}

/// Request permission
class RequestPermissionMessage extends PlatformMessage {
  final String permission;
  final String? rationale;

  const RequestPermissionMessage({
    required this.permission,
    this.rationale,
  });

  @override
  String get method => 'requestPermission';

  @override
  Map<String, dynamic> get arguments => {
        'permission': permission,
        if (rationale != null) 'rationale': rationale,
      };
}

/// Check permission
class CheckPermissionMessage extends PlatformMessage {
  final String permission;

  const CheckPermissionMessage({required this.permission});

  @override
  String get method => 'checkPermission';

  @override
  Map<String, dynamic> get arguments => {'permission': permission};
}

/// Secure store
class SecureStoreMessage extends PlatformMessage {
  final String key;
  final String value;

  const SecureStoreMessage({
    required this.key,
    required this.value,
  });

  @override
  String get method => 'secureStore';

  @override
  Map<String, dynamic> get arguments => {
        'key': key,
        'value': value,
      };
}

/// Secure retrieve
class SecureRetrieveMessage extends PlatformMessage {
  final String key;

  const SecureRetrieveMessage({required this.key});

  @override
  String get method => 'secureRetrieve';

  @override
  Map<String, dynamic> get arguments => {'key': key};
}

/// Secure delete
class SecureDeleteMessage extends PlatformMessage {
  final String key;

  const SecureDeleteMessage({required this.key});

  @override
  String get method => 'secureDelete';

  @override
  Map<String, dynamic> get arguments => {'key': key};
}

/// Get system info
class GetSystemInfoMessage extends PlatformMessage {
  const GetSystemInfoMessage();

  @override
  String get method => 'getSystemInfo';
}

/// Log event
class LogEventMessage extends PlatformMessage {
  final String event;
  final Map<String, dynamic>? parameters;

  const LogEventMessage({
    required this.event,
    this.parameters,
  });

  @override
  String get method => 'logEvent';

  @override
  Map<String, dynamic> get arguments => {
        'event': event,
        if (parameters != null) 'parameters': parameters,
      };
}

/// Perform health check
class PerformHealthCheckMessage extends PlatformMessage {
  final List<String>? components;

  const PerformHealthCheckMessage({this.components});

  @override
  String get method => 'performHealthCheck';

  @override
  Map<String, dynamic>? get arguments =>
      components != null ? {'components': components} : null;
}

/// Base class for platform responses
abstract class PlatformResponse {
  const PlatformResponse();

  /// Check if response is successful
  bool get isSuccess;

  /// Check if response is error
  bool get isError => !isSuccess;

  /// Convert to JSON
  Map<String, dynamic> toJson();

  /// Factory method to create from platform response
  static PlatformResponse fromPlatformResponse(dynamic response) {
    if (response == null) {
      return const SuccessResponse();
    }

    if (response is Map<String, dynamic>) {
      if (response.containsKey('error')) {
        return ErrorResponse(
          code: response['error']['code'] as String? ?? 'unknown',
          message: response['error']['message'] as String? ?? 'Unknown error',
          details: response['error']['details'],
        );
      }

      if (response.containsKey('permission')) {
        return PermissionResponse(
          permission: response['permission'] as String,
          granted: response['granted'] as bool,
          reason: response['reason'] as String?,
        );
      }

      if (response.containsKey('platform')) {
        return SystemInfoResponse(
          platform: response['platform'] as String,
          version: response['version'] as String,
          capabilities: response['capabilities'] as Map<String, dynamic>,
        );
      }

      if (response.containsKey('status') &&
          response.containsKey('components')) {
        return HealthCheckResponse(
          status: response['status'] as String,
          components: response['components'] as Map<String, dynamic>,
        );
      }
    }

    return SuccessResponse(data: response);
  }
}

/// Success response
class SuccessResponse extends PlatformResponse {
  final dynamic data;
  final String? message;

  const SuccessResponse({this.data, this.message});

  @override
  bool get isSuccess => true;

  @override
  Map<String, dynamic> toJson() => {
        'success': true,
        if (data != null) 'data': data,
        if (message != null) 'message': message,
      };
}

/// Error response
class ErrorResponse extends PlatformResponse {
  final String code;
  final String message;
  final dynamic details;

  const ErrorResponse({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  bool get isSuccess => false;

  @override
  Map<String, dynamic> toJson() => {
        'success': false,
        'error': {
          'code': code,
          'message': message,
          if (details != null) 'details': details,
        },
      };
}

/// Permission response
class PermissionResponse extends PlatformResponse {
  final String permission;
  final bool granted;
  final String? reason;

  const PermissionResponse({
    required this.permission,
    required this.granted,
    this.reason,
  });

  @override
  bool get isSuccess => true;

  @override
  Map<String, dynamic> toJson() => {
        'permission': permission,
        'granted': granted,
        if (reason != null) 'reason': reason,
      };
}

/// System info response
class SystemInfoResponse extends PlatformResponse {
  final String platform;
  final String version;
  final Map<String, dynamic> capabilities;

  const SystemInfoResponse({
    required this.platform,
    required this.version,
    required this.capabilities,
  });

  @override
  bool get isSuccess => true;

  @override
  Map<String, dynamic> toJson() => {
        'platform': platform,
        'version': version,
        'capabilities': capabilities,
      };
}

/// Health check response
class HealthCheckResponse extends PlatformResponse {
  final String status;
  final Map<String, dynamic> components;

  const HealthCheckResponse({
    required this.status,
    required this.components,
  });

  @override
  bool get isSuccess => true;

  @override
  Map<String, dynamic> toJson() => {
        'status': status,
        'components': components,
      };
}

/// Type-safe tray menu item
class TrayMenuItem {
  final String id;
  final String label;
  final String? iconPath;
  final bool disabled;
  final bool checked;
  final List<TrayMenuItem>? submenu;
  final String? shortcut;

  const TrayMenuItem({
    required this.id,
    required this.label,
    this.iconPath,
    this.disabled = false,
    this.checked = false,
    this.submenu,
    this.shortcut,
  });

  /// Create a separator menu item
  factory TrayMenuItem.separator() => const TrayMenuItem(
        id: 'separator',
        label: '-',
      );

  /// Check if this is a separator
  bool get isSeparator => label == '-';

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (iconPath != null) 'iconPath': iconPath,
        'disabled': disabled,
        'checked': checked,
        if (submenu != null)
          'submenu': submenu!.map((item) => item.toJson()).toList(),
        if (shortcut != null) 'shortcut': shortcut,
      };

  /// Create from JSON
  factory TrayMenuItem.fromJson(Map<String, dynamic> json) => TrayMenuItem(
        id: json['id'] as String,
        label: json['label'] as String,
        iconPath: json['iconPath'] as String?,
        disabled: json['disabled'] as bool? ?? false,
        checked: json['checked'] as bool? ?? false,
        submenu: (json['submenu'] as List<dynamic>?)
            ?.map((item) => TrayMenuItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        shortcut: json['shortcut'] as String?,
      );
}
