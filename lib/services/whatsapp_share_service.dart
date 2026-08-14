import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/quantity_utils.dart';

class WhatsAppShareService {
  static Future<void> shareInvoice({
    required int invoiceNo,
    String? invoiceLabel,
    required String customerName,
    required double total,
    required List<InvoiceLine> items,
    required DateTime date,
    double? cashReceived,
    double? changeDue,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('🧾 SUPERMART POS');
    buffer.writeln('Invoice ${invoiceLabel ?? '#$invoiceNo'}');
    buffer.writeln('Date: ${date.toLocal().toString().split(' ')[0]}');
    buffer.writeln('Customer: $customerName');
    buffer.writeln('---');
    for (final item in items) {
      buffer.writeln(
        '${item.name} x${formatQty(item.qty)} @ ₹${item.price.toStringAsFixed(2)} = ₹${item.total.toStringAsFixed(2)}',
      );
    }
    buffer.writeln('---');
    buffer.writeln('Total: ₹${total.toStringAsFixed(2)}');
    if (cashReceived != null && cashReceived > 0) {
      buffer.writeln('Cash Received: ₹${cashReceived.toStringAsFixed(2)}');
    }
    if (changeDue != null && changeDue > 0) {
      buffer.writeln('Change Returned: ₹${changeDue.toStringAsFixed(2)}');
    }
    buffer.writeln('Thank you! Visit again!');

    final message = buffer.toString();
    final encoded = Uri.encodeComponent(message);
    final waUri = Uri.parse('https://wa.me/?text=$encoded');

    // Fixed: url_launcher 6.x removed the old String-based canLaunch/launch
    // in favor of the Uri-based canLaunchUrl/launchUrl used here — the
    // previous code called the removed API and would not compile against
    // the url_launcher version declared in pubspec.yaml.
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else {
      // Fixed: migrated from the discontinued `share` package (no updates
      // or security patches since 2021) to its actively maintained
      // successor, `share_plus`.
      await SharePlus.instance.share(ShareParams(text: message));
    }
  }

  /// Opens WhatsApp with a prefilled "come back" message addressed to a
  /// specific customer's number (unlike [shareInvoice], which shares to
  /// whichever chat the user picks). Only opens the compose screen — the
  /// user still has to press send inside WhatsApp themselves.
  static Future<void> sendReminder({
    required String customerName,
    required String phone,
    required List<String> topProducts,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Hi $customerName! 👋');
    buffer.writeln("We've missed you at SuperMart POS.");
    if (topProducts.isNotEmpty) {
      buffer.writeln('Your usual favorites are back in stock: ${topProducts.join(', ')}.');
    }
    buffer.writeln('Come visit us again soon!');

    final message = buffer.toString();
    final encoded = Uri.encodeComponent(message);

    // Indian numbers are stored without a country code in this app; wa.me
    // requires one, so digits-only + a 91 prefix (unless already present).
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final withCountryCode = digits.startsWith('91') ? digits : '91$digits';

    final waUri = Uri.parse('https://wa.me/$withCountryCode?text=$encoded');
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else {
      await SharePlus.instance.share(ShareParams(text: message));
    }
  }

  /// Opens WhatsApp pre-filled with an already-composed message, addressed
  /// to a specific customer's number — same digits+91-prefix and launch/
  /// share-sheet-fallback logic as [sendReminder], generalized to take the
  /// message instead of building a fixed "come back" text. Used by the
  /// Campaigns screen so offer/dues/birthday templates share one code path.
  static Future<void> sendCampaignMessage({
    required String phone,
    required String message,
  }) async {
    final encoded = Uri.encodeComponent(message);
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final withCountryCode = digits.startsWith('91') ? digits : '91$digits';

    final waUri = Uri.parse('https://wa.me/$withCountryCode?text=$encoded');
    if (await canLaunchUrl(waUri)) {
      await launchUrl(waUri, mode: LaunchMode.externalApplication);
    } else {
      await SharePlus.instance.share(ShareParams(text: message));
    }
  }
}

class InvoiceLine {
  final String name;
  final double qty;
  final double price;
  final double total;

  InvoiceLine({required this.name, required this.qty, required this.price, required this.total});
}