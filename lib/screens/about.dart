import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _mitLicense = '''MIT License

Copyright (c) 2026 AI2TH

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          // ── Hero header ──────────────────────────────────────────────────
          _HeroHeader(),
          const SizedBox(height: 24),

          // ── Developed by ─────────────────────────────────────────────────
          _SectionLabel('Developed by'),
          const SizedBox(height: 10),
          _CompanyCard(),
          const SizedBox(height: 24),

          // ── Description ──────────────────────────────────────────────────
          _SectionLabel('About the App'),
          const SizedBox(height: 10),
          _InfoBox(
            child: Text(
              'Zyvr (Zero-carrier Your Voice Router) runs a full Asterisk 20 PBX '
              'inside a QEMU Alpine Linux VM on your Android device — no root, '
              'no Termux. Any SIP client on the same WiFi can register and make '
              'calls routed entirely on-device.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.65),
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── App details ───────────────────────────────────────────────────
          _SectionLabel('App Info'),
          const SizedBox(height: 10),
          _InfoBox(
            child: Column(
              children: const [
                _DetailRow('Version',   '1.1.0 (build 2)'),
                Divider(height: 1),
                _DetailRow('Package',   'com.ai2th.zyvr'),
                Divider(height: 1),
                _DetailRow('Min SDK',   'Android 8.0 (API 26)'),
                Divider(height: 1),
                _DetailRow('Target SDK','Android 14 (API 34)'),
                Divider(height: 1),
                _DetailRow('Asterisk',  'Asterisk 20 (PJSIP)'),
                Divider(height: 1),
                _DetailRow('VM',        'QEMU 8 / Alpine Linux 3.19'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── License ───────────────────────────────────────────────────────
          _SectionLabel('License'),
          const SizedBox(height: 10),
          _InfoBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF2196F3).withOpacity(0.3)),
                      ),
                      child: const Text('MIT',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64B5F6))),
                    ),
                    const SizedBox(width: 8),
                    Text('Copyright © 2026 AI2TH',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.45))),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _mitLicense,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Colors.white.withOpacity(0.5),
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── OSS licenses button ───────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Zyvr',
              applicationVersion: '1.1.0',
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset('assets/icon_master_512.png',
                    width: 48, height: 48),
              ),
              applicationLegalese: '© 2026 AI2TH',
            ),
            icon: const Icon(Icons.article_outlined, size: 16),
            label: const Text('Open Source Licenses'),
          ),
        ],
      ),
    );
  }
}

// ── Hero header ──────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/icon_master_512.png',
              width: 88,
              height: 88,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Zyvr',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Zero-carrier Your Voice Router',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.55),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: const Text(
                  'Version 1.1.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF64B5F6).withOpacity(0.4)),
                ),
                child: const Text(
                  'MIT License',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF90CAF9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '© 2026 AI2TH',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Company card ─────────────────────────────────────────────────────────────

class _CompanyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _InfoBox(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/logo.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI2TH',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                'Applied Intelligence To Tackle Hardships',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withOpacity(0.45)),
              ),
              const SizedBox(height: 3),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://ai2th.github.io'),
                    mode: LaunchMode.externalApplication),
                child: Text(
                  'ai2th.github.io',
                  style: TextStyle(
                      fontSize: 11,
                      color: const Color(0xFF64B5F6).withOpacity(0.8),
                      decoration: TextDecoration.underline,
                      decorationColor: const Color(0xFF64B5F6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white.withOpacity(0.35),
        letterSpacing: 1.2,
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final Widget child;
  const _InfoBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withOpacity(0.45))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
