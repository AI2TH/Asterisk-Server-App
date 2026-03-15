import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vm_platform.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<VmState>().refreshMessages());
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();
    final msgs = vm.messages;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Messages'),
            Text(
              msgs.isEmpty
                  ? 'No messages'
                  : '${msgs.length} message${msgs.length > 1 ? 's' : ''}',
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withOpacity(0.45)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: vm.refreshMessages,
          ),
        ],
      ),
      body: msgs.isEmpty
          ? _EmptyMessagesState(isRunning: vm.status == VmStatus.running)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: msgs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final msg = msgs[msgs.length - 1 - i]; // newest first
                return _MessageCard(
                  msg: msg,
                  onDelete: () => _delete(context, vm, msg.id),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: vm.status == VmStatus.running
            ? () => _showSendSheet(context, vm)
            : () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Start the VM from the Dashboard tab first'),
                    backgroundColor: Colors.deepOrange,
                    behavior: SnackBarBehavior.floating,
                  ),
                ),
        backgroundColor: vm.status == VmStatus.running
            ? const Color(0xFF9C27B0)
            : Colors.grey.shade700,
        foregroundColor: Colors.white,
        child: const Icon(Icons.send_outlined),
      ),
    );
  }

  Future<void> _delete(BuildContext context, VmState vm, String id) async {
    final ok = await vm.deleteMessage(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Message deleted' : 'Failed to delete'),
      backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
    ));
  }
}

// ---------------------------------------------------------------------------
// Send sheet (reusable — also called from extensions.dart)
// ---------------------------------------------------------------------------

Future<void> showSendMessageSheet(
  BuildContext context,
  VmState vm, {
  String? prefilledTo,
}) async {
  if (vm.extensions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No extensions registered'),
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final extNames = vm.extensions.map((e) => e.name).toList();
  String? fromExt = extNames.first;
  String toExt    = prefilledTo ?? (extNames.length > 1 ? extNames[1] : '');
  final bodyCtrl  = TextEditingController();

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
                    color: const Color(0xFF9C27B0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Send Message',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            // From
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.03),
              ),
              child: Row(
                children: [
                  Text('From:  ',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.5))),
                  DropdownButton<String>(
                    value: fromExt,
                    underline: const SizedBox(),
                    dropdownColor: const Color(0xFF1C1C2E),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    items: extNames
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setS(() => fromExt = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // To
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'To (extension)',
                hintText: '1002',
                prefixIcon: Icon(Icons.person_outline, size: 18),
              ),
              controller: TextEditingController(text: toExt),
              onChanged: (v) => toExt = v.trim(),
            ),
            const SizedBox(height: 12),
            // Body
            TextField(
              controller: bodyCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Type your message…',
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 42),
                  child: Icon(Icons.message_outlined, size: 18),
                ),
                alignLabelWithHint: true,
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
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF9C27B0)),
                    onPressed: () async {
                      final body = bodyCtrl.text.trim();
                      final from = fromExt;
                      final to   = toExt.trim();
                      if (from == null || to.isEmpty || body.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Fill in all fields'),
                              behavior: SnackBarBehavior.floating),
                        );
                        return;
                      }
                      if (from == to) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('From and To must differ'),
                              behavior: SnackBarBehavior.floating),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      final ok = await vm.sendMessage(
                        fromExt: from,
                        toExt: to,
                        body: body,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content:
                              Text(ok ? 'Message sent' : 'Failed to send'),
                          backgroundColor: ok
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ));
                      }
                    },
                    child: const Text('Send'),
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

void _showSendSheet(BuildContext context, VmState vm) =>
    showSendMessageSheet(context, vm);

// ---------------------------------------------------------------------------
// Message card — mirrors _CallCard from calls.dart
// ---------------------------------------------------------------------------

class _MessageCard extends StatelessWidget {
  final Message msg;
  final VoidCallback onDelete;
  const _MessageCard({required this.msg, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
        (msg.timestamp * 1000).round());
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final isSent = msg.direction == 'sent';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF9C27B0).withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF9C27B0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF9C27B0).withOpacity(0.25)),
            ),
            child: Icon(
              isSent ? Icons.send_outlined : Icons.sms_outlined,
              color: const Color(0xFF9C27B0),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${msg.from}  →  ${msg.to}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _Tag(isSent ? 'Sent' : 'Received',
                        isSent ? Colors.blue : Colors.teal),
                    const SizedBox(width: 6),
                    _Tag(timeStr, Colors.white38),
                    if (isSent) ...[
                      const SizedBox(width: 6),
                      _Tag(
                        msg.delivered ? 'Delivered' : 'Undelivered',
                        msg.delivered ? Colors.green : Colors.orange,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  msg.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: Colors.white.withOpacity(0.3), size: 22),
            tooltip: 'Delete',
            onPressed: onDelete,
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

// ---------------------------------------------------------------------------
// Empty state — mirrors _EmptyCallsState from calls.dart
// ---------------------------------------------------------------------------

class _EmptyMessagesState extends StatelessWidget {
  final bool isRunning;
  const _EmptyMessagesState({required this.isRunning});

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
              isRunning
                  ? Icons.message_outlined
                  : Icons.phone_disabled_outlined,
              size: 30,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isRunning ? 'No messages' : 'Asterisk not running',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 6),
          Text(
            isRunning
                ? 'Tap + to send a message between extensions'
                : 'Start the VM from the Dashboard tab',
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.3)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
