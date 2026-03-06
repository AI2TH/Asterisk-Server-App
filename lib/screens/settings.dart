import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _vcpu = 2;
  int _ramMb = 1024;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vcpu  = prefs.getInt('vcpu_count') ?? 2;
      _ramMb = prefs.getInt('ram_mb')     ?? 1024;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vcpu_count', _vcpu);
    await prefs.setInt('ram_mb',     _ramMb);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved — restart VM to apply')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('VM Resources', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListTile(
            title: Text('vCPUs: $_vcpu'),
            subtitle: Slider(
              value: _vcpu.toDouble(),
              min: 1, max: 4, divisions: 3,
              label: '$_vcpu',
              onChanged: (v) => setState(() => _vcpu = v.round()),
            ),
          ),
          ListTile(
            title: Text('RAM: ${_ramMb} MB'),
            subtitle: Slider(
              value: _ramMb.toDouble(),
              min: 512, max: 2048, divisions: 6,
              label: '${_ramMb}MB',
              onChanged: (v) => setState(() => _ramMb = v.round()),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const Divider(height: 32),
          const Text('Asterisk', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _InfoTile('SIP Port', '5060 (UDP + TCP)'),
          _InfoTile('RTP Range', '10000–10019 UDP'),
          _InfoTile('AMI', '127.0.0.1:5038'),
          _InfoTile('ARI', 'http://127.0.0.1:8088/asterisk/ari/'),
          _InfoTile('ARI User', 'stardial'),
          _InfoTile('ARI Pass', 'stardial_ari_pass'),
          const Divider(height: 32),
          const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const ListTile(
            title: Text('Stardial'),
            subtitle: Text('Asterisk PBX on Android — powered by QEMU + Alpine Linux'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Text(value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
    );
  }
}
