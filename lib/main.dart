import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// MakeupProduct, MakeupShade, cart, checkout and orders live here.
import 'shop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(TryOnApp(cameras: cameras));
}

// ============================================================
// STARTUP (no-Firebase version)
// ============================================================

/// Loads products, cart and orders (no Firebase in this version).
Future<void> initBackend() async {
  await ProductStore.instance.start();
  CartStore.instance.start();
  await OrderStore.instance.start();
}

class StartupScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const StartupScreen({super.key, required this.cameras});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    _init = initBackend();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _init,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return TryOnScreen(cameras: widget.cameras);
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: snapshot.hasError
                  ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    "Something went wrong",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please try again.\n'
                        '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _init = initBackend()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Try Again'),
                  ),
                ],
              )
                  : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Try On Me',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 20),
                  CircularProgressIndicator(color: Colors.black),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// MODELS
// ============================================================

/// All face geometry needed for makeup, in ML Kit image coordinates
/// (already upright, i.e. after ML Kit applied the rotation metadata).
class FaceGeometry {
  final List<Offset> upperLipTop;
  final List<Offset> upperLipBottom;
  final List<Offset> lowerLipTop;
  final List<Offset> lowerLipBottom;
  final List<Offset> faceOval;
  final List<Offset> leftEye;
  final List<Offset> rightEye;
  final Offset? leftCheek;
  final Offset? rightCheek;
  final Rect box;

  const FaceGeometry({
    required this.upperLipTop,
    required this.upperLipBottom,
    required this.lowerLipTop,
    required this.lowerLipBottom,
    required this.faceOval,
    required this.leftEye,
    required this.rightEye,
    required this.leftCheek,
    required this.rightCheek,
    required this.box,
  });
}

List<Offset> _contourPoints(Face face, FaceContourType type) {
  final c = face.contours[type];
  if (c == null) return const [];
  return c.points.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList();
}

Offset? _landmarkPoint(Face face, FaceLandmarkType type) {
  final l = face.landmarks[type];
  if (l == null) return null;
  return Offset(l.position.x.toDouble(), l.position.y.toDouble());
}

/// Converts an ML Kit [Face] into the geometry the painter needs.
/// Shared by the live camera and the captured photo.
FaceGeometry buildFaceGeometry(Face face) {
  return FaceGeometry(
    upperLipTop: _contourPoints(face, FaceContourType.upperLipTop),
    upperLipBottom: _contourPoints(face, FaceContourType.upperLipBottom),
    lowerLipTop: _contourPoints(face, FaceContourType.lowerLipTop),
    lowerLipBottom: _contourPoints(face, FaceContourType.lowerLipBottom),
    faceOval: _contourPoints(face, FaceContourType.face),
    leftEye: _contourPoints(face, FaceContourType.leftEye),
    rightEye: _contourPoints(face, FaceContourType.rightEye),
    leftCheek: _landmarkPoint(face, FaceLandmarkType.leftCheek),
    rightCheek: _landmarkPoint(face, FaceLandmarkType.rightCheek),
    box: face.boundingBox,
  );
}

// ============================================================
// PHOTO CAPTURE + RENDERING
// ============================================================

class CapturedLook {
  final Uint8List before; // photo without makeup (PNG)
  final Uint8List after; // photo with makeup (PNG)
  final bool faceFound;

  const CapturedLook({
    required this.before,
    required this.after,
    required this.faceFound,
  });
}

/// Draws the makeup onto a full-resolution still photo.
///
/// Why not just screenshot the screen? CameraPreview is a platform
/// texture, and RepaintBoundary.toImage() often captures it as black.
/// So we take a real photo, detect the face again on it, and paint the
/// same makeup with the same MakeupPainter.
class MakeupRenderer {
  static Future<CapturedLook> render({
    required String photoPath,
    required Map<String, Color> looks,
    required bool mirror,
  }) async {
    // Separate detector in accurate mode: speed doesn't matter for one photo.
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    try {
      // ML Kit and Flutter's decoder both apply the photo's EXIF rotation,
      // so face points and pixels are in the same upright space.
      final faces =
      await detector.processImage(InputImage.fromFilePath(photoPath));

      final bytes = await File(photoPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final photo = (await codec.getNextFrame()).image;
      final size = Size(photo.width.toDouble(), photo.height.toDouble());

      final geometry = faces.isEmpty ? null : buildFaceGeometry(faces.first);

      final before = await _draw(photo, size, null, const {}, mirror);
      final after = await _draw(photo, size, geometry, looks, mirror);

      return CapturedLook(
        before: before,
        after: after,
        faceFound: geometry != null,
      );
    } finally {
      detector.close();
    }
  }

  static Future<Uint8List> _draw(
      ui.Image photo,
      Size size,
      FaceGeometry? geometry,
      Map<String, Color> looks,
      bool mirror,
      ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Mirror the front-camera photo so it matches what the user saw.
    canvas.save();
    if (mirror) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImage(photo, Offset.zero, Paint());
    canvas.restore();

    if (geometry != null && looks.isNotEmpty) {
      MakeupPainter(
        face: geometry,
        looks: looks,
        imageSize: size,
        sensorOrientation: 0, // photo is already upright
        isFrontCamera: mirror,
        showDebug: false,
      ).paint(canvas, size);
    }

    final image = await recorder
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

// ============================================================
// MAKEUP PAINTER
// ============================================================

class MakeupPainter extends CustomPainter {
  final FaceGeometry? face;

  /// category -> applied colour. Only categories in this map are drawn.
  final Map<String, Color> looks;

  final Size? imageSize;
  final int sensorOrientation;
  final bool isFrontCamera;
  final bool showDebug;

  MakeupPainter({
    required this.face,
    required this.looks,
    required this.imageSize,
    required this.sensorOrientation,
    required this.isFrontCamera,
    required this.showDebug,
  });

  // ---------- coordinate mapping ----------

  /// ML Kit returns points in the *rotated* (upright) image space.
  /// On Android the CameraImage is landscape (e.g. 640x480) while the
  /// face points are portrait (480x640), so width/height must be swapped.
  /// This was the real cause of the offset/stretched markers.
  Size get _uprightImageSize {
    final s = imageSize!;
    final rotated = !Platform.isIOS &&
        (sensorOrientation == 90 || sensorOrientation == 270);
    return rotated ? Size(s.height, s.width) : s;
  }

  late double _scale;
  late Offset _offset;
  late Size _img;

  void _prepare(Size canvas) {
    _img = _uprightImageSize;
    // Same maths as BoxFit.cover used for the preview.
    _scale = math.max(canvas.width / _img.width, canvas.height / _img.height);
    _offset = Offset(
      (canvas.width - _img.width * _scale) / 2,
      (canvas.height - _img.height * _scale) / 2,
    );
  }

  Offset _map(Offset p) {
    final x = isFrontCamera ? _img.width - p.dx : p.dx;
    return Offset(x * _scale + _offset.dx, p.dy * _scale + _offset.dy);
  }

  List<Offset> _mapAll(List<Offset> pts) => pts.map(_map).toList();

  // ---------- path helpers ----------

  /// Joins two contour halves into one closed shape, flipping the second
  /// half if needed so the outline doesn't cross itself.
  Path? _closedShape(List<Offset> a, List<Offset> b) {
    if (a.isEmpty || b.isEmpty) return null;
    var second = b;
    if ((a.last - b.first).distance > (a.last - b.last).distance) {
      second = b.reversed.toList();
    }
    final pts = [...a, ...second];
    return Path()..addPolygon(pts, true);
  }

  Path? _lipPath(FaceGeometry f) {
    final outer = _closedShape(
      _mapAll(f.upperLipTop),
      _mapAll(f.lowerLipBottom),
    );
    if (outer == null) return null;

    final inner = _closedShape(
      _mapAll(f.upperLipBottom),
      _mapAll(f.lowerLipTop),
    );

    final path = Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addPath(outer, Offset.zero);
    if (inner != null) path.addPath(inner, Offset.zero); // cut out the mouth
    return path;
  }

  // ---------- makeup layers ----------

  void _paintFoundation(Canvas canvas, FaceGeometry f, Color color) {
    if (f.faceOval.length < 3) return;

    final path = Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addPolygon(_mapAll(f.faceOval), true);

    // Leave eyes and lips uncovered.
    if (f.leftEye.length > 2) path.addPolygon(_mapAll(f.leftEye), true);
    if (f.rightEye.length > 2) path.addPolygon(_mapAll(f.rightEye), true);
    final lips = _closedShape(
      _mapAll(f.upperLipTop),
      _mapAll(f.lowerLipBottom),
    );
    if (lips != null) path.addPath(lips, Offset.zero);

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.28)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          math.max(2.0, f.box.width * _scale * 0.04),
        ),
    );
  }

  void _paintBlush(Canvas canvas, FaceGeometry f, Color color) {
    final radius = f.box.width * _scale * 0.14;

    // Prefer ML Kit's cheek landmarks; fall back to a face-box estimate.
    final cx = f.box.center.dx;
    final cy = f.box.top + f.box.height * 0.60;
    final dx = f.box.width * 0.25;
    final cheeks = [
      f.leftCheek ?? Offset(cx - dx, cy),
      f.rightCheek ?? Offset(cx + dx, cy),
    ];

    for (final c in cheeks) {
      final center = _map(c);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withOpacity(0.40), color.withOpacity(0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintLips(Canvas canvas, FaceGeometry f, Color color) {
    final path = _lipPath(f);
    if (path == null) return;

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.55)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          math.max(1.0, f.box.width * _scale * 0.006),
        ),
    );
  }

  void _paintDebug(Canvas canvas, FaceGeometry f) {
    final dot = Paint()..style = PaintingStyle.fill;

    dot.color = Colors.red;
    for (final p in [...f.upperLipTop, ...f.lowerLipBottom]) {
      canvas.drawCircle(_map(p), 2, dot);
    }
    dot.color = Colors.blue;
    for (final p in [...f.leftEye, ...f.rightEye]) {
      canvas.drawCircle(_map(p), 1.5, dot);
    }
    dot.color = Colors.greenAccent;
    for (final p in f.faceOval) {
      canvas.drawCircle(_map(p), 1.5, dot);
    }
    dot.color = Colors.pink;
    for (final p in [f.leftCheek, f.rightCheek]) {
      if (p != null) canvas.drawCircle(_map(p), 6, dot);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = face;
    if (f == null ||
        imageSize == null ||
        imageSize!.width == 0 ||
        imageSize!.height == 0) {
      return;
    }

    _prepare(size);

    // Order matters: base -> cheeks -> lips.
    final foundation = looks['Foundation'];
    if (foundation != null) _paintFoundation(canvas, f, foundation);

    final blush = looks['Blush'];
    if (blush != null) _paintBlush(canvas, f, blush);

    final lipstick = looks['Lipstick'];
    if (lipstick != null) _paintLips(canvas, f, lipstick);

    if (showDebug) _paintDebug(canvas, f);
  }

  @override
  bool shouldRepaint(covariant MakeupPainter old) => true;
}

// ============================================================
// APP
// ============================================================

class TryOnApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const TryOnApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Try On Me',
      theme: ThemeData(useMaterial3: true),
      home: StartupScreen(cameras: cameras),
    );
  }
}

// ============================================================
// TRY ON SCREEN
// ============================================================

class TryOnScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const TryOnScreen({super.key, required this.cameras});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  CameraController? cameraController;
  late final FaceDetector faceDetector;

  bool isDetecting = false;
  int faceCount = 0;

  FaceGeometry? faceGeometry;

  Size? cameraImageSize;
  int cameraSensorOrientation = 0;
  bool isFrontCamera = false;

  bool showDebug = false;

  /// false while the user holds the camera view (before/after compare).
  bool showMakeup = true;

  bool isCapturing = false;

  /// Applied looks: category -> colour.
  final Map<String, Color> appliedLooks = {};

  /// Same as appliedLooks but with the product + shade, for the cart.
  final Map<String, LookItem> appliedProducts = {};

  void addSelectedToCart() {
    final product = currentProducts[selectedProduct];
    final shade = product.shades[selectedShade];
    CartStore.instance.add(product, shade);
    showAddedToCart(
      context,
      'Added ${product.name} (${shade.name}) to cart',
    );
  }

  String selectedCategory = 'Lipstick';
  int selectedProduct = 0;
  int selectedShade = 0;

  // ============================================================
  // PRODUCTS (live from Firestore — see ProductStore in shop.dart)
  // ============================================================

  List<MakeupProduct> get currentProducts =>
      ProductStore.instance.byCategory(selectedCategory);

  /// Called when products change in Firestore. Keeps the selected
  /// product/shade index valid if items were added or removed.
  void _onProductsChanged() {
    if (!mounted) return;
    setState(() {
      final products = currentProducts;
      if (selectedProduct >= products.length) {
        selectedProduct = 0;
        selectedShade = 0;
      }
      if (products.isNotEmpty &&
          selectedShade >= products[selectedProduct].shades.length) {
        selectedShade = 0;
      }
    });
  }

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();
    ProductStore.instance.addListener(_onProductsChanged);
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        enableClassification: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    initializeCamera();
  }

  // ============================================================
  // CAMERA
  // ============================================================

  Future<void> initializeCamera() async {
    if (widget.cameras.isEmpty) return;

    final selectedCamera = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );

    cameraSensorOrientation = selectedCamera.sensorOrientation;
    isFrontCamera = selectedCamera.lensDirection == CameraLensDirection.front;

    cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      // NV21 is Android-only; iOS needs BGRA.
      imageFormatGroup:
      Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
    );

    try {
      await cameraController!.initialize();
      if (!mounted) return;
      setState(() {});
      await cameraController!.startImageStream(processCameraImage);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  // ============================================================
  // FACE DETECTION
  // ============================================================

  List<Offset> _contour(Face face, FaceContourType type) {
    final c = face.contours[type];
    if (c == null) return const [];
    return c.points.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList();
  }

  Offset? _landmark(Face face, FaceLandmarkType type) {
    final l = face.landmarks[type];
    if (l == null) return null;
    return Offset(l.position.x.toDouble(), l.position.y.toDouble());
  }

  /// Light smoothing between frames to reduce jitter.
  List<Offset> _smooth(List<Offset>? prev, List<Offset> next, [double t = 0.5]) {
    if (prev == null || prev.length != next.length) return next;
    return List.generate(next.length, (i) => Offset.lerp(prev[i], next[i], t)!);
  }

  Offset? _smoothPoint(Offset? prev, Offset? next, [double t = 0.5]) {
    if (prev == null || next == null) return next;
    return Offset.lerp(prev, next, t);
  }

  Future<void> processCameraImage(CameraImage image) async {
    if (isDetecting) return;
    isDetecting = true;

    cameraImageSize = Size(image.width.toDouble(), image.height.toDouble());

    try {
      final inputImage = convertCameraImage(image);
      if (inputImage == null) return;

      final faces = await faceDetector.processImage(inputImage);
      if (!mounted) return;

      if (faces.isEmpty) {
        setState(() {
          faceCount = 0;
          faceGeometry = null;
        });
        return;
      }

      final face = faces.first;
      final prev = faceGeometry;

      final geometry = FaceGeometry(
        upperLipTop: _smooth(prev?.upperLipTop,
            _contour(face, FaceContourType.upperLipTop)),
        upperLipBottom: _smooth(prev?.upperLipBottom,
            _contour(face, FaceContourType.upperLipBottom)),
        lowerLipTop: _smooth(prev?.lowerLipTop,
            _contour(face, FaceContourType.lowerLipTop)),
        lowerLipBottom: _smooth(prev?.lowerLipBottom,
            _contour(face, FaceContourType.lowerLipBottom)),
        faceOval: _smooth(prev?.faceOval, _contour(face, FaceContourType.face)),
        leftEye:
        _smooth(prev?.leftEye, _contour(face, FaceContourType.leftEye)),
        rightEye:
        _smooth(prev?.rightEye, _contour(face, FaceContourType.rightEye)),
        leftCheek: _smoothPoint(
            prev?.leftCheek, _landmark(face, FaceLandmarkType.leftCheek)),
        rightCheek: _smoothPoint(
            prev?.rightCheek, _landmark(face, FaceLandmarkType.rightCheek)),
        box: face.boundingBox,
      );

      setState(() {
        faceCount = faces.length;
        faceGeometry = geometry;
      });
    } catch (e) {
      debugPrint('Face detection error: $e');
    } finally {
      isDetecting = false;
    }
  }

  InputImage? convertCameraImage(CameraImage image) {
    if (cameraController == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      cameraController!.description.sensorOrientation,
    );
    if (rotation == null) return null;

    final format = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    return InputImage.fromBytes(
      bytes: _concatenatePlanes(image.planes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = BytesBuilder();
    for (final plane in planes) {
      allBytes.add(plane.bytes);
    }
    return allBytes.toBytes();
  }

  // ============================================================
  // CAPTURE
  // ============================================================

  Future<void> capturePhoto() async {
    final controller = cameraController;
    if (controller == null || isCapturing) return;

    setState(() => isCapturing = true);

    try {
      // Pause the live stream while taking the picture (more reliable).
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final file = await controller.takePicture();

      final look = await MakeupRenderer.render(
        photoPath: file.path,
        looks: Map.of(appliedLooks),
        mirror: isFrontCamera,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PhotoResultScreen(
            look: look,
            lookItems: appliedProducts.values.toList(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not take photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isCapturing = false);
      if (!controller.value.isStreamingImages) {
        try {
          await controller.startImageStream(processCameraImage);
        } catch (e) {
          debugPrint('Restart stream error: $e');
        }
      }
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    faceDetector.close();
    ProductStore.instance.removeListener(_onProductsChanged);
    super.dispose();
  }

  // ============================================================
  // CAMERA PREVIEW (cover fit)
  // ============================================================

  /// CameraPreview on its own is stretched inside StackFit.expand.
  /// Wrapping it in FittedBox(cover) makes the preview match the
  /// cover maths used by MakeupPainter, so the overlay lines up.
  Widget _buildPreview() {
    final controller = cameraController!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) return CameraPreview(controller);

    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // previewSize is reported in landscape; swap for portrait.
        width: previewSize.height,
        height: previewSize.width,
        child: CameraPreview(controller),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final products = currentProducts;

    // Category has no products in Firestore (e.g. all set to active=false).
    if (products.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    _categoryButton('Lipstick'),
                    _categoryButton('Blush'),
                    _categoryButton('Foundation'),
                  ],
                ),
                const Expanded(
                  child: Center(
                    child: Text('No products in this category yet.'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final product = products[selectedProduct];
    final shade = product.shades[selectedShade];

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'My Orders',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MyOrdersScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                  ),
                  const Expanded(
                    child: Text(
                      'Try On Me',
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  // Tap to toggle landmark debug dots.
                  IconButton(
                    onPressed: () => setState(() => showDebug = !showDebug),
                    icon: Icon(
                      showDebug ? Icons.bug_report : Icons.info_outline,
                    ),
                  ),
                  const CartIconButton(),
                ],
              ),
            ),

            // CAMERA
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                width: double.infinity,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: cameraController != null &&
                    cameraController!.value.isInitialized
                    ? GestureDetector(
                  // Hold anywhere on the camera to see "before".
                  onLongPressStart: (_) =>
                      setState(() => showMakeup = false),
                  onLongPressEnd: (_) =>
                      setState(() => showMakeup = true),
                  onLongPressCancel: () =>
                      setState(() => showMakeup = true),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(),
                      CustomPaint(
                        painter: MakeupPainter(
                          face: faceGeometry,
                          looks: showMakeup ? appliedLooks : const {},
                          imageSize: cameraImageSize,
                          sensorOrientation: cameraSensorOrientation,
                          isFrontCamera: isFrontCamera,
                          showDebug: showDebug,
                        ),
                      ),
                      Positioned(
                        top: 20,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 9),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              !showMakeup
                                  ? 'Before'
                                  : faceCount > 0
                                  ? 'Face detected ✓'
                                  : 'No face detected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Hint for before/after
                      if (appliedLooks.isNotEmpty && showMakeup)
                        const Positioned(
                          left: 16,
                          bottom: 30,
                          child: Text(
                            'Hold to compare',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black),
                              ],
                            ),
                          ),
                        ),

                      // Capture button
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: isCapturing ? null : capturePhoto,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 4),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Processing overlay
                      if (isCapturing)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                    color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'Applying makeup to photo...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),

            const SizedBox(height: 10),

            // CATEGORY
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _categoryButton('Lipstick'),
                  _categoryButton('Blush'),
                  _categoryButton('Foundation'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // PRODUCT LABEL
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    '$selectedCategory Products',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${products.length} products',
                    style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // PRODUCT CARDS
            SizedBox(
              height: 125,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final item = products[index];
                  final isSelected = selectedProduct == index;

                  return GestureDetector(
                    onTap: () => setState(() {
                      selectedProduct = index;
                      selectedShade = 0;
                      _liveUpdate();
                    }),
                    child: Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                          isSelected ? Colors.black : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Center(
                                child: Image.asset(
                                  item.image,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.shopping_bag_outlined,
                                        size: 38,
                                        color: Colors.grey.shade500,
                                      ),
                                ),
                              ),
                            ),
                            Text(
                              item.brand,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 8, color: Colors.grey.shade700),
                            ),
                            Text(
                              '₱${item.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // SHADES HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Shades',
                    style:
                    TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 5),

            // SHADE VARIANTS
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: product.shades.length,
                itemBuilder: (context, index) {
                  final s = product.shades[index];
                  final isSelected = selectedShade == index;

                  return GestureDetector(
                    onTap: () => setState(() {
                      selectedShade = index;
                      _liveUpdate();
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      child: Column(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.black
                                    : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                size: 15, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 5),

            // APPLY / REMOVE
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: faceCount > 0
                            ? () => setState(() {
                          if (appliedLooks
                              .containsKey(selectedCategory)) {
                            appliedLooks.remove(selectedCategory);
                            appliedProducts.remove(selectedCategory);
                          } else {
                            appliedLooks[selectedCategory] =
                                shade.color;
                            appliedProducts[selectedCategory] =
                                LookItem(
                                    product: product, shade: shade);
                          }
                        })
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: Text(
                          appliedLooks.containsKey(selectedCategory)
                              ? 'Remove $selectedCategory'
                              : 'Try On ${product.name} - ${shade.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    width: 48,
                    child: IconButton.filledTonal(
                      tooltip: 'Add to cart',
                      onPressed: addSelectedToCart,
                      icon: const Icon(Icons.add_shopping_cart),
                    ),
                  ),
                  if (appliedLooks.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      width: 48,
                      child: IconButton.outlined(
                        tooltip: 'Clear all makeup',
                        onPressed: () => setState(() {
                          appliedLooks.clear();
                          appliedProducts.clear();
                        }),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// If the current category is already applied, changing product/shade
  /// updates the look immediately.
  void _liveUpdate() {
    if (appliedLooks.containsKey(selectedCategory)) {
      final product = currentProducts[selectedProduct];
      final shade = product.shades[selectedShade];
      appliedLooks[selectedCategory] = shade.color;
      appliedProducts[selectedCategory] =
          LookItem(product: product, shade: shade);
    }
  }

  // ============================================================
  // CATEGORY BUTTON
  // ============================================================

  Widget _categoryButton(String text) {
    final isSelected = selectedCategory == text;
    final isApplied = appliedLooks.containsKey(text);

    return GestureDetector(
      onTap: () => setState(() {
        selectedCategory = text;
        selectedProduct = 0;
        selectedShade = 0;
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isApplied) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: appliedLooks[text],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PHOTO RESULT SCREEN (before/after slider + save)
// ============================================================

class PhotoResultScreen extends StatefulWidget {
  final CapturedLook look;

  /// Products worn in this photo (for "Add look to cart").
  final List<LookItem> lookItems;

  const PhotoResultScreen({
    super.key,
    required this.look,
    this.lookItems = const [],
  });

  @override
  State<PhotoResultScreen> createState() => _PhotoResultScreenState();
}

class _PhotoResultScreenState extends State<PhotoResultScreen> {
  /// 0.0 = all "after", 1.0 = all "before".
  double split = 0.5;
  bool isSaving = false;
  bool isSaved = false;

  Future<void> savePhoto() async {
    setState(() => isSaving = true);
    try {
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) throw Exception('Gallery permission denied');
      }

      await Gal.putImageBytes(
        widget.look.after,
        name: 'tryonme_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;
      setState(() => isSaved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to gallery ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Widget _label(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Your Look',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        actions: const [CartIconButton()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!look.faceFound)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'No face found in the photo, so makeup was not applied. '
                      'Try again facing the camera in good light.',
                  style: TextStyle(fontSize: 12),
                ),
              ),

            // BEFORE / AFTER COMPARE
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final dividerX = width * split;

                    return GestureDetector(
                      onHorizontalDragUpdate: (d) => setState(() {
                        split = (d.localPosition.dx / width).clamp(0.0, 1.0);
                      }),
                      onTapDown: (d) => setState(() {
                        split = (d.localPosition.dx / width).clamp(0.0, 1.0);
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // After (full)
                          Image.memory(
                            look.after,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),

                          // Before (clipped to the left side)
                          ClipRect(
                            clipper: _SplitClipper(split),
                            child: Image.memory(
                              look.before,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          ),

                          // Divider line + handle
                          Positioned(
                            left: dividerX - 1,
                            top: 0,
                            bottom: 0,
                            child: Container(width: 2, color: Colors.white),
                          ),
                          Positioned(
                            left: dividerX - 18,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                        blurRadius: 6, color: Colors.black26),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.compare_arrows,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),

                          Positioned(top: 16, left: 16, child: _label('Before')),
                          Positioned(top: 16, right: 16, child: _label('After')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 8),
            Text(
              'Drag to compare before and after',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),

            // ADD LOOK TO CART
            if (widget.lookItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      CartStore.instance.addLook(widget.lookItems);
                      showAddedToCart(
                        context,
                        'Added ${widget.lookItems.length} product(s) '
                            'from this look to cart',
                      );
                    },
                    icon: const Icon(Icons.add_shopping_cart),
                    label: Text(
                      'Add This Look to Cart · ${peso(widget.lookItems.fold<double>(0, (sum, i) => sum + i.product.price))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink.shade400,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ),

            // ACTIONS
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isSaving || isSaved ? null : savePhoto,
                        icon: isSaving
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : Icon(isSaved ? Icons.check : Icons.download),
                        label: Text(isSaved ? 'Saved' : 'Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitClipper extends CustomClipper<Rect> {
  final double fraction;
  _SplitClipper(this.fraction);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_SplitClipper old) => old.fraction != fraction;
}