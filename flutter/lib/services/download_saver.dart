import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../protocol/bridge_messages.dart';

abstract class FileDownloadSaver {
  Future<String?> save(DownloadedFileInfo file);
}

class PickerFileDownloadSaver implements FileDownloadSaver {
  const PickerFileDownloadSaver();

  @override
  Future<String?> save(DownloadedFileInfo file) {
    return FilePicker.saveFile(
      dialogTitle: 'Save ${file.name}',
      fileName: file.name,
      bytes: _decodeBytes(file.dataBase64),
    );
  }
}

Uint8List _decodeBytes(String dataBase64) {
  return Uint8List.fromList(base64Decode(dataBase64));
}
