import 'dart:async';
import 'dart:isolate';

/// Pool of isolates for parallel processing
class IsolatePool {
  final int maxConcurrent;
  final List<_IsolateWorker> _workers = [];
  final List<_WorkItem> _workQueue = [];
  bool _started = false;

  /// Creates an isolate pool
  ///
  /// [maxConcurrent]: Maximum number of concurrent isolates
  IsolatePool(this.maxConcurrent);

  /// Start the isolate pool
  Future<void> start() async {
    if (_started) return;

    // Create worker isolates
    for (int i = 0; i < maxConcurrent; i++) {
      final worker = _IsolateWorker();
      await worker.spawn();
      _workers.add(worker);
    }

    _started = true;
  }

  /// Run a function in an isolate
  Future<T> run<T>(FutureOr<T> Function() function) async {
    if (!_started) {
      throw StateError('Isolate pool not started');
    }

    // Create completer for this work item
    final completer = Completer<T>();

    // Find available worker or queue
    final availableWorker = _workers.firstWhere(
          (worker) => !worker.busy,
      orElse: () => _workers.first,
    );

    if (!availableWorker.busy) {
      // Worker available, use it directly
      availableWorker.busy = true;

      try {
        final result = await availableWorker.execute(function);
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        availableWorker.busy = false;
        _processQueue();
      }
    } else {
      // All workers busy, queue the work
      _workQueue.add(_WorkItem(function, completer));
    }

    return completer.future;
  }

  /// Process the work queue
  void _processQueue() {
    if (_workQueue.isEmpty) return;

    // Find available worker
    final availableWorkers = _workers.where((worker) => !worker.busy);
    if (availableWorkers.isNotEmpty) {
      final availableWorker = availableWorkers.first;
      final workItem = _workQueue.removeAt(0);
      availableWorker.busy = true;

      availableWorker.execute(workItem.function).then((result) {
        workItem.completer.complete(result);
      }).catchError((e, st) {
        workItem.completer.completeError(e, st);
      }).whenComplete(() {
        availableWorker.busy = false;
        _processQueue();
      });
    }
  }

  /// Stop the isolate pool
  Future<void> stop() async {
    if (!_started) return;

    // Terminate all workers
    for (final worker in _workers) {
      await worker.terminate();
    }

    _workers.clear();

    // Fail any pending work
    for (final workItem in _workQueue) {
      workItem.completer.completeError(
          StateError('Isolate pool stopped before work could be processed')
      );
    }

    _workQueue.clear();
    _started = false;
  }
}

/// Worker isolate wrapper
class _IsolateWorker {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();
  final Map<int, Completer> _completers = {};
  int _nextId = 0;
  bool busy = false;

  /// Spawn a new worker isolate
  Future<void> spawn() async {
    if (_isolate != null) return;

    final completer = Completer<SendPort>();

    // Listen for messages from worker
    _receivePort.listen((message) {
      if (message is SendPort) {
        // Initial port message
        completer.complete(message);
      } else if (message is Map) {
        // Result message
        final id = message['id'] as int;
        final error = message['error'];

        if (_completers.containsKey(id)) {
          final completer = _completers.remove(id)!;

          if (error != null) {
            completer.completeError(error);
          } else {
            completer.complete(message['result']);
          }
        }
      }
    });

    // Spawn the isolate
    _isolate = await Isolate.spawn(
      _isolateMain,
      _receivePort.sendPort,
    );

    // Wait for send port
    _sendPort = await completer.future;
  }

  /// Execute a function in the isolate
  Future<dynamic> execute(Function function) async {
    if (_sendPort == null) {
      throw StateError('Worker not spawned');
    }

    final id = _nextId++;
    final completer = Completer();
    _completers[id] = completer;

    // Send function to isolate
    _sendPort!.send({
      'id': id,
      'function': function,
    });

    return completer.future;
  }

  /// Terminate the isolate
  Future<void> terminate() async {
    _isolate?.kill();
    _isolate = null;
    _receivePort.close();

    // Fail any pending completers
    for (final completer in _completers.values) {
      completer.completeError(
          StateError('Worker terminated before operation completed')
      );
    }

    _completers.clear();
  }

  /// Main isolate entry point
  static void _isolateMain(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is Map) {
        final id = message['id'] as int;
        final function = message['function'] as Function;

        try {
          final result = function();

          // Handle futures
          if (result is Future) {
            result.then((value) {
              sendPort.send({
                'id': id,
                'result': value,
              });
            }).catchError((error) {
              sendPort.send({
                'id': id,
                'error': error.toString(),
              });
            });
          } else {
            sendPort.send({
              'id': id,
              'result': result,
            });
          }
        } catch (e) {
          sendPort.send({
            'id': id,
            'error': e.toString(),
          });
        }
      }
    });
  }
}

/// Work item for queue
class _WorkItem {
  final Function function;
  final Completer completer;

  _WorkItem(this.function, this.completer);
}