import 'dart:io';

/// Sends raw ESC/POS bytes to a network (WiFi/Ethernet) thermal printer
/// over a plain TCP socket — the "JetDirect"-style raw print protocol most
/// network thermal printers listen on, conventionally port 9100.
class NetworkPrinter {
  static Future<bool> printRawBytes({
    required String ipAddress,
    required List<int> bytes,
    int port = 9100,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ipAddress, port, timeout: timeout);
      socket.add(bytes);
      await socket.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      await socket?.close();
    }
  }
}
