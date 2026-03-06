import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vm_platform.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _buffer = StringBuffer();
  bool _loading = false;

  Future<void> _run() async {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;
    _controller.clear();

    setState(() => _loading = true);
    _buffer.write('\n\$ $cmd\n');

    try {
      final result = await vmExec(cmd);
      final stdout = result['stdout'] as String? ?? '';
      final stderr = result['stderr'] as String? ?? '';
      if (stdout.isNotEmpty) _buffer.write(stdout);
      if (stderr.isNotEmpty) _buffer.write('[stderr] $stderr');
    } catch (e) {
      _buffer.write('[error] $e\n');
    }

    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final vm = context.read<VmState>();
      await vm.refreshLogs();
      _buffer.write('\n--- Asterisk log tail ---\n');
      _buffer.write(vm.logs);
    } catch (e) {
      _buffer.write('[error] $e\n');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Load Asterisk Logs',
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: () => setState(() => _buffer.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Text(
                  _buffer.toString(),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              top: 4,
            ),
            child: Row(
              children: [
                const Text('\$ ', style: TextStyle(fontFamily: 'monospace')),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'asterisk -rx "core show version"',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _run),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
