import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'preview_screen.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? controller;
  List<CameraDescription>? cameras;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    initCam();
  }

  Future initCam() async {
    cameras = await availableCameras();
    final back = cameras!.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: ()=>cameras!.first);
    controller = CameraController(back, ResolutionPreset.medium, enableAudio: false);
    await controller!.initialize();
    setState(()=>ready = true);
  }

  @override
  void dispose() { controller?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(controller!),
          Positioned(
            bottom: 40, left: 0, right: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: () async {
                  final xfile = await controller!.takePicture();
                  if (!mounted) return;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PreviewScreen(photo: xfile),
                  ));
                },
                child: const Icon(Icons.camera),
              ),
            ),
          )
        ],
      ),
    );
  }
}
