import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:clip_vault/features/home/presentation/home_page.dart';
import 'package:clip_vault/features/library/presentation/library_page.dart';
import 'package:clip_vault/features/settings/presentation/settings_page.dart';
import 'package:clip_vault/features/download/presentation/downloads_page.dart';
import 'package:clip_vault/features/player/presentation/video_player_page.dart';

/// 底部导航 Shell
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (index) => _onItemTapped(index, context),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: '资源库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/library')) return 1;
    if (location.startsWith('/settings')) return 2;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/library');
      case 2:
        context.go('/settings');
    }
  }
}

/// 路由配置
final router = GoRouter(
  initialLocation: '/',
  routes: [
    // 带底部导航的 Shell 路由
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: '/library',
          name: 'library',
          builder: (context, state) => const LibraryPage(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),

    // 独立页面（无底部导航）
    GoRoute(
      path: '/downloads',
      name: 'downloads',
      builder: (context, state) => const DownloadsPage(),
    ),
    GoRoute(
      path: '/video/:id',
      name: 'videoPlayer',
      builder: (context, state) => VideoPlayerPage(
        videoId: state.pathParameters['id']!,
      ),
    ),
  ],
);
