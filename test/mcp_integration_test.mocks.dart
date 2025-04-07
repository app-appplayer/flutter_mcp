// Mocks generated by Mockito 5.4.5 from annotations
// in flutter_mcp/test/mcp_integration_test.dart.
// Do not manually edit this file.

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i4;

import 'package:flutter_mcp/src/config/mcp_config.dart' as _i5;
import 'package:flutter_mcp/src/platform/platform_services.dart' as _i2;
import 'package:flutter_mcp/src/platform/tray/tray_manager.dart' as _i6;
import 'package:mockito/mockito.dart' as _i1;
import 'package:mockito/src/dummies.dart' as _i3;

// ignore_for_file: type=lint
// ignore_for_file: avoid_redundant_argument_values
// ignore_for_file: avoid_setters_without_getters
// ignore_for_file: comment_references
// ignore_for_file: deprecated_member_use
// ignore_for_file: deprecated_member_use_from_same_package
// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: must_be_immutable
// ignore_for_file: prefer_const_constructors
// ignore_for_file: unnecessary_parenthesis
// ignore_for_file: camel_case_types
// ignore_for_file: subtype_of_sealed_class

/// A class which mocks [PlatformServices].
///
/// See the documentation for Mockito's code generation for more information.
class MockPlatformServices extends _i1.Mock implements _i2.PlatformServices {
  MockPlatformServices() {
    _i1.throwOnMissingStub(this);
  }

  @override
  bool get isBackgroundServiceRunning =>
      (super.noSuchMethod(
            Invocation.getter(#isBackgroundServiceRunning),
            returnValue: false,
          )
          as bool);

  @override
  String get platformName =>
      (super.noSuchMethod(
            Invocation.getter(#platformName),
            returnValue: _i3.dummyValue<String>(
              this,
              Invocation.getter(#platformName),
            ),
          )
          as String);

  @override
  _i4.Future<void> initialize(_i5.MCPConfig? config) =>
      (super.noSuchMethod(
            Invocation.method(#initialize, [config]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<bool> startBackgroundService() =>
      (super.noSuchMethod(
            Invocation.method(#startBackgroundService, []),
            returnValue: _i4.Future<bool>.value(false),
          )
          as _i4.Future<bool>);

  @override
  _i4.Future<bool> stopBackgroundService() =>
      (super.noSuchMethod(
            Invocation.method(#stopBackgroundService, []),
            returnValue: _i4.Future<bool>.value(false),
          )
          as _i4.Future<bool>);

  @override
  _i4.Future<void> showNotification({
    required String? title,
    required String? body,
    String? icon,
    String? id = 'mcp_notification',
  }) =>
      (super.noSuchMethod(
            Invocation.method(#showNotification, [], {
              #title: title,
              #body: body,
              #icon: icon,
              #id: id,
            }),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<void> hideNotification(String? id) =>
      (super.noSuchMethod(
            Invocation.method(#hideNotification, [id]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<void> secureStore(String? key, String? value) =>
      (super.noSuchMethod(
            Invocation.method(#secureStore, [key, value]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<String?> secureRead(String? key) =>
      (super.noSuchMethod(
            Invocation.method(#secureRead, [key]),
            returnValue: _i4.Future<String?>.value(),
          )
          as _i4.Future<String?>);

  @override
  _i4.Future<bool> secureDelete(String? key) =>
      (super.noSuchMethod(
            Invocation.method(#secureDelete, [key]),
            returnValue: _i4.Future<bool>.value(false),
          )
          as _i4.Future<bool>);

  @override
  _i4.Future<bool> secureContains(String? key) =>
      (super.noSuchMethod(
            Invocation.method(#secureContains, [key]),
            returnValue: _i4.Future<bool>.value(false),
          )
          as _i4.Future<bool>);

  @override
  _i4.Future<void> setTrayMenu(List<_i6.TrayMenuItem>? items) =>
      (super.noSuchMethod(
            Invocation.method(#setTrayMenu, [items]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<void> setTrayIcon(String? path) =>
      (super.noSuchMethod(
            Invocation.method(#setTrayIcon, [path]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  _i4.Future<void> setTrayTooltip(String? tooltip) =>
      (super.noSuchMethod(
            Invocation.method(#setTrayTooltip, [tooltip]),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);

  @override
  void setLifecycleChangeListener(dynamic Function(dynamic)? listener) =>
      super.noSuchMethod(
        Invocation.method(#setLifecycleChangeListener, [listener]),
        returnValueForMissingStub: null,
      );

  @override
  _i4.Future<void> shutdown() =>
      (super.noSuchMethod(
            Invocation.method(#shutdown, []),
            returnValue: _i4.Future<void>.value(),
            returnValueForMissingStub: _i4.Future<void>.value(),
          )
          as _i4.Future<void>);
}
