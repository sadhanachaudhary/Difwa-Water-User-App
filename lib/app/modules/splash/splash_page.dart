import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/state/auth_store.dart';
import '../../routes/app_routes.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 3-second cap — cached users finish instantly, others don't wait all day.
      await ref.read(authStoreProvider.notifier).init()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Timeout or error — navigate with whatever state we already have.
    }

    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
    final authState = ref.read(authStoreProvider);

    if (authState is AuthAuthenticated) {
      final role = authState.user.role.toLowerCase();
      if (role.contains('rider') ||
          role.contains('delivery') ||
          role.contains('driver') ||
          role.contains('staff')) {
        Navigator.pushReplacementNamed(context, AppRoutes.riderHome);
      } else if (role.contains('retailer') || role.contains('vendor')) {
        Navigator.pushReplacementNamed(context, AppRoutes.retailerHome);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00ACC1)),
          ),
        ),
      ),
    );
  }
}
