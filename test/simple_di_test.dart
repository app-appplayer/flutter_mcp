import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_mcp/src/core/enhanced_dependency_injection.dart';

void main() {
  group('Simple DI Test', () {
    test('should register and get service', () async {
      final container = EnhancedDIContainer.instance;

      container.register<String>(
        factory: () => 'Hello World',
      );

      final result = await container.get<String>();
      expect(result, equals('Hello World'));

      await container.clear();
    });
  });
}
