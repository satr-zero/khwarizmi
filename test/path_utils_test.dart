import 'package:flutter_test/flutter_test.dart';
import 'package:khwarizmi/core/utils/path_utils.dart';

void main() {
  group('PathUtils (إصلاح 05)', () {
    test('normalizePathSeparators يوحّد الشرطة الخلفية إلى أمامية', () {
      expect(
        normalizePathSeparators(r'C:\proj\lib\main.dart'),
        'C:/proj/lib/main.dart',
      );
      expect(normalizePathSeparators('lib/main.dart'), 'lib/main.dart');
      expect(
        normalizePathSeparators(r'lib\features\chat\widget.dart'),
        'lib/features/chat/widget.dart',
      );
    });

    test('isSameFilePath يطابق المسار المطلق بنسبيته رغم اختلاف الفواصل', () {
      // جوهر إصلاح 05: النموذج يرسل lib/main.dart والتعديل المعلّق
      // يخزّن المسار المطلق بالشرطة الخلفية على Windows.
      expect(
        isSameFilePath(
          r'C:\Users\dev\projects\app\lib\main.dart',
          'lib/main.dart',
        ),
        isTrue,
      );
      expect(
        isSameFilePath(
          r'C:\proj\lib\features\chat\widget.dart',
          r'lib\features\chat\widget.dart',
        ),
        isTrue,
      );
    });

    test('isSameFilePath متطابق تماماً ومتجاهل لحالة الأحرف', () {
      expect(isSameFilePath('lib/main.dart', 'lib/main.dart'), isTrue);
      expect(isSameFilePath('lib/Main.dart', 'lib/main.dart'), isTrue);
      expect(isSameFilePath(r'C:\Proj\LIB\main.dart', 'lib/main.dart'), isTrue);
    });

    test('isSameFilePath يرفض المطابقة داخل اسم الملف بلا حد فاصل', () {
      expect(isSameFilePath('src/utils.dart', 'domain.dart'), isFalse);
      expect(isSameFilePath('main.dart', 'domain.dart'), isFalse);
      expect(isSameFilePath('my_utils.dart', 'utils.dart'), isFalse);
      // لكن عند حد مجلد كامل فالمطابقة صحيحة:
      expect(isSameFilePath('test/src/utils.dart', 'src/utils.dart'), isTrue);
    });

    test(
      'isSameFilePath يرفض المسارات الفارغة (كانت تطابق الجميع بـ endsWith)',
      () {
        expect(isSameFilePath('', 'lib/main.dart'), isFalse);
        expect(isSameFilePath('lib/main.dart', ''), isFalse);
        expect(isSameFilePath('', ''), isFalse);
      },
    );

    test('isSameFilePath يرفض المسارات المختلفة فعلياً', () {
      expect(
        isSameFilePath(r'C:\proj\lib\main.dart', 'lib/other.dart'),
        isFalse,
      );
      expect(isSameFilePath(r'C:\proj\lib\main.dart', 'main.dartx'), isFalse);
    });
  });
}
