/// Widget tests for LoginPage.
///
/// Tests form validation and user interactions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hypertrophy/pages/login_page.dart';

void main() {
  group('LoginPage Widget Tests', () {
    testWidgets('test_login_page_renders', (WidgetTester tester) async {
      // Build the widget
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginPage(),
        ),
      );

      // Verify email and password fields are present
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('test_login_page_validation', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginPage(),
        ),
      );

      // Try to submit empty form
      final loginButton = find.text('Login');
      expect(loginButton, findsOneWidget);

      await tester.tap(loginButton);
      await tester.pump();

      // Should show validation errors
      expect(find.text('Please enter your email'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('test_login_page_email_validation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginPage(),
        ),
      );

      // Enter invalid email
      final emailField = find.byType(TextFormField).first;
      await tester.enterText(emailField, 'invalid-email');
      await tester.pump();

      // Trigger validation
      final loginButton = find.text('Login');
      await tester.tap(loginButton);
      await tester.pump();

      // Should show email validation error
      expect(find.text('Please enter a valid email'), findsOneWidget);
    });

    testWidgets('test_login_page_shows_loading',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginPage(),
        ),
      );

      // Fill in valid credentials
      final emailField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;

      await tester.enterText(emailField, 'test@example.com');
      await tester.enterText(passwordField, 'password123');
      await tester.pump();

      // Tap login button
      final loginButton = find.text('Login');
      await tester.tap(loginButton);
      await tester.pump();

      // Should show loading indicator (circular progress)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('test_login_page_navigates_to_register',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const LoginPage(),
          routes: {
            '/register': (context) => const Scaffold(
                  body: Text('Register Page'),
                ),
          },
        ),
      );

      // Find and tap register button
      final registerButton = find.text("Don't have an account? Register");
      expect(registerButton, findsOneWidget);

      await tester.tap(registerButton);
      await tester.pumpAndSettle();

      // Should navigate to register page
      expect(find.text('Register Page'), findsOneWidget);
    });
  });
}

