# Platform Guides

Flutter MCP supports multiple platforms with platform-specific optimizations and features. Choose your platform to learn more:

## Supported Platforms

### Mobile
- [Android](android.md) - Android-specific implementation details
- [iOS](ios.md) - iOS-specific implementation details

### Desktop
- [macOS](macos.md) - macOS desktop support
- [Windows](windows.md) - Windows desktop support
- [Linux](linux.md) - Linux desktop support

### Web
- [Web](web.md) - Web platform support

## Platform Feature Matrix

| Feature | Android | iOS | macOS | Windows | Linux | Web |
|---------|---------|-----|-------|---------|-------|-----|
| Background Service | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Local Notifications | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| System Tray | ❌ | ❌ | ✅ | ✅ | ✅ | ❌ |
| Secure Storage | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Process Management | ✅ | ⚠️ | ✅ | ✅ | ✅ | ❌ |
| File System Access | ✅ | ⚠️ | ✅ | ✅ | ✅ | ⚠️ |

Legend:
- ✅ Full support
- ⚠️ Limited support
- ❌ Not supported

## Platform-Specific Considerations

### Mobile Platforms
- Battery optimization
- Background execution limits
- App lifecycle management
- Push notification integration

### Desktop Platforms
- System tray integration
- Native menu support
- Window management
- File system integration

### Web Platform
- Browser limitations
- Service worker support
- Storage quotas
- CORS restrictions

## Common Tasks

### Background Execution
Each platform has different limitations and capabilities for background execution:
- Android: Foreground services and WorkManager
- iOS: Background fetch and processing tasks
- Desktop: Unrestricted background execution
- Web: Service workers with limitations

### Notifications
Local notifications work differently across platforms:
- Mobile: Native notification centers
- Desktop: System notification APIs
- Web: Browser notification API

### Storage
Secure storage implementations vary:
- Mobile: Keychain (iOS) and Keystore (Android)
- Desktop: Platform-specific secure storage
- Web: IndexedDB with encryption

## Choosing the Right Platform

Consider these factors when choosing target platforms:

1. **User Base**: Where are your users?
2. **Feature Requirements**: Which platform features do you need?
3. **Development Resources**: Platform-specific expertise
4. **Maintenance**: Long-term support considerations

## Platform-Specific Development

### Development Environment
Each platform may require specific tools:
- Android: Android Studio
- iOS: Xcode (macOS only)
- macOS: Xcode
- Windows: Visual Studio
- Linux: Various IDEs
- Web: Any modern browser

### Testing
Platform-specific testing considerations:
- Mobile: Device farms and simulators
- Desktop: Virtual machines
- Web: Browser compatibility testing

## Next Steps

Choose your platform guide:
- [Android Guide](android.md)
- [iOS Guide](ios.md)
- [macOS Guide](macos.md)
- [Windows Guide](windows.md)
- [Linux Guide](linux.md)
- [Web Guide](web.md)