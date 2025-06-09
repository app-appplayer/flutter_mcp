import 'package:flutter_test/flutter_test.dart';

void main() {
  test('minimal test', () async {
    print('Test started');
    await Future.delayed(Duration(milliseconds: 10));
    print('Test completed');
    expect(true, isTrue);
  });
}