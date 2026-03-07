# Architecture — Stardial: Asterisk PBX on Android (No Root)

## 1. Objective

A single Android APK that runs a full Asterisk telephony server on non-rooted devices by embedding a QEMU virtual machine running Alpine Linux. No external apps (no Termux), no root required.

One Android phone becomes a private PBX server. Every other device on the same WiFi network installs a standard SIP client (Linphone, Zoiper, Bria) and registers to the Stardial device. They can then call each other through Asterisk — no SIP provider, no internet, no carrier needed.

---

## 2. Deployment Model

```
WiFi Network (192.168.1.x)
│
├── [Android phone running Stardial]   ← PBX server
│     Asterisk 20 listening on :5060
│     WiFi IP: 192.168.1.42 (shown in app)
│
├── [Phone B — Linphone]               ← SIP client
│     SIP server: 192.168.1.42:5060
│     Extension: 1001 / password: abc
│
├── [Phone C — Zoiper]                 ← SIP client
│     SIP server: 192.168.1.42:5060
│     Extension: 1002 / password: xyz
│
└── [Laptop — browser + SIP.js]        ← WebRTC client
      WSS server: 192.168.1.42:8089/asterisk/sip
      Extension: 1003
```

**Rules:**
- There is exactly **one** Stardial server per WiFi network (the phone running the app).
- All other devices are clients — they never run Stardial.
- Asterisk handles all call routing via the `from-internal` dialplan.
- Up to **10 concurrent calls** (limited by the 20 RTP UDP hostfwd slots).
- The device's WiFi IP is fetched at startup and displayed on the Dashboard.

---

## 3. High-Level Architecture

```
Android OS (non-rooted)
└── APK (Flutter + Kotlin)
    ├── StardialApp (Application singleton)
    │   └── VmManager — asset extraction, QEMU lifecycle
    │       └── VmApiClient — HTTP client (auth token, port 7080)
    ├── VmService — ForegroundService (persistent notification)
    └── Flutter UI — 5 tabs: Dashboard, Extensions, Calls, Terminal, Settings
          └── VmPlatform (MethodChannel) ──▶ Kotlin

QEMU process (qemu-system-aarch64)
└── Alpine Linux 3.19 (aarch64) VM
    ├── Asterisk 20 PBX
    │   ├── PJSIP (chan_pjsip) — SIP transport  :5060 UDP/TCP
    │   ├── RTP media  :10000–10019 UDP
    │   ├── AMI (Manager Interface)  :5038 TCP  (127.0.0.1 only)
    │   └── ARI (REST Interface)  :8088 HTTP / :8089 HTTPS
    └── FastAPI control server  :7080
          ↑
          SLIRP hostfwd (multiple ports, see §5)
          ↑
Android host (0.0.0.0 — accessible from WiFi)
```

---

## 4. Components

### 4.1 Android App (Kotlin + Flutter)

**StardialApp** (`Application` subclass) holds the `VmManager` singleton.

**VmManager** handles:
- First-run asset extraction from `AssetManager` to app-private storage
- `user.qcow2` overlay creation via `libqemu_img.so`
- QEMU launch via `ProcessBuilder` with all required `hostfwd` entries
- Health checking and lifecycle (start/stop/restart)

**VmApiClient** is an OkHttp client that:
- Signs every request with `Authorization: Bearer <token>`
- Uses a 60 s read timeout for most endpoints
- Connects to `http://127.0.0.1:7080` (SLIRP hostfwd → guest :7080)

**VmService** is a `ForegroundService` keeping the VM alive in the background.

**Flutter UI** uses a `MethodChannel` to call Kotlin from Dart and a `VmState` ChangeNotifier that polls `/health` every 5 seconds.

**getWifiIp** is a MethodChannel call (`getWifiIp`) that reads the device's active non-loopback IPv4 address via `NetworkInterface.getNetworkInterfaces()`. The result is displayed on the Dashboard and in the Settings WiFi setup guide.

### 4.2 QEMU Setup

QEMU binaries installed as `jniLibs/arm64-v8a/` .so files with `exec_type` SELinux label. Symlinked from the Pockr project (not committed; 51 files).

| File | Role |
|---|---|
| `libqemu.so` | `qemu-system-aarch64` |
| `libqemu_img.so` | `qemu-img` |
| `lib*.so` (×49) | Shared dependencies |

### 4.3 VM Disk Layout

| Image | Type | Description |
|---|---|---|
| `base.qcow2.gz` | Asset (compressed) | Read-only Alpine root with Asterisk pre-installed |
| `base.qcow2` | Extracted | Decompressed on first run |
| `user.qcow2` | QCOW2 overlay | Writable overlay (8 GB virtual) — persists extensions, voicemail, CDR |

### 4.4 Guest (Alpine VM)

**init_bootstrap.sh** runs on the very first boot to configure Asterisk, generate self-signed TLS certs for WSS, and start the API server. OpenRC brings up Asterisk and the API server on every subsequent boot.

**api_server.py** is a FastAPI application on `0.0.0.0:7080` that:
- Manages PJSIP extensions (read/write `/etc/asterisk/pjsip.conf`)
- Queries active channels via `asterisk -rx "core show channels"`
- Tails Asterisk logs
- Reloads Asterisk config
- Proxies shell commands (Terminal screen)

**Asterisk configuration files:**
- `/etc/asterisk/pjsip.conf` — SIP transports + endpoints (managed by API server)
- `/etc/asterisk/extensions.conf` — dial plan (`from-internal`)
- `/etc/asterisk/rtp.conf` — RTP port range (10000–10019)
- `/etc/asterisk/manager.conf` — AMI config (127.0.0.1 only)
- `/etc/asterisk/http.conf` — ARI + WS HTTP server
- `/etc/asterisk/ari.conf` — ARI credentials
- `/etc/asterisk/pjsip_wizard.conf` — WebRTC transport (DTLS/SRTP, self-signed cert)

---

## 5. Networking

### SLIRP hostfwd table

QEMU SLIRP `hostfwd` entries with an empty host address bind to `0.0.0.0` — meaning the port is reachable from WiFi clients on the same network, not just localhost.

| Android port | Proto | Guest port | Service | Accessible from |
|---|---|---|---|---|
| 7080 | TCP | 7080 | FastAPI control server | 127.0.0.1 (app-internal) |
| 5038 | TCP | 5038 | Asterisk AMI | 127.0.0.1 (app-internal) |
| 8088 | TCP | 8088 | ARI (REST) + WS (SIP.js `ws:`) | WiFi |
| 8089 | TCP | 8089 | WSS TLS (SIP.js `wss:`) + ARI TLS | WiFi |
| 5060 | TCP | 5060 | SIP (TCP transport) | WiFi |
| 5060 | UDP | 5060 | SIP (UDP transport) | WiFi |
| 10000–10019 | UDP | 10000–10019 | RTP/SRTP media (10 concurrent calls) | WiFi |

The API and AMI ports are only used by the app itself; all SIP/RTP/WS ports are reachable by other WiFi devices.

### QEMU launch `-netdev` string

```
-netdev user,id=net0,
  hostfwd=tcp::7080-:7080,
  hostfwd=tcp::5038-:5038,
  hostfwd=tcp::8088-:8088,
  hostfwd=tcp::8089-:8089,
  hostfwd=tcp::5060-:5060,
  hostfwd=udp::5060-:5060,
  hostfwd=udp::10000-:10000, ... hostfwd=udp::10019-:10019
```

All 20 RTP UDP hostfwd entries are generated programmatically in `VmManager.buildNetdev()`.

### WiFi SIP client registration

1. User starts Stardial on the server phone.
2. Dashboard shows the device's WiFi IP (e.g., `192.168.1.42`).
3. On any other phone or laptop on the same WiFi:
   - SIP clients (Linphone, Zoiper, Bria): server = `192.168.1.42`, port `5060`
   - WebRTC browsers (SIP.js): WSS = `wss://192.168.1.42:8089/asterisk/sip`
4. Create extensions in the Stardial app (Extensions tab).
5. Clients register and can dial each other by extension number.

---

## 6. Token Authentication

1. `VmManager` generates a UUID on first launch, stored in `stardial_app_prefs`.
2. Injected into every QEMU boot via `-fw_cfg name=opt/api_token,string=<UUID>`.
3. `api_server.py` reads from `/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw`.
4. Every API call (except `/health`) requires `Authorization: Bearer <UUID>`.

---

## 7. Asterisk Configuration

### pjsip.conf (managed by API server)

```ini
[global]
type=global
user_agent=Stardial PBX

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[transport-tcp]
type=transport
protocol=tcp
bind=0.0.0.0:5060

[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
; cert_file and priv_key_file point to self-signed cert generated on first boot

; Extensions are appended dynamically by the API server
; Each extension = 3 stanzas: endpoint, auth, aor
; WebRTC endpoints include: dtls_auto_generate_cert=yes, media_encryption=dtls, ice_support=yes
```

### extensions.conf (static)

```ini
[from-internal]
exten => _X.,1,NoOp(Dial ${EXTEN})
 same => n,Dial(PJSIP/${EXTEN},30)
 same => n,Hangup()

exten => *97,1,VoicemailMain()
 same => n,Hangup()
```

### rtp.conf

```ini
[general]
rtpstart=10000
rtpend=10019
```

### manager.conf (AMI)

```ini
[general]
enabled=yes
port=5038
bindaddr=127.0.0.1

[stardial]
secret=stardial_ami_secret
read=all
write=all
```

### http.conf + ari.conf (ARI)

```ini
; http.conf
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
prefix=asterisk
tlsenable=yes
tlsbindaddr=0.0.0.0:8089
tlscertfile=/etc/asterisk/keys/cert.pem
tlsprivatekey=/etc/asterisk/keys/key.pem

; ari.conf
[general]
enabled=yes
pretty=yes
[stardial]
type=user
password=stardial_ari_pass
password_format=plain
```

---

## 8. Guest API Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/health` | No | Asterisk running status + version |
| GET | `/extensions` | Yes | List all PJSIP endpoints |
| POST | `/extensions` | Yes | Create endpoint (name, password, context, webrtc) |
| DELETE | `/extensions/{name}` | Yes | Remove endpoint + auth + aor stanzas |
| POST | `/asterisk/reload` | Yes | `asterisk -rx "module reload"` |
| GET | `/calls` | Yes | Active channels |
| POST | `/calls/hangup` | Yes | Hangup a channel |
| GET | `/logs` | Yes | Tail `/var/log/asterisk/messages` |
| POST | `/vm/exec` | Yes | Shell command on VM host |

---

## 9. QEMU Launch Command

```
libqemu.so
  -machine virt
  -cpu cortex-a53
  -smp <vcpu>
  -m <ram>
  -drive if=none,file=base.qcow2,id=base,format=qcow2,readonly=on
  -drive if=none,file=user.qcow2,id=user,format=qcow2
  -device virtio-blk-pci,drive=user
  -netdev user,id=net0,
      hostfwd=tcp::7080-:7080,
      hostfwd=tcp::5038-:5038,
      hostfwd=tcp::8088-:8088,
      hostfwd=tcp::8089-:8089,
      hostfwd=tcp::5060-:5060,
      hostfwd=udp::5060-:5060,
      hostfwd=udp::10000-:10000, ... hostfwd=udp::10019-:10019
  -device virtio-net-pci,netdev=net0,romfile=
  -fw_cfg name=opt/api_token,string=<TOKEN>
  -display none
  -serial stdio
  -kernel vmlinuz-virt
  -initrd initramfs-virt
  -append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 rootflags=rw modules=virtio_blk,ext4 api_token=<TOKEN> quiet"
```

---

## 10. UI Design

### Theme

Material 3 dark with a custom ColorScheme:

| Role | Color | Usage |
|---|---|---|
| Primary | `#2196F3` (blue) | Buttons, active states, icons |
| Secondary | `#00BFA5` (teal) | WebRTC badge, accents |
| Surface | `#1C1C2E` | Cards, bottom sheets |
| Background | `#0E0E1A` | Scaffold background |
| Terminal bg | `#080810` | Terminal output area |

### Tab structure

| Index | Tab | Icon | Content |
|---|---|---|---|
| 0 | Dashboard | signal_cellular | VM status, controls, WiFi IP card, SIP endpoints |
| 1 | Extensions | contacts | PJSIP endpoint list + add/delete |
| 2 | Calls | call (badged) | Live active channel list + hangup |
| 3 | Terminal | terminal | VM shell with quick command chips |
| 4 | Settings | settings | vCPU/RAM sliders, Asterisk config ref, WiFi guide |

### Dashboard layout

```
┌─────────────────────────────┐
│  StatusCard                 │  ← status dot + glow, version, SIP/RTP/ARI chips
├─────────────────────────────┤
│  VmControls (2×2 grid)      │  ← Start / Stop / Restart / Reload
├─────────────────────────────┤
│  WifiConnectionCard         │  ← device WiFi IP, SIP address with copy button
├─────────────────────────────┤
│  EndpointsCard              │  ← SIP / WS / WSS / ARI / AMI with copy buttons
├─────────────────────────────┤
│  SipJsCard                  │  ← WebRTC WSS endpoint, DTLS fingerprint loader
└─────────────────────────────┘
```

### Design principles

- All interactive cards use `color: 0xFF1C1C2E`, 14 px radius, 7% white border.
- Section headers: blue icon + bold blue title, muted subtitle.
- Empty states: centered icon with contextual message (different when VM is off vs no data).
- Calls tab badge shows live count of active channels.
- Terminal uses monospace green-on-dark with quick command chips above the input.

---

## 11. Build System

| Stage | Docker image | Output |
|---|---|---|
| Alpine base | `arm64v8/alpine:3.19` | `base.qcow2.gz` (~150 MB — larger than Pockr due to Asterisk) |
| APK build | `ubuntu:22.04` (amd64) | `stardial-release.apk` (~31.5 MB) |

APK builder uses `--platform linux/amd64` on Apple Silicon Macs (same as Pockr).

---

## 12. Asset Extraction Versioning

Same scheme as Pockr: marker file `assets_extracted.vN` in `filesDir`.
Bump `N` whenever `base.qcow2.gz` changes.

Current version: **v1**

---

## 13. Settings and SharedPreferences

| Preference | File | Key |
|---|---|---|
| vCPU count | `FlutterSharedPreferences` | `flutter.vcpu_count` |
| RAM (MB) | `FlutterSharedPreferences` | `flutter.ram_mb` |
| API token | `stardial_app_prefs` | `api_token` |
| AMI secret | `stardial_app_prefs` | `ami_secret` |

Defaults: vCPU = 2, RAM = 1024 MB.

---

## 14. Differences from Pockr (docker-app)

| Aspect | Pockr | Stardial |
|---|---|---|
| Guest service | Docker daemon | Asterisk 20 PBX |
| API server purpose | Container lifecycle | Extension mgmt + call control |
| Forwarded ports | 7080 only | 7080, 5038, 8088, 8089, 5060 TCP/UDP, 10000–10019 UDP |
| Alpine packages | docker docker-compose | asterisk asterisk-pjsip |
| VM RAM recommended | 2 GB | 1 GB (Asterisk is lighter than Docker) |
| Overlay persistence | Docker image layers | Asterisk config, voicemail, CDR |
| UI tabs | Dashboard, Containers, Terminal, Settings | Dashboard, Extensions, Calls, Terminal, Settings |
| External connectivity | None | WiFi SIP clients register to device LAN IP |

---

## 15. Limitations

- ARM64 only (`jniLibs/arm64-v8a/`)
- No KVM — TCG software emulation only; VM boot takes ~30–60 s
- SLIRP networking — no inbound connections from the internet (LAN WiFi only)
- RTP range limited to 10 port pairs (20 UDP hostfwds) = 10 concurrent calls max
- TLS cert is self-signed — SIP clients must accept untrusted cert or import CA
- Android may kill background processes under memory pressure despite ForegroundService

---

## 16. References

| Topic | Source |
|---|---|
| Asterisk PJSIP configuration | https://wiki.asterisk.org/wiki/display/AST/PJSIP+Configuration |
| Asterisk ARI | https://wiki.asterisk.org/wiki/display/AST/Getting+Started+with+ARI |
| Asterisk WebRTC / SIP.js | https://wiki.asterisk.org/wiki/display/AST/WebRTC+tutorial+using+SIPJS+and+Asterisk |
| QEMU SLIRP networking | https://wiki.qemu.org/Documentation/Networking |
| Alpine Asterisk package | https://pkgs.alpinelinux.org/package/edge/community/aarch64/asterisk |
| Pockr architecture (reference) | ../pockr/ARCHITECTURE.md |

_Last updated: 2026-03-07 (v1)_
