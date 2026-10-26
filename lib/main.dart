import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  
  // متغيرات جديدة للتحكم في خطوات الرسم
  bool _showSteps = false; // هل نعرض شاشة الخطوات؟
  double _currentStep = 1.0; // الخطوة الحالية من 1 إلى 8

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
          // عند انتهاء الإعلان، نقوم بتفعيل وضع الخطوات وتوليد الرسم النهائي
          setState(() {
            _showSteps = true; 
            _currentStep = 1.0;
          });
          _convertToSketch();
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

  Future<void> _convertToSketch() async {
    if (_originalImage == null) return;
    setState(() => _isProcessing = true);

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
          
          // شريط التحكم بالخطوات (يظهر فقط إذا تم تفعيل الخطوات)
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

          // أزرار التحكم
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
    if (_isProcessing && _sketchImage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_originalImage == null) {
      return const Center(child: Text('لم يتم اختيار صورة بعد'));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. الصورة الأصلية في الخلفية
          Image.file(_originalImage!, fit: BoxFit.contain),
          
          // 2. طبقة رسم خطوات لوميس (تظهر حسب الخطوة الحالية)
          if (_showSteps && _currentStep < 8)
            CustomPaint(
              painter: LoomisPainter(step: _currentStep),
            ),

          // 3. الرسم النهائي (يظهر فقط في الخطوة 8)
          if (_showSteps && _currentStep == 8 && _sketchImage != null)
            Container(
              color: Colors.white, // خلفية بيضاء للرسم النهائي
              child: Image.memory(_sketchImage!, fit: BoxFit.contain),
            ),
            
          // مؤشر التحميل إذا كان في الخطوة 8 ولا يزال ينتج الرسم
          if (_showSteps && _currentStep == 8 && _sketchImage == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

// =====================================================================
// كلاس رسم خطوات لوميس
// ملاحظة: هذا الرسم تقريبي ومبني على النسب الرياضية للصورة.
// لتطابق تام 100%، يتم استبدال الإحداثيات بنقاط اكتشاف الوجه (Face Detection).
// =====================================================================
class LoomisPainter extends CustomPainter {
  final double step;

  LoomisPainter({required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    // إعداد الأقلام
    final guidePaint = Paint()
      ..color = Colors.pinkAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final constructionPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // افتراض أن الوجه في منتصف الصورة (لتقريب الشكل)
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final faceWidth = size.width * 0.4; // عرض الوجه التقريبي
    final faceHeight = size.height * 0.6; // طول الوجه التقريبي

    // الخطوة 1: رسم دائرة الجمجمة
    if (step >= 1) {
      canvas.drawCircle(Offset(centerX, centerY - faceHeight * 0.1), faceWidth * 0.6, guidePaint);
    }

    // الخطوة 2: رسم خط الفك والذقن
    if (step >= 2) {
      final jawPath = Path()
        ..moveTo(centerX - faceWidth * 0.6, centerY - faceHeight * 0.1)
        ..quadraticBezierTo(
          centerX - faceWidth * 0.5, centerY + faceHeight * 0.4,
          centerX, centerY + faceHeight * 0.4, // الذقن
        )
        ..quadraticBezierTo(
          centerX + faceWidth * 0.5, centerY + faceHeight * 0.4,
          centerX + faceWidth * 0.6, centerY - faceHeight * 0.1,
        );
      canvas.drawPath(jawPath, guidePaint);
    }

    // الخطوة 3: الخط المركزي (الأنف)
    if (step >= 3) {
      canvas.drawLine(
        Offset(centerX, centerY - faceHeight * 0.5),
        Offset(centerX, centerY + faceHeight * 0.4),
        guidePaint,
      );
    }

    // الخطوة 4: خط العينين (Brow Line)
    if (step >= 4) {
      final eyeLineY = centerY - faceHeight * 0.05;
      canvas.drawLine(
        Offset(centerX - faceWidth * 0.6, eyeLineY),
        Offset(centerX + faceWidth * 0.6, eyeLineY),
        constructionPaint,
      );
    }

    // الخطوة 5: قسمة الوجه إلى أثلاث (لرسم الأنف والفم)
    if (step >= 5) {
      final browY = centerY - faceHeight * 0.05;
      final chinY = centerY + faceHeight * 0.4;
      final noseY = browY + (chinY - browY) / 3;
      final mouthY = browY + 2 * (chinY - browY) / 3;

      canvas.drawLine(Offset(centerX - faceWidth * 0.4, noseY), Offset(centerX + faceWidth * 0.4, noseY), constructionPaint);
      canvas.drawLine(Offset(centerX - faceWidth * 0.3, mouthY), Offset(centerX + faceWidth * 0.3, mouthY), constructionPaint);
    }

    // الخطوة 6: رسم العينين
    if (step >= 6) {
      final eyeY = centerY - faceHeight * 0.05;
      final eyeSpacing = faceWidth * 0.35;
      // العين اليسرى
      canvas.drawOval(Rect.fromCenter(center: Offset(centerX - eyeSpacing, eyeY), width: faceWidth * 0.2, height: faceWidth * 0.08), guidePaint);
      // العين اليمنى
      canvas.drawOval(Rect.fromCenter(center: Offset(centerX + eyeSpacing, eyeY), width: faceWidth * 0.2, height: faceWidth * 0.08), guidePaint);
    }

    // الخطوة 7: رسم الأنف والفم (أشكال هندسية)
    if (step >= 7) {
      final browY = centerY - faceHeight * 0.05;
      final chinY = centerY + faceHeight * 0.4;
      final noseY = browY + (chinY - browY) / 3;
      final mouthY = browY + 2 * (chinY - browY) / 3;

      // الأنف (مثلث)
      final nosePath = Path()
        ..moveTo(centerX, noseY - faceHeight * 0.1)
        ..lineTo(centerX - faceWidth * 0.1, noseY)
        ..lineTo(centerX + faceWidth * 0.1, noseY);
      canvas.drawPath(nosePath, guidePaint);

      // الفم (شكل بيضاوي)
      canvas.drawOval(Rect.fromCenter(center: Offset(centerX, mouthY), width: faceWidth * 0.25, height: faceWidth * 0.1), guidePaint);
    }
  }

  @override
  bool shouldRepaint(covariant LoomisPainter oldDelegate) {
    return oldDelegate.step != step;
  }
}