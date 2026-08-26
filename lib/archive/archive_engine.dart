import 'archive_entry.dart';
import 'archive_options.dart';

typedef ProgressCallback = void Function(double progress);

abstract interface class ArchiveEngine {
  Future<bool> get isAvailable;

  Future<ArchiveListing> list(String archivePath, {String? password});

  Future<void> create(
    CreateArchiveOptions options, {
    ProgressCallback? onProgress,
  });

  Future<void> extract(
    ExtractArchiveOptions options, {
    ProgressCallback? onProgress,
  });

  Future<void> test(
    String archivePath, {
    String? password,
    ProgressCallback? onProgress,
  });

  Future<void> cancel();
}

class ArchiveException implements Exception {
  const ArchiveException(this.message, {this.output, this.exitCode});

  final String message;
  final String? output;
  final int? exitCode;

  @override
  String toString() => message;
}

class ArchivePasswordRequiredException extends ArchiveException {
  const ArchivePasswordRequiredException({super.output}) : super('这个压缩包需要密码');
}

class ArchiveCancelledException extends ArchiveException {
  const ArchiveCancelledException() : super('操作已取消', exitCode: 255);
}
