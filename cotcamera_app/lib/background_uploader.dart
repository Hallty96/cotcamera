import 'dart:io';
import 'package:flutter/widgets.dart';            // for debugPrint + binding
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'backend.dart';
import 'queue_store.dart';

const taskName = 'uploadSubmission';

bool _uploaderRegistered = false;

Future<void> ensureUploaderRegistered() async {
  if (_uploaderRegistered) return;
  _uploaderRegistered = true;

  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  await Workmanager().registerOneOffTask(
    taskName,                 // e.g. 'uploadSubmission'
    taskName,
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    tag: taskName,
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // Init for background isolate
    WidgetsFlutterBinding.ensureInitialized();
    await QueueStore.init();

    final items = QueueStore.all();
    debugPrint('[worker] starting, queue size = ${items.length}');

    for (final entry in items) {
      final key = entry.key;
      final job = entry.value;

      try {
        debugPrint('[worker] -> job key=$key sha=${job.sha256.substring(0, 8)} '
            'size=${job.sizeBytes} file=${job.localFilePath}');

        // 1) Get signed URL (fail fast)
        final session = await Backend.createSubmissionSession(
          contentType: 'image/jpeg',
          sizeBytes: job.sizeBytes,
          imageSha256: job.sha256,
        ).timeout(const Duration(seconds: 12));
        debugPrint('[worker]    got uploadUrl (len=${session.uploadUrl.length})');

        // 2) Read bytes
        final fileBytes = await File(job.localFilePath).readAsBytes();

        // 3) PUT upload (fail fast)
        final headers = {
          'Content-Type': 'image/jpeg',
          'x-goog-meta-image_sha256': job.sha256,
          // if (job.lat != null) 'x-goog-meta-lat': job.lat.toString(),
          // if (job.lng != null) 'x-goog-meta-lng': job.lng.toString(),
          // 'x-goog-meta-takenAt': job.takenAt.toUtc().toIso8601String(),
        };

        final putResp = await http.put(
          Uri.parse(session.uploadUrl),
          headers: {
            'Content-Type': 'image/jpeg',
            'x-goog-meta-image_sha256': job.sha256, // 64-char lowercase hex
          },
          body: fileBytes,
        ).timeout(const Duration(seconds: 20));
        debugPrint('[worker]    PUT status ${putResp.statusCode}');

        if (putResp.statusCode >= 400) {
          debugPrint('[worker]    body: ${putResp.body}');
          throw Exception('PUT failed ${putResp.statusCode}');
        }

        // 4) Success → remove from queue
        await QueueStore.delete(key);
        debugPrint('[worker]    done, removed from queue: $key');
        // (Day 4 would enqueue completeSubmission here)

      } catch (e, st) {
        debugPrint('[worker]    error: $e');
        debugPrint('[worker]    stack: $st');

        // Requeue with backoff, give up after 6 tries
        final nextRetries = job.retries + 1;
        if (nextRetries >= 6) {
          await QueueStore.delete(key); // drop (or move to dead-letter)
          debugPrint('[worker]    giving up after $nextRetries tries; deleted $key');
        } else {
          await QueueStore.put(key, job.copyWith(retries: nextRetries));
          debugPrint('[worker]    will retry later (retries=$nextRetries) for $key');
        }
      }
    }

    debugPrint('[worker] finished run');
    return Future.value(true);
  });
}
