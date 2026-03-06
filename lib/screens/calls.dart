import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vm_platform.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<VmState>().refreshCalls());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Active Calls'),
            Text(
              vm.activeCalls.isEmpty
                  ? 'No active calls'
                  : '${vm.activeCalls.length} call${vm.activeCalls.length > 1 ? 's' : ''} in progress',
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withOpacity(0.45)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: vm.refreshCalls,
          ),
        ],
      ),
      body: vm.activeCalls.isEmpty
          ? _EmptyCallsState(isRunning: vm.status == VmStatus.running)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: vm.activeCalls.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final call = vm.activeCalls[i];
                return _CallCard(
                  call: call,
                  onHangup: () => _hangup(context, vm, call.channel),
                );
              },
            ),
    );
  }

  Future<void> _hangup(BuildContext context, VmState vm, String channel) async {
    final ok = await vm.hangupCall(channel);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Call ended' : 'Failed to hangup'),
      backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
    ));
  }
}

class _CallCard extends StatelessWidget {
  final ActiveCall call;
  final VoidCallback onHangup;
  const _CallCard({required this.call, required this.onHangup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.25)),
            ),
            child: const Icon(Icons.call, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  call.exten.isNotEmpty ? call.exten : call.channel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Tag(call.state, Colors.green),
                    if (call.duration.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _Tag(call.duration, Colors.white38),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  call.channel,
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.3),
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_end_rounded,
                color: Colors.red, size: 22),
            tooltip: 'Hangup',
            onPressed: onHangup,
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _EmptyCallsState extends StatelessWidget {
  final bool isRunning;
  const _EmptyCallsState({required this.isRunning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRunning ? Icons.call_outlined : Icons.phone_disabled_outlined,
              size: 30,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isRunning ? 'No active calls' : 'Asterisk not running',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 6),
          Text(
            isRunning
                ? 'Calls appear here when SIP clients connect'
                : 'Start the VM from the Dashboard tab',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withOpacity(0.3)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
