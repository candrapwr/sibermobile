/// SSH/SFTP tools: run commands and move files on the user's own servers.
///
/// Credentials never reach the model: accounts live in the Akun SSH menu
/// (passwords in secure storage), the user picks the account for the
/// conversation via ask_user + ssh_select_account, and everything else goes
/// through the host-side SshAccess implementation.
library;

import '../tool.dart';
import '../results.dart';

/// Lists saved SSH accounts (metadata only) — step 1 of the pick flow.
class SshListAccountsTool extends Tool {
  @override
  String get name => 'ssh_list_accounts';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'List the SSH accounts saved on this device (name, username, host, '
      'port, and which one is selected for this conversation). Passwords '
      'are never shown. Flow: if no account is selected, show the options '
      'to the user with ask_user (choices = account names), then call '
      'ssh_select_account with the chosen name. Once an account is '
      'selected it stays active for the rest of this conversation.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
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
            '(ask_user), then ssh_select_account.',
    });
  }
}

/// Marks the account the user picked for this conversation.
class SshSelectAccountTool extends Tool {
  @override
  String get name => 'ssh_select_account';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'Select the SSH account to use for this conversation. Call it with '
      'the account name the USER picked via ask_user — do not pick an '
      'account on your own. The selection lasts until the conversation '
      'session changes.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'name': <String, dynamic>{
        'type': 'string',
        'description': 'The account name exactly as listed by '
            'ssh_list_accounts.',
      },
    },
    'required': <String>['name'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final out = await ssh.selectAccount(requireString(args, 'name'));
    return out['ok'] == true ? jsonResult(out) : errorResult(out['error']?.toString() ?? 'selection failed');
  }
}

/// Runs one command over SSH on the selected account.
class SshExecTool extends Tool {
  @override
  String get name => 'ssh_exec';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'Run a shell command on the selected SSH server and return stdout, '
      'stderr and the exit code. Requires an account selected for this '
      'conversation (ssh_list_accounts → ask_user → ssh_select_account). '
      'Output is capped; long-running commands are killed by the timeout '
      'but keep running on the server.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'command': <String, dynamic>{
        'type': 'string',
        'description': 'The command line to run, e.g. "df -h" or '
            '"systemctl status nginx".',
      },
      'timeoutSeconds': <String, dynamic>{
        'type': 'integer',
        'description': 'Default 30, max 300.',
      },
    },
    'required': <String>['command'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final timeout = optionalInt(args, 'timeoutSeconds', 30).clamp(5, 300);
    final out = await ssh.exec(requireString(args, 'command'), timeout);
    return out['ok'] == true ? jsonResult(out) : errorResult(out['error']?.toString() ?? 'exec failed');
  }
}

/// Lists a remote directory over SFTP.
class SftpListTool extends Tool {
  @override
  String get name => 'sftp_list';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'List a directory on the selected SSH server via SFTP: file names, '
      'directory flags and sizes (up to 500 entries). Requires a selected '
      'account.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'path': <String, dynamic>{
        'type': 'string',
        'description': 'Remote directory, e.g. "/var/log" (default "/").',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final out = await ssh.sftpList(optionalString(args, 'path') ?? '/');
    return out['ok'] == true ? jsonResult(out) : errorResult(out['error']?.toString() ?? 'listing failed');
  }
}

/// Downloads a remote file into the session workdir.
class SftpGetTool extends Tool {
  @override
  String get name => 'sftp_get';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'Download a file from the selected SSH server into the session '
      'workspace (ssh/<filename>), then offer it to the user with '
      'send_file_to_user using the returned path. Requires a selected '
      'account.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'remotePath': <String, dynamic>{
        'type': 'string',
        'description': 'Absolute path on the server, e.g. "/etc/nginx/nginx.conf".',
      },
    },
    'required': <String>['remotePath'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final out = await ssh.sftpDownload(requireString(args, 'remotePath'));
    return out['ok'] == true ? jsonResult(out) : errorResult(out['error']?.toString() ?? 'download failed');
  }
}

/// Uploads a workdir file to the server.
class SftpPutTool extends Tool {
  @override
  String get name => 'sftp_put';

  @override
  String get category => 'SSH';

  @override
  String get description =>
      'Upload a file from the session workspace to the selected SSH server. '
      'The local path is inside the session sandbox (e.g. something the '
      'user attached, "uploads/report.pdf", or a file you created with '
      'write_file / generate_image). Requires a selected account.';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'localPath': <String, dynamic>{
        'type': 'string',
        'description': 'File inside the session sandbox, e.g. "uploads/report.pdf".',
      },
      'remotePath': <String, dynamic>{
        'type': 'string',
        'description': 'Absolute destination path on the server.',
      },
    },
    'required': <String>['localPath', 'remotePath'],
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final ssh = ctx.ssh;
    if (ssh == null) return errorResult('SSH is not available.');
    final out = await ssh.sftpUpload(
      requireString(args, 'localPath'),
      requireString(args, 'remotePath'),
    );
    return out['ok'] == true ? jsonResult(out) : errorResult(out['error']?.toString() ?? 'upload failed');
  }
}

final List<Tool> sshTools = <Tool>[
  SshListAccountsTool(),
  SshSelectAccountTool(),
  SshExecTool(),
  SftpListTool(),
  SftpGetTool(),
  SftpPutTool(),
];
