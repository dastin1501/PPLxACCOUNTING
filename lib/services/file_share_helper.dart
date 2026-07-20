import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Shares an exported file using the native share sheet on mobile
/// (Android/iOS), or reveals it in the file explorer on desktop platforms
/// where file sharing is unreliable/unsupported.
Future<void> shareOrRevealFile(BuildContext context, File file) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Exported from POS Stock Manager',
        files: [XFile(file.path)],
      ),
    );
    return;
  }

  if (Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', file.path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', file.path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [file.parent.path]);
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Saved to ${file.path}')),
  );
}
