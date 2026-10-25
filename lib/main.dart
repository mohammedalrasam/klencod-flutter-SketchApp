import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة إعلانات جوجل
  MobileAds.instance.initialize();
  runApp(const SketchApp());
}

class SketchApp extends StatelessWidget {
  const SketchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sketch Steps AI',
      theme: ThemeData(primarySwatch: Colors.blueGrey),
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

  // متغيرات الإعلانات
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  
  // معرف إعلان تجريبي من جوجل (للتجربة فقط)
  static const String _rewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  @override
  void initState() {
    super.initState();
    _loadRewardedAd();
  }

  // 1. تحميل الإعلان المكافأة
  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          debugPrint('تم تحميل الإعلان بنجاح.');
          setState(() {
            _rewardedAd = ad;
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (LoadAdError error) {
          debugPrint('فشل تحميل الإعلان: $error');
          setState(() {
            _rewardedAd = null;
            _isAdLoaded = false;
          });
        },
      ),
    );
  }

  // 2. اختيار الصورة من المعرض
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _originalImage = File(pickedFile.path);
        _sketchImage = null; // إعادة تعيين الرسم السابق
      });
    }
  }

  // 3. عرض الإعلان لمنح المكافأة
  void _showRewardedAd() {
    if (_isAdLoaded && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (RewardedAd ad) {
          debugPrint('تم إغلاق الإعلان.');
          ad.dispose();
          _loadRewardedAd(); // تحميل إعلان جديد للاستخدام القادم
        },
        onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
          debugPrint('فشل عرض الإعلان: $error');
          ad.dispose();
          _loadRewardedAd();
        },
      );

      // عند مشاهدة الإعلان كاملاً، نمنح المكافأة ونبدأ التحويل
      _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          debugPrint('حصل المستخدم على المكافأة: ${reward.amount} ${reward.type}');
          _convertToSketch(); // تنفيذ التحويل هنا
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

  // 4. خوارزمية تحويل الصورة إلى رسم رصاص (Sketch)
  Future<void> _convertToSketch() async {
    if (_originalImage == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // قراءة الصورة
      final bytes = await _originalImage!.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) return;

      // تصغير الصورة قليلاً لتسريع المعالجة
      final resized = img.copyResize(image, width: 800);

      // تطبيق فلتر الرسم الرصاصي (Grayscale + Invert + Blur)
      final grayscale = img.grayscale(resized);
      final inverted = img.invert(grayscale);
      final blurred = img.gaussianBlur(inverted, radius: 10);

      // دمج الطبقات (Color Dodge) لإنتاج تأثير الرصاص
      final sketch = img.Image(width: grayscale.width, height: grayscale.height);
      for (var y = 0; y < grayscale.height; y++) {
        for (var x = 0; x < grayscale.width; x++) {
          final pixelG = grayscale.getPixel(x, y);
          final pixelB = blurred.getPixel(x, y);
          
          final r = (pixelG.r * 255) ~/ (255 - pixelB.r + 1);
          final g = (pixelG.g * 255) ~/ (255 - pixelB.g + 1);
          final b = (pixelG.b * 255) ~/ (255 - pixelB.b + 1);

          // تحديد اللون الجديد
          sketch.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
        }
      }

      // تحويل الصورة الناتجة إلى بايتات لعرضها
      setState(() {
        _sketchImage = Uint8List.fromList(img.encodePng(sketch));
        _isProcessing = false;
      });

    } catch (e) {
      debugPrint('خطأ في المعالجة: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sketch Steps AI')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // منطقة عرض الصور
            Container(
              height: 400,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey),
              ),
              child: _buildImageDisplay(),
            ),
            const SizedBox(height: 20),

            // أزرار التحكم
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('اختر صورة'),
                ),
                ElevatedButton.icon(
                  onPressed: _originalImage != null ? _showRewardedAd : null,
                  icon: const Icon(Icons.play_circle),
                  label: const Text('شاهد إعلاناً للتحويل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // دالة مساعدة لعرض الصور أو حالة التحميل
  Widget _buildImageDisplay() {
    if (_isProcessing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sketchImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(_sketchImage!, fit: BoxFit.contain),
      );
    }
    if (_originalImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(_originalImage!, fit: BoxFit.contain),
      );
    }
    return const Center(child: Text('لم يتم اختيار صورة بعد'));
  }
}