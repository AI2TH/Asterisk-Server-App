import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/vm_platform.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();
    final isRunning = vm.status == VmStatus.running;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
              ),
              child: const Icon(Icons.star, size: 16, color: Color(0xFF2196F3)),
            ),
            const SizedBox(width: 10),
            const Text('Stardial'),
          ],
        ),
        actions: [
          if (isRunning)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    const Text('Live',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _StatusCard(vm: vm),
          const SizedBox(height: 12),
          _VmControls(vm: vm),
          const SizedBox(height: 12),
          _WifiConnectionCard(vm: vm),
          const SizedBox(height: 12),
          _EndpointsCard(vm: vm),
          if (isRunning) ...[
            const SizedBox(height: 12),
            _SipJsCard(vm: vm),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status card
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  final VmState vm;
  const _StatusCard({required this.vm});

  Color get _color => switch (vm.status) {
        VmStatus.running => Colors.green,
        VmStatus.error   => Colors.red,
        VmStatus.unknown => const Color(0xFFFFA726),
        _                => Colors.grey,
      };

  String get _label => switch (vm.status) {
        VmStatus.running => 'Running',
        VmStatus.error   => 'Error',
        VmStatus.unknown => 'Starting…',
        _                => 'Stopped',
      };

  IconData get _icon => vm.status == VmStatus.running
      ? Icons.memory
      : Icons.memory_outlined;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _color.withOpacity(0.25)),
                  ),
                  child: Icon(_icon, color: _color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: _color.withOpacity(0.4),
                                    blurRadius: 5)
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(_label,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _color)),
                        ],
                      ),
                      if (vm.asteriskVersion.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(vm.asteriskVersion,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.4))),
                        ),
                    ],
                  ),
                ),
                if (vm.status == VmStatus.unknown)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _color),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniStat(icon: Icons.phone_outlined,      label: 'SIP',  value: ':5060'),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.cell_tower_outlined, label: 'RTP',  value: '20 UDP'),
                const SizedBox(width: 8),
                _MiniStat(icon: Icons.api_outlined,        label: 'ARI',  value: ':8088'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _MiniStat({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF64B5F6)),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.4),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 1),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VM Controls
// ---------------------------------------------------------------------------

class _VmControls extends StatelessWidget {
  final VmState vm;
  const _VmControls({required this.vm});

  @override
  Widget build(BuildContext context) {
    final isRunning = vm.status == VmStatus.running;
    final isBusy = vm.status == VmStatus.unknown;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isRunning || isBusy ? null : startVm,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: !isRunning || isBusy ? null : stopVm,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Stop'),
                style: FilledButton.styleFrom(
                  backgroundColor: isRunning
                      ? Colors.red.shade700
                      : Colors.white.withOpacity(0.08),
                  foregroundColor:
                      isRunning ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : restartVm,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Restart VM'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isRunning ? vm.reloadAsterisk : null,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('Reload Config'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// WiFi Connection Card — shows how to connect SIP clients via LAN
// ---------------------------------------------------------------------------

class _WifiConnectionCard extends StatelessWidget {
  final VmState vm;
  const _WifiConnectionCard({required this.vm});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final ip = vm.wifiIp.isEmpty ? '— (WiFi not detected)' : vm.wifiIp;
    final sipAddr = vm.wifiIp.isEmpty ? '—' : '${vm.wifiIp}:5060';
    final hasIp = vm.wifiIp.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFA5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.wifi,
                      size: 16, color: Color(0xFF00BFA5)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('WiFi VoIP Server',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: vm.refreshWifiIp,
                  child: Icon(Icons.refresh,
                      size: 16, color: Colors.white.withOpacity(0.3)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Devices on the same WiFi can register to this Asterisk server as a SIP client:',
              style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 10),
            _ConnectRow(
              label: 'Device IP',
              value: ip,
              canCopy: hasIp,
              onCopy: hasIp ? () => _copy(context, vm.wifiIp) : null,
            ),
            const SizedBox(height: 6),
            _ConnectRow(
              label: 'SIP Server',
              value: sipAddr,
              canCopy: hasIp,
              onCopy: hasIp ? () => _copy(context, sipAddr) : null,
              highlight: true,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Use Linphone, Zoiper or Bria on any device connected to the same WiFi.\n'
                'Add extension from the Extensions tab, then register with SIP Server above.',
                style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectRow extends StatelessWidget {
  final String label;
  final String value;
  final bool canCopy;
  final VoidCallback? onCopy;
  final bool highlight;
  const _ConnectRow({
    required this.label,
    required this.value,
    required this.canCopy,
    this.onCopy,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.45),
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.normal,
              color: highlight ? const Color(0xFF00BFA5) : Colors.white,
            ),
          ),
        ),
        if (canCopy)
          GestureDetector(
            onTap: onCopy,
            child: Icon(Icons.copy_outlined,
                size: 14, color: Colors.white.withOpacity(0.3)),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Endpoints card
// ---------------------------------------------------------------------------

class _EndpointsCard extends StatelessWidget {
  final VmState vm;
  const _EndpointsCard({required this.vm});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lan_outlined,
                    size: 15, color: Colors.white.withOpacity(0.4)),
                const SizedBox(width: 8),
                const Text('Local Endpoints',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            _EpRow('SIP',  '127.0.0.1:5060',  Icons.phone_outlined,    () => _copy(context, '127.0.0.1:5060')),
            _EpRow('WS',   vm.wsEndpoint,      Icons.language_outlined, () => _copy(context, vm.wsEndpoint)),
            _EpRow('WSS',  vm.wssEndpoint,     Icons.lock_outlined,     () => _copy(context, vm.wssEndpoint)),
            _EpRow('ARI',  '127.0.0.1:8088',   Icons.api_outlined,      () => _copy(context, 'http://127.0.0.1:8088/asterisk/ari/')),
            _EpRow('AMI',  '127.0.0.1:5038',   Icons.terminal_outlined, () => _copy(context, '127.0.0.1:5038'), last: true),
          ],
        ),
      ),
    );
  }
}

class _EpRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onCopy;
  final bool last;
  const _EpRow(this.label, this.value, this.icon, this.onCopy, {this.last = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withOpacity(0.25)),
              const SizedBox(width: 8),
              SizedBox(
                width: 34,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.45))),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Icon(Icons.copy_outlined,
                    size: 13, color: Colors.white.withOpacity(0.25)),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// SIP.js / WebRTC card
// ---------------------------------------------------------------------------

class _SipJsCard extends StatelessWidget {
  final VmState vm;
  const _SipJsCard({required this.vm});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFA5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: const Color(0xFF00BFA5).withOpacity(0.3)),
                  ),
                  child: const Text('WebRTC',
                      style: TextStyle(
                          color: Color(0xFF00BFA5),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                const Text('SIP.js / Browser',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            _CodeLine(
              label: 'WSS',
              value: vm.wssEndpoint,
              onCopy: () => _copy(context, vm.wssEndpoint),
            ),
            const SizedBox(height: 10),
            if (vm.certFingerprint.isEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.fingerprint, size: 16),
                  label: const Text('Load DTLS Fingerprint'),
                  onPressed: vm.refreshCertFingerprint,
                ),
              )
            else
              _CodeLine(
                label: 'DTLS',
                value: vm.certFingerprint,
                onCopy: () => _copy(context, vm.certFingerprint),
                small: true,
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;
  final bool small;
  const _CodeLine(
      {required this.label,
      required this.value,
      required this.onCopy,
      this.small = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.4),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: small ? 10 : 12,
                        color: const Color(0xFF64B5F6))),
              ),
              GestureDetector(
                onTap: onCopy,
                child: Icon(Icons.copy_outlined,
                    size: 13, color: Colors.white.withOpacity(0.3)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
