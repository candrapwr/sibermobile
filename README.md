<div align="center">

<img src="assets/branding/sibermobile_icon.png" alt="SiberMobile" width="96">

# SiberMobile

**Asisten AI serbaguna untuk Android — privat, dapat diperluas, dan siap
berinteraksi dengan perangkat.**

Tanya apa saja, diskusikan ide, tulis dan analisis dokumen, atau minta AI
menjalankan kemampuan perangkat melalui tool yang aman. SiberMobile memakai
provider OpenAI-compatible yang dapat dikonfigurasi sendiri; tidak ada API key
yang ditanam di aplikasi dan data sesi tetap tersimpan di perangkat.

[![Flutter](https://img.shields.io/badge/Flutter-3.47%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-API%2024%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![Tests](https://img.shields.io/badge/tests-34%20passing-success)](#testing)
[![Status](https://img.shields.io/badge/status-in%20development-orange)](#roadmap)

</div>

> Bagian dari ekosistem Siber — dibangun untuk menjadi fondasi asisten AI
> personal di perangkat Android.

## Ringkasan proyek

SiberMobile adalah aplikasi Flutter yang menggabungkan chat AI streaming,
tool-calling, compact context, lampiran file lokal, dan sandbox per sesi dalam
satu pengalaman chat. Arsitektur inti dipisahkan dari UI sehingga provider,
agent, registry tool, dan penyimpanan sesi tetap mudah diuji serta diperluas.

Implementasinya terinspirasi dari arsitektur **siberflow** `packages/desktop`
(Electron/TypeScript), lalu disederhanakan menjadi satu provider custom untuk
Android.

**Status verifikasi** (Flutter 3.47.6 / Dart 3.13.5)

| Pemeriksaan | Hasil |
|---|---|
| `flutter analyze` | ✅ 0 issue |
| `flutter test` | ✅ 34 test lolos |
| `flutter build apk --debug` | ✅ berhasil |
| Uji runtime di perangkat/emulator | ⚠️ belum dilakukan |

---

## Daftar isi

- [Fitur](#fitur)
- [Mulai cepat](#mulai-cepat)
- [Cara kerja AI](#cara-kerja-ai)
- [Struktur proyek](#struktur-proyek)
- [Menjalankan proyek](#menjalankan-proyek)
- [Konfigurasi provider](#konfigurasi-provider)
- [Daftar tool](#daftar-tool)
- [Menambahkan tool baru](#menambahkan-tool-baru)
- [Penyimpanan data](#penyimpanan-data)
- [Permission Android](#permission-android)
- [Konfigurasi build Android](#konfigurasi-build-android)
- [Testing](#testing)
- [Keterbatasan](#keterbatasan)
- [Roadmap](#roadmap)

---

## Mulai cepat

### Prasyarat

- Flutter `3.47+` dan Dart `3.13+`
- Android SDK dengan platform 35/36
- JDK 17 atau lebih baru
- Perangkat Android API 24+ atau emulator

### Jalankan dari source

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Setelah aplikasi terbuka, masuk ke **Pengaturan** dan isi Base URL, API key,
serta nama model. Contoh endpoint:

```text
Base URL : https://api.openai.com/v1
Model    : gpt-4o-mini
```

API key disimpan menggunakan secure storage Android. Gunakan HTTPS untuk
endpoint publik; Base URL `http://` hanya cocok untuk gateway lokal/LAN yang
memang Anda kontrol.

---

## Fitur

- **Chat streaming** — teks AI muncul per-token (SSE), bukan setelah selesai.
- **Compact context** — saat prompt mencapai ambang context window, AI membuat
  ringkasan turn lama sendiri dan tetap mempertahankan turn terbaru secara
  utuh. Riwayat asli tidak dihapus dari sesi.
- **Meter konteks token** — bar di bawah input menampilkan prompt token terakhir,
  context window, persentase pemakaian, serta garis ambang auto-compact.
- **Tema manual** — pilih *Ikuti tema perangkat*, *Terang*, atau *Gelap* dari
  Pengaturan. Perubahan diterapkan langsung dan tetap tersimpan setelah aplikasi
  dibuka kembali.
- **Tool inti selalu aktif** — `get_current_time` membaca jam perangkat,
  `ask_user` membuka pertanyaan/opsi dari AI, dan `send_file_to_user` membuat
  file hasil kerja siap disimpan ke HP; semuanya tidak bisa dinonaktifkan.
- **24 tool opsional** untuk perangkat dan web: info perangkat, baterai,
  jaringan, GPS, kamera/media, TTS/STT, getar, notifikasi, kontak, aplikasi,
  file sandbox, interaksi sistem, dan pencarian web. Asisten tetap berguna
  penuh tanpa memakai tool opsional apa pun.
- **Web search Exa-compatible** — `web_search` memiliki mode `search` untuk
  menemukan sumber dan mode `content` untuk membaca URL. Endpoint bisa
  `https://api.exa.ai` atau proxy kompatibel; tool baru aktif setelah endpoint,
  API key, dan toggle-nya lengkap.
- **Lampiran file apa pun** — pilih satu atau beberapa file dari perangkat,
  maksimal **10 MB per file**. File disalin lokal ke working directory sesi dan
  AI menerima path sandbox relatifnya; riwayat chat hanya menampilkan nama file.
- **Kirim file ke pengguna** — AI dapat menawarkan file hasil kerja melalui
  kartu riwayat dengan nama, ukuran, dan tombol **Simpan**. Pemilihan lokasi
  dilakukan lewat system file picker Android; file tidak dikirim ke server lain.
- **Status tool call ringkas** — setiap pemanggilan tool hanya menampilkan nama
  dan status Menunggu/Menjalankan/Berhasil/Gagal; argumen dan hasil tetap
  diproses agent tanpa membebani UI.
- **Branding SiberMobile** — logo yang sama dipakai di dalam aplikasi, launcher
  legacy/adaptive, ikon bulat, dan splash screen Android terang/gelap.
- **Persetujuan aksi berisiko** — aksi seperti hapus file, TTS/STT, atau membuka
  pengaturan sistem memunculkan dialog konfirmasi dulu. Bisa dimatikan di
  Pengaturan.
- **Toggle per tool opsional** — matikan tool perangkat dari layar *Tool
  perangkat*; tool inti tetap terpasang di registry.
- **Riwayat percakapan** — tiap sesi disimpan sebagai JSON, bisa dibuka lagi.
- **API key terenkripsi** — disimpan lewat `flutter_secure_storage`
  (Android Keystore + AES-GCM), bukan di file plain.

---

## Cara kerja AI

Satu putaran (*turn*) percakapan:

```
user mengetik / melampirkan file ≤10 MB
   │
   ▼
ChatController.send()            lib/app/chat_controller.dart
   │  buat sesi + working dir (bila belum ada), salin file ke uploads/
   │  bangun provider + registry + agent dari settings
   ▼
Agent.send()                     lib/core/agent/agent.dart
   │  prompt token terakhir ≥ contextWindow × threshold?
   │  ya → AI meringkas turn lama, simpan ContextSummary
   │  loop maksimal `maxIterations` (default 25)
   ▼
OpenAiCompatibleProvider         lib/core/ai/openai_compatible_provider.dart
   │  POST {baseUrl}/chat/completions  (stream: true)
   │  tools = registry.schemas()
   ▼
parseSse()                       lib/core/ai/sse.dart
   │  ContentDelta      → gelembung teks bertambah
   │  ToolCallStart/Args → status tool muncul dan diperbarui
   │  StreamDone        → pesan assistant final
   ▼
finish_reason == "tool_calls" ?
   │ ya                                  │ tidak
   ▼                                     ▼
ToolRegistry.execute()            kembalikan teks final
   │  requiresApproval? → dialog konfirmasi
   │  permission needed? → ensurePermission()
   ▼
Tool.execute(args, ctx)           lib/core/tools/hardware/*.dart
   │  hasil sebagai String (JSON)
   ▼
pesan role:"tool" → loop lagi ke provider
```

Poin penting yang diwarisi dari siberflow dan tetap dipertahankan:

- **Tool call streaming diakumulasi per `index`**, karena provider mengirim
  `id`, `name`, dan fragmen `arguments` secara terpisah.
- **Assistant `content` tidak pernah null/kosong** tanpa `tool_calls` — server
  OpenAI-compatible yang ketat menolak itu dengan HTTP 400, jadi fallback-nya
  satu spasi.
- **`finish_reason` dinormalisasi** (`end_turn`, `function_call`, `MAX_TOKENS`,
  dll.) supaya gateway non-OpenAI tetap jalan.
- **Auto-continue**: jawaban yang terpotong `length` dilanjutkan otomatis
  (maks. 4 kali) dengan nudge "lanjutkan dari titik berhenti".
- **Retry jawaban kosong**: model *reasoning-only* kadang tidak mengirim konten
  visible; agent mencoba sekali lagi, lalu memakai fallback teks.
- **Usage lintas gateway**: parser menerima kedua bentuk statistik umum,
  `prompt_tokens`/`completion_tokens` (Chat Completions) dan
  `input_tokens`/`output_tokens` (Responses-style gateway). Frame usage yang
  datang setelah `finish_reason` juga tetap ditangkap singkat.
- **Tool dieksekusi berurutan**, tidak paralel — kamera dan mikrofon adalah
  sumber daya tunggal yang akan *race* bila dipakai bersamaan.

---

## Struktur proyek

```
lib/
├── main.dart                        # entry point + theme + bootstrap gate
│
├── core/                            # ← murni Dart, tanpa Flutter UI
│   │                                #   (mudah dites, bisa dipakai host lain)
│   ├── ai/
│   │   ├── provider.dart            # interface ChatProvider (contract agent)
│   │   ├── openai_compatible_provider.dart  # implementasi HTTP + SSE
│   │   ├── sse.dart                 # parser Server-Sent Events + idle timeout
│   │   └── types.dart               # Message, ToolCall, StreamEvent, UsageStats,
│   │                                #   CancellationToken, FinishReason
│   ├── agent/
│   │   ├── agent.dart               # loop tool-calling (Agent + AgentEvents)
│   │   ├── context_compaction.dart  # ringkasan AI + splice history konteks
│   │   └── prompts.dart             # builder system prompt
│   ├── session/
│   │   └── session_store.dart       # Session, SessionSummary, simpan/muat JSON
│   ├── settings/
│   │   └── settings.dart            # AppSettings + SettingsStore (+ API key)
│   └── tools/
│       ├── tool.dart                # interface Tool, ToolContext, parser arg
│       ├── registry.dart            # lookup + execute + gerbang approval
│       ├── core_tools.dart          # tool inti yang selalu aktif
│       ├── file_delivery.dart       # tool kirim file ke system save picker
│       ├── registry_builder.dart    # allTools + buildRegistry(settings)
│       ├── permissions.dart         # ensurePermission, PermissionOutcome
│       ├── results.dart             # jsonResult, errorResult, round2/round3
│       ├── web_tools.dart           # web_search: search + content Exa-compatible
│       └── hardware/                # 12 file, 23 tool perangkat (lihat Daftar tool)
│
└── app/                             # ← lapisan Flutter (widget + state)
    ├── chat_controller.dart         # ChangeNotifier: jembatan core ↔ UI
    ├── chat_items.dart              # model item list chat
    ├── file_uploads.dart            # validasi/salin lampiran ke sandbox sesi
    ├── theme/
    │   └── app_theme.dart           # palet SiberMobile + Material 3
    ├── screens/
    │   ├── chat_screen.dart         # layar utama
    │   ├── settings_screen.dart     # konfigurasi provider + tuning agent
    │   ├── tools_screen.dart        # toggle per tool
    │   └── sessions_screen.dart     # riwayat percakapan
    └── widgets/
        ├── common_widgets.dart      # logo, surface, heading, status
        ├── message_widgets.dart     # Markdown chat + status tool call
        ├── composer.dart            # input + tombol kirim/stop
        └── prompt_dialogs.dart      # dialog ask_user + approval

assets/branding/sibermobile_icon.png       # sumber logo UI Flutter
android/app/src/main/AndroidManifest.xml   # permission + queries
android/app/src/main/res/mipmap-*          # launcher legacy/adaptive/round
android/app/build.gradle.kts               # minSdk 24 + desugaring
test/core_agent_test.dart                  # unit test agent/registry/SSE
test/widget_test.dart                      # smoke test UI
```

**Prinsip pemisahan:** `lib/core/` tidak mengimpor `package:flutter/material.dart`.
Provider, agent loop, registry, dan session store semuanya Dart murni — hanya
`app/` yang tahu soal widget. Artinya logika AI bisa dites tanpa device dan bisa
dipindah ke host lain (mis. CLI atau service) tanpa ditulis ulang.

---

## Menjalankan proyek

**Prasyarat:** Flutter 3.47+ (Dart 3.13+), Android SDK dengan platform 35/36,
JDK 17+.

```bash
flutter pub get
flutter analyze          # harus 0 issue
flutter test             # 34 test
flutter run              # perlu device/emulator Android (API 24+)
flutter build apk --debug
```

> Build APK debug pertama memakan waktu beberapa menit (unduh Gradle +
> dependency). Artefak: `build/app/outputs/flutter-apk/app-debug.apk`.

---

## Konfigurasi provider

Buka **Pengaturan** (ikon gerigi) di aplikasi, lalu isi tiga hal wajib:

| Field | Contoh | Catatan |
|---|---|---|
| **Base URL** | `https://api.openai.com/v1` | Tanpa `/chat/completions` — path itu ditambahkan otomatis. Trailing `/` dibersihkan sendiri. |
| **API key** | `sk-...` | Disimpan terenkripsi. Kosongkan field ini untuk *tidak mengubah* key yang sudah tersimpan. |
| **Model** | `gpt-4o-mini` | Nama model apa adanya, dikirim di field `model`. |

Dua tombol bantu:

- **Ambil daftar model** — memanggil `GET {baseUrl}/models`, lalu menampilkan
  bottom sheet untuk dipilih. Kalau gateway tidak punya endpoint itu, daftar
  kosong dan kamu isi manual.
- **Tes koneksi** — mengirim permintaan kecil non-streaming (`max_tokens: 8`)
  dan menampilkan balasan atau errornya.

**Tuning agent** (opsional):

| Setting | Default | Fungsi |
|---|---|---|
| Temperature | `0.7` | Sampling model |
| Max tokens | `50000` | Batas output per panggilan; bisa diubah manual sesuai gateway/model |
| Max iterasi | `25` | Batas putaran tool-call dalam satu pesan |
| Auto-continue | on | Lanjutkan jawaban yang terpotong batas token |
| Ringkas konteks otomatis | on | AI merangkum turn lama saat ambang tercapai |
| Context window | `200000` | Batas token prompt model; isi sesuai model/provider |
| Ringkas pada | `80%` | Rasio context window yang memicu ringkasan |
| Turn terbaru disimpan | `2` | Turn lengkap terbaru yang tidak diringkas |
| `stream_options.include_usage` | on | Matikan bila gateway menolak field ini (konsekuensi: tidak ada statistik token) |
| Kirim `reasoning_effort` | **off** | Hanya untuk gateway yang mendukung; banyak gateway menolak field tak dikenal |
| Minta izin aksi berisiko | on | Dialog konfirmasi sebelum tool destruktif |

### Web search (Exa-compatible)

Pencarian web adalah tool opsional yang kompatibel dengan API Exa. Konfigurasinya
tersedia di kartu **Web search** pada layar Pengaturan:

| Field | Nilai awal | Catatan |
|---|---|---|
| Endpoint | `https://api.exa.ai` | Aplikasi menambahkan `/search` dan `/contents` secara otomatis. Endpoint proxy dengan kontrak yang sama juga bisa dipakai. |
| API key | kosong | Disimpan terenkripsi di Android Keystore. Wajib diisi agar tool tersedia untuk AI. |

Setelah endpoint dan key diisi, aktifkan toggle `web_search` di kartu ini atau
di layar **Tool perangkat**. Jika salah satu belum tersedia, tool tidak
didaftarkan ke agent dan tidak dikirim dalam schema tools. Toggle tetap terlihat
sebagai **Atur** agar konfigurasi dapat dilengkapi kapan saja.

Tool memiliki dua mode:

- `search` — menemukan sumber berdasarkan query dan mengembalikan judul, URL,
  tanggal, penulis, serta highlight ringkas.
- `content` — mengambil isi URL tertentu dari endpoint `/contents` dengan batas
  karakter yang diminta.

### Tampilan

Tema aplikasi dapat diubah dari bagian **Tampilan** di Pengaturan:

| Pilihan | Perilaku |
|---|---|
| Ikuti tema perangkat | Mengikuti dark/light mode Android |
| Terang | Selalu memakai tema terang |
| Gelap | Selalu memakai tema gelap |

Pilihan tema diterapkan dan disimpan langsung; tombol **Simpan pengaturan**
tetap digunakan untuk menyimpan konfigurasi provider dan agent.

---

## Daftar tool

3 tool inti dan 24 tool opsional dalam 14 kategori. Tool inti tidak bisa
dinonaktifkan. Kolom 🔒 = `requiresApproval` (dialog konfirmasi dulu bila
"Minta izin aksi berisiko" aktif). Kolom **Izin** = permission runtime yang
diminta otomatis saat tool dipanggil.

### Core (selalu aktif)
| Tool | Fungsi | Izin |
|---|---|---|
| `get_current_time` | Waktu/tanggal perangkat saat ini, UTC, offset, zona waktu, dan timestamp. Dipanggil AI saat butuh informasi waktu aktual. | – |
| `ask_user` | AI bertanya balik lewat dialog pilihan atau input bebas ketika butuh keputusan/konfirmasi. | – |
| `send_file_to_user` | Menandai file di workdir sesi agar pengguna dapat menyimpannya melalui system file picker Android. | – |

### Device
| Tool | Fungsi | Izin |
|---|---|---|
| `get_device_info` | Model, brand, versi Android, SDK, ABI, RAM | – |
| `get_storage_info` | Total/sisa/terpakai penyimpanan (MB) + working dir | – |
| `get_app_info` | Nama paket, versi app, build number | – |

### Battery
| Tool | Fungsi | Izin |
|---|---|---|
| `battery_status` | Persentase, status charging, battery saver | – |

### Network
| Tool | Fungsi | Izin |
|---|---|---|
| `network_info` | Tipe koneksi + SSID/IP/gateway Wi-Fi | Location (detail Wi-Fi di Android 8+) |
| `web_search` | Pencarian web (`mode: search`) atau pengambilan isi URL (`mode: content`) melalui endpoint Exa-compatible. Hanya terdaftar jika endpoint, API key, dan toggle aktif. | – |

### Location
| Tool | Fungsi | Izin |
|---|---|---|
| `get_current_location` | GPS: lintang, bujur, akurasi, ketinggian, kecepatan. Param `accuracy`: low/medium/high/best | Location |

### Camera
| Tool | Fungsi | Izin |
|---|---|---|
| `take_photo` | Ambil foto (depan/belakang), simpan ke working dir | Camera |
| `pick_gallery_image` | Pilih gambar dari galeri, salin ke working dir | Photos/Storage |

### Media
| Tool | Fungsi | Izin |
|---|---|---|
| `play_audio` | Putar audio dari path atau URL | – |
| `stop_audio` | Hentikan pemutaran audio | – |

### Speech
| Tool | Fungsi | Izin |
|---|---|---|
| `speak_text` 🔒 | Ucapkan teks (TTS). Param `language`, `rate`, `pitch` | – |
| `stop_speaking` | Hentikan TTS | – |
| `speech_to_text` 🔒 | Dikte dari mikrofon. Param `durationSeconds` (1–60), `language` (default `id-ID`) | Microphone |

### System
| Tool | Fungsi | Izin |
|---|---|---|
| `vibrate` | Getarkan perangkat (`durationMs`) | – |
| `open_app_settings` 🔒 | Buka layar pengaturan Android (Wi‑Fi, Bluetooth, lokasi, notifikasi, baterai, …) | – |

### Notification
| Tool | Fungsi | Izin |
|---|---|---|
| `show_notification` | Kirim notifikasi lokal (`title`, `body`, `id`) | Notification (Android 13+) |

### Contacts
| Tool | Fungsi | Izin |
|---|---|---|
| `search_contacts` | Cari kontak by nama/telepon/email (`matchBy`, `limit`) | Contacts |

### Apps
| Tool | Fungsi | Izin |
|---|---|---|
| `list_installed_apps` | Daftar aplikasi terpasang (`search`, `limit`, `includeSystem`) | – |
| `launch_app` | Buka aplikasi by nama paket | – |

### Files (sandbox)
| Tool | Fungsi | Izin |
|---|---|---|
| `read_file` | Baca file (`offset`, `limit`) | – |
| `write_file` | Tulis/timpa file | – |
| `list_dir` | Isi direktori | – |
| `delete_file` 🔒 | Hapus file/direktori | – |

Semua path diselesaikan lewat `resolveWithin()` dan **ditolak bila keluar dari
working dir sesi** — `..` dan path absolut tidak bisa kabur dari sandbox.

File yang dipilih dari tombol lampiran juga disalin ke `uploads/` dalam working
dir sesi. Batasnya **10 MB per file**; AI menerima contoh path relatif
`uploads/laporan.pdf`, sedangkan gelembung riwayat hanya menampilkan
`laporan.pdf`.

File hasil kerja tidak langsung masuk galeri atau folder publik. AI memanggil
`send_file_to_user`, lalu pengguna menekan **Simpan** pada kartu file di riwayat
dan memilih lokasi tujuan sendiri.

---

## Menambahkan tool baru

Ini alur yang paling sering kamu butuhkan. Empat langkah, tanpa menyentuh UI:

**1. Buat kelasnya** di `lib/core/tools/hardware/<grup>_tools.dart` (atau
pindahkan ke grup tool baru bila kategorinya bukan perangkat):

```dart
import '../tool.dart';
import '../results.dart';

class GetCurrentTimeTool extends Tool {
  @override
  String get name => 'get_current_time';

  @override
  String get description =>
      'Read the current local time on the device.';

  @override
  String get category => 'Utility';                 // grouping di layar Tools

  @override
  bool get requiresApproval => false;               // true = dialog konfirmasi

  @override
  Map<String, dynamic> get parameters => const {
        'type': 'object',
        'properties': <String, dynamic>{
        },
        'additionalProperties': false,
      };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    return jsonResult({'localTime': DateTime.now().toIso8601String()});
  }
}

// Ekspos lewat list grup agar registry_builder mengenalinya.
final List<Tool> utilityTools = [GetCurrentTimeTool()];
```

**2. Daftarkan** di `lib/core/tools/registry_builder.dart` — tambahkan import
dan spread ke `allTools`:

```dart
import 'hardware/utility_tools.dart';

final List<Tool> allTools = <Tool>[
  ...deviceTools,
  ...utilityTools,   // ← di sini
  // ...
];
```

Bila kategorinya baru, tambahkan juga namanya ke `order` di `toolsByCategory()`
agar posisinya stabil (bukan wajib — kategori tak dikenal otomatis ditaruh
paling akhir).

**3. Tambahkan permission** ke `android/app/src/main/AndroidManifest.xml` bila
tool-nya butuh izin baru. Bila pakai `Permission.xxx` yang belum ada di
`permissionByName()`, tambahkan case-nya di `lib/core/tools/permissions.dart`.

**4. Verifikasi:**

```bash
flutter analyze && flutter test && flutter build apk --debug
```

Selesai — tool langsung muncul di layar *Tool perangkat* (bisa di-toggle) dan
terkirim ke model sebagai JSON schema. Untuk tool yang wajib selalu tersedia,
override `isCoreTool` menjadi `true`; ia tetap terdaftar meski pengguna
mematikan semua tool opsional.

### Konvensi yang harus dijaga

- **`execute()` selalu mengembalikan String**, jangan melempar exception keluar.
  Registry menangkap error dan mengubahnya jadi `Error: ...` supaya model bisa
  bereaksi, bukan membuat turn crash.
- **Gunakan `jsonResult()` / `errorResult()`** agar hasil konsisten dan otomatis
  terpotong di 20.000 karakter (`truncateResult`) — mencegah satu tool call
  menghabiskan context window.
- **Parser argumen**: `requireString`, `optionalString`, `optionalInt`,
  `optionalDouble`, `optionalBool`. Jangan baca `args['x']` mentah.
- **`description` adalah prompt**. Tulis apa yang dikembalikan tool dan kapan
  dipakai — model memutuskan memakai tool hanya dari teks ini.
- **Tandai `requiresApproval = true`** untuk aksi yang tidak bisa ditarik
  kembali (hapus, kirim, ubah setelan sistem).
- **Tool dieksekusi berurutan.** Kalau tool-mu memegang sumber daya tunggal
  (kamera atau mikrofon), jangan asumsikan bisa jalan paralel.

---

## Penyimpanan data

Semua lokal, tidak ada server milik aplikasi ini.

| Data | Lokasi | Format |
|---|---|---|
| Settings (provider, tema, tuning compact, endpoint web, `disabledTools`) | `shared_preferences`, key `sibermobile.settings.v1` | JSON |
| **API key provider AI** | `flutter_secure_storage` (Android Keystore, AES-GCM), key `custom` | terenkripsi |
| **API key web search** | `flutter_secure_storage` (Android Keystore, AES-GCM), key `exa` | terenkripsi |
| Riwayat percakapan + `ContextSummary` + usage token + metadata lampiran | `<appDocuments>/sessions/<id>.json` | JSON, ditulis atomik via `.tmp` → rename |
| Working dir tool file + lampiran | `<appDocuments>/work/<id>/uploads/` | sandbox per sesi |

ID sesi berupa timestamp UTC + suffix acak, jadi urut menurut waktu dibuat.
File sesi ditulis atomik supaya crash di tengah penulisan tidak merusak
riwayat; file yang korup dilewati saat listing, bukan menggagalkan seluruh
daftar.

**Catatan:** API key dikirim langsung dari perangkat ke Base URL yang kamu isi.
Bila Base URL memakai `http://` (bukan `https://`), Android akan menolaknya
karena `usesCleartextTraffic` dimatikan. Gunakan HTTPS, termasuk untuk gateway
yang diakses dari perangkat.

---

## Permission Android

Deklarasi lengkap ada di `android/app/src/main/AndroidManifest.xml`. Yang
berkategori *dangerous* diminta saat runtime, tepat sebelum tool yang
membutuhkannya jalan (lewat `ensurePermission()`).

| Permission | Dipakai oleh |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | panggilan ke API AI |
| `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `CHANGE_NETWORK_STATE` | `network_info` |
| `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` | `get_current_location`, detail Wi-Fi |
| `CAMERA` | `take_photo` |
| `RECORD_AUDIO` | `speech_to_text` |
| `POST_NOTIFICATIONS` | `show_notification` |
| `READ_CONTACTS` | `search_contacts` |
| `READ_MEDIA_IMAGES/AUDIO/VIDEO`, `READ/WRITE_EXTERNAL_STORAGE` | galeri & file |
| `QUERY_ALL_PACKAGES` | `list_installed_apps` |
| `VIBRATE` | getar |

Blok `<queries>` mendeklarasikan intent yang dilihat aplikasi (`VIEW`,
`PROCESS_TEXT`, `RecognitionService`, `TTS_SERVICE`) — wajib sejak Android 11
agar tautan Markdown dan TTS/STT bisa menemukan aplikasi atau layanan tujuan.

**Bila permission ditolak permanen**, tool tidak retry buta. Ia mengembalikan
pesan yang menyuruh model memberi tahu user untuk mengaktifkannya di pengaturan
sistem — dan AI bisa memakai `open_app_settings` untuk membukanya.

---

## Konfigurasi build Android

Tiga penyesuaian dari template Flutter standar, semuanya di
`android/app/build.gradle.kts` dan `AndroidManifest.xml`:

```kotlin
compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    isCoreLibraryDesugaringEnabled = true   // ← wajib
}

defaultConfig {
    minSdk = maxOf(24, flutter.minSdkVersion)  // ← plugin butuh API 24
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

- **Desugaring** dibutuhkan `flutter_local_notifications` v10+ (backport
  `java.time`). Tanpa ini build gagal meski kamu tidak memakai notifikasi
  terjadwal.
- **minSdk 24** karena `flutter_local_notifications`, `flutter_secure_storage`,
  dan `flutter_contacts` semuanya butuh API 24.
- **`MainActivity` memakai `FlutterActivity`** standar. Ubah ke
  `FlutterFragmentActivity` hanya bila nanti menambahkan fitur biometrik
  `local_auth`.

### ⚠️ Pin versi `permission_handler`

`pubspec.yaml` mengunci **`permission_handler: 12.0.3`** — jangan naikkan tanpa
memeriksa ini:

```
permission_handler 13.x
  → permission_handler_android 14.x
      → compileSdk = 37  (hardcode di build.gradle.kts plugin)
```

SDK platform 37 sekarang diinstal sebagai folder `android-37.0` (skema versi
minor baru), sedangkan AGP 8.11.1 mencari `android-37`. Hasilnya build gagal:

```
Failed to find target with hash string 'android-37'
```

Versi 12.0.3 menarik `permission_handler_android` 13.0.1 yang masih memakai
`compileSdkVersion 35`. **Cara melepas pin nanti:** bila AGP/Flutter sudah
mengenali skema `android-37.0`, naikkan ke 13.x lalu jalankan
`flutter build apk --debug` untuk memastikan. Alternatif darurat:
`flutter build apk --android-skip-build-dependency-validation`.

---

## Testing

```bash
flutter test                        # semua (34 test)
flutter test test/core_agent_test.dart
flutter test test/widget_test.dart
```

**`test/core_agent_test.dart`** — murni Dart, tanpa device:

- `parseSse`: decode frame `data:`, berhenti di `[DONE]`, mengabaikan komentar
  keep-alive.
- `ToolRegistry`: tool tak dikenal, argumen JSON rusak, error yang dilempar
  tool — semuanya dikembalikan sebagai String, bukan exception.
- **Gerbang approval**: tool `requiresApproval` diblokir saat ditolak, jalan
  saat diizinkan, dan otomatis diizinkan bila callback approval null.
- **Agent loop**: streaming teks, tool call → eksekusi → jawaban final (2
  panggilan provider, hasil tool masuk history), fallback untuk jawaban kosong,
  dan pembatalan lewat `CancellationToken`.
- **Compact context**: saat ambang token tercapai, turn lama diringkas oleh
  provider tanpa mengirim tool, dua turn terbaru dipertahankan, dan request
  berikutnya menerima summary + tail verbatim.
- **Usage gateway**: usage `input_tokens`/`output_tokens` yang datang pada
  frame setelah terminal tetap dipakai sebagai statistik konteks.
- **Lampiran**: file disalin ke `uploads/` sandbox, batas 10 MB dipaksa ulang
  saat salin, dan metadata tampilan tidak mengekspos path working directory.
- **Kirim file**: metadata `send_file_to_user` diuji tetap relatif terhadap
  sandbox; widget menguji kartu file dan alur tombol simpan.
- **Tema**: preferensi `system`, `light`, dan `dark` diuji melalui serialisasi
  settings agar tetap konsisten setelah aplikasi dibuka kembali.
- **Web search**: tool tidak masuk registry tanpa konfigurasi endpoint/key,
  toggle tetap dihormati, dan client fake memverifikasi request `/search` serta
  `/contents` beserta header autentikasinya.

Agent diuji memakai `_FakeProvider` yang meng-*implement* interface
`ChatProvider` dan memutar ulang `StreamEvent` yang sudah disiapkan. Inilah
alasan interface itu ada di `lib/core/ai/provider.dart` — agent tidak terikat ke
kelas HTTP konkret, jadi tidak ada jaringan dalam test.

**`test/widget_test.dart`** — smoke test UI: app boot, menampilkan empty state
"belum dikonfigurasi", lalu membuka layar Settings. Channel
`flutter_secure_storage` di-stub (read → null) karena tidak ada platform channel
di test binding; tanpa stub, bootstrap menggantung dan `pumpAndSettle` timeout.

---

## Keterbatasan

Jujur soal apa yang **belum** ada, supaya tidak salah asumsi:

### Belum diverifikasi
- **Belum diuji runtime di device/emulator.** Build APK debug sukses dan semua
  test lolos, tapi tidak ada satu pun tool yang pernah dijalankan di Android
  sungguhan. Ekspektasi realistis saat pertama `flutter run`: beberapa plugin
  butuh penyesuaian izin/perilaku versi.

### Celah fungsional
- **Tidak ada dukungan multimodal.** `take_photo` menyimpan gambar dan
  mengembalikan *path*-nya, tapi `Message.toApiJson()` hanya mengirim `content`
  bertipe string — gambar tidak pernah dikirim ke model. AI tahu foto sudah
  diambil, tidak tahu isinya. Untuk menambahkannya, `content` harus jadi array
  `[{type:text},{type:image_url}]` (lihat Roadmap).
- **Lampiran belum berarti pembacaan semua format.** AI mengetahui path file
  yang diunggah dan dapat memakai tool file untuk teks, tetapi PDF, dokumen
  Office, gambar, atau binary tidak otomatis diubah menjadi isi yang dapat
  dipahami model.
- **Hanya mode compact yang di-port.** Mode desktop lain (`drop`, `summary`,
  dan `recent`) tidak tersedia karena compact adalah strategi yang menjaga
  fakta percakapan paling baik untuk aplikasi chat ini. Pemicu otomatis
  memerlukan usage token dari gateway; bila gateway tidak mengirimnya, bar
  tetap tampil tetapi auto-compact belum punya ukuran prompt yang akurat.
- **Tidak ada `task_update` / sub-agent.** Mesin checklist dan `agent_general`/
  `agent_explorer` dari siberflow sengaja tidak di-port — terlalu berat untuk
  layar ponsel.
- **Tidak ada streaming untuk `reasoning_content`.** Provider menghitung
  panjangnya saja, tidak menampilkannya.
- **`play_audio` fire-and-forget.** Tidak menunggu selesai, tidak melaporkan
  durasi/posisi. `stop_audio` memakai player singleton global.

### Build & rilis
- **Release build belum dikonfigurasi.** `signingConfig` masih memakai debug
  key, jadi `flutter build apk --release` menghasilkan APK yang tidak bisa
  dipublikasikan. Ikon dan splash sudah custom, tetapi keystore belum ada.
- **APK debug relatif besar** — normal untuk debug build dengan plugin native.
  Untuk rilis gunakan `--split-per-abi` + R8/minify.
- `QUERY_ALL_PACKAGES` membuat aplikasi **kurang disukai untuk Play Store**
  (butuh deklarasi khusus). Kalau tidak perlu daftar semua aplikasi, hapus
  permission ini dan matikan tool `list_installed_apps`.

---

## Roadmap

Urutan yang disarankan — tiap poin berdiri sendiri dan bisa dikerjakan terpisah.

### Prioritas 1 — buat aplikasi benar-benar usable
- [ ] **Uji runtime di device.** Pasang APK debug, isi konfigurasi provider,
      coba tiap kategori tool, catat yang gagal. Ini prasyarat semua yang lain.
- [x] **Rapikan kategori tool** + daftar `order` di `toolsByCategory()`.
- [x] **Bersihkan dependensi tool dan dependency langsung yang belum dipakai.**
- [x] **Ikon aplikasi + splash screen** untuk launcher legacy/adaptive.
- [ ] **Keystore release + `--split-per-abi`.**

### Prioritas 2 — kemampuan AI
- [ ] **Tool AI umum**: tambahkan integrasi pencarian, knowledge base, atau
      layanan produktivitas sesuai kebutuhan, tanpa menjadikan tool perangkat
      sebagai fokus aplikasi.
- [ ] **Multimodal (vision)**: ubah `content` jadi array parts, tambah tool
      `analyze_image` yang mengirim foto hasil `take_photo` ke model. Perlu
      provider vision dan perubahan `Message`/`toApiJson`.
- [x] **Compact context**: port strategi `compact` siberflow dengan summary AI,
      threshold token, persistence sesi, dan turn terbaru yang tetap verbatim.
- [x] **Statistik token di UI**: meter context token tampil tepat di bawah input.
- [x] **Tema manual**: pilihan sistem/terang/gelap diterapkan langsung dari
      Pengaturan dan dipersistenkan.
- [ ] **Regenerate / edit pesan terakhir**: `Agent` sudah punya
      `rewindToLastUserMessage()`; tinggal disambungkan ke UI.

### Prioritas 3 — tool baru
- [ ] **`local_auth`**: kunci app/aksi sensitif dengan sidik jari. Tambahkan
      dependency lalu gunakan `FlutterFragmentActivity` kembali bila diperlukan.
- [ ] **`share_plus`**: bagikan file hasil foto/rekaman ke app lain.
- [x] **`file_picker`**: user dapat melampirkan file apa pun hingga 10 MB ke
      sandbox sesi; nama saja tampil pada riwayat.
- [x] **`send_file_to_user`**: AI dapat menawarkan file hasil kerja dan user
      menyimpannya lewat system file picker Android dari kartu riwayat.
- [ ] **`open_filex`**: buka file hasil sesi di aplikasi lain.
- [ ] **`android_intent_plus`**: buka intent Android umum (share, view,
      settings spesifik) tanpa menambah permission baru.
- [ ] **Rekam audio** (`record`), **baca kalender**, dan kalender/notifikasi
      terjadwal.
- [ ] **Mode suara penuh**: STT → kirim otomatis → jawaban dibaca TTS.

### Prioritas 4 — kualitas
- [ ] **Test integration** dengan `integration_test` di emulator.
- [ ] **Test provider** memakai `MockClient` dari `package:http/testing.dart`
      (`chatStream` sudah menerima parameter `httpClient` untuk ini) — verifikasi
      akumulasi tool_call streaming dan penanganan HTTP 4xx/5xx.
- [ ] **Export/impor sesi** sebagai JSON.
- [ ] **Layar debug** yang menampilkan request body terakhir (siberflow punya
      `debug.ts`; di sini belum ada).
- [ ] **Lokalisasi** penuh (`flutter_localizations`) — UI sekarang hardcode
      bahasa Indonesia.

---

## Referensi

Proyek ini meng-port arsitektur `@siberflow/core` (TypeScript) ke Dart:

| siberflow (TypeScript) | sibermobile (Dart) |
|---|---|
| `providers/openai-compatible.ts` | `core/ai/openai_compatible_provider.dart` |
| `providers/sse.ts` | `core/ai/sse.dart` |
| `agent/types.ts` | `core/ai/types.dart` |
| `agent/agent.ts` | `core/agent/agent.dart` |
| `agent/prompts.ts` | `core/agent/prompts.dart` |
| `tools/base.ts` | `core/tools/tool.dart` |
| `tools/registry.ts` | `core/tools/registry.dart` |
| `tools/index.ts` (`createDefaultRegistry`) | `core/tools/registry_builder.dart` |
| `session/store.ts` | `core/session/session_store.dart` |
| `desktop/src/main/settings.ts` + `secrets.ts` | `core/settings/settings.dart` |
| `desktop/src/main/agent-host.ts` | `app/chat_controller.dart` |
| `desktop/src/shared/protocol.ts` (`MainEvent`) | `app/chat_items.dart` |

Yang **tidak** di-port: multi-provider registry, `skills`, mode optimize selain
`compact`, `task_update`, sub-agent, dan seluruh tool desktop (exec shell, browser
puppeteer, database, SSH, excel/docx/pdf, OCR, image generation).

---

## 📬 Kontak & Komunitas

<div align="center">

**Dibuat dengan ❤️ oleh [dataSiberLab](https://datasiber.com) sebagai bagian
dari ekosistem Siber.**

🌐 [datasiber.com](https://datasiber.com)

SiberMobile masih dalam tahap pengembangan. Masukan, laporan bug, dan ide tool
baru sangat membantu pengembangan berikutnya.

<br>

<a href="#sibermobile">⬆ Kembali ke atas</a>

</div>

<!-- repo: sibermobile · dataSiberLab · 2026 -->
<!-- updated: 2026-10-07 -->
