/// SSH accounts screen: manage the servers the AI may connect to.
///
/// Account metadata lives in settings; passwords live only in secure
/// storage (Android Keystore) and are never shown, exported, or sent to
/// the model.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings/settings.dart';
import '../chat_controller.dart';
import '../widgets/app_modal.dart';
import '../widgets/common_widgets.dart';

class SshAccountsScreen extends StatelessWidget {
  const SshAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ChatController>();
    final accounts = controller.settings.sshAccounts;

    return Scaffold(
      appBar: AppBar(title: const Text('Akun SSH')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah akun'),
      ),
      body: accounts.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.dns_outlined, size: 44),
                const SizedBox(height: 10),
                Text(
                  'Belum ada akun SSH',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tambahkan server yang boleh diakses AI. Password disimpan '
                  'terenkripsi di perangkat dan tidak pernah dibagikan ke '
                  'percakapan.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: accounts.length,
              itemBuilder: (context, i) {
                final account = accounts[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.dns_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${account.username}@${account.host}:${account.port}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit akun',
                          icon: Icon(
                            Icons.edit_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () =>
                              _showEditDialog(context, controller, account),
                        ),
                        IconButton(
                          tooltip: 'Hapus akun',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => _confirmDelete(
                            context,
                            controller,
                            account,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    ChatController controller,
  ) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final host = TextEditingController();
    final port = TextEditingController(text: '22');
    final username = TextEditingController();
    final password = TextEditingController();
    final portFocus = FocusNode();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Tambah akun SSH',
        icon: Icons.dns_outlined,
        onClose: () => Navigator.pop(dialogContext, false),
        footer: AppModal.actions(
          dialogContext,
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama',
                    hintText: 'Server utama',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: host,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Host',
                    hintText: '192.168.1.10 atau server.example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: port,
                  focusNode: portFocus,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                  validator: (v) {
                    final p = int.tryParse((v ?? '').trim());
                    return (p == null || p < 1 || p > 65535)
                        ? '1–65535'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: username,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) =>
                      Navigator.pop(dialogContext, true),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'Disimpan terenkripsi (Android Keystore). '
                        'Tidak pernah dibagikan ke percakapan AI.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Wajib diisi' : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    final enabledTools = await controller.addSshAccount(
      name: name.text.trim(),
      host: host.text.trim(),
      port: int.parse(port.text.trim()),
      username: username.text.trim(),
      password: password.text,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              enabledTools
                  ? 'Akun "${name.text.trim()}" tersimpan — tool SSH & SFTP '
                        'diaktifkan.'
                  : 'Akun "${name.text.trim()}" tersimpan.',
            ),
          ),
        );
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    ChatController controller,
    SshAccount account,
  ) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: account.name);
    final host = TextEditingController(text: account.host);
    final port = TextEditingController(text: account.port.toString());
    final username = TextEditingController(text: account.username);
    final password = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Edit akun SSH',
        subtitle: account.name,
        icon: Icons.dns_outlined,
        onClose: () => Navigator.pop(dialogContext, false),
        footer: AppModal.actions(
          dialogContext,
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nama'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: host,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Host'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: port,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
                validator: (v) {
                  final p = int.tryParse((v ?? '').trim());
                  return (p == null || p < 1 || p > 65535)
                      ? '1–65535'
                      : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: username,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Password baru',
                  helperText: 'Kosongkan untuk mempertahankan password lama.',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    await controller.updateSshAccount(
      account,
      name: name.text.trim(),
      host: host.text.trim(),
      port: int.parse(port.text.trim()),
      username: username.text.trim(),
      password: password.text.isEmpty ? null : password.text,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Akun "${name.text.trim()}" diperbarui.')),
        );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatController controller,
    SshAccount account,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppModal(
        title: 'Hapus akun SSH?',
        subtitle: account.name,
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onClose: () => Navigator.pop(dialogContext, false),
        footer: AppModal.actions(
          dialogContext,
          [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
        child: Text(
          'Akun "${account.name}" beserta password tersimpannya akan dihapus '
          'dari perangkat.',
          style: Theme.of(dialogContext).textTheme.bodyMedium,
        ),
      ),
    );
    if (approved != true) return;
    await controller.deleteSshAccount(account.id);
  }
}
