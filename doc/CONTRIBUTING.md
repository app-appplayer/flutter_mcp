# Contributing to Flutter MCP

Thank you for your interest in contributing to Flutter MCP! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

By participating in this project, you are expected to uphold our Code of Conduct:

- Be respectful and inclusive
- Welcome newcomers and help them get started
- Focus on constructive criticism
- Respect differing viewpoints and experiences

## Getting Started

### Prerequisites

1. **Flutter SDK** (latest stable version)
   ```bash
   flutter --version
   ```

2. **Dart SDK** (comes with Flutter)
   ```bash
   dart --version
   ```

3. **Git**
   ```bash
   git --version
   ```

4. **Development tools**
   - IDE (VS Code, IntelliJ IDEA, or Android Studio)
   - Flutter/Dart plugins

### Setting Up Development Environment

1. **Fork the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/flutter_mcp.git
   cd flutter_mcp
   ```

2. **Add upstream remote**
   ```bash
   git remote add upstream https://github.com/flutter-mcp/flutter_mcp.git
   ```

3. **Install dependencies**
   ```bash
   flutter pub get
   ```

4. **Run tests**
   ```bash
   flutter test
   ```

5. **Set up pre-commit hooks**
   ```bash
   ./scripts/setup_hooks.sh
   ```

## Development Workflow

### Branch Naming Convention

- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test additions or modifications
- `chore/` - Maintenance tasks

Example: `feature/add-websocket-compression`

### Making Changes

1. **Create a new branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write clean, readable code
   - Follow the coding standards
   - Add tests for new functionality
   - Update documentation as needed

3. **Run tests**
   ```bash
   flutter test
   ```

4. **Check code formatting**
   ```bash
   dart format .
   flutter analyze
   ```

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

### Commit Message Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style changes (formatting, etc.)
- `refactor:` Code refactoring
- `test:` Test additions or modifications
- `chore:` Maintenance tasks

Examples:
```
feat(client): add connection retry logic

fix(android): resolve background service crash

docs(api): update connection documentation
```

### Pull Request Process

1. **Update your branch**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

2. **Push your changes**
   ```bash
   git push origin feature/your-feature-name
   ```

3. **Create a pull request**
   - Go to the GitHub repository
   - Click "New pull request"
   - Select your branch
   - Fill out the PR template

4. **PR Requirements**
   - Clear description of changes
   - Tests for new functionality
   - Documentation updates
   - All tests passing
   - Code review approval

## Coding Standards

### Dart Style Guide

Follow the official [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style):

```dart
// Good
class McpClient {
  final String serverId;
  final Duration timeout;
  
  McpClient({
    required this.serverId,
    this.timeout = const Duration(seconds: 30),
  });
  
  Future<ToolResult> callTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    // Implementation
  }
}

// Bad
class mcp_client {
  String server_id;
  Duration Timeout;
  
  mcp_client(this.server_id, [this.Timeout]);
  
  Future CallTool(String Name, Map args) {
    // Implementation
  }
}
```

### Code Organization

```
lib/
├── src/
│   ├── client/          # Client implementation
│   ├── server/          # Server implementation
│   ├── protocol/        # Protocol definitions
│   ├── utils/           # Utility functions
│   └── constants.dart   # Constants
├── flutter_mcp.dart     # Main library exports
└── flutter_mcp_platform_interface.dart
```

### Documentation

All public APIs must be documented:

```dart
/// Connects to an MCP server.
///
/// The [config] parameter specifies the server configuration.
/// 
/// Throws [MCPConnectionException] if connection fails.
/// 
/// Example:
/// ```dart
/// final mcp = FlutterMCP();
/// await mcp.initialize(config: McpConfig(
///   servers: [ServerConfig(url: 'ws://localhost:8080')],
/// ));
/// ```
Future<void> initialize({required McpConfig config}) async {
  // Implementation
}
```

### Error Handling

Use proper exception types:

```dart
// Define specific exceptions
class MCPConnectionException extends MCPException {
  MCPConnectionException(String message, {String? code})
      : super(message: message, code: code ?? 'MCP-CONN-001');
}

// Throw with context
throw MCPConnectionException(
  'Failed to connect to server',
  code: 'MCP-CONN-001',
);

// Handle gracefully
try {
  await connectToServer();
} on MCPConnectionException catch (e) {
  logger.error('Connection failed: ${e.message}');
  // Handle error
}
```

## Testing

### Test Structure

```
test/
├── unit/              # Unit tests
├── integration/       # Integration tests
├── widget/           # Widget tests
├── mocks/            # Mock objects
└── fixtures/         # Test fixtures
```

### Writing Tests

```dart
// test/unit/client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/flutter_mcp.dart';
import '../mocks/mock_server.dart';

void main() {
  group('McpClient', () {
    late McpClient client;
    late MockServer mockServer;
    
    setUp(() {
      mockServer = MockServer();
      client = McpClient(server: mockServer);
    });
    
    tearDown(() {
      client.dispose();
      mockServer.dispose();
    });
    
    test('should connect to server', () async {
      // Arrange
      mockServer.setupConnection();
      
      // Act
      await client.connect();
      
      // Assert
      expect(client.isConnected, isTrue);
      verify(mockServer.onConnect).called(1);
    });
    
    test('should handle connection errors', () async {
      // Arrange
      mockServer.setupConnectionError();
      
      // Act & Assert
      expect(
        () => client.connect(),
        throwsA(isA<MCPConnectionException>()),
      );
    });
  });
}
```

### Test Coverage

Maintain high test coverage:

```bash
# Generate coverage report
flutter test --coverage

# View coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

Minimum coverage requirements:
- Overall: 80%
- Critical paths: 95%
- New code: 90%

## Documentation

### API Documentation

Use DartDoc comments:

```dart
/// A client for interacting with MCP servers.
///
/// This class provides methods to connect to MCP servers,
/// execute tools, and handle real-time communication.
///
/// {@category Client}
class McpClient {
  /// Creates a new MCP client instance.
  ///
  /// The [config] parameter specifies the client configuration.
  ///
  /// {@macro mcp.client.config}
  McpClient({required McpConfig config});
  
  /// Executes a tool on the server.
  ///
  /// {@template mcp.client.callTool}
  /// The [serverId] identifies the target server.
  /// The [name] is the tool name to execute.
  /// The [arguments] are passed to the tool.
  /// {@endtemplate}
  ///
  /// Returns a [Future] that completes with the tool result.
  ///
  /// Example:
  /// ```dart
  /// final result = await client.callTool(
  ///   serverId: 'main',
  ///   name: 'getData',
  ///   arguments: {'query': 'users'},
  /// );
  /// ```
  ///
  /// Throws:
  /// - [MCPToolNotFoundException] if the tool doesn't exist
  /// - [MCPTimeoutException] if the operation times out
  Future<ToolResult> callTool({
    required String serverId,
    required String name,
    required Map<String, dynamic> arguments,
  });
}
```

### Markdown Documentation

Update relevant documentation:

```markdown
# Feature Name

Brief description of the feature.

## Overview

Detailed explanation of what the feature does and why it's useful.

## Usage

### Basic Example

```dart
// Code example
```

### Advanced Example

```dart
// More complex example
```

## Configuration

Configuration options and their effects.

## Best Practices

- Best practice 1
- Best practice 2

## Troubleshooting

Common issues and solutions.

## See Also

- [Related Feature](/doc/related.md)
- [API Reference](/doc/api/feature.md)
```

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- MAJOR version: Breaking changes
- MINOR version: New features (backward compatible)
- PATCH version: Bug fixes

### Release Checklist

1. **Update version**
   ```yaml
   # pubspec.yaml
   version: 1.2.0
   ```

2. **Update CHANGELOG**
   ```markdown
   ## [1.2.0] - 2024-03-15
   
   ### Added
   - New feature description
   
   ### Fixed
   - Bug fix description
   
   ### Changed
   - Change description
   ```

3. **Update documentation**
   - API documentation
   - README if needed
   - Migration guide for breaking changes

4. **Create release PR**
   - Title: `Release v1.2.0`
   - Include changelog in description

5. **After merge**
   - Create GitHub release
   - Tag the commit
   - Publish to pub.dev

### Publishing

```bash
# Dry run
dart pub publish --dry-run

# Publish
dart pub publish
```

## Development Scripts

### Available Scripts

```bash
# Run all tests
./scripts/test.sh

# Check formatting
./scripts/check_format.sh

# Generate code
./scripts/generate.sh

# Build all platforms
./scripts/build_all.sh

# Create release
./scripts/release.sh
```

### Creating New Scripts

Place scripts in the `scripts/` directory:

```bash
#!/bin/bash
set -e

echo "Running script..."

# Script logic
```

Make executable:
```bash
chmod +x scripts/your_script.sh
```

## Architecture Decisions

### ADR Template

Document architecture decisions in `doc/adr/`:

```markdown
# ADR-001: Use WebSocket for Real-time Communication

## Status
Accepted

## Context
We need real-time bidirectional communication between client and server.

## Decision
Use WebSocket protocol for real-time communication.

## Consequences
### Positive
- Real-time bidirectional communication
- Lower latency than HTTP polling

### Negative
- More complex connection management
- Requires fallback for environments without WebSocket
```

## Community

### Getting Help

- GitHub Issues: Bug reports and feature requests
- Discussions: General questions and ideas
- Discord: Real-time chat with community

### Code Reviews

All PRs require review:

1. **Code quality**
   - Follows style guide
   - Well-documented
   - Properly tested

2. **Architecture**
   - Fits with existing design
   - Scalable and maintainable

3. **Performance**
   - No performance regressions
   - Efficient implementation

4. **Security**
   - No security vulnerabilities
   - Proper input validation

### Becoming a Maintainer

Active contributors may be invited to become maintainers:

1. Consistent high-quality contributions
2. Good understanding of the codebase
3. Helpful to other contributors
4. Commitment to the project

## Tools and Resources

### Recommended Tools

- **VS Code Extensions**
  - Dart
  - Flutter
  - GitLens
  - Error Lens

- **Testing Tools**
  - Flutter Inspector
  - Dart DevTools
  - Coverage Gutters

- **Code Quality**
  - Dart Format
  - Dart Analyze
  - Dart Fix

### Useful Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Documentation](https://dart.dev/guides)
- [MCP Specification](https://github.com/modelcontextprotocol/specification)
- [Contributing to Open Source](https://opensource.guide/how-to-contribute/)

## License

By contributing to Flutter MCP, you agree that your contributions will be licensed under the project's MIT License.

## Questions?

If you have questions about contributing:

1. Check existing issues and discussions
2. Join our Discord community
3. Create a new discussion
4. Email: contribute@flutter-mcp.dev

Thank you for contributing to Flutter MCP! 🎉