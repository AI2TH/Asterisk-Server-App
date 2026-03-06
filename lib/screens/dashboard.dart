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
      appBar: AppBar(title: const Text('Stardial')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(vm: vm),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isRunning ? null : startVm,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start VM'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isRunning ? stopVm : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop VM'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: restartVm,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart VM'),
          ),
          if (isRunning) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: vm.reloadAsterisk,
              icon: const Icon(Icons.sync),
              label: const Text('Reload Asterisk Config'),
            ),
            const SizedBox(height: 16),
            _SipJsCard(vm: vm),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final VmState vm;
  const _StatusCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final isRunning = vm.status == VmStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRunning ? Icons.circle : Icons.circle_outlined,
                  color: isRunning ? Colors.green : Colors.red,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  isRunning ? 'RUNNING' : vm.status.name.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (vm.asteriskVersion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(vm.asteriskVersion,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            _InfoRow('SIP',    '127.0.0.1:5060 (UDP/TCP)'),
            _InfoRow('WS',     vm.wsEndpoint),
            _InfoRow('WSS',    vm.wssEndpoint),
            _InfoRow('ARI',    'http://127.0.0.1:8088/asterisk/ari/'),
            _InfoRow('AMI',    '127.0.0.1:5038'),
            _InfoRow('RTP',    'UDP 10000–10019'),
          ],
        ),
      ),
    );
  }
}

class _SipJsCard extends StatelessWidget {
  final VmState vm;
  const _SipJsCard({required this.vm});

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SIP.js / WebRTC',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text(
              'Connect SIP.js to the WSS endpoint:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    vm.wssEndpoint,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.greenAccent),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copy(context, vm.wssEndpoint),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vm.certFingerprint.isEmpty)
              TextButton.icon(
                icon: const Icon(Icons.fingerprint, size: 16),
                label: const Text('Load cert fingerprint'),
                onPressed: vm.refreshCertFingerprint,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DTLS fingerprint:',
                      style: TextStyle(fontSize: 11)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vm.certFingerprint,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 10),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        onPressed: () => _copy(context, vm.certFingerprint),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
