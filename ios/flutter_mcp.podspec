#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_mcp.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_mcp'
  s.version          = '1.0.0'
  s.summary          = 'Flutter plugin that integrates MCP into a unified agent system.'
  s.description      = <<-DESC
Flutter plugin that integrates MCP server, client, and LLM into a unified agent system.
Provides background execution, notification, system tray, lifecycle management,
secure data storage, and scheduling for cross-platform agent apps.
                       DESC
  s.homepage         = 'https://github.com/app-appplayer/flutter_mcp'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'app-appplayer' => 'author@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_mcp_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
