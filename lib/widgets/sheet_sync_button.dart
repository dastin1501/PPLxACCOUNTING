import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_helper.dart';
import '../services/sheet_sync_service.dart';
import '../services/sheet_sync_settings.dart';

/// Opens the Google Sheets connection dialog. [onSynced] runs after a
/// successful sync so inventory and sales can reload.
class SheetSyncButton extends StatelessWidget {
  const SheetSyncButton({super.key, this.onSynced});

  final VoidCallback? onSynced;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Google Sheets',
      onPressed: () async {
        final synced = await showDialog<bool>(
          context: context,
          builder: (context) => const SheetSyncDialog(),
        );
        if (synced != true || !context.mounted) return;
        onSynced?.call();
        final message = await SheetSyncSettings.lastMessage();
        if (!context.mounted || message == null || message.isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      },
      icon: const Icon(Icons.cloud_sync_outlined),
    );
  }
}

class SheetSyncDialog extends StatefulWidget {
  const SheetSyncDialog({super.key});

  @override
  State<SheetSyncDialog> createState() => _SheetSyncDialogState();
}

class _SheetSyncDialogState extends State<SheetSyncDialog> {
  final _urlCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  bool _loading = true;
  bool _syncing = false;
  bool _hideSecret = true;
  int _pending = 0;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await SheetSyncSettings.load();
    final pending = await DatabaseHelper.instance.pendingSyncCount();
    final lastSync = await SheetSyncSettings.lastSyncIso();
    final lastMessage = await SheetSyncSettings.lastMessage();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = config.webAppUrl;
      _secretCtrl.text = config.secret;
      _pending = pending;
      _status = _describe(lastSync, lastMessage);
      _loading = false;
    });
  }

  String? _describe(String? lastSyncIso, String? lastMessage) {
    if (lastMessage == null || lastMessage.isEmpty) return null;
    if (lastSyncIso == null) return lastMessage;
    final when = DateTime.tryParse(lastSyncIso);
    if (when == null) return lastMessage;
    return '${DateFormat('MMM d, h:mm a').format(when.toLocal())} — $lastMessage';
  }

  Future<void> _saveAndSync() async {
    final url = _urlCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (url.isEmpty || secret.isEmpty) {
      setState(() => _status = 'Paste the web app URL and the shared secret first');
      return;
    }
    setState(() {
      _syncing = true;
      _status = 'Syncing...';
    });
    await SheetSyncSettings.save(webAppUrl: url, secret: secret);
    final result = await SheetSyncService.instance.sync(
      SheetSyncConfig(webAppUrl: url, secret: secret),
    );
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _status = result.message;
    });
    if (result.ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Google Sheets'),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'The tablet keeps its own copy and still works offline. Sync sends products, sales, and stock changes to the sheet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Web app URL',
                      hintText: 'https://script.google.com/macros/s/.../exec',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secretCtrl,
                    obscureText: _hideSecret,
                    decoration: InputDecoration(
                      labelText: 'Shared secret',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _hideSecret = !_hideSecret),
                        icon: Icon(_hideSecret ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _pending == 0 ? 'Nothing waiting to upload' : '$_pending record${_pending == 1 ? '' : 's'} waiting to upload',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(_status!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _syncing ? null : () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _loading || _syncing ? null : _saveAndSync,
          icon: _syncing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(_syncing ? 'Syncing...' : 'Save and sync'),
        ),
      ],
    );
  }
}
