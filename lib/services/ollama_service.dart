import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin client for a local Ollama server (https://ollama.com) — used to turn
/// the AI Analysis report's raw numbers into a plain-English summary.
///
/// Every method here fails soft: no running server, wrong port, model not
/// pulled, timeout — all of it comes back as null/false instead of an
/// exception, because the AI narrative is an optional enhancement on top of
/// reports that must keep working with Ollama absent entirely.
class OllamaService {
  Future<String?> generate({
    required String prompt,
    required String baseUrl,
    required String model,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/generate');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model': model, 'prompt': prompt, 'stream': false}),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = decoded['response'] as String?;
      return (text == null || text.trim().isEmpty) ? null : text.trim();
    } catch (_) {
      return null;
    }
  }

  /// Reachability + model check for Settings' "Test Connection" button —
  /// separate from [generate] since it shouldn't wait on a full model run.
  Future<bool> isReachable(String baseUrl, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/tags');
      final response = await http.get(uri).timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
