import 'package:hive_flutter/hive_flutter.dart';
import 'offline_queue.dart';

class QueueStore {
  static const boxName = 'uploadQueue';

  static Future init() async {
    await Hive.initFlutter();
    await Hive.openBox<String>(boxName);
  }

  static Box<String> get _box => Hive.box<String>(boxName);

  static Future add(UploadJob job) async {
    await _box.add(job.toJson());
  }

  static List<MapEntry<dynamic, UploadJob>> all() {
    return _box.toMap().entries
      .map((e) => MapEntry(e.key, UploadJob.fromJson(e.value)))
      .toList();
  }

  static Future put(dynamic key, UploadJob job) => _box.put(key, job.toJson());
  static Future delete(dynamic key) => _box.delete(key);
  static bool isEmpty() => _box.isEmpty;
}
