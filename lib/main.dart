import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MobileAds.instance.initialize();
  runApp(const SketchApp());
}

class SketchApp extends StatelessWidget {
  const SketchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sketch Steps AI',
      theme: ThemeData(primarySwatch: Colors.blueGrey, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? _originalImage;
  Uint8List? _sketchImage;
  bool _isProcessing = false;
  
  // متغيرات الخطوات واكتشاف الوجه
  bool _showSteps = false;
  double _currentStep = 1.0;
  Face? _detectedFace; // بيانات الوجه المكتشف
  Size? _imageSize; // الأبعاد الأصلية للصورة

  // متغيرات الإعلانات
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  static const String _rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  @override
  void initState() {
    super.initState();
    _loadRewardedAd();
  }

  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          setState(() {
            _rewardedAd = ad;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          setState(() {
            _rewardedAd = null;
            _isAdLoaded = false;
          });
        },
      ),
    );
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _originalImage = File(pickedFile.path);
        _sketchImage = null;
        _detectedFace = null;
        _showSteps = false;
        _currentStep = 1.0;
      });
    }
  }

  void _showRewardedAd() {
    if (_isAdLoaded && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (RewardedAd ad) {
          ad.dispose();
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
          ad.dispose();
          _loadRewardedAd();
        },
      );

      _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          // عند انتهاء الإعلان: نكتشف الوجه ونبدأ المعالجة
          _processImageWithAI(); 
        },
      );
      _rewardedAd = null;
      _isAdLoaded = false;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الإعلان غير جاهز بعد، يرجى المحاولة بعد قليل.')),
      );
      _loadRewardedAd();
    }
  }

  // دالة اكتشاف الوجه باستخدام الذكاء الاصطناعي
  Future<void> _processImageWithAI() async {
    if (_originalImage == null) return;
    
    setState(() {
      _isProcessing = true;
      _showSteps = true;
      _currentStep = 1.0;
    });

    try {
      // 1. الحصول على أبعاد الصورة
      final decodedImage = await decodeImageFromList(await _originalImage!.readAsBytes());
      _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());

      // 2. إعداد كاشف الوجه
      final options = FaceDetectorOptions(
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      );
      final faceDetector = FaceDetector(options: options);

      // 3. اكتشاف الوجه
      final inputImage = InputImage.fromFilePath(_originalImage!.path);
      final faces = await faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        setState(() {
          _detectedFace = faces.first; // نأخذ أول وجه يتم اكتشافه
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم اكتشاف وجه في الصورة. يرجى استخدام صورة أوضح.')),
        );
        setState(() => _showSteps = false);
      }

      faceDetector.close();

      // 4. توليد الرسم الرصاصي النهائي (الخطوة 8)
      await _convertToSketch();

    } catch (e) {
      debugPrint("Error: $e");
      setState(() {
        _isProcessing = false;
        _showSteps = false;
      });
    }
  }

  Future<void> _convertToSketch() async {
    if (_originalImage == null) return;

    try {
      final bytes = await _originalImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return;

      final resized = img.copyResize(image, width: 600);
      final grayscale = img.grayscale(resized);
      final inverted = img.invert(grayscale);
      final blurred = img.gaussianBlur(inverted, radius: 8);

      final sketch = img.Image(width: grayscale.width, height: grayscale.height);
      for (var y = 0; y < grayscale.height; y++) {
        for (var x = 0; x < grayscale.width; x++) {
          final pixelG = grayscale.getPixel(x, y);
          final pixelB = blurred.getPixel(x, y);
          final r = (pixelG.r * 255) ~/ (255 - pixelB.r + 1);
          final g = (pixelG.g * 255) ~/ (255 - pixelB.g + 1);
          final b = (pixelG.b * 255) ~/ (255 - pixelB.b + 1);
          sketch.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
        }
      }

      setState(() {
        _sketchImage = Uint8List.fromList(img.encodePng(sketch));
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sketch Steps AI'),
        actions: [
          if (_originalImage != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _originalImage = null;
                _sketchImage = null;
                _showSteps = false;
                _detectedFace = null;
              }),
            )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey),
              ),
              child: _buildMainDisplay(),
            ),
          ),
          
          if (_showSteps && _originalImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Text(
                    'الخطوة ${_currentStep.toInt()} من 8',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Slider(
                    value: _currentStep,
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: _currentStep.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        _currentStep = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('اختر صورة'),
                ),
                ElevatedButton.icon(
                  onPressed: _originalImage != null && !_showSteps ? _showRewardedAd : null,
                  icon: const Icon(Icons.play_circle),
                  label: const Text('تحويل لخطوات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainDisplay() {
    if (_isProcessing && _sketchImage == null && _currentStep < 8) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_originalImage == null) {
      return const Center(child: Text('لم يتم اختيار صورة بعد'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. الصورة الأصلية
              Image.file(_originalImage!, fit: BoxFit.contain),
              
              // 2. طبقة رسم خطوات لوميس الحقيقية
              if (_showSteps && _currentStep < 8 && _detectedFace != null && _imageSize != null)
                CustomPaint(
                  painter: LoomisPainter(
                    face: _detectedFace!,
                    imageSize: _imageSize!,
                    step: _currentStep,
                    containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),

              // 3. الرسم النهائي (الخطوة 8)
              if (_showSteps && _currentStep == 8 && _sketchImage != null)
                Container(
                  color: Colors.white,
                  child: Image.memory(_sketchImage!, fit: BoxFit.contain),
                ),
                
              if (_showSteps && _currentStep == 8 && _sketchImage == null)
                const Center(child: CircularProgressIndicator()),
            ],
          );
        },
      ),
    );
  }
}

// =====================================================================
// كلاس رسم خطوات لوميس بناءً على إحداثيات الوجه المكتشفة
// =====================================================================
class LoomisPainter extends CustomPainter {
  final Face face;
  final Size imageSize;
  final double step;
  final Size containerSize;

  LoomisPainter({
    required this.face,
    required this.imageSize,
    required this.step,
    required this.containerSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final constructionPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // حساب التكبير/التصغير (Scale) ليتطابق رسم الـ Canvas مع الصورة
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;
    // نستخدم أصغر نسبة لضمان عدم تشوه الرسم (لأن BoxFit.contain يحافظ على النسبة)
    final scale = scaleX < scaleY ? scaleX : scaleY; 

    // حساب الإزاحة (Offset) للصورة داخل الحاوية
    final dx = (size.width - (imageSize.width * scale)) / 2;
    final dy = (size.height - (imageSize.height * scale)) / 2;

    // دالة مساعدة لتحويل إحداثيات الصورة الأصلية إلى إحداثيات الشاشة
    Offset mapPoint(Offset point) {
      return Offset((point.dx * scale) + dx, (point.dy * scale) + dy);
    }

    // إحداثيات الوجه
    final faceRect = face.boundingBox;
    final topLeft = mapPoint(Offset(faceRect.left, faceRect.top));
    final bottomRight = mapPoint(Offset(faceRect.right, faceRect.bottom));
    final faceWidth = bottomRight.dx - topLeft.dx;
    final faceHeight = bottomRight.dy - topLeft.dy;
    final centerX = topLeft.dx + (faceWidth / 2);

    // استخراج النقاط الرئيسية
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];
    
    if (leftEye != null && rightEye != null) {
      final leftEyePos = mapPoint(Offset(leftEye.position.x, leftEye.position.y));
      final rightEyePos = mapPoint(Offset(rightEye.position.x, rightEye.position.y));
      final eyeY = (leftEyePos.dy + rightEyePos.dy) / 2;

      // الخطوة 1: دائرة الجمجمة
      if (step >= 1) {
        canvas.drawCircle(
          Offset(centerX, topLeft.dy + (faceHeight * 0.35)), 
          faceWidth * 0.5, 
          guidePaint
        );
      }

      // الخطوة 2: خط منتصف الوجه
      if (step >= 2) {
        canvas.drawLine(
          Offset(centerX, topLeft.dy),
          Offset(centerX, bottomRight.dy + (faceHeight * 0.1)), // تمتد قليلاً تحت الذقن
          guidePaint,
        );
      }

      // الخطوة 3: خط العينين
      if (step >= 3) {
        canvas.drawLine(
          Offset(leftEyePos.dx - (faceWidth * 0.2), eyeY),
          Offset(rightEyePos.dx + (faceWidth * 0.2), eyeY),
          constructionPaint,
        );
      }

      // الخطوة 4: خط الفك والذقن
      if (step >= 4) {
        final jawPath = Path()
          ..moveTo(leftEyePos.dx - (faceWidth * 0.3), eyeY)
          ..quadraticBezierTo(
            leftEyePos.dx - (faceWidth * 0.3), bottomRight.dy - (faceHeight * 0.2),
            centerX, bottomRight.dy,
          )
          ..quadraticBezierTo(
            rightEyePos.dx + (faceWidth * 0.3), bottomRight.dy - (faceHeight * 0.2),
            rightEyePos.dx + (faceWidth * 0.3), eyeY,
          );
        canvas.drawPath(jawPath, constructionPaint);
      }

      // الخطوة 5: خطوط قسمة الوجه (الأنف والفم)
      if (step >= 5) {
        final noseY = eyeY + (bottomRight.dy - eyeY) / 3;
        final mouthY = eyeY + 2 * (bottomRight.dy - eyeY) / 3;
        
        canvas.drawLine(Offset(topLeft.dx, noseY), Offset(bottomRight.dx, noseY), constructionPaint);
        canvas.drawLine(Offset(topLeft.dx + (faceWidth * 0.1), mouthY), Offset(bottomRight.dx - (faceWidth * 0.1), mouthY), constructionPaint);
      }

      // الخطوة 6: رسم العينين
      if (step >= 6) {
        canvas.drawOval(Rect.fromCenter(center: leftEyePos, width: faceWidth * 0.2, height: faceWidth * 0.08), guidePaint);
        canvas.drawOval(Rect.fromCenter(center: rightEyePos, width: faceWidth * 0.2, height: faceWidth * 0.08), guidePaint);
      }

      // الخطوة 7: رسم الأنف والفم تقريبياً
      if (step >= 7) {
        final nosePos = face.landmarks[FaceLandmarkType.noseBase];
        final mouthPos = face.landmarks[FaceLandmarkType.bottomMouth];
        
        if (nosePos != null) {
          final nPos = mapPoint(Offset(nosePos.position.x, nosePos.position.y));
          final nosePath = Path()
            ..moveTo(centerX, eyeY + (faceHeight * 0.1))
            ..lineTo(nPos.dx - (faceWidth * 0.08), nPos.dy)
            ..lineTo(nPos.dx + (faceWidth * 0.08), nPos.dy);
          canvas.drawPath(nosePath, guidePaint);
        }
        
        if (mouthPos != null) {
          final mPos = mapPoint(Offset(mouthPos.position.x, mouthPos.position.y));
          canvas.drawOval(Rect.fromCenter(center: mPos, width: faceWidth * 0.25, height: faceWidth * 0.1), guidePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant LoomisPainter oldDelegate) {
    return oldDelegate.step != step;
  }
}