import 'package:flutter/material.dart';

/// Shown while the app is resolving persisted state (the configured server
/// URL, then the stored auth token) before the router can decide where to
/// send the user (`/server-setup`, `/login`, or `/households`).
///
/// Without this, `app_router.dart`'s `initialLocation` briefly rendered
/// `/login` (or whichever route it happened to be) for a frame or two before
/// redirecting — a visible "flash" on cold start (TASK-067 F-25).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const _teal = Color(0xFF0D9488);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_rounded, size: 56, color: _teal),
            SizedBox(height: 20),
            CircularProgressIndicator(color: _teal),
          ],
        ),
      ),
    );
  }
}
