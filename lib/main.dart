import 'package:flutter/material.dart';
import 'package:hypertrophy/pages/home_page.dart';
import 'package:hypertrophy/pages/login_page.dart';
import 'package:hypertrophy/pages/templates_page.dart';
import 'package:hypertrophy/services/auth_service.dart';
import 'package:hypertrophy/services/anonymous_user_service.dart';
import 'package:hypertrophy/services/sync_service.dart';

/// Application entry point
/// Initializes Flutter app with Material design and routing
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hypertrophy App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 5, 39, 46), // Bright orange
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Helvetica',
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Helvetica'),
          displayMedium: TextStyle(fontFamily: 'Helvetica'),
          displaySmall: TextStyle(fontFamily: 'Helvetica'),
          headlineLarge: TextStyle(fontFamily: 'Helvetica'),
          headlineMedium: TextStyle(fontFamily: 'Helvetica'),
          headlineSmall: TextStyle(fontFamily: 'Helvetica'),
          titleLarge: TextStyle(fontFamily: 'Helvetica'),
          titleMedium: TextStyle(fontFamily: 'Helvetica'),
          titleSmall: TextStyle(fontFamily: 'Helvetica'),
          bodyLarge: TextStyle(fontFamily: 'Helvetica'),
          bodyMedium: TextStyle(fontFamily: 'Helvetica'),
          bodySmall: TextStyle(fontFamily: 'Helvetica'),
          labelLarge: TextStyle(fontFamily: 'Helvetica'),
          labelMedium: TextStyle(fontFamily: 'Helvetica'),
          labelSmall: TextStyle(fontFamily: 'Helvetica'),
        ),
      ),
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
        '/templates': (context) => const TemplatesPage(),
      },
    );
  }
}

/// Wrapper widget that handles authentication state and routing
/// Manages anonymous user creation, authentication state, and foreground sync
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  final _authService = AuthService();
  final _anonymousUserService = AnonymousUserService();
  final _syncService = SyncService();
  // Track if user was previously authenticated to prevent anonymous access after logout
  bool _wasAuthenticated = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authService.addListener(_onAuthChange);
    _checkAnonymousUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authService.removeListener(_onAuthChange);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncOnForeground();
    }
  }

  Future<void> _syncOnForeground() async {
    try {
      final deviceId = await _anonymousUserService.getOrCreateDeviceId();
      final userId = await _authService.getCurrentUserId();
      await _syncService.syncOnForeground(deviceId: deviceId, userId: userId);
    } catch (e) {
      // Silently fail - sync will retry later
      debugPrint('⚠️ Foreground sync failed: $e');
    }
  }

  Future<void> _checkAnonymousUser() async {
    if (mounted) {
      setState(() {
        _wasAuthenticated = _authService.isAuthenticated;
        _isChecking = false;
      });
    }
  }

  void _onAuthChange() {
    // If user was authenticated and now is not, they just logged out
    // Keep _wasAuthenticated as true to show LoginPage instead of anonymous HomePage
    if (mounted) {
      setState(() {
        // Only update _wasAuthenticated if user is currently authenticated
        // This way, if they log out, _wasAuthenticated stays true
        if (_authService.isAuthenticated) {
          _wasAuthenticated = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking auth state
    if (_isChecking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If authenticated, show home page
    if (_authService.isAuthenticated) {
      return const HomePage();
    }

    // If user was previously authenticated and now logged out, show login page
    // (Don't allow anonymous access after logout)
    if (_wasAuthenticated) {
      return const LoginPage();
    }

    // Replace the FutureBuilder block (lines 146-161) with:
    return FutureBuilder<String>(
      future: _anonymousUserService
          .getOrCreateDeviceId(), // Create if doesn't exist
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Anonymous user now exists (created if needed), go to HomePage
        return const HomePage();
      },
    );
  }
}
