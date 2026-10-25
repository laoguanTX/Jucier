import 'package:jucier/platform/desktop_window_service.dart';

class FakeDesktopWindowService implements DesktopWindowService {
  FakeDesktopWindowService({
    this.compact = true,
    this.quitAfterOperation = true,
  });

  final bool compact;
  final bool quitAfterOperation;
  int prepareCalls = 0;
  int operationShows = 0;
  int mainShows = 0;
  int finishCalls = 0;
  final operationHeights = <double>[];

  @override
  Future<bool> prepareOperation() async {
    prepareCalls++;
    return compact;
  }

  @override
  Future<void> showPreparedWindow() async => operationShows++;

  @override
  Future<void> resizeOperationWindow(double height) async {
    operationHeights.add(height);
  }

  @override
  Future<void> showMainWindow({bool explicit = true}) async => mainShows++;

  @override
  Future<bool> finishOperation() async {
    finishCalls++;
    return quitAfterOperation;
  }
}
