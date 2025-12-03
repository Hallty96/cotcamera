import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'backend.dart';
import 'queue_store.dart';
import 'offline_queue.dart';
import 'background_uploader.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/foundation.dart'; // for compute()


class PreviewScreen extends StatefulWidget {
  final XFile photo;
  const PreviewScreen({super.key, required this.photo});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

String sha256HexSync(Uint8List bytes) {
  final d = crypto.sha256.convert(bytes);
  return d.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String? ocrHint;
  bool uploading = false;

  @override
  void initState() {
    super.initState();
    _runOcrHint();
  }

  Future _runOcrHint() async {
    final input = InputImage.fromFilePath(widget.photo.path);
    final recognizer = TextRecognizer();
    final result = await recognizer.processImage(input);
    recognizer.close();

    // Very simple heuristic: first 4–8 digit number we see
    final regex = RegExp(r'\b\d{4,8}\b');
    String? hint;
    for (final block in result.blocks) {
      final match = regex.firstMatch(block.text.replaceAll(',', ''));
      if (match != null) { hint = match.group(0); break; }
    }
    setState(()=> ocrHint = hint);
  }

  Future<String> _sha256Hex(Uint8List bytes) async {
    return compute(sha256HexSync, bytes);
  }

  Future<Position?> _getGps() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return null;
      return await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 7));
    } catch (_) { return null; }
  }

  Future _confirmUpload() async {
    setState(()=>uploading=true);

    try {
      final file = File(widget.photo.path);
      final bytes = await file.readAsBytes();
      final sha = await _sha256Hex(bytes);
      final size = bytes.lengthInBytes;
      final takenAt = DateTime.now().toUtc();
      final gps = await _getGps(); // ok if null

      // Ask backend for signed URL
      final session = await Backend.createSubmissionSession(
        contentType: 'image/jpeg',
        sizeBytes: size,
        imageSha256: sha,
      );

      // Attempt direct PUT
      final headers = {
        'Content-Type': 'image/jpeg',
        'x-goog-meta-image_sha256': sha,
        if (gps != null) 'x-goog-meta-lat': gps.latitude.toString(),
        if (gps != null) 'x-goog-meta-lng': gps.longitude.toString(),
        'x-goog-meta-takenAt': takenAt.toIso8601String(),
      };

      final putResp = await http
        .put(Uri.parse(session.uploadUrl), headers: headers, body: bytes)
        .timeout(const Duration(seconds: 20));

      // If network down / non-2xx → queue it
      if (putResp.statusCode < 200 || putResp.statusCode >= 300) {
        throw Exception('PUT failed ${putResp.statusCode}');
      }

      if (!mounted) return;
      Navigator.pop(context); // success
    } catch (e) {
      // Queue job for Workmanager
      final file = File(widget.photo.path);
      final bytes = await file.readAsBytes();
      final sha = await _sha256Hex(bytes);
      final size = bytes.lengthInBytes;
      final takenAt = DateTime.now().toUtc();
      final gps = await _getGps();

      await QueueStore.add(UploadJob(
        localFilePath: widget.photo.path,
        sha256: sha,
        sizeBytes: size,
        takenAt: takenAt,
        lat: gps?.latitude,
        lng: gps?.longitude,
      ));

      // Schedule background worker (runs soon)
      await Workmanager().registerOneOffTask(
        'try_upload_${DateTime.now().millisecondsSinceEpoch}',
        taskName,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline: queued to upload automatically')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(()=>uploading=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm photo')),
      body: Column(
        children: [
          Expanded(child: Image.file(File(widget.photo.path))),
          if (ocrHint != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('OCR hint (not final): $ocrHint', style: const TextStyle(fontSize: 16)),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: ()=> Navigator.pop(context),
                icon: const Icon(Icons.refresh),
                label: const Text('Retake'),
              ),
              ElevatedButton.icon(
                onPressed: uploading ? null : _confirmUpload,
                icon: const Icon(Icons.check),
                label: Text(uploading ? 'Uploading...' : 'Confirm & upload'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
