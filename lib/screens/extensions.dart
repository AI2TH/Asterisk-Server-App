import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vm_platform.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<VmState>().refreshExtensions());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: vm.refreshExtensions),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, vm),
          ),
        ],
      ),
      body: vm.extensions.isEmpty
          ? const Center(
              child: Text(
                'No extensions configured.\nTap + to add one.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: vm.extensions.length,
              itemBuilder: (context, i) {
                final ext = vm.extensions[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(ext.name,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(ext.name),
                  subtitle: Row(
                    children: [
                      Text('Context: ${ext.context}'),
                      const SizedBox(width: 8),
                      if (ext.webrtc)
                        const Chip(
                          label: Text('WebRTC', style: TextStyle(fontSize: 10)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(context, vm, ext.name),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, VmState vm) async {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ctxCtrl  = TextEditingController(text: 'from-internal');
    bool webrtc = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Extension'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Extension (e.g. 1001)',
                  hintText: '1001',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'SIP Password'),
                obscureText: true,
              ),
              TextField(
                controller: ctxCtrl,
                decoration: const InputDecoration(labelText: 'Context'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('WebRTC / SIP.js'),
                subtitle: const Text('DTLS+SRTP, ICE support'),
                value: webrtc,
                onChanged: (v) => setDialogState(() => webrtc = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await vm.createExtension(
                  name:     nameCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  context:  ctxCtrl.text.trim(),
                  webrtc:   webrtc,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok ? 'Extension created' : 'Failed to create extension'),
                ));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, VmState vm, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('This will remove the extension and its auth config from Asterisk.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteExtension(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Extension $name deleted' : 'Failed to delete $name'),
    ));
  }
}
