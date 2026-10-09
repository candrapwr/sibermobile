/// UI-facing representations of one chat turn.
///
/// The agent emits low-level streaming events; the controller folds them into
/// these items so the chat list is a simple sequence of widgets. Assistant text
/// and tool calls are mutable while a turn is in flight and are appended to the
/// list in arrival order (so interleaved text/tool blocks render correctly).
library;

import 'dart:convert';

/// Status of a tool call as it moves through execution.
enum ToolCallStatus { pending, running, done, denied, error }

/// Base type for everything shown in the chat list.
sealed class ChatItem {
  ChatItem({required this.id});

  /// Stable id used as the list key.
  final String id;
}

/// A message the user sent.
class UserBubble extends ChatItem {
  UserBubble({
    required super.id,
    required this.text,
    this.attachmentNames = const [],
  });

  final String text;
  final List<String> attachmentNames;
}

/// Streaming assistant text. [text] grows as deltas arrive.
class AssistantBubble extends ChatItem {
  AssistantBubble({required super.id, this.text = ''});

  String text;
  bool isStreaming = true;
}

/// One tool call: arguments stream in, then the result is attached.
class ToolCallBlock extends ChatItem {
  ToolCallBlock({
    required super.id,
    required this.name,
    required this.toolCallId,
    this.arguments = '',
  });

  final String name;
  final String toolCallId;

  /// Raw JSON arguments exactly as streamed (may be incomplete while running).
  String arguments;

  /// Model-visible result once execution finishes.
  String? result;

  ToolCallStatus status = ToolCallStatus.pending;

  /// Whether the UI has this block expanded to show args/result.
  bool expanded = false;

  bool get isFinished =>
      status == ToolCallStatus.done ||
      status == ToolCallStatus.error ||
      status == ToolCallStatus.denied;

  /// Metadata returned by `send_file_to_user`, if this block represents a
  /// successfully delivered file.
  SharedFileInfo? get sharedFile => SharedFileInfo.fromToolResult(result);
}

/// Safe, session-relative metadata for a file the assistant offered to the
/// user. The absolute path never enters chat history or provider messages.
class SharedFileInfo {
  const SharedFileInfo({
    required this.relativePath,
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String relativePath;
  final String name;
  final int bytes;
  final String mimeType;

  static SharedFileInfo? fromToolResult(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['ok'] != true ||
          decoded['type'] != 'file') {
        return null;
      }
      final path = decoded['path']?.toString().trim() ?? '';
      final name = decoded['name']?.toString().trim() ?? '';
      if (path.isEmpty || name.isEmpty) return null;
      final bytes = decoded['bytes'];
      return SharedFileInfo(
        relativePath: path,
        name: name,
        bytes: bytes is num ? bytes.toInt().clamp(0, 1 << 53) : 0,
        mimeType: decoded['mimeType']?.toString() ?? 'application/octet-stream',
      );
    } catch (_) {
      return null;
    }
  }
}

/// An inline notice (errors, cancellation, max-iterations, compaction).
class SystemNotice extends ChatItem {
  SystemNotice({required super.id, required this.text, this.isError = false});

  final String text;
  final bool isError;
}

/// Short human narration shown in the UI instead of the raw tool name.
/// Unknown tools fall back to the name with underscores as spaces.
const Map<String, String> _toolNarrations = {
  'get_current_time': 'Memeriksa waktu',
  'ask_user': 'Menanyakan sesuatu',
  'send_file_to_user': 'Menyiapkan file',
  'web_search': 'Mencari di web',
  'http_request': 'Mengirim permintaan HTTP',
  'analyze_image': 'Menganalisa gambar',
  'generate_image': 'Membuat gambar',
  'get_device_info': 'Membaca info perangkat',
  'get_storage_info': 'Mengecek penyimpanan',
  'get_app_info': 'Membaca info aplikasi',
  'battery_status': 'Mengecek baterai',
  'get_current_location': 'Mencari lokasi',
  'take_photo': 'Mengambil foto',
  'pick_gallery_image': 'Memilih gambar dari galeri',
  'play_audio': 'Memutar audio',
  'stop_audio': 'Menghentikan audio',
  'speak_text': 'Membacakan teks',
  'stop_speaking': 'Menghentikan suara',
  'speech_to_text': 'Mendengarkan suara',
  'show_notification': 'Mengirim notifikasi',
  'search_contacts': 'Mencari kontak',
  'list_installed_apps': 'Mendaftar aplikasi terpasang',
  'launch_app': 'Membuka aplikasi',
  'nfc_status': 'Mengecek NFC',
  'nfc_analyze': 'Memindai kartu NFC',
  'nfc_transceive': 'Berkomunikasi dengan NFC',
  'nfc_write_ndef': 'Menulis ke kartu NFC',
  'wifi_scan': 'Memindai Wi-Fi',
  'cell_scan': 'Memeriksa jaringan seluler',
  'net_probe': 'Menguji koneksi',
  'shell_exec': 'Menjalankan perintah',
  'ssh_client': 'Terhubung ke server SSH',
  'sftp_client': 'Memindahkan file via SFTP',
  'read_file': 'Membaca file',
  'write_file': 'Menulis file',
  'list_dir': 'Melihat isi folder',
  'delete_file': 'Menghapus file',
};

String toolNarration(String name) =>
    _toolNarrations[name] ?? name.replaceAll('_', ' ');
