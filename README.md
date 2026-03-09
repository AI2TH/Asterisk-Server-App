# Zyvr — Asterisk PBX on Android

Run a full Asterisk telephony server on a non-rooted Android device — no Termux, no root, one APK.

Built on the same QEMU-in-Android architecture as [Pockr](../pockr/README.md).

---

## How it works

```
Android App (Flutter + Kotlin)
  └── VmManager  ──launches──▶  QEMU (libqemu.so from nativeLibraryDir)
                                  └── Alpine Linux VM
                                        └── Asterisk 20 PBX
                                              ├── SIP :5060 (UDP/TCP)
                                              ├── RTP :10000-10019 (UDP)
                                              ├── AMI :5038 (TCP)
                                              └── ARI :8088 (HTTP)
                                        └── FastAPI control server :7080
  └── VmApiClient ──HTTP──▶  http://127.0.0.1:7080  (QEMU SLIRP hostfwd)
```

- **No root required** — QEMU user-mode networking (SLIRP)
- **No Termux** — QEMU binaries ship as `jniLibs` inside the APK
- **Token auth** — UUID injected via QEMU fw_cfg, read from `/sys/firmware/qemu_fw_cfg/`
- **Persistent config** — `user.qcow2` overlay preserves SIP extensions and voicemail across reboots

---

## Features

- Start / stop the embedded Alpine VM
- Manage SIP extensions (create, delete, list) — PJSIP
- View active calls and hangup channels
- Tail Asterisk logs in real time
- Terminal — shell access into the Alpine VM host
- Configurable vCPU count and RAM
- Persistent ForegroundService notification

---

## Requirements

- Android 8.0+ (API 26+), ARM64 (aarch64)
- ~250 MB storage for APK
- ~1–1.5 GB RAM for VM (Asterisk is lighter than Docker)

---

## Project structure

```
asterisk-app/
├── lib/                        Flutter UI (Dart)
│   ├── main.dart               5 tabs
│   ├── screens/
│   │   ├── dashboard.dart      VM status, start/stop
│   │   ├── extensions.dart     SIP extension management
│   │   ├── calls.dart          Active calls, hangup
│   │   ├── terminal.dart       VM shell
│   │   └── settings.dart       vCPU / RAM / About
│   └── services/
│       └── vm_platform.dart    MethodChannel + VmState
│
├── android/app/src/main/
│   ├── kotlin/com/ai2th/zyvr/
│   │   ├── ZyvrApp.kt          Application singleton
│   │   ├── MainActivity.kt     MethodChannel handler
│   │   ├── VmManager.kt        Asset extraction + QEMU launch (multi-port)
│   │   ├── VmApiClient.kt      HTTP client (auth token)
│   │   └── VmService.kt        ForegroundService
│   ├── jniLibs/arm64-v8a/      QEMU + shared libs (same as Pockr)
│   └── assets/
│       ├── vm/                 base.qcow2.gz, vmlinuz-virt, initramfs-virt
│       └── bootstrap/          api_server.py, init_bootstrap.sh
│
├── guest/                      Source baked into Alpine base image
│   ├── api_server.py           FastAPI (Asterisk control)
│   ├── init_bootstrap.sh       First-boot: configure & start Asterisk
│   ├── requirements.txt
│   └── asterisk_config/        Asterisk config file templates
│       ├── pjsip.conf
│       ├── extensions.conf
│       ├── rtp.conf
│       ├── manager.conf
│       ├── http.conf
│       └── ari.conf
│
├── docker/
│   └── Dockerfile.build        Ubuntu → Android SDK → Flutter (same as Pockr)
│
└── scripts/
    ├── build_apk.sh
    ├── build_alpine_base.sh
    └── alpine_build_inner.sh
```

---

## Getting started

### 1. Build the Alpine base image

```bash
./scripts/build_alpine_base.sh
# Output: android/app/src/main/assets/vm/base.qcow2.gz
```

### 2. Build the APK

```bash
./scripts/build_apk.sh release
# Output: build/zyvr-release.apk
```

### 3. Install

```bash
adb install -r build/zyvr-release.apk
```

---

## First run

1. Open the app → tap **Start VM**
2. Assets extract (~10–30 seconds)
3. QEMU boots Alpine (~30–60 seconds)
4. `init_bootstrap.sh` configures Asterisk and starts services (~2–5 minutes on first boot)
5. Dashboard shows **RUNNING** when `/health` passes

---

## Connecting a SIP client

Register any SIP softphone to:
- **Server**: `127.0.0.1` (on-device) or `<device-LAN-IP>` (same WiFi)
- **Port**: `5060` (UDP or TCP)
- **Username / Password**: created via the Extensions tab in the app

Tested clients: Linphone, Zoiper, Bria, MicroSIP.

---

## Guest API

All endpoints except `/health` require `Authorization: Bearer <token>`.

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Asterisk status + version |
| GET | `/extensions` | List PJSIP endpoints |
| POST | `/extensions` | Create endpoint |
| DELETE | `/extensions/{name}` | Remove endpoint |
| POST | `/asterisk/reload` | Reload Asterisk config |
| GET | `/calls` | Active channels |
| POST | `/calls/hangup` | Hangup channel by name |
| GET | `/logs` | Tail Asterisk messages log |
| POST | `/vm/exec` | Shell command on VM host |

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.
