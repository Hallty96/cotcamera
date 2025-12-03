// lib/backend.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;

const _base = 'http://10.0.2.2:5001/cotcamera-prod/australia-southeast1';

// Matches your index.ts: app.post('/createSubmissionSession', …)
Uri _sessionUri() => Uri.parse('$_base/api/createSubmissionSession');

class CreateSessionResponse {
  final String uploadUrl;
  final String? submissionId; // optional if you added it
  CreateSessionResponse({required this.uploadUrl, this.submissionId});
  factory CreateSessionResponse.fromJson(Map<String, dynamic> j) => 
      CreateSessionResponse(
        uploadUrl: j['uploadUrl'],
        submissionId: j['submissionId'],
      );
}

class Backend {
  static Future<CreateSessionResponse> createSubmissionSession({
    required String contentType,
    required int sizeBytes,
    required String imageSha256,
    double? lat,
    double? lng,
    String? takenAtIso,
    String? idToken, // <-- OPTIONAL now
  }) async {
    final r = await http.post(
      _sessionUri(),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'contentType': contentType,
        'sizeBytes': sizeBytes,
        'imageSha256': imageSha256,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (takenAtIso != null) 'takenAt': takenAtIso,
      }),
    ).timeout(const Duration(seconds: 12));

    if (r.statusCode != 200) {
      debugPrint('[backend] createSubmissionSession -> ${r.statusCode}  ${r.body}');
      throw Exception('createSubmissionSession ${r.statusCode}: ${r.body}');
    }
    return CreateSessionResponse.fromJson(jsonDecode(r.body));
  }
}
