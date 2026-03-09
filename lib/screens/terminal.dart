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

  static const _quickCmds = [
    'asterisk -rx "core show version"',
    'asterisk -rx "core show channels"',
    'asterisk -rx "pjsip show endpoints"',
    'asterisk -rx "sip show peers"',
    'asterisk -rx "core show uptime"',
  ];

  Future<void> _run([String? cmd]) async {
    final command = (cmd ?? _controller.text).trim();
    if (command.isEmpty) return;
    _controller.clear();

    setState(() {
      _loading = true;
      _buffer.write('\n\$ $command\n');
    });

    try {
      final result = await vmExec(command);
      final stdout = result['stdout'] as String? ?? '';
      final stderr = result['stderr'] as String? ?? '';
      if (stdout.isNotEmpty) _buffer.write(stdout);
      if (stderr.isNotEmpty) {
        _buffer.write('\x1b[31m[stderr] $stderr\x1b[0m');
      }
    } catch (e) {
      _buffer.write('[error] $e\n');
    }

    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final vm = context.read<VmState>();
      await vm.refreshLogs();
      _buffer.write('\n─── Asterisk log tail ───\n');
      _buffer.write(vm.logs);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Asterisk Logs',
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => setState(() => _buffer.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick commands
          SizedBox(
            height: 36,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: _quickCmds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ActionChip(
                label: Text(_quickCmds[i].split('"')[1],
                    style: const TextStyle(fontSize: 10)),
                onPressed: () => _run(_quickCmds[i]),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFF1C1C2E),
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
          ),
          const Divider(height: 1),
          // Output buffer
          Expanded(
            child: Container(
              color: const Color(0xFF080810),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Text(
                  _buffer.isEmpty
                      ? '# Zyvr terminal — run commands on the Alpine VM\n# Tap a quick command above or type below\n'
                      : _buffer.toString(),
                  style: TextStyle(
                    color: _buffer.isEmpty
                        ? Colors.white24
                        : Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            LinearProgressIndicator(
              backgroundColor: Colors.white.withOpacity(0.05),
              color: const Color(0xFF2196F3),
              minHeight: 2,
            ),
          Container(
            color: const Color(0xFF0E0E1A),
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8,
            ),
            child: Row(
              children: [
                Text('\$',
                    style: TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.greenAccent.withOpacity(0.7),
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'asterisk -rx "core show version"',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2), fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFF2196F3), width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Color(0xFF2196F3)),
                  onPressed: _loading ? null : _run,
                  tooltip: 'Run',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
