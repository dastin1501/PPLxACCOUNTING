import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/database_helper.dart';
import '../services/image_storage_service.dart';

/// Shows the paper-receipt photo for a sale, and lets the cashier take a
/// new one or pick a picture already on the device.
class ReceiptPhotoPanel extends StatefulWidget {
  const ReceiptPhotoPanel({
    super.key,
    required this.saleId,
    required this.initialPath,
    this.onChanged,
  });

  final String saleId;
  final String initialPath;
  final VoidCallback? onChanged;

  @override
  State<ReceiptPhotoPanel> createState() => _ReceiptPhotoPanelState();
}

class _ReceiptPhotoPanelState extends State<ReceiptPhotoPanel> {
  late String _path = widget.initialPath;
  bool _busy = false;

  bool get _hasPhoto => ImageStorageService.exists(_path);

  @override
  void didUpdateWidget(ReceiptPhotoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPath != widget.initialPath && _path != widget.initialPath) {
      _path = widget.initialPath;
    }
  }

  Future<void> _chooseSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a picture'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('Remove photo', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'remove') {
      final removed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove receipt photo?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
          ],
        ),
      );
      if (removed == true) await _save(null);
      return;
    }
    await _capture(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _capture(ImageSource source) async {
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
      if (picked == null) return;
      final saved = await ImageStorageService.saveReceiptImage(picked.path);
      await _save(saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the receipt photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String? path) async {
    await DatabaseHelper.instance.setSaleReceiptImage(widget.saleId, path);
    if (!mounted) return;
    setState(() => _path = path ?? '');
    widget.onChanged?.call();
  }

  void _view() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.file(File(_path), fit: BoxFit.contain),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasPhoto)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _view,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(_path),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _chooseSource,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(_hasPhoto ? Icons.photo_camera_outlined : Icons.add_a_photo_outlined),
          label: Text(_hasPhoto ? 'Replace receipt photo' : 'Photograph receipt'),
        ),
      ],
    );
  }
}
