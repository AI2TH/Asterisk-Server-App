# Architecture — Asterisk PBX on Android (No Root)

## 1. Objective

A single Android APK that runs a full Asterisk telephony server on non-rooted devices by embedding a QEMU virtual machine running Alpine Linux. No external apps (no Termux), no root required.

---

## 2. Why a VM is Required

Same constraint as Pockr (docker-app): stock Android kernels on non-rooted devices lack kernel features required for container runtimes and for binding privileged ports. A QEMU VM provides a complete Linux environment with its own kernel — Asterisk runs normally inside the guest.

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
    │   └── ARI (REST Interface)  :8088 HTTP
    └── FastAPI control server  :7080
          ↑
          SLIRP hostfwd (multiple ports, see §5)
          ↑
Android host ports (127.0.0.1)
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

**Flutter UI** uses a `MethodChannel` to call Kotlin from Dart and a `VmState` provider that polls `/health` every 5 seconds.

### 4.2 QEMU Setup

Same as Pockr — QEMU binaries installed as `jniLibs/arm64-v8a/` .so files with `exec_type` SELinux label.

| File | Role |
|---|---|
| `libqemu.so` | `qemu-system-aarch64` |
| `libqemu_img.so` | `qemu-img` |
| `lib*.so` (×48) | Shared dependencies |

### 4.3 VM Disk Layout

| Image | Type | Description |
|---|---|---|
| `base.qcow2.gz` | Asset (compressed) | Read-only Alpine root with Asterisk pre-installed |
| `base.qcow2` | Extracted | Decompressed on first run |
| `user.qcow2` | QCOW2 overlay | Writable overlay (8 GB virtual) — persists config & voicemail |

### 4.4 Guest (Alpine VM)

**init_bootstrap.sh** runs on the very first boot to configure Asterisk and start the API server. OpenRC brings up Asterisk and the API server on every subsequent boot.

**api_server.py** is a FastAPI application on `0.0.0.0:7080` that:
- Manages PJSIP extensions (read/write `/etc/asterisk/pjsip.conf`)
- Queries active channels via `asterisk -rx "core show channels"`
- Tails Asterisk logs
- Reloads Asterisk config
- Proxies shell commands (Terminal screen)

**Asterisk configuration files** (see §7):
- `/etc/asterisk/pjsip.conf` — SIP transports + endpoints (managed by API server)
- `/etc/asterisk/extensions.conf` — dial plan
- `/etc/asterisk/rtp.conf` — RTP port range (10000–10019)
- `/etc/asterisk/manager.conf` — AMI config (127.0.0.1 only)
- `/etc/asterisk/http.conf` — ARI HTTP server
- `/etc/asterisk/ari.conf` — ARI credentials

---

## 5. Networking

### SLIRP hostfwd table

| Android port | Proto | Guest port | Service |
|---|---|---|---|
| 7080 | TCP | 7080 | FastAPI control server |
| 5038 | TCP | 5038 | Asterisk AMI |
| 8088 | TCP | 8088 | ARI (REST) + WS (SIP.js `ws:`) |
| 8089 | TCP | 8089 | WSS TLS (SIP.js `wss:`) + ARI TLS |
| 5060 | TCP | 5060 | SIP (TCP transport) |
| 5060 | UDP | 5060 | SIP (UDP transport) |
| 10000–10019 | UDP | 10000–10019 | RTP/SRTP media (10 concurrent calls) |

Each RTP port pair supports one call direction; 20 UDP ports = up to 10 concurrent calls.

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

### SIP client connectivity

External SIP clients on the same WiFi network can register with the Android device at `<device-LAN-IP>:5060`. SLIRP does **not** provide inbound connectivity from outside — Android must forward the port via its own network stack or the SIP client must be on the same device.

For on-device SIP: a SIP softphone (linphone, baresip) can register to `127.0.0.1:5060` which SLIRP delivers to the Asterisk guest.

---

## 6. Token Authentication

Same scheme as Pockr:
1. `VmManager` generates a UUID on first launch, stored in `stardial_app_prefs`
2. Injected into every QEMU boot via `-fw_cfg name=opt/api_token,string=<UUID>`
3. `api_server.py` reads from `/sys/firmware/qemu_fw_cfg/by_name/opt/api_token/raw`
4. Every API call (except `/health`) requires `Authorization: Bearer <UUID>`

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

; Extensions are appended dynamically by the API server
; Each extension = 3 stanzas: endpoint, auth, aor
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
| POST | `/extensions` | Yes | Create endpoint (name, password, context) |
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

## 10. Build System

| Stage | Docker image | Output |
|---|---|---|
| Alpine base | `arm64v8/alpine:3.19` | `base.qcow2.gz` (~150 MB — larger than Pockr due to Asterisk) |
| APK build | `ubuntu:22.04` (amd64) | `stardial-release.apk` |

APK builder uses `--platform linux/amd64` on Apple Silicon Macs (same as Pockr).

---

## 11. Asset Extraction Versioning

Same scheme as Pockr: marker file `assets_extracted.vN` in `filesDir`.
Bump `N` whenever `base.qcow2.gz` changes.

Current version: **v1**

---

## 12. Settings and SharedPreferences

| Preference | File | Key |
|---|---|---|
| vCPU count | `FlutterSharedPreferences` | `flutter.vcpu_count` |
| RAM (MB) | `FlutterSharedPreferences` | `flutter.ram_mb` |
| API token | `stardial_app_prefs` | `api_token` |
| AMI secret | `stardial_app_prefs` | `ami_secret` |

---

## 13. Differences from Pockr (docker-app)

| Aspect | Pockr | Stardial |
|---|---|---|
| Guest service | Docker daemon | Asterisk 20 PBX |
| API server purpose | Container lifecycle | Extension mgmt + call control |
| Forwarded ports | 7080 only | 7080, 5038, 8088, 5060 TCP/UDP, 10000–10019 UDP |
| Alpine packages | docker docker-compose | asterisk asterisk-pjsip |
| VM RAM recommended | 2 GB | 1 GB (Asterisk is lighter than Docker) |
| Overlay persistence | Docker image layers | Asterisk voicemail + CDR |
| UI tabs | Dashboard, Containers, Terminal, Settings | Dashboard, Extensions, Calls, Terminal, Settings |

---

## 14. Limitations

- ARM64 only (`jniLibs/arm64-v8a/`)
- No KVM — TCG software emulation only
- SLIRP networking — no inbound from outside the device without additional port forwarding
- RTP range limited to 10 ports (20 UDP hostfwds) = 10 concurrent calls max
- No WebRTC gateway in v1 — SIP clients must support plain SIP over UDP/TCP

---

## 15. References

| Topic | Source |
|---|---|
| Asterisk PJSIP configuration | https://wiki.asterisk.org/wiki/display/AST/PJSIP+Configuration |
| Asterisk ARI | https://wiki.asterisk.org/wiki/display/AST/Getting+Started+with+ARI |
| QEMU SLIRP networking | https://wiki.qemu.org/Documentation/Networking |
| Alpine Asterisk package | https://pkgs.alpinelinux.org/package/edge/community/aarch64/asterisk |
| Pockr architecture (reference) | ../pockr/ARCHITECTURE.md |

_Last updated: 2026-03-06 (v1)_
