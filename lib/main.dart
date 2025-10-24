import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'decompressor_page.dart';

void main() {
  runApp(const RLECompressorApp());
}

class RLECompressorApp extends StatelessWidget {
  const RLECompressorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RLE Demo - 1st Group',
      theme: ThemeData(fontFamily: 'Quicksand', colorSchemeSeed: Colors.teal),
      home: const CompressorHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CompressorHomePage extends StatefulWidget {
  const CompressorHomePage({super.key});

  @override
  State<CompressorHomePage> createState() => _CompressorHomePageState();
}

class _CompressorHomePageState extends State<CompressorHomePage> {
  File? _originalImageFile;
  Uint8List? _compressedRLEData;
  img.Image? _previewCompressedImage;
  bool _useThreshold = false;
  bool _useRGB = false;

  static const platform = MethodChannel('rle.flutter.dev/media');

  Future<void> _triggerMediaScan(String filePath) async {
    try {
      await platform.invokeMethod('scanFile', {'path': filePath});
    } on PlatformException catch (_) {}
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _originalImageFile = File(pickedFile.path);
        _compressedRLEData = null;
        _previewCompressedImage = null;
      });
    }
  }

  List<int> _rleEncode(Uint8List bytes) {
    List<int> encoded = [];
    for (int i = 0; i < bytes.length;) {
      int value = bytes[i];
      int count = 1;
      while (i + count < bytes.length && bytes[i + count] == value && count < 255) {
        count++;
      }
      encoded.add(count);
      encoded.add(value);
      i += count;
    }
    return encoded;
  }

  Future<void> _compressImageRLE() async {
    if (_originalImageFile == null) return;

    final raw = await _originalImageFile!.readAsBytes();
    final image = img.decodeImage(raw);
    if (image == null) return;

    img.Image targetImage;

    if (_useRGB) {
      targetImage = img.copyRotate(image, angle: 0);
    } else if (_useThreshold) {
      final gray = img.grayscale(image);
      targetImage = img.Image(width: gray.width, height: gray.height);
      for (int y = 0; y < gray.height; y++) {
        for (int x = 0; x < gray.width; x++) {
          final pixel = gray.getPixel(x, y);
          final grayValue = pixel.r.toInt();
          final bw = grayValue >= 128 ? 255 : 0;
          targetImage.setPixelRgba(x, y, bw, bw, bw, 255);
        }
      }
    } else {
      targetImage = img.grayscale(image);
    }

    late Uint8List pixelData;
    if (_useRGB) {
      List<int> rgbData = [];
      for (int y = 0; y < targetImage.height; y++) {
        for (int x = 0; x < targetImage.width; x++) {
          final pixel = targetImage.getPixel(x, y);
          rgbData.add(pixel.r.toInt());
          rgbData.add(pixel.g.toInt());
          rgbData.add(pixel.b.toInt());
        }
      }
      pixelData = Uint8List.fromList(rgbData);
    } else {
      List<int> grayData = [];
      for (int y = 0; y < targetImage.height; y++) {
        for (int x = 0; x < targetImage.width; x++) {
          final pixel = targetImage.getPixel(x, y);
          grayData.add(pixel.r.toInt());
        }
      }
      pixelData = Uint8List.fromList(grayData);
    }

    final encoded = _rleEncode(pixelData);

    setState(() {
      _compressedRLEData = Uint8List.fromList(encoded);
      _previewCompressedImage = targetImage;
    });

    _showMessage('Completed.');
  }

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

  Future<void> _saveRLEFile() async {
    if (_compressedRLEData == null) return;
    if (!await _requestStoragePermission()) {
      _showMessage('Access Denied.');
      return;
    }

    try {
      final now = DateTime.now();
      final fileName = 'compressed_${now.millisecondsSinceEpoch}.rle';
      final downloadsPath = '/storage/emulated/0/Download';
      final filePath = '$downloadsPath/$fileName';
      final file = File(filePath);

      final width = _previewCompressedImage!.width;
      final height = _previewCompressedImage!.height;

      final header = [
        width >> 8, width & 0xFF,
        height >> 8, height & 0xFF,
      ];

      final fullData = Uint8List.fromList([...header, ..._compressedRLEData!]);
      await file.writeAsBytes(fullData);
      await _triggerMediaScan(file.path);

      _showMessage('Saved in:\n$filePath');
    } catch (e) {
      _showMessage('Error: $e');
    }
  }

  Widget _buildMetadataSection() {
    if (_originalImageFile == null || _compressedRLEData == null) return const SizedBox();

    final originalSize = _originalImageFile!.lengthSync();
    final compressedSize = _compressedRLEData!.lengthInBytes + 4;
    final ratio = (compressedSize / originalSize);
    final ratioText = ratio >= 1 ? '1:${(ratio).toStringAsFixed(2)}' : '${(1 / ratio).toStringAsFixed(2)}:1';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text('Metadata:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text('Original Size: $originalSize B'),
        Text('Compressed Size: $compressedSize B'),
        Text('Ratio: $ratioText'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RLE Demo - 1st Group')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose image file:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('Choose image file'),
              onPressed: _pickImage,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _useThreshold,
                  onChanged: (val) {
                    setState(() {
                      _useThreshold = val!;
                      if (val) _useRGB = false;
                    });
                  },
                ),
                const Text("Binary (Threshold)"),
                const SizedBox(width: 20),
                Checkbox(
                  value: _useRGB,
                  onChanged: (val) {
                    setState(() {
                      _useRGB = val!;
                      if (val) _useThreshold = false;
                    });
                  },
                ),
                const Text("RGB"),
              ],
            ),
            const SizedBox(height: 10),
            if (_originalImageFile != null) ...[
              const Text('Original Image:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Image.file(_originalImageFile!, height: 200),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.compress),
                label: const Text('Compress (RLE)'),
                onPressed: _compressImageRLE,
              ),
            ],
            if (_previewCompressedImage != null) ...[
              const SizedBox(height: 30),
              const Text('Preview Compression Result:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Image.memory(Uint8List.fromList(img.encodePng(_previewCompressedImage!)), height: 200, fit: BoxFit.contain),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save .rle file to Download'),
                onPressed: _saveRLEFile,
              ),
              _buildMetadataSection(),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('RLE File Decompression'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DecompressorPage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
