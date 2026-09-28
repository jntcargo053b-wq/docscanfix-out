import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docscan/theme/app_theme.dart';

void main() {
  test('application theme retains the dark design system', () {
    final theme = AppTheme.darkTheme;

    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppTheme.background);
    expect(theme.colorScheme.primary, AppTheme.primary);
  });
}
