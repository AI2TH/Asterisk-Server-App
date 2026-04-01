import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/calls.dart';
import 'screens/dashboard.dart';
import 'screens/extensions.dart';
import 'screens/messages.dart';
import 'screens/settings.dart';
import 'screens/terminal.dart';
import 'services/sip_service.dart';
import 'services/vm_platform.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VmState()..startPolling()),
        ChangeNotifierProvider(create: (_) => SipService()),
      ],
      child: const ZyvrApp(),
    ),
  );
}

class ZyvrApp extends StatelessWidget {
  const ZyvrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zyvr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xFF2196F3),
          secondary: const Color(0xFF00BFA5),
          surface: const Color(0xFF1C1C2E),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E0E1A),
        cardTheme: CardTheme(
          color: const Color(0xFF1C1C2E),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.07)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0E0E1A),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: Colors.white70),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF12121F),
          surfaceTintColor: Colors.transparent,
          indicatorColor: const Color(0xFF2196F3).withOpacity(0.18),
          height: 64,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C1C2E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2196F3), width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2196F3),
            side: const BorderSide(color: Color(0xFF2196F3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withOpacity(0.07),
          thickness: 1,
          space: 1,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF2196F3).withOpacity(0.12),
          labelStyle: const TextStyle(fontSize: 10, color: Color(0xFF64B5F6)),
          side: BorderSide(color: const Color(0xFF2196F3).withOpacity(0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
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
    MessagesScreen(),
    TerminalScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmState>().addListener(_onVmStateChanged);
    });
  }

  void _onVmStateChanged() {
    final vm = context.read<VmState>();
    final sip = context.read<SipService>();
    if (vm.status == VmStatus.running && !sip.isRegistered) {
      sip.register();
    } else if (vm.status != VmStatus.running && sip.isRegistered) {
      sip.unregister();
    }
  }

  @override
  void dispose() {
    context.read<VmState>().removeListener(_onVmStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();
    final callCount = vm.activeCalls.length;

    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.07)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            const NavigationDestination(
              icon: Icon(Icons.contacts_outlined),
              selectedIcon: Icon(Icons.contacts),
              label: 'Extensions',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: callCount > 0,
                label: Text('$callCount'),
                child: const Icon(Icons.call_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: callCount > 0,
                label: Text('$callCount'),
                child: const Icon(Icons.call),
              ),
              label: 'Calls',
            ),
            const NavigationDestination(
              icon: Icon(Icons.message_outlined),
              selectedIcon: Icon(Icons.message),
              label: 'Messages',
            ),
            const NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal),
              label: 'Terminal',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
