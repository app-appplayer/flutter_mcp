# iOS Integration

Complete guide for iOS-specific Flutter MCP features.

## Overview

This example demonstrates iOS-specific features and integrations for Flutter MCP:
- iOS background execution
- Push notifications via APNs
- Native iOS APIs
- App Extensions
- SwiftUI integration

## Features

### Background Execution

iOS background execution with Background Tasks and Background Modes.

#### Swift Implementation

```swift
// ios/Runner/BackgroundTaskHandler.swift
import BackgroundTasks
import Flutter

class BackgroundTaskHandler {
    static let taskIdentifier = "com.example.mcpBackgroundTask"
    
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    static func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh() // Schedule the next refresh
        
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = 1
        
        let operation = BlockOperation {
            // Call Flutter method
            DispatchQueue.main.async {
                guard let controller = UIApplication.shared.keyWindow?.rootViewController as? FlutterViewController else {
                    return
                }
                
                let channel = FlutterMethodChannel(
                    name: "com.example.flutter_mcp/background",
                    binaryMessenger: controller.binaryMessenger
                )
                
                channel.invokeMethod("executeBackgroundTask", arguments: nil) { result in
                    if let error = result as? FlutterError {
                        print("Background task error: \(error.message ?? "")")
                    }
                    task.setTaskCompleted(success: error == nil)
                }
            }
        }
        
        task.expirationHandler = {
            operations.cancelAllOperations()
        }
        
        operations.addOperation(operation)
    }
}

// AppDelegate.swift
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register background tasks
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskHandler.taskIdentifier,
            using: nil
        ) { task in
            BackgroundTaskHandler.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

### Push Notifications

Apple Push Notification service (APNs) integration.

```swift
// ios/Runner/NotificationService.swift
import UserNotifications
import Flutter

class NotificationService: NSObject {
    static let shared = NotificationService()
    private var channel: FlutterMethodChannel?
    
    func setup(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.example.flutter_mcp/notifications",
            binaryMessenger: messenger
        )
        
        channel?.setMethodCallHandler { call, result in
            switch call.method {
            case "requestPermission":
                self.requestNotificationPermission(result: result)
            case "scheduleNotification":
                if let args = call.arguments as? [String: Any] {
                    self.scheduleLocalNotification(args: args, result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func requestNotificationPermission(result: @escaping FlutterResult) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                result(FlutterError(
                    code: "PERMISSION_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            } else {
                result(granted)
            }
        }
    }
    
    private func scheduleLocalNotification(args: [String: Any], result: @escaping FlutterResult) {
        let content = UNMutableNotificationContent()
        content.title = args["title"] as? String ?? ""
        content.body = args["body"] as? String ?? ""
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: args["delay"] as? TimeInterval ?? 1,
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                result(FlutterError(
                    code: "NOTIFICATION_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            } else {
                result(nil)
            }
        }
    }
}

extension AppDelegate {
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        // Send token to Flutter
        channel?.invokeMethod("onTokenReceived", arguments: token)
    }
    
    override func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle remote notification
        channel?.invokeMethod("onMessageReceived", arguments: userInfo)
        completionHandler(.newData)
    }
}
```

### Native iOS APIs

Integration with native iOS frameworks.

```swift
// ios/Runner/NativeAPIBridge.swift
import CoreLocation
import HealthKit
import Photos
import Flutter

class NativeAPIBridge: NSObject {
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var channel: FlutterMethodChannel?
    
    func setup(with messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "com.example.flutter_mcp/native",
            binaryMessenger: messenger
        )
        
        channel?.setMethodCallHandler { call, result in
            switch call.method {
            case "getCurrentLocation":
                self.getCurrentLocation(result: result)
            case "requestHealthData":
                self.requestHealthData(result: result)
            case "saveToPhotoLibrary":
                if let args = call.arguments as? [String: Any] {
                    self.saveToPhotoLibrary(args: args, result: result)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private func getCurrentLocation(result: @escaping FlutterResult) {
        locationManager.requestWhenInUseAuthorization()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let location = self.locationManager.location {
                result([
                    "latitude": location.coordinate.latitude,
                    "longitude": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy
                ])
            } else {
                result(FlutterError(
                    code: "LOCATION_ERROR",
                    message: "Could not get location",
                    details: nil
                ))
            }
            self.locationManager.stopUpdatingLocation()
        }
    }
    
    private func requestHealthData(result: @escaping FlutterResult) {
        guard HKHealthStore.isHealthDataAvailable() else {
            result(FlutterError(
                code: "HEALTH_UNAVAILABLE",
                message: "Health data is not available",
                details: nil
            ))
            return
        }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let readTypes: Set<HKObjectType> = [stepType]
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            if success {
                self.fetchStepCount(result: result)
            } else {
                result(FlutterError(
                    code: "HEALTH_ERROR",
                    message: error?.localizedDescription ?? "Unknown error",
                    details: nil
                ))
            }
        }
    }
    
    private func fetchStepCount(result: @escaping FlutterResult) {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if let error = error {
                result(FlutterError(
                    code: "HEALTH_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            } else if let sum = statistics?.sumQuantity() {
                let steps = sum.doubleValue(for: HKUnit.count())
                result(["steps": steps])
            } else {
                result(["steps": 0])
            }
        }
        
        healthStore.execute(query)
    }
    
    private func saveToPhotoLibrary(args: [String: Any], result: @escaping FlutterResult) {
        guard let imagePath = args["path"] as? String,
              let image = UIImage(contentsOfFile: imagePath) else {
            result(FlutterError(
                code: "INVALID_IMAGE",
                message: "Invalid image path",
                details: nil
            ))
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { success, error in
                    if success {
                        result(nil)
                    } else {
                        result(FlutterError(
                            code: "SAVE_ERROR",
                            message: error?.localizedDescription ?? "Unknown error",
                            details: nil
                        ))
                    }
                }
            } else {
                result(FlutterError(
                    code: "PERMISSION_DENIED",
                    message: "Photo library access denied",
                    details: nil
                ))
            }
        }
    }
}
```

### App Extensions

Widget and notification service extensions.

```swift
// ios/MCPWidget/MCPWidget.swift
import WidgetKit
import SwiftUI

struct MCPEntry: TimelineEntry {
    let date: Date
    let status: String
    let serverCount: Int
    let activeJobs: Int
}

struct MCPWidgetEntryView: View {
    var entry: MCPEntry
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("MCP Status")
                .font(.headline)
            
            HStack {
                Image(systemName: "server.rack")
                Text("\(entry.serverCount) servers")
            }
            
            HStack {
                Image(systemName: "gearshape.fill")
                Text("\(entry.activeJobs) active jobs")
            }
            
            Text(entry.status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct MCPWidget: Widget {
    let kind: String = "MCPWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MCPProvider()) { entry in
            MCPWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("MCP Status")
        .description("Monitor your MCP servers")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MCPProvider: TimelineProvider {
    func placeholder(in context: Context) -> MCPEntry {
        MCPEntry(date: Date(), status: "Loading...", serverCount: 0, activeJobs: 0)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (MCPEntry) -> ()) {
        let entry = MCPEntry(date: Date(), status: "Connected", serverCount: 3, activeJobs: 2)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<MCPEntry>) -> ()) {
        var entries: [MCPEntry] = []
        
        // Generate timeline entries for the next hour
        let currentDate = Date()
        for minuteOffset in 0 ..< 60 where minuteOffset % 15 == 0 {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: currentDate)!
            let entry = MCPEntry(
                date: entryDate,
                status: "Connected",
                serverCount: 3,
                activeJobs: Int.random(in: 0...5)
            )
            entries.append(entry)
        }
        
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }
}
```

### SwiftUI Integration

Using Flutter with SwiftUI views.

```swift
// ios/Runner/SwiftUIIntegration.swift
import SwiftUI
import Flutter

struct MCPSettingsView: View {
    @Binding var serverUrl: String
    @Binding var apiKey: String
    var onSave: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Configuration")) {
                    TextField("Server URL", text: $serverUrl)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    
                    SecureField("API Key", text: $apiKey)
                }
                
                Section {
                    Button("Save Configuration") {
                        onSave()
                    }
                    .foregroundColor(.accentColor)
                }
            }
            .navigationTitle("MCP Settings")
        }
    }
}

class SwiftUIViewController: UIHostingController<MCPSettingsView> {
    private let channel: FlutterMethodChannel
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
        
        var serverUrl = ""
        var apiKey = ""
        
        let settingsView = MCPSettingsView(
            serverUrl: Binding(
                get: { serverUrl },
                set: { serverUrl = $0 }
            ),
            apiKey: Binding(
                get: { apiKey },
                set: { apiKey = $0 }
            ),
            onSave: {
                channel.invokeMethod("saveConfiguration", arguments: [
                    "serverUrl": serverUrl,
                    "apiKey": apiKey
                ])
            }
        )
        
        super.init(rootView: settingsView)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// Integration in Flutter
class SwiftUIIntegrationPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.example.flutter_mcp/swiftui",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = SwiftUIIntegrationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "openSwiftUISettings":
            openSwiftUISettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func openSwiftUISettings(result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            guard let viewController = UIApplication.shared.keyWindow?.rootViewController else {
                result(FlutterError(
                    code: "NO_VIEWCONTROLLER",
                    message: "No view controller available",
                    details: nil
                ))
                return
            }
            
            let channel = FlutterMethodChannel(
                name: "com.example.flutter_mcp/swiftui",
                binaryMessenger: viewController as! FlutterBinaryMessenger
            )
            
            let swiftUIController = SwiftUIViewController(channel: channel)
            viewController.present(swiftUIController, animated: true)
            result(nil)
        }
    }
}
```

## Flutter Integration

### Background Task Handler

```dart
// lib/ios_integration.dart
import 'package:flutter/services.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

class IOSIntegration {
  static const _backgroundChannel = MethodChannel('com.example.flutter_mcp/background');
  static const _notificationChannel = MethodChannel('com.example.flutter_mcp/notifications');
  static const _nativeChannel = MethodChannel('com.example.flutter_mcp/native');
  static const _swiftUIChannel = MethodChannel('com.example.flutter_mcp/swiftui');
  
  void setupBackgroundTasks() {
    _backgroundChannel.setMethodCallHandler((call) async {
      if (call.method == 'executeBackgroundTask') {
        await _handleBackgroundTask();
      }
    });
  }
  
  Future<void> _handleBackgroundTask() async {
    final mcp = FlutterMCP();
    
    try {
      // Execute background MCP operations
      await mcp.client.executeBackgroundTask(
        'dataSync',
        parameters: {
          'action': 'sync',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      print('Background task error: $e');
    }
  }
  
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await _notificationChannel.invokeMethod('requestPermission');
      return result as bool;
    } catch (e) {
      print('Permission error: $e');
      return false;
    }
  }
  
  Future<void> scheduleNotification({
    required String title,
    required String body,
    Duration delay = const Duration(seconds: 5),
  }) async {
    try {
      await _notificationChannel.invokeMethod('scheduleNotification', {
        'title': title,
        'body': body,
        'delay': delay.inSeconds.toDouble(),
      });
    } catch (e) {
      print('Notification error: $e');
    }
  }
  
  Future<Map<String, double>> getCurrentLocation() async {
    try {
      final result = await _nativeChannel.invokeMethod('getCurrentLocation');
      return Map<String, double>.from(result as Map);
    } catch (e) {
      print('Location error: $e');
      return {};
    }
  }
  
  Future<int> getTodayStepCount() async {
    try {
      final result = await _nativeChannel.invokeMethod('requestHealthData');
      final data = Map<String, dynamic>.from(result as Map);
      return (data['steps'] as num).toInt();
    } catch (e) {
      print('Health data error: $e');
      return 0;
    }
  }
  
  Future<void> openSwiftUISettings() async {
    try {
      await _swiftUIChannel.invokeMethod('openSwiftUISettings');
    } catch (e) {
      print('SwiftUI error: $e');
    }
  }
}
```

### Usage Example

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_mcp/flutter_mcp.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MCP iOS Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const IOSDemoScreen(),
    );
  }
}

class IOSDemoScreen extends StatefulWidget {
  const IOSDemoScreen({Key? key}) : super(key: key);

  @override
  State<IOSDemoScreen> createState() => _IOSDemoScreenState();
}

class _IOSDemoScreenState extends State<IOSDemoScreen> {
  final _integration = IOSIntegration();
  final _mcp = FlutterMCP();
  String _status = 'Not connected';
  Map<String, double> _location = {};
  int _stepCount = 0;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }
  
  Future<void> _initializeServices() async {
    _integration.setupBackgroundTasks();
    
    await _mcp.initialize(
      config: McpConfig(
        servers: [
          ServerConfig(
            id: 'ios-server',
            url: 'ws://localhost:8080',
          ),
        ],
      ),
    );
    
    await _integration.requestNotificationPermission();
    
    setState(() {
      _status = 'Connected';
    });
  }
  
  Future<void> _getLocation() async {
    final location = await _integration.getCurrentLocation();
    setState(() {
      _location = location;
    });
  }
  
  Future<void> _getHealthData() async {
    final steps = await _integration.getTodayStepCount();
    setState(() {
      _stepCount = steps;
    });
  }
  
  Future<void> _scheduleNotification() async {
    await _integration.scheduleNotification(
      title: 'MCP Update',
      body: 'Background sync completed',
      delay: Duration(seconds: 10),
    );
  }
  
  Future<void> _openSettings() async {
    await _integration.openSwiftUISettings();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('iOS Integration Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                title: Text('Status'),
                subtitle: Text(_status),
                leading: Icon(
                  Icons.circle,
                  color: _status == 'Connected' ? Colors.green : Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            if (_location.isNotEmpty)
              Card(
                child: ListTile(
                  title: Text('Location'),
                  subtitle: Text(
                    'Lat: ${_location['latitude']?.toStringAsFixed(4)}, '
                    'Lng: ${_location['longitude']?.toStringAsFixed(4)}',
                  ),
                  leading: Icon(Icons.location_on),
                ),
              ),
            
            if (_stepCount > 0)
              Card(
                child: ListTile(
                  title: Text('Today\'s Steps'),
                  subtitle: Text('$_stepCount steps'),
                  leading: Icon(Icons.directions_walk),
                ),
              ),
            
            const Spacer(),
            
            ElevatedButton.icon(
              icon: Icon(Icons.location_searching),
              label: Text('Get Location'),
              onPressed: _getLocation,
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              icon: Icon(Icons.favorite),
              label: Text('Get Health Data'),
              onPressed: _getHealthData,
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              icon: Icon(Icons.notifications),
              label: Text('Schedule Notification'),
              onPressed: _scheduleNotification,
            ),
            const SizedBox(height: 8),
            
            ElevatedButton.icon(
              icon: Icon(Icons.settings),
              label: Text('Open SwiftUI Settings'),
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }
}
```

## Configuration

### Info.plist

```xml
<!-- ios/Runner/Info.plist -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
    <string>remote-notification</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.example.mcpBackgroundTask</string>
</array>

<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to provide location-based MCP services</string>

<key>NSHealthShareUsageDescription</key>
<string>This app needs health data access to sync with your MCP health services</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app needs photo library access to save generated images</string>

<key>NSUserNotificationsUsageDescription</key>
<string>This app needs notification permissions to alert you about MCP updates</string>
```

### Podfile Configuration

```ruby
# ios/Podfile
platform :ios, '13.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # Add any additional pods here
  pod 'SwiftProtobuf', '~> 1.0'
end

target 'MCPWidget' do
  use_frameworks!
  use_modular_headers!
  
  # Widget extension pods
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
```

## Troubleshooting

### Common Issues

1. **Background Tasks Not Running**
   - Ensure BGTaskSchedulerPermittedIdentifiers includes your task identifier
   - Background tasks require device to be idle and connected to power
   - Test using Xcode's Background Task Debugger

2. **Push Notifications Not Working**
   - Verify APNs certificates are properly configured
   - Check notification permissions in Settings
   - Ensure proper provisioning profile with Push Notifications capability

3. **Health Data Access Issues**
   - Health data requires actual device (not simulator)
   - User must grant permissions in Settings > Health
   - Some data types require additional permissions

4. **SwiftUI Integration Crashes**
   - Ensure minimum iOS deployment target is 13.0+
   - Add SwiftUI framework to your project
   - Check for proper view controller hierarchy

## See Also

- [Platform-Specific Code](/doc/platform-specific.md)
- [Background Execution](/doc/advanced/background-execution.md)
- [Security](/doc/advanced/security.md)
- [Desktop Applications](/doc/examples/desktop-applications.md)