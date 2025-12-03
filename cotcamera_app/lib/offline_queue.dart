import 'dart:convert';

class UploadJob {
  final String localFilePath;
  final String sha256;
  final int sizeBytes;
  final DateTime takenAt;
  final double? lat;
  final double? lng;
  final int retries;

  UploadJob({
    required this.localFilePath,
    required this.sha256,
    required this.sizeBytes,
    required this.takenAt,
    this.lat,
    this.lng,
    this.retries = 0,
  });

  UploadJob copyWith({int? retries}) => UploadJob(
    localFilePath: localFilePath,
    sha256: sha256,
    sizeBytes: sizeBytes,
    takenAt: takenAt,
    lat: lat,
    lng: lng,
    retries: retries ?? this.retries,
  );

  Map<String, dynamic> toMap() => {
    'localFilePath': localFilePath,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'takenAt': takenAt.toIso8601String(),
    'lat': lat,
    'lng': lng,
    'retries': retries,
  };

  factory UploadJob.fromMap(Map<String, dynamic> m) => UploadJob(
    localFilePath: m['localFilePath'],
    sha256: m['sha256'],
    sizeBytes: m['sizeBytes'],
    takenAt: DateTime.parse(m['takenAt']),
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    retries: m['retries'] ?? 0,
  );

  String toJson() => jsonEncode(toMap());
  factory UploadJob.fromJson(String s) => UploadJob.fromMap(jsonDecode(s));
}
