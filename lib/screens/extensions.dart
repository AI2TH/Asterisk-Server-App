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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Extensions'),
            Text('${vm.extensions.length} registered',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.45))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: vm.refreshExtensions,
          ),
        ],
      ),
      body: vm.extensions.isEmpty
          ? _EmptyState(
              onAdd: vm.status == VmStatus.running
                  ? () => _showAddDialog(context, vm)
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Start the VM from the Dashboard tab first'),
                          backgroundColor: Colors.deepOrange,
                          behavior: SnackBarBehavior.floating,
                        ),
                      ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: vm.extensions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final ext = vm.extensions[i];
                return _ExtensionCard(
                  ext: ext,
                  onDelete: () => _confirmDelete(context, vm, ext.name),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: vm.status == VmStatus.running
            ? () => _showAddDialog(context, vm)
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Start the VM from the Dashboard tab first'),
                    backgroundColor: Colors.deepOrange,
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
        icon: const Icon(Icons.add),
        label: const Text('Add Extension'),
        backgroundColor: vm.status == VmStatus.running
            ? const Color(0xFF2196F3)
            : Colors.grey.shade700,
        foregroundColor: Colors.white,
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, VmState vm) async {
    final nameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final ctxCtrl  = TextEditingController(text: 'from-internal');
    bool webrtc = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text('Add Extension',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Extension Number',
                  hintText: '1001',
                  prefixIcon: Icon(Icons.tag, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'SIP Password',
                  prefixIcon: Icon(Icons.lock_outline, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctxCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dialplan Context',
                  prefixIcon: Icon(Icons.route_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SwitchListTile(
                  title: const Text('WebRTC / SIP.js',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text('DTLS+SRTP, ICE, browser compatible',
                      style: TextStyle(
                          fontSize: 11, color: Colors.white.withOpacity(0.45))),
                  value: webrtc,
                  onChanged: (v) => setS(() => webrtc = v),
                  activeColor: const Color(0xFF2196F3),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (vm.status != VmStatus.running) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('VM is not running — start it from the Dashboard tab'),
                              backgroundColor: Colors.deepOrange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        final name = nameCtrl.text.trim();
                        final ok = await vm.createExtension(
                          name:     name,
                          password: passCtrl.text.trim(),
                          context:  ctxCtrl.text.trim(),
                          webrtc:   webrtc,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(ok
                              ? 'Extension $name created'
                              : 'Failed to create extension'),
                          backgroundColor:
                              ok ? Colors.green.shade800 : Colors.red.shade800,
                        ));
                      },
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, VmState vm, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Text('Delete Extension?'),
        content: Text(
            'Remove extension $name and all its auth config from Asterisk?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await vm.deleteExtension(name);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Extension $name deleted' : 'Failed to delete $name'),
      backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
    ));
  }
}

class _ExtensionCard extends StatelessWidget {
  final Extension ext;
  final VoidCallback onDelete;
  const _ExtensionCard({required this.ext, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF2196F3).withOpacity(0.25)),
            ),
            child: Center(
              child: Text(ext.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64B5F6),
                      fontFamily: 'monospace')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Extension ${ext.name}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(ext.context,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.4))),
                    if (ext.webrtc) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00BFA5).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF00BFA5).withOpacity(0.3)),
                        ),
                        child: const Text('WebRTC',
                            style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFF00BFA5),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                    if (ext.hasAuth) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock,
                          size: 10, color: Colors.white.withOpacity(0.3)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 19, color: Colors.white.withOpacity(0.3)),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

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
            child: Icon(Icons.contacts_outlined,
                size: 32, color: Colors.white.withOpacity(0.2)),
          ),
          const SizedBox(height: 16),
          Text('No extensions yet',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.6))),
          const SizedBox(height: 6),
          Text('Add a SIP extension to start making calls',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.35))),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Extension'),
          ),
        ],
      ),
    );
  }
}
