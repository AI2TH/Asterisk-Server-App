import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sip_service.dart';
import '../services/vm_platform.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The "other party" in a message from extension 1000's perspective.
String _contact(Message msg) =>
    msg.direction == 'sent' ? msg.to : msg.from;

class _Conversation {
  final String contact;
  final List<Message> messages;

  _Conversation({required this.contact, required this.messages});

  Message get last => messages.last;

  String get preview => last.body.length > 60
      ? '${last.body.substring(0, 60)}…'
      : last.body;
}

List<_Conversation> _buildConversations(List<Message> all) {
  final Map<String, List<Message>> byContact = {};
  for (final m in all) {
    final key = _contact(m);
    byContact.putIfAbsent(key, () => []).add(m);
  }
  final convos = byContact.entries
      .map((e) => _Conversation(contact: e.key, messages: e.value))
      .toList();
  convos.sort(
      (a, b) => b.last.timestamp.compareTo(a.last.timestamp));
  return convos;
}

// ---------------------------------------------------------------------------
// Messages screen — conversation list
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
    final convos = _buildConversations(vm.messages);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Messages'),
            Text(
              convos.isEmpty
                  ? 'No conversations'
                  : '${convos.length} conversation${convos.length > 1 ? 's' : ''}',
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
      body: convos.isEmpty
          ? _EmptyState(isRunning: vm.status == VmStatus.running)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: convos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _ConversationTile(
                convo: convos[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _ThreadScreen(
                      contact: convos[i].contact,
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: vm.status == VmStatus.running
            ? () => _showNewMessageSheet(context, vm)
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
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final _Conversation convo;
  final VoidCallback onTap;
  const _ConversationTile({required this.convo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
        (convo.last.timestamp * 1000).round());
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final isSent = convo.last.direction == 'sent';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF9C27B0).withOpacity(0.25)),
              ),
              child: Center(
                child: Text(
                  convo.contact,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFCE93D8),
                      fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Ext ${convo.contact}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(timeStr,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.35))),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (isSent)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.done_all,
                              size: 13,
                              color: convo.last.delivered
                                  ? Colors.blue
                                  : Colors.white38),
                        ),
                      Expanded(
                        child: Text(
                          convo.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.4)),
                        ),
                      ),
                      Text(
                        '${convo.messages.length}',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withOpacity(0.25)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                size: 18, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread screen — chat bubbles + call button
// ---------------------------------------------------------------------------

class _ThreadScreen extends StatefulWidget {
  final String contact;
  const _ThreadScreen({required this.contact});

  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(VmState vm) async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    final ok = await vm.sendMessage(
      fromExt: kLocalExtension,
      toExt: widget.contact,
      body: body,
    );
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to send'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        _scrollToBottom();
      }
    }
  }

  void _call(SipService sip) {
    if (!sip.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('SIP not registered — wait for VM to start'),
        backgroundColor: Colors.deepOrange,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    sip.call(widget.contact);
    // Navigate to calls tab (index 2) by popping back
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VmState>();
    final sip = context.watch<SipService>();

    final msgs = vm.messages
        .where((m) => _contact(m) == widget.contact)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ext ${widget.contact}'),
            Text('Extension',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.4))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Call',
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: sip.isRegistered
                    ? Colors.green.withOpacity(0.15)
                    : Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.call_rounded,
                size: 18,
                color: sip.isRegistered ? Colors.green : Colors.white38,
              ),
            ),
            onPressed: () => _call(sip),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Message bubbles
          Expanded(
            child: msgs.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet\nSend one below',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: msgs.length,
                    itemBuilder: (ctx, i) =>
                        _Bubble(msg: msgs[i]),
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF12121F),
              border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.07))),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(vm),
                      decoration: InputDecoration(
                        hintText: 'Message Ext ${widget.contact}…',
                        hintStyle: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.25)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                              color: Color(0xFF9C27B0), width: 1.5),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1C1C2E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _send(vm),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _sending
                            ? Colors.white.withOpacity(0.1)
                            : const Color(0xFF9C27B0),
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Center(
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54)))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat bubble
// ---------------------------------------------------------------------------

class _Bubble extends StatelessWidget {
  final Message msg;
  const _Bubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isSent = msg.direction == 'sent';
    final dt = DateTime.fromMillisecondsSinceEpoch(
        (msg.timestamp * 1000).round());
    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSent
                  ? const Color(0xFF7B1FA2)
                  : const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isSent ? 18 : 4),
                bottomRight: Radius.circular(isSent ? 4 : 18),
              ),
              border: isSent
                  ? null
                  : Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  msg.body,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.45)),
                    ),
                    if (isSent) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.done_all,
                        size: 12,
                        color: msg.delivered
                            ? Colors.blue.shade200
                            : Colors.white38,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New message sheet (compose to a new contact)
// ---------------------------------------------------------------------------

Future<void> showSendMessageSheet(
  BuildContext context,
  VmState vm, {
  String? prefilledTo,
}) async {
  final toCtrl = TextEditingController(text: prefilledTo ?? '');
  final bodyCtrl = TextEditingController();

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
      child: Column(
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
              const Text('New Message',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: toCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'To (extension)',
              hintText: '1001',
              prefixIcon: Icon(Icons.person_outline, size: 18),
            ),
          ),
          const SizedBox(height: 12),
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
                    final to = toCtrl.text.trim();
                    final body = bodyCtrl.text.trim();
                    if (to.isEmpty || body.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Fill in all fields'),
                          behavior: SnackBarBehavior.floating));
                      return;
                    }
                    Navigator.pop(ctx);
                    final ok = await vm.sendMessage(
                      fromExt: kLocalExtension,
                      toExt: to,
                      body: body,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Message sent' : 'Failed to send'),
                        backgroundColor:
                            ok ? Colors.green.shade800 : Colors.red.shade800,
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
  );
}

void _showNewMessageSheet(BuildContext context, VmState vm) =>
    showSendMessageSheet(context, vm);

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool isRunning;
  const _EmptyState({required this.isRunning});

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
                  ? Icons.chat_bubble_outline
                  : Icons.phone_disabled_outlined,
              size: 30,
              color: Colors.white.withOpacity(0.2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isRunning ? 'No conversations yet' : 'Asterisk not running',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 6),
          Text(
            isRunning
                ? 'Tap the compose button to start a conversation'
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
