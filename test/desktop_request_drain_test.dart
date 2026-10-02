import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jucier/platform/desktop_request_drain.dart';

void main() {
  test(
    'startup synchronization awaits an active native request handler',
    () async {
      final started = Completer<void>();
      final finished = Completer<void>();
      var reads = 0;
      final drain = DesktopRequestDrain<String>(
        hasHandler: () => true,
        readPending: () async => reads++ == 0 ? ['archive.zip'] : [],
        dispatch: (_) async {
          started.complete();
          await finished.future;
        },
      );
      final nativeEvent = drain.synchronize();
      await started.future;
      final startupCheck = drain.synchronize();
      var returned = false;
      unawaited(startupCheck.then((_) => returned = true));
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
      expect(identical(nativeEvent, startupCheck), isTrue);
      finished.complete();
      await startupCheck;
      expect(returned, isTrue);
    },
  );

  test('new notifications are drained serially before returning', () async {
    final pending = <String>['first'];
    final handled = <String>[];
    late DesktopRequestDrain<String> drain;
    drain = DesktopRequestDrain<String>(
      hasHandler: () => true,
      readPending: () async {
        final batch = pending.toList();
        pending.clear();
        return batch;
      },
      dispatch: (request) async {
        handled.add(request);
        if (request == 'first') {
          pending.add('second');
          unawaited(drain.synchronize());
        }
      },
    );
    await drain.synchronize();
    expect(handled, ['first', 'second']);
  });

  test('an unavailable channel does not block a later retry', () async {
    var unavailable = true;
    var reads = 0;
    final drain = DesktopRequestDrain<String>(
      hasHandler: () => true,
      readPending: () async {
        reads++;
        if (unavailable) throw MissingPluginException();
        return [];
      },
      dispatch: (_) async {},
    );
    await drain.synchronize();
    unavailable = false;
    await drain.synchronize();
    expect(reads, 2);
  });
}
