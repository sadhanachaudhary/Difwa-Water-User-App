import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import 'rider_home_page.dart';
import 'rider_history_page.dart';
import 'rider_profile_page.dart';

class RiderMainPage extends StatefulWidget {
  const RiderMainPage({super.key});

  @override
  State<RiderMainPage> createState() => _RiderMainPageState();
}

class _RiderMainPageState extends State<RiderMainPage> {
  int _currentIndex = 0;
  DateTime? _lastPressedAt;

  final List<Widget> _pages = [
    const RiderHomePage(),
    const RiderHistoryPage(),
    const RiderProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;

        // If not on the first tab, go to the first tab instead of exiting
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        // Handle double-tap to exit
        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          _lastPressedAt = now;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Press back again to exit the app.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              backgroundColor: Color(0xFF0891B2),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.all(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: _pages[_currentIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: AppColors.accentGreen,
            unselectedItemColor: Colors.grey,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded),
                label: 'History',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
