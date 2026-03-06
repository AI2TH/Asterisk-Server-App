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
      _vcpu   = prefs.getInt('vcpu_count') ?? 2;
      _ramMb  = prefs.getInt('ram_mb')     ?? 1024;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vcpu_count', _vcpu);
    await prefs.setInt('ram_mb',     _ramMb);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Saved — restart VM to apply'),
        backgroundColor: Colors.green.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // VM Resources section
          _SectionHeader(
            icon: Icons.memory_outlined,
            title: 'VM Resources',
            subtitle: 'Takes effect after VM restart',
          ),
          const SizedBox(height: 10),
          _ResourceCard(
            vcpu: _vcpu,
            ramMb: _ramMb,
            onVcpuChanged: (v) => setState(() => _vcpu = v),
            onRamChanged: (v) => setState(() => _ramMb = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save Settings'),
            ),
          ),

          const SizedBox(height: 24),

          // Asterisk section
          _SectionHeader(
            icon: Icons.phone_outlined,
            title: 'Asterisk Config',
            subtitle: 'Read-only reference',
          ),
          const SizedBox(height: 10),
          _InfoCard(rows: const [
            _InfoRow('SIP Port',  '5060 (UDP + TCP)'),
            _InfoRow('RTP Range', '10000–10019 UDP'),
            _InfoRow('AMI',       '127.0.0.1:5038'),
            _InfoRow('ARI',       '127.0.0.1:8088'),
            _InfoRow('ARI User',  'stardial'),
            _InfoRow('WS',        '127.0.0.1:8088 /asterisk/sip'),
            _InfoRow('WSS',       '127.0.0.1:8089 /asterisk/sip'),
          ]),

          const SizedBox(height: 24),

          // WiFi VoIP section
          _SectionHeader(
            icon: Icons.wifi_outlined,
            title: 'WiFi VoIP Setup',
            subtitle: 'Connect SIP clients from the same network',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Step('1', 'Start the VM from the Dashboard tab'),
                const SizedBox(height: 10),
                _Step('2', 'Create a SIP extension from the Extensions tab'),
                const SizedBox(height: 10),
                _Step('3', 'Install Linphone, Zoiper, or Bria on any device connected to the same WiFi'),
                const SizedBox(height: 10),
                _Step('4', 'Configure SIP account:\n  • Server: <Android device WiFi IP>:5060\n  • Username: your extension (e.g. 1001)\n  • Password: extension password'),
                const SizedBox(height: 10),
                _Step('5', 'Dial another extension to call — Asterisk routes it via the dialplan'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About section
          _SectionHeader(icon: Icons.info_outline, title: 'About'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.star,
                          size: 20, color: Color(0xFF2196F3)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stardial',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('Version 1.0.0',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.4))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Asterisk 20 PBX running inside a QEMU Alpine Linux VM — no root, no Termux. '
                  'Any SIP client on the same WiFi can register and make calls.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionHeader(
      {required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF2196F3)),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2196F3))),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(subtitle!,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.3)),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final int vcpu;
  final int ramMb;
  final ValueChanged<int> onVcpuChanged;
  final ValueChanged<int> onRamChanged;
  const _ResourceCard({
    required this.vcpu,
    required this.ramMb,
    required this.onVcpuChanged,
    required this.onRamChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.developer_board_outlined,
                  size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              const Text('vCPUs',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$vcpu',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2196F3))),
              ),
            ],
          ),
          Slider(
            value: vcpu.toDouble(),
            min: 1, max: 4, divisions: 3,
            label: '$vcpu',
            onChanged: (v) => onVcpuChanged(v.round()),
            activeColor: const Color(0xFF2196F3),
          ),
          const Divider(height: 16),
          Row(
            children: [
              const Icon(Icons.memory_outlined,
                  size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              const Text('RAM',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${ramMb} MB',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2196F3))),
              ),
            ],
          ),
          Slider(
            value: ramMb.toDouble(),
            min: 512, max: 2048, divisions: 6,
            label: '${ramMb}MB',
            onChanged: (v) => onRamChanged(v.round()),
            activeColor: const Color(0xFF2196F3),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: List.generate(rows.length, (i) {
          final r = rows[i];
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(r.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.45))),
                    ),
                    Expanded(
                      child: Text(r.value,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              if (i < rows.length - 1) const Divider(height: 1),
            ],
          );
        }),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2196F3))),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.6),
                  height: 1.5)),
        ),
      ],
    );
  }
}
