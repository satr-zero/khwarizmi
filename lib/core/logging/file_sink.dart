/// مصرف الملفات — يكتب السجلات إلى ملف مع تدوير يومي وحد أقصى للحجم
library khwarizmi.core.logging;

import 'dart:async';
import 'dart:io';

import 'logger.dart';

/// مصرف يكتب إلى ملف JSONL مع تدوير
class FileSink implements LogSink {
  FileSink({
    required this.path,
    required this.minLevel,
    this.maxFileSizeBytes = 10 * 1024 * 1024,
    this.maxFiles = 7,
  }) {
    _initFile();
  }

  @override
  final LogLevel minLevel;

  final String path;
  final int maxFileSizeBytes;
  final int maxFiles;

  File? _file;
  IOSink? _sink;
  int _currentSize = 0;
  final _lock = _AsyncLock();

  void _initFile() {
    final file = File(path);
    final dir = file.parent;
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _file = file;
    _sink = file.openWrite(mode: FileMode.append);
    _currentSize = file.existsSync() ? file.lengthSync() : 0;
  }

  @override
  void write(LogEntry entry) {
    _lock.synchronized(() {
      if (_sink == null) return;

      final line = entry.toJsonLine() + '\n';
      _sink!.write(line);
      _currentSize += line.length;

      // فحص التدوير بالحجم
      if (_currentSize >= maxFileSizeBytes) {
        _rotateBySize();
      }
    });
  }

  void _rotateBySize() {
    if (_file == null || _sink == null) return;

    _sink!.close();
    _sink = null;

    // إعادة تسمية الملف الحالي
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .substring(0, 19);
    final rotatedPath = '${_file!.path}.$timestamp';
    _file!.renameSync(rotatedPath);

    // حذف الملفات القديمة (الاحتفاظ بـ maxFiles)
    _cleanOldFiles();

    // إنشاء ملف جديد
    _initFile();
  }

  void _cleanOldFiles() {
    final dir = _file!.parent;
    final pattern = RegExp(
      r'khwarizmi-\d{8}\.log\.\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}',
    );

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => pattern.hasMatch(f.path))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );

    for (var i = maxFiles; i < files.length; i++) {
      try {
        files[i].deleteSync();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    await _lock.synchronized(() async {
      await _sink?.flush();
      await _sink?.close();
      _sink = null;
      _file = null;
    });
  }
}

/// قفل غير متزامن بسيط لحماية الكتابة المتزامنة
class _AsyncLock {
  final _completers = <Completer<void>>[];
  bool _locked = false;

  Future<T> synchronized<T>(FutureOr<T> Function() action) async {
    if (_locked) {
      final completer = Completer<void>();
      _completers.add(completer);
      await completer.future;
    }

    _locked = true;
    try {
      return await action();
    } finally {
      _locked = false;
      if (_completers.isNotEmpty) {
        _completers.removeAt(0).complete();
      }
    }
  }
}
