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
  final configurations = <bool>[];

  @override
  Future<bool> prepareOperation() async {
    prepareCalls++;
    return compact;
  }

  @override
  Future<void> showPreparedWindow() async => operationShows++;

  @override
  Future<void> configureOperationWindow(bool configuration) async {
    configurations.add(configuration);
  }

  @override
  Future<void> showMainWindow({bool explicit = true}) async => mainShows++;

  @override
  Future<bool> finishOperation() async {
    finishCalls++;
    return quitAfterOperation;
  }
}
