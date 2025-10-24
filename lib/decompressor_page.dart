import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

class DecompressorPage extends StatefulWidget {
  const DecompressorPage({super.key});

  @override
  State<DecompressorPage> createState() => _DecompressorPageState();
}

class _DecompressorPageState extends State<DecompressorPage> {
  img.Image? _decompressedImage;
  String? _fileName;
  Uint8List? _imageBytes;
  int? _originalWidth;
  int? _originalHeight;

  static const platform = MethodChannel('rle.flutter.dev/media');

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 30) {
      final status = await Permission.manageExternalStorage.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  Future<void> _triggerMediaScan(String filePath) async {
    try {
      await platform.invokeMethod('scanFile', {'path': filePath});
    } on PlatformException catch (e) {
      debugPrint('Media scan failed: $e');
    }
  }

  Uint8List _rleDecodeWithHeader(Uint8List encoded) {
    int width = (encoded[0] << 8) + encoded[1];
    int height = (encoded[2] << 8) + encoded[3];
    List<int> decoded = [];
    for (int i = 4; i < encoded.length; i += 2) {
      if (i + 1 >= encoded.length) break;
      int count = encoded[i];
      int value = encoded[i + 1];
      decoded.addAll(List.filled(count, value));
    }
    final image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int i = y * width + x;
        int v = (i < decoded.length) ? decoded[i] : 0;
        image.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    setState(() {
      _decompressedImage = image;
      _imageBytes = Uint8List.fromList(img.encodePng(image));
      _fileName = 'decompressed_image';
      _originalWidth = width;
      _originalHeight = height;
    });
    return _imageBytes!;
  }

  Future<void> _pickRLEFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        dialogTitle: 'Choose the .rle file from Files',
      );
      if (!mounted) return;
      if (result != null && result.files.single.bytes != null) {
        Uint8List rleData = result.files.single.bytes!;
        _rleDecodeWithHeader(rleData);
        setState(() {
          _fileName = result.files.single.name;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Decompression successful.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _saveImageAs(String format) async {
    final messenger = ScaffoldMessenger.of(context);
    if (_decompressedImage == null) return;
    if (!await _requestStoragePermission()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Access Denied')),
      );
      return;
    }
    final dir = Directory('/storage/emulated/0/Download');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = format.toLowerCase();
    final filePath = '${dir.path}/decompressed_$timestamp.$ext';
    final encoded = ext == 'jpg'
        ? img.encodeJpg(_decompressedImage!)
        : img.encodePng(_decompressedImage!);
    await File(filePath).writeAsBytes(encoded);
    await _triggerMediaScan(filePath);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Saved as $ext in Download')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RLE Decompressor')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose the .rle file from Files'),
              onPressed: _pickRLEFile,
            ),
            const SizedBox(height: 20),
            if (_imageBytes != null) ...[
              Text('Preview frrom: $_fileName'),
              if (_originalWidth != null && _originalHeight != null)
                Text('Size: $_originalWidth x $_originalHeight'),
              const SizedBox(height: 10),
              Image.memory(_imageBytes!, height: 300, fit: BoxFit.contain),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save as PNG'),
                onPressed: () => _saveImageAs('png'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Save as JPG'),
                onPressed: () => _saveImageAs('jpg'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
