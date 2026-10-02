import 'dart:async';

import 'package:flutter/services.dart';

/// Shares native request draining between file opens and contextual actions.
/// Concurrent startup checks must await the active handler, not reveal Home
/// while a native event is already selecting its quick-action window.
class DesktopRequestDrain<T> {
  DesktopRequestDrain({
    required this.readPending,
    required this.hasHandler,
    required this.dispatch,
  });

  final Future<List<T>?> Function() readPending;
  final bool Function() hasHandler;
  final Future<void> Function(T) dispatch;
  Future<void>? _active;
  bool _requested = false;

  Future<void> synchronize() {
    _requested = true;
    if (_active case final active?) return active;
    if (!hasHandler()) return Future.value();
    final completion = Completer<void>();
    _active = completion.future;
    unawaited(() async {
      try {
        do {
          _requested = false;
          try {
            while (hasHandler()) {
              final requests = await readPending();
              if (requests == null || requests.isEmpty) break;
              for (final request in requests) {
                if (!hasHandler()) break;
                await dispatch(request);
              }
            }
          } on MissingPluginException {
            // Runners without this channel have no native requests.
          } on PlatformException {
            // A later native event can retry the pending requests.
          }
        } while (_requested && hasHandler());
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _active = null;
      }
    }());
    return completion.future;
  }
}
