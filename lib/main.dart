import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/calls.dart';
import 'screens/dashboard.dart';
import 'screens/extensions.dart';
import 'screens/settings.dart';
import 'screens/terminal.dart';
import 'services/vm_platform.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => VmState()..startPolling(),
      child: const StardialApp(),
    ),
  );
}

class StardialApp extends StatelessWidget {
  const StardialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stardial',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    ExtensionsScreen(),
    CallsScreen(),
    TerminalScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.contacts), label: 'Extensions'),
          NavigationDestination(icon: Icon(Icons.call), label: 'Calls'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Terminal'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
