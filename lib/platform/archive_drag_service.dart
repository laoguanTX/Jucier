import 'dart:async';

import 'package:flutter/services.dart';

import '../archive/archive_engine.dart';

class ArchiveDragItem {
  const ArchiveDragItem({
    required this.id,
    required this.name,
    required this.isDirectory,
  });

  final String id;
  final String name;
  final bool isDirectory;

  Map<String, Object> toMap() => {
    'id': id,
    'name': name,
    'isDirectory': isDirectory,
  };
}

class ArchiveDragMaterializationRequest {
  const ArchiveDragMaterializationRequest({
    required this.id,
    required this.outputPath,
  });

  final String id;
  final String outputPath;
}

typedef ArchiveDragMaterializer = Future<void> Function(
  ArchiveDragMaterializationRequest request,
);

class MacOSArchiveDragService {
  MacOSArchiveDragService({required this.onMaterialize, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channelName = 'dev.jucier/file_drag';

  final ArchiveDragMaterializer onMaterialize;
  final MethodChannel _channel;
  Future<void> _materializationQueue = Future.value();
  bool _dragInProgress = false;

  bool get dragInProgress => _dragInProgress;

  Future<void> beginDrag(List<ArchiveDragItem> items) async {
    if (items.isEmpty) return;
    if (_dragInProgress) throw const ArchiveException('已有文件拖拽正在进行');
    _dragInProgress = true;
    try {
      await _channel.invokeMethod<void>(
        'beginDrag',
        items.map((item) => item.toMap()).toList(),
      );
    } on PlatformException catch (error) {
      throw ArchiveException(error.message ?? '无法开始文件拖拽');
    } on MissingPluginException {
      throw const ArchiveException('当前平台不支持将压缩包文件拖出');
    } finally {
      _dragInProgress = false;
    }
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'materialize') return null;
    final arguments = call.arguments;
    if (arguments is! Map) {
      throw const ArchiveException('拖拽解压参数无效');
    }
    final id = arguments['id'];
    final outputPath = arguments['outputPath'];
    if (id is! String || outputPath is! String) {
      throw const ArchiveException('拖拽解压参数无效');
    }
    final operation = _materializationQueue.then(
      (_) => onMaterialize(
        ArchiveDragMaterializationRequest(id: id, outputPath: outputPath),
      ),
    );
    _materializationQueue = operation.onError((_, _) {});
    await operation;
    return null;
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
