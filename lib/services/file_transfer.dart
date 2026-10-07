import 'package:flutter/services.dart';

class FileTransferException implements Exception {
  final String message;
  const FileTransferException(this.message);

  @override
  String toString() => message;
}

/// Save/open a text file through Android's system file dialogs (Storage
/// Access Framework), so no storage permission is needed and the user can
/// pick any location, including cloud drives. See MainActivity.
class FileTransfer {
  const FileTransfer._();

  static const _channel = MethodChannel('org.amirmb.wakeflow/files');

  /// True when saved, false when the user cancelled the dialog.
  static Future<bool> saveText({
    required String name,
    required String text,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('saveText', {
            'name': name,
            'text': text,
          }) ??
          false;
    } on PlatformException catch (error) {
      throw FileTransferException(error.message ?? 'Could not save the file.');
    }
  }

  /// The chosen file's text, or null when the user cancelled the dialog.
  static Future<String?> pickText() async {
    try {
      return await _channel.invokeMethod<String>('pickText');
    } on PlatformException catch (error) {
      throw FileTransferException(error.message ?? 'Could not open the file.');
    }
  }
}
