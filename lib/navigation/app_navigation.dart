import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/tests/tests_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/nova/nova_chat_screen.dart';
import '../screens/courses/courses_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../theme/app_theme.dart';

class AppNavigation extends StatefulWidget {
  final int initialIndex;

  const AppNavigation({super.key, this.initialIndex = 0});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation> {
  late int _index;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _screens = [
      TestsScreen(onGoToProfile: () => _onItemTapped(4)),
      const HomeScreen(),
      const NovaChatScreen(),
      const CoursesScreen(),
      const ProfileScreen(),
    ];
  }

  void _onItemTapped(int index) {
    if (_index == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppTheme.borderColor, width: 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 10,
          right: 10,
          top: 8,
          bottom: bottomPadding > 0 ? bottomPadding : 10,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              index: 0,
              label: "Profil & Notes",
              icon: Icons.analytics_rounded,
              outlineIcon: Icons.analytics_outlined,
            ),
            _buildNavItem(
              index: 1,
              label: "Exécution",
              icon: Icons.calendar_month_rounded,
              outlineIcon: Icons.calendar_month_outlined,
            ),
            _buildNavItem(
              index: 2,
              label: "Nova",
              icon: Icons.psychology_rounded,
              outlineIcon: Icons.psychology_outlined,
            ),
            _buildNavItem(
              index: 3,
              label: "Cours",
              icon: Icons.menu_book_rounded,
              outlineIcon: Icons.menu_book_outlined,
            ),
            _buildNavItem(
              index: 4,
              label: "Profil",
              icon: Icons.person_rounded,
              outlineIcon: Icons.person_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData outlineIcon,
  }) {
    final isSelected = _index == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? icon : outlineIcon,
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                  letterSpacing: -0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
