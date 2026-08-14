import 'dart:io';
import 'package:oauth2/oauth2.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';

/// Uploads a database backup to the signed-in user's OneDrive, in a
/// "SuperMart POS Backups" folder under their drive root.
///
/// SETUP REQUIRED before this works: register an app in the Azure Portal
/// (Azure Active Directory > App registrations > New registration), choose
/// "Accounts in any organizational directory and personal Microsoft
/// accounts", add a redirect URI of platform type "Mobile and desktop
/// applications" pointing at http://localhost:8765/callback (matching
/// [_redirectPort] below), and add the Microsoft Graph delegated permission
/// `Files.ReadWrite`. No client secret is needed — this uses the public
/// client / PKCE flow. Paste the Application (client) ID into [_clientId].
class OneDriveBackupService {
  static const String _clientId = 'YOUR_AZURE_APP_CLIENT_ID';
  static const int _redirectPort = 8765;
  static const String _backupFolderName = 'SuperMart POS Backups';

  static final Uri _authorizationEndpoint =
      Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
  static final Uri _tokenEndpoint = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/token');
  static const List<String> _scopes = ['Files.ReadWrite', 'offline_access'];

  bool get isConfigured => !_clientId.startsWith('YOUR_');

  /// Runs the OAuth "public client" consent flow (opens the system browser,
  /// listens on a local loopback port for the redirect) and uploads a fresh
  /// backup once signed in.
  Future<String> backupToOneDrive() async {
    if (!isConfigured) {
      throw Exception(
        'OneDrive backup is not set up yet — add your Azure app client ID '
        'in onedrive_backup_service.dart (see the setup note at the top of that file).',
      );
    }

    final redirectUri = Uri.parse('http://localhost:$_redirectPort/callback');
    final grant = AuthorizationCodeGrant(
      _clientId,
      _authorizationEndpoint,
      _tokenEndpoint,
    );
    final authorizationUrl = grant.getAuthorizationUrl(redirectUri, scopes: _scopes);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);
    Client client;
    try {
      if (!await launchUrl(authorizationUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not open the browser for Microsoft sign-in. Visit this URL manually: $authorizationUrl');
      }

      final request = await server.first;
      final responseParams = request.uri.queryParameters;
      request.response
        ..statusCode = 200
        ..headers.set('content-type', 'text/html')
        ..write('<html><body>Signed in — you can close this tab and return to SuperMart POS.</body></html>');
      await request.response.close();

      client = await grant.handleAuthorizationResponse(responseParams);
    } finally {
      await server.close();
    }

    try {
      final backupFile = await BackupService().createBackupFile();
      final folderName = Uri.encodeComponent(_backupFolderName);
      final fileName = Uri.encodeComponent(basename(backupFile.path));
      final uploadUri = Uri.parse(
        'https://graph.microsoft.com/v1.0/me/drive/root:/$folderName/$fileName:/content',
      );

      final response = await client.put(
        uploadUri,
        headers: {'Content-Type': 'application/octet-stream'},
        body: await backupFile.readAsBytes(),
      );
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('OneDrive upload failed (HTTP ${response.statusCode}): ${response.body}');
      }
      return 'Uploaded to OneDrive: $_backupFolderName/${basename(backupFile.path)}';
    } finally {
      client.close();
    }
  }
}
