import '../../flutter_mcp.dart';

class PluginConfig {
  final MCPPlugin plugin;
  final Map<String, dynamic> config;
  final List<String>? targets;

  const PluginConfig({
    required this.plugin,
    this.config = const {},
    this.targets,
  });
}