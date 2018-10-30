// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui show window, PointerDataPacket;

import 'package:flutter/foundation.dart';

import 'arena.dart';
import 'converter.dart';
import 'debug.dart';
import 'events.dart';
import 'hit_test.dart';
import 'pointer_router.dart';

/// A binding for the gesture subsystem.
abstract class GestureBinding extends BindingBase with HitTestable, HitTestDispatcher, HitTestTarget {
  // This class is intended to be used as a mixin, and should not be
  // extended directly.
  factory GestureBinding._() => null;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    ui.window.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  /// The singleton instance of this object.
  static GestureBinding get instance => _instance;
  static GestureBinding _instance;

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  void _handlePointerDataPacket(ui.PointerDataPacket packet) {
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    _pendingPointerEvents.addAll(PointerEventConverter.expand(packet.data, ui.window.devicePixelRatio));
    if (!locked)
      _flushPointerEventQueue();
  }

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatch before the next pointer event and
  /// before the end of the microtask but not within this function call.
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked)
      scheduleMicrotask(_flushPointerEventQueue);
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);
    while (_pendingPointerEvents.isNotEmpty)
      _handlePointerEvent(_pendingPointerEvents.removeFirst());
  }

  /// A router that routes all pointer events received from the engine.
  final PointerRouter pointerRouter = PointerRouter();

  /// The gesture arenas used for disambiguating the meaning of sequences of
  /// pointer events.
  final GestureArenaManager gestureArena = GestureArenaManager();

  /// State for all pointers which are currently down.
  ///
  /// The state of hovering pointers is not tracked because that would require
  /// hit-testing on every frame.
  final Map<int, HitTestResult> _hitTests = <int, HitTestResult>{};

  void _handlePointerEvent(PointerEvent event) {
    assert(!locked);
    HitTestResult result;
    if (event is PointerDownEvent) {
      assert(!_hitTests.containsKey(event.pointer));
      result = HitTestResult();
      hitTest(result, event.position);
      _hitTests[event.pointer] = result;
      assert(() {
        if (debugPrintHitTestResults)
          debugPrint('$event: $result');
        return true;
      }());
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      result = _hitTests.remove(event.pointer);
    } else if (event.down) {
      result = _hitTests[event.pointer];
    } else {
      return; // We currently ignore add, remove, and hover move events.
    }
    if (result != null)
      dispatchEvent(event, result);
  }

  /// Determine which [HitTestTarget] objects are located at a given position.
  @override // from HitTestable
  void hitTest(HitTestResult result, Offset position) {
    result.add(HitTestEntry(this));
  }

  /// Dispatch an event to a hit test result's path.
  ///
  /// This sends the given event to every [HitTestTarget] in the entries
  /// of the given [HitTestResult], and catches exceptions that any of
  /// the handlers might throw. The `result` argument must not be null.
  @override // from HitTestDispatcher
  void dispatchEvent(PointerEvent event, HitTestResult result) {
    assert(!locked);
    assert(result != null);
    for (HitTestEntry entry in result.path) {
      try {
        entry.target.handleEvent(event, entry);
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetailsForPointerEventDispatcher(
          exception: exception,
          stack: stack,
          library: 'gesture library',
          context: 'while dispatching a pointer event',
          event: event,
          hitTestEntry: entry,
          informationCollector: (StringBuffer information) {
            information.writeln('Event:');
            information.writeln('  $event');
            information.writeln('Target:');
            information.write('  ${entry.target}');
          }
        ));
      }
    }
  }

  @override // from HitTestTarget
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    pointerRouter.route(event);
    if (event is PointerDownEvent) {
      gestureArena.close(event.pointer);
    } else if (event is PointerUpEvent) {
      gestureArena.sweep(event.pointer);
    }
  }
}

/// Variant of [FlutterErrorDetails] with extra fields for the gesture
/// library's binding's pointer event dispatcher ([GestureBinding.dispatchEvent]).
///
/// See also [FlutterErrorDetailsForPointerRouter], which is also used by the
/// gesture library.
class FlutterErrorDetailsForPointerEventDispatcher extends FlutterErrorDetails {
  /// Creates a [FlutterErrorDetailsForPointerEventDispatcher] object with the given
  /// arguments setting the object's properties.
  ///
  /// The gesture library calls this constructor when catching an exception
  /// that will subsequently be reported using [FlutterError.onError].
  const FlutterErrorDetailsForPointerEventDispatcher({
    dynamic exception,
    StackTrace stack,
    String library,
    String context,
    this.event,
    this.hitTestEntry,
    InformationCollector informationCollector,
    bool silent = false
  }) : super(
    exception: exception,
    stack: stack,
    library: library,
    context: context,
    informationCollector: informationCollector,
    silent: silent
  );

  /// The pointer event that was being routed when the exception was raised.
  final PointerEvent event;

  /// The hit test result entry for the object whose handleEvent method threw
  /// the exception.
  ///
  /// The target object itself is given by the [HitTestEntry.target] property of
  /// the hitTestEntry object.
  final HitTestEntry hitTestEntry;
}
