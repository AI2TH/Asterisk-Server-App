import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../services/sip_service.dart';
import '../services/vm_platform.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  final TextEditingController _dialController = TextEditingController();
  Timer? _durationTimer;
  int _callSeconds = 0;
  bool _incomingDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VmState>().refreshCalls();
      context.read<SipService>().addListener(_onSipStateChanged);
    });
  }

  @override
  void dispose() {
    _dialController.dispose();
    _durationTimer?.cancel();
    context.read<SipService>().removeListener(_onSipStateChanged);
    super.dispose();
  }

  void _onSipStateChanged() {
    if (!mounted) return;
    final sip = context.read<SipService>();

    if (sip.callState == SipCallState.active) {
      if (_durationTimer == null || !_durationTimer!.isActive) {
        _callSeconds = 0;
        _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _callSeconds++);
        });
      }
    } else {
      _durationTimer?.cancel();
      _durationTimer = null;
      if (mounted) setState(() => _callSeconds = 0);
    }

    if (sip.callState == SipCallState.incoming && !_incomingDialogShown) {
      _incomingDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showIncomingDialog();
      });
    } else if (sip.callState != SipCallState.incoming) {
      _incomingDialogShown = false;
    }
  }

  void _showIncomingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer<SipService>(
        builder: (ctx, sip, _) {
          if (sip.callState != SipCallState.incoming) {
            // Dismiss dialog if call was handled elsewhere
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
            });
          }
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.call_outlined, color: Colors.green, size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Incoming Call',
                  style: TextStyle(fontSize: 13, color: Colors.white54),
                ),
                const SizedBox(height: 6),
                Text(
                  sip.callerId ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Decline
                    _RoundCallButton(
                      icon: Icons.call_end_rounded,
                      color: Colors.red,
                      label: 'Decline',
                      onTap: () {
                        sip.hangup();
                        Navigator.of(ctx).pop();
                      },
                    ),
                    // Answer
                    _RoundCallButton(
                      icon: Icons.call_rounded,
                      color: Colors.green,
                      label: 'Answer',
                      onTap: () {
                        sip.answer();
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    ).then((_) => _incomingDialogShown = false);
  }

  void _dialDigit(String digit) {
    _dialController.text += digit;
  }

  void _deleteDigit() {
    final text = _dialController.text;
    if (text.isNotEmpty) {
      _dialController.text = text.substring(0, text.length - 1);
    }
  }

  Future<void> _startCall(SipService sip) async {
    final ext = _dialController.text.trim();
    if (ext.isEmpty || !sip.isRegistered) return;
    final granted = await Permission.microphone.request();
    if (!granted.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission required'),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }
    sip.call(ext);
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sip = context.watch<SipService>();
    final vm = context.watch<VmState>();

    final isCallActive = sip.callState == SipCallState.active ||
        sip.callState == SipCallState.ringing;

    if (isCallActive) {
      return _ActiveCallScreen(
        sip: sip,
        callSeconds: _callSeconds,
        formatDuration: _formatDuration,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Calls'),
            Text(
              vm.activeCalls.isEmpty
                  ? 'No active calls'
                  : '${vm.activeCalls.length} call${vm.activeCalls.length > 1 ? 's' : ''} in progress',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.45)),
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
      body: Column(
        children: [
          // Registration status chip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sip.isRegistered
                        ? Colors.green.withOpacity(0.12)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sip.isRegistered
                          ? Colors.green.withOpacity(0.3)
                          : Colors.white.withOpacity(0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sip.isRegistered ? Colors.green : Colors.white38,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        sip.isRegistered ? 'Ext 1000 · Registered' : 'Not registered',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: sip.isRegistered ? Colors.green : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Dial display
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dialController,
                      readOnly: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        hintText: 'Enter number',
                        hintStyle: TextStyle(
                          fontSize: 16,
                          color: Colors.white24,
                          letterSpacing: 1,
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined, color: Colors.white38),
                    onPressed: _deleteDigit,
                    tooltip: 'Delete',
                  ),
                ],
              ),
            ),
          ),

          // Dialpad
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
            child: _Dialpad(onDigit: _dialDigit),
          ),

          // Call button
          Padding(
            padding: const EdgeInsets.fromLTRB(80, 16, 80, 0),
            child: ListenableBuilder(
              listenable: _dialController,
              builder: (ctx, _) {
                final canCall = sip.isRegistered && _dialController.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: canCall ? () => _startCall(sip) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 58,
                    decoration: BoxDecoration(
                      color: canCall
                          ? Colors.green
                          : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(29),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.call_rounded,
                        size: 28,
                        color: canCall ? Colors.white : Colors.white30,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),
          if (vm.activeCalls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Active Channels',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.4),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

          // Active calls list (channel monitoring)
          Expanded(
            child: vm.activeCalls.isEmpty
                ? const SizedBox.shrink()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: vm.activeCalls.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final call = vm.activeCalls[i];
                      return _CallCard(
                        call: call,
                        onHangup: () => _hangupChannel(context, vm, call.channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _hangupChannel(BuildContext context, VmState vm, String channel) async {
    final ok = await vm.hangupCall(channel);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Call ended' : 'Failed to hangup'),
      backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
    ));
  }
}

// ---------------------------------------------------------------------------
// Active / ringing call full-screen card
// ---------------------------------------------------------------------------

class _ActiveCallScreen extends StatelessWidget {
  final SipService sip;
  final int callSeconds;
  final String Function(int) formatDuration;

  const _ActiveCallScreen({
    required this.sip,
    required this.callSeconds,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final isRinging = sip.callState == SipCallState.ringing;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Avatar
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C2E),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 2),
                ),
                child: const Icon(Icons.person_outline, size: 44, color: Colors.white38),
              ),
              const SizedBox(height: 20),
              // Caller / extension
              Text(
                sip.callerId ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              // State label
              Text(
                isRinging ? 'Calling...' : formatDuration(callSeconds),
                style: TextStyle(
                  fontSize: 15,
                  color: isRinging ? Colors.white38 : Colors.green.shade300,
                  fontVariations: isRinging ? [] : [const FontVariation('wght', 500)],
                ),
              ),
              const Spacer(flex: 3),
              // Controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _CallControlButton(
                    icon: sip.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: sip.isMuted ? 'Unmute' : 'Mute',
                    active: sip.isMuted,
                    onTap: sip.toggleMute,
                  ),
                  // Hangup
                  GestureDetector(
                    onTap: sip.hangup,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                  // Speaker
                  _CallControlButton(
                    icon: sip.isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: sip.isSpeaker ? 'Speaker' : 'Earpiece',
                    active: sip.isSpeaker,
                    onTap: sip.toggleSpeaker,
                  ),
                ],
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialpad widget
// ---------------------------------------------------------------------------

class _Dialpad extends StatelessWidget {
  final void Function(String) onDigit;
  const _Dialpad({required this.onDigit});

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: row.map((digit) {
              return _DialKey(digit: digit, onTap: () => onDigit(digit));
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _DialKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;
  const _DialKey({required this.digit, required this.onTap});

  static const _subLabels = {
    '2': 'ABC', '3': 'DEF', '4': 'GHI', '5': 'JKL',
    '6': 'MNO', '7': 'PQRS', '8': 'TUV', '9': 'WXYZ',
    '0': '+',
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              digit,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                color: Colors.white,
              ),
            ),
            if (_subLabels.containsKey(digit))
              Text(
                _subLabels[digit]!,
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white.withOpacity(0.3),
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Round call button (for incoming dialog)
// ---------------------------------------------------------------------------

class _RoundCallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _RoundCallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Call control button (mute / speaker)
// ---------------------------------------------------------------------------

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CallControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF2196F3).withOpacity(0.2)
                  : const Color(0xFF1C1C2E),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? const Color(0xFF2196F3).withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF2196F3) : Colors.white54,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Channel monitoring card (existing calls via AMI)
// ---------------------------------------------------------------------------

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
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_end_rounded, color: Colors.red, size: 22),
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
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
