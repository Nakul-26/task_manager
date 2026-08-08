import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wraps [action] so that calls arriving in the same microtask burst
/// collapse into a single deferred invocation.
///
/// Hive emits one box-change event per key, so a bulk write of N keys
/// (e.g. persisting a reorder) fires N separate listener invocations in
/// every screen currently listening on that box — including screens kept
/// alive underneath the current route by [Navigator.push]. Without this,
/// each of those N events can trigger a full, expensive reload/setState in
/// every listening screen, all draining back-to-back before the next frame
/// renders, which is what makes a bulk write feel like a hang.
///
/// Store the returned callback in a field and reuse that exact instance for
/// both `addListener` and `removeListener` — each call to this function
/// creates a new, distinct closure.
VoidCallback debounceMicrotask(VoidCallback action) {
  var scheduled = false;
  return () {
    if (scheduled) {
      return;
    }
    scheduled = true;
    scheduleMicrotask(() {
      scheduled = false;
      action();
    });
  };
}
