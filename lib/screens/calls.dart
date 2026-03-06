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
        title: const Text('Active Calls'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: vm.refreshCalls),
        ],
      ),
      body: vm.activeCalls.isEmpty
          ? const Center(child: Text('No active calls.'))
          : ListView.builder(
              itemCount: vm.activeCalls.length,
              itemBuilder: (context, i) {
                final call = vm.activeCalls[i];
                return ListTile(
                  leading: const Icon(Icons.call, color: Colors.green),
                  title: Text(call.channel, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  subtitle: Text('Exten: ${call.exten}  State: ${call.state}  Duration: ${call.duration}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.call_end, color: Colors.red),
                    onPressed: () => _hangup(context, vm, call.channel),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _hangup(BuildContext context, VmState vm, String channel) async {
    final ok = await vm.hangupCall(channel);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Hung up $channel' : 'Failed to hangup $channel'),
    ));
  }
}
