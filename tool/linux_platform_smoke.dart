import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// 使用独立的 XDG_CONFIG_HOME，先设置 JUCIER_SMOKE_PHASE=write 运行一次，
// 再设置 JUCIER_SMOKE_PHASE=read 运行一次，验证设置能否在重启后保留。
// 不绘制 Flutter 画面，也不打开外部应用。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannel('dev.jucier/platform');
  const archiveOpen = MethodChannel('dev.jucier/archive_open');
  const window = MethodChannel('dev.jucier/window');
  try {
    if (!Platform.isLinux) throw StateError('此测试需要使用 Linux 启动程序运行');
    final status = await platform.invokeMapMethod<String, Object?>(
      'fileAccessStatus',
    );
    if (status?['requested'] != true || status?['granted'] != true) {
      throw StateError('Linux 文件访问通道检查失败');
    }
    if (await window.invokeMethod<bool>('prepareOperationWindow') != false ||
        await window.invokeMethod<bool>('finishOperationWindow') != false) {
      throw StateError('Linux 应复用主窗口，窗口行为检查失败');
    }
    await window.invokeMethod<void>('resizeOperationWindow', 300.0);

    const preferences = [
      (getter: 'themeMode', setter: 'setThemeMode', value: 'dark'),
      (
        getter: 'compressionPerformance',
        setter: 'setCompressionPerformance',
        value: 'resourceSaving',
      ),
      (
        getter: 'archiveOpenMode',
        setter: 'setArchiveOpenMode',
        value: 'extract',
      ),
      (
        getter: 'singleEntryExtractionMode',
        setter: 'setSingleEntryExtractionMode',
        value: 'selectedOnly',
      ),
      (
        getter: 'smartExtractionEnabled',
        setter: 'setSmartExtractionEnabled',
        value: false,
      ),
      (
        getter: 'archiveColumnPreferences',
        setter: 'setArchiveColumnPreferences',
        value: {
          'compression': ['name', 'size'],
          'extraction': ['name', 'modified'],
        },
      ),
    ];
    final phase = Platform.environment['JUCIER_SMOKE_PHASE'] ?? 'write';
    final phaseLabel = phase == 'read' ? '读取验证' : '写入验证';
    for (final preference in preferences) {
      if (phase != 'read') {
        await platform.invokeMethod<void>(preference.setter, preference.value);
      }
      final value = await platform.invokeMethod<Object?>(preference.getter);
      if (jsonEncode(value) != jsonEncode(preference.value)) {
        throw StateError('${preference.getter} 在$phaseLabel阶段检查失败：$value');
      }
      try {
        await platform.invokeMethod<void>(preference.setter, 123);
        throw StateError('${preference.getter} 错误地接受了无效设置值');
      } on PlatformException catch (error) {
        if (error.code != 'invalid_preference') rethrow;
      }
    }
    try {
      await platform.invokeMethod<void>('openFile', '');
      throw StateError('错误地接受了无效的预览路径');
    } on PlatformException catch (error) {
      if (error.code != 'invalid_path') rethrow;
    }

    final expected = Platform.environment['JUCIER_SMOKE_EXPECT_PATH'];
    final received = <String>[];
    final opened = Completer<void>();
    Future<void> drain() async {
      received.addAll(
        await archiveOpen.invokeListMethod<String>('takePendingOpenFiles') ??
            [],
      );
      if (received.isNotEmpty && !opened.isCompleted) opened.complete();
    }

    archiveOpen.setMethodCallHandler((call) async {
      if (call.method == 'archiveFilesAvailable') await drain();
    });
    await drain();
    if (expected != null) {
      debugPrint('Linux 平台冒烟测试：正在等待文件打开请求');
      await opened.future.timeout(const Duration(seconds: 20));
      if (received.length != 1 || received.single != expected) {
        throw StateError('文件打开请求不符合预期：收到 $received；预期为 $expected');
      }
    }
    if ((await archiveOpen.invokeListMethod<String>('takePendingOpenFiles'))
            ?.isEmpty !=
        true) {
      throw StateError('待处理的文件打开请求未被取完');
    }
    debugPrint('Linux 平台冒烟测试通过（$phaseLabel）');
    await archiveOpen.invokeMethod<void>('quitApplication');
  } catch (error, stack) {
    debugPrint('Linux 平台冒烟测试失败：$error\n$stack');
    exit(1);
  }
}
