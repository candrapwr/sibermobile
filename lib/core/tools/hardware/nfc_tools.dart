/// NFC tools: adapter status, tag analysis (NDEF + tech parameters), raw
/// frame exchange and NDEF writing — all through the DeviceBridge channel.
///
/// The tools are intentionally composable primitives: `nfc_analyze` discovers
/// and profiles a tag, `nfc_transceive` lets the model send any raw frame
/// (APDU for IsoDep cards, native commands for NfcA/B/F/V tags) so it can
/// freely explore tags it is asked to analyze.
library;

import '../../native/device_bridge.dart';
import '../tool.dart';
import '../results.dart';

/// Reports whether the device has NFC and whether it is switched on.
class NfcStatusTool extends Tool {
  @override
  String get name => 'nfc_status';

  @override
  String get category => 'NFC';

  @override
  String get description =>
      'Check whether this device has an NFC adapter and whether NFC is '
      'currently enabled. Use this before nfc_analyze; if NFC is disabled, '
      'tell the user to turn it on in Android settings (NFC cannot be enabled '
      'from this app).';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final status = await DeviceBridge.nfcStatus();
    return jsonResult({
      'available': status['available'] ?? false,
      'enabled': status['enabled'] ?? false,
    });
  }
}

/// Waits for a tag tap, then profiles it: UID, technologies, per-tech
/// parameters, and parsed NDEF content.
class NfcAnalyzeTool extends Tool {
  @override
  String get name => 'nfc_analyze';

  @override
  String get description =>
      'Analyze an NFC tag: start reader mode and wait for the user to tap a '
      'tag, then return its UID (hex), supported technologies (NfcA, IsoDep, '
      'MifareClassic, Ndef, ...), per-technology parameters (ATQA/SAK, sizes, '
      'sector counts) and parsed NDEF records (text/URI). First ask the user '
      'to hold the tag on the back of the phone, then call this tool. After a '
      'successful scan the tag stays connected ~30 seconds for follow-up '
      'nfc_transceive / nfc_write_ndef calls while it remains on the reader.';

  @override
  String get category => 'NFC';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'How long to wait for a tag tap (default 20, max 60).',
      },
      'readNdef': <String, dynamic>{
        'type': 'boolean',
        'description': 'Also read and parse NDEF records (default true).',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final timeout = optionalInt(args, 'timeoutSeconds', 20).clamp(5, 60);
    final readNdef = optionalBool(args, 'readNdef', true);
    final info = await DeviceBridge.nfcAnalyze(
      timeoutSeconds: timeout,
      readNdef: readNdef,
    );
    final error = info['error'];
    if (error is String && error.isNotEmpty) {
      return errorResult(error);
    }
    return jsonResult(info);
  }
}

/// Sends a raw frame to the tag of the active NFC session — the free-form
/// exploration primitive (APDUs for IsoDep, native commands otherwise).
class NfcTransceiveTool extends Tool {
  @override
  String get name => 'nfc_transceive';

  @override
  String get description =>
      'Send a raw frame (hex bytes) to the NFC tag of the active session and '
      'return the response as hex. With tech=auto an IsoDep tag is preferred, '
      'so frames are APDUs — the last 2 response bytes are the status word '
      '(9000 = success); e.g. select an application AID, read records, or run '
      'any command the card supports. For tags without IsoDep the frame goes '
      'to NfcA/B/F/V native commands instead (e.g. Mifare Ultralight READ = '
      '30xx). tech=mifareUltralight targets the Ultralight command set '
      'directly. MIFARE CLASSIC CANNOT BE READ with raw frames — its sectors '
      'need dedicated authenticate/read commands this tool does not expose; '
      'use the metadata from nfc_analyze instead. Each command opens and '
      'closes one connection, so consecutive transceives work without '
      're-tapping. Requires an active session: run nfc_analyze first and '
      'keep the tag on the reader. 6E00/6Axx responses mean the card itself '
      'rejected the instruction, not a connection problem.';

  @override
  String get category => 'NFC';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'dataHex': <String, dynamic>{
        'type': 'string',
        'description':
            'Hex-encoded frame to send, e.g. "00A4040007A0000000041010" '
            '(spaces allowed).',
      },
      'tech': <String, dynamic>{
        'type': 'string',
        'enum': <String>[
          'auto', 'isoDep', 'nfcA', 'nfcB', 'nfcF', 'nfcV', 'mifareUltralight',
        ],
        'description':
            'Which tag technology to use (default auto: IsoDep if present, '
            'else NfcA/B/F/V). MIFARE Classic has no raw-frame support.',
      },
    },
    'required': <String>['dataHex'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final dataHex = requireString(args, 'dataHex');
    if (dataHex.replaceFirst(' ', '').length % 2 != 0 ||
        !RegExp(r'^[0-9a-fA-F ]+$').hasMatch(dataHex)) {
      return errorResult(
        'dataHex must be an even-length hex string (spaces allowed).',
      );
    }
    final tech = optionalString(args, 'tech') ?? 'auto';
    final result = await DeviceBridge.nfcTransceive(dataHex, tech: tech);
    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      return errorResult(error);
    }
    return jsonResult(result);
  }
}

/// Writes NDEF text/URI records to the tag of the active NFC session.
class NfcWriteNdefTool extends Tool {
  @override
  String get name => 'nfc_write_ndef';

  @override
  String get description =>
      'Write NDEF records to the NFC tag of the active session (it must be '
      'NDEF-formatted and writable; check nfc_analyze output first). Records '
      'are written as one message — existing content is replaced. Requires an '
      'active session: run nfc_analyze first and keep the tag on the reader.';

  @override
  String get category => 'NFC';

  @override
  bool get requiresApproval => true;

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'records': <String, dynamic>{
        'type': 'array',
        'minItems': 1,
        'items': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'kind': <String, dynamic>{
              'type': 'string',
              'enum': <String>['text', 'uri'],
            },
            'value': <String, dynamic>{
              'type': 'string',
              'description': 'Text content, or full URI for kind=uri.',
            },
            'language': <String, dynamic>{
              'type': 'string',
              'description': 'Language code for kind=text (default "en").',
            },
          },
          'required': <String>['kind', 'value'],
        },
        'description': 'NDEF records to write.',
      },
    },
    'required': <String>['records'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final raw = args['records'];
    if (raw is! List || raw.isEmpty) {
      return errorResult('records must be a non-empty array.');
    }
    final records = <Map<String, Object?>>[];
    for (final e in raw) {
      if (e is Map) {
        records.add({
          'kind': e['kind']?.toString() ?? 'text',
          'value': e['value']?.toString() ?? '',
          if (e['language'] != null) 'language': e['language'].toString(),
        });
      }
    }
    if (records.isEmpty) {
      return errorResult('records must contain at least one valid entry.');
    }
    final result = await DeviceBridge.nfcWriteNdef(records);
    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      return errorResult(error);
    }
    return jsonResult({'ok': true, 'written': records.length});
  }
}

final List<Tool> nfcTools = <Tool>[
  NfcStatusTool(),
  NfcAnalyzeTool(),
  NfcTransceiveTool(),
  NfcWriteNdefTool(),
];
