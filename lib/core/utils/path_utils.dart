// أدوات موحّدة للمقارنة بين مسارات الملفات عبر أنظمة التشغيل.
//
// إصلاح 05: النموذج يرسل المسارات بصيغة POSIX (lib/main.dart) بينما
// Windows يبني المسارات المطلقة بالشرطة الخلفية (C:\...\lib\main.dart)،
// فأي مقارنة لاحقة (endsWith) تفشل بسبب اختلاف الفاصل وحده. هذه الدوال
// توحّد الفواصل قبل المقارنة.

/// يوحّد فواصل المسار إلى الشرطة الأمامية `/` (صيغة POSIX).
///
/// مثال: `C:\proj\lib\main.dart` يصبح `C:/proj/lib/main.dart`
String normalizePathSeparators(String path) => path.replaceAll('\\', '/');

/// يقارن مسارين مع تجاهل اختلاف الفواصل وحالة الأحرف (Windows غير
/// حساسة لحالة الأحرف)، ويدعم أن يكون أحدهما مساراً مطلقاً والآخر
/// نسبياً — بشرط أن تقع المطابقة عند حدّ مجلد كامل لا داخل اسم ملف.
bool isSameFilePath(String a, String b) {
  final na = normalizePathSeparators(a).toLowerCase();
  final nb = normalizePathSeparators(b).toLowerCase();
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  // الطرف الأطول يجب أن ينتهي بالطرف الآخر مسبوقاً بفاصل، حتى لا
  // تتطابق `main.dart` مع `domain.dart` أو `utils.dart` مع `my_utils.dart`.
  if (na.length > nb.length) return na.endsWith('/$nb');
  if (nb.length > na.length) return nb.endsWith('/$na');
  return false;
}
