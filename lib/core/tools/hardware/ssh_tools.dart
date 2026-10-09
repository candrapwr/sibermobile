/// SSH/SFTP tools: run commands and move files on the user's own servers.
///
/// Two user-facing tools, each with an `op` parameter: ssh_client
/// (accounts / select / exec) and sftp_client (list / get / put). They map
/// to one toggle each in the Tools screen and default to off. Credentials
/// never reach the model: accounts live in the Akun SSH menu (passwords in
/// secure storage), the user picks the account for the conversation via
/// ask_user + op:select, and everything goes through the host-side
/// SshAccess implementation.
library;

import '../tool.dart';
import '../results.dart';

/// SSH operations in one tool: list accounts, select one, run commands.
class SshClientTool extends Tool {
  @override
  String get name => 'ssh_client';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'SSH access to the user\'s own servers, in three operations. '
      'op=accounts: list saved SSH accounts (name, username, host, port, '
      'and which one is selected for this conversation — passwords are '
      'never shown). op=select: mark the account the USER picked via '
      'ask_user (do not pick on your own); the selection lasts for the '
      'rest of this conversation session. op=exec: run a shell command on '
      'the selected account and get stdout, stderr and the exit code — '
      'output is capped and long-running commands are killed by the '
      'timeout but keep running on the server.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'op': <String, dynamic>{
        'type': 'string',
        'enum': <String>['accounts', 'select', 'exec'],
        'description': 'accounts = list saved accounts; select = pick the '
            'account the user chose; exec = run a command.',
      },
      'command': <String, dynamic>{
        'type': 'string',
        'description': 'For op=exec: the command line to run, e.g. "df -h".',
      },
      'name': <String, dynamic>{
        'type': 'string',
        'description': 'For op=select: the account name exactly as listed '
            'by op=accounts.',
      },
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'For op=exec: default 30, max 300.',
      },
    },
    'required': <String>['op'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final op = requireString(args, 'op');

    switch (op) {
      case 'accounts':
        final accounts = await ssh.listAccounts();
        if (accounts.isEmpty) {
          return errorResult(
            'No SSH accounts are saved yet. Ask the user to add one via the '
            'Akun SSH menu (three-dot menu → Akun SSH).',
          );
        }
        return jsonResult({
          'accounts': accounts,
          if (!accounts.any((a) => a['selected'] == true))
            'hint': 'No account selected yet: ask the user to pick one '
                '(ask_user), then op=select.',
        });
      case 'select':
        final out = await ssh.selectAccount(requireString(args, 'name'));
        return out['ok'] == true
            ? jsonResult(out)
            : errorResult(out['error']?.toString() ?? 'selection failed');
      case 'exec':
        final out = await ssh.exec(
          requireString(args, 'command'),
          optionalInt(args, 'timeoutSeconds', 30).clamp(5, 300),
        );
        return out['ok'] == true
            ? jsonResult(out)
            : errorResult(out['error']?.toString() ?? 'exec failed');
      default:
        return errorResult('op must be accounts, select or exec.');
    }
  }
}

/// SFTP operations in one tool: list directories, download, upload.
class SftpClientTool extends Tool {
  @override
  String get name => 'sftp_client';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'File transfer over SFTP on the selected SSH account (pick one first '
      'via ssh_client op=accounts + ask_user + op=select). op=list: list a '
      'remote directory (names, directory flags, sizes, up to 500 entries). '
      'op=get: download a remote file into the session workspace '
      '(ssh/<filename>) — then offer it to the user with send_file_to_user '
      'using the returned path. op=put: upload a file from the session '
      'sandbox (attachments, generated images, files you wrote) to the '
      'server.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'op': <String, dynamic>{
        'type': 'string',
        'enum': <String>['list', 'get', 'put'],
        'description': 'list = directory listing; get = download to the '
            'session sandbox; put = upload from the sandbox.',
      },
      'path': <String, dynamic>{
        'type': 'string',
        'description': 'For op=list: remote directory (default "/").',
      },
      'remotePath': <String, dynamic>{
        'type': 'string',
        'description': 'Remote path: the file to download (op=get) or the '
            'upload destination (op=put).',
      },
      'localPath': <String, dynamic>{
        'type': 'string',
        'description': 'For op=put: file inside the session sandbox, e.g. '
            '"uploads/report.pdf".',
      },
    },
    'required': <String>['op'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final op = requireString(args, 'op');

    switch (op) {
      case 'list':
        final out = await ssh.sftpList(optionalString(args, 'path') ?? '/');
        return out['ok'] == true
            ? jsonResult(out)
            : errorResult(out['error']?.toString() ?? 'listing failed');
      case 'get':
        final out = await ssh.sftpDownload(requireString(args, 'remotePath'));
        return out['ok'] == true
            ? jsonResult(out)
            : errorResult(out['error']?.toString() ?? 'download failed');
      case 'put':
        final out = await ssh.sftpUpload(
          requireString(args, 'localPath'),
          requireString(args, 'remotePath'),
        );
        return out['ok'] == true
            ? jsonResult(out)
            : errorResult(out['error']?.toString() ?? 'upload failed');
      default:
        return errorResult('op must be list, get or put.');
    }
  }
}

final List<Tool> sshTools = <Tool>[SshClientTool(), SftpClientTool()];
