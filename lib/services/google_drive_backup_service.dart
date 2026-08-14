import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';
import 'backup_service.dart';

/// Uploads a database backup to the signed-in user's Google Drive, in a
/// "SuperMart POS Backups" folder (created on first use).
///
/// SETUP REQUIRED before this works: create an OAuth 2.0 Client ID of type
/// "Desktop app" in Google Cloud Console (APIs & Services > Credentials),
/// enable the Google Drive API for that project, and paste the client ID
/// (and secret, if one was issued) into [_clientId]/[_clientSecret] below.
/// Without that, [backupToGoogleDrive] throws immediately rather than
/// silently doing nothing.
class GoogleDriveBackupService {
  static const String _clientId = 'YOUR_GOOGLE_OAUTH_CLIENT_ID.apps.googleusercontent.com';
  static const String _clientSecret = 'YOUR_GOOGLE_OAUTH_CLIENT_SECRET';
  static const String _backupFolderName = 'SuperMart POS Backups';

  bool get isConfigured => !_clientId.startsWith('YOUR_');

  /// Runs the OAuth "installed app" consent flow (opens the system browser,
  /// listens on a local loopback port for the redirect) and uploads a fresh
  /// backup once signed in. Returns the uploaded file's Drive web link.
  Future<String> backupToGoogleDrive() async {
    if (!isConfigured) {
      throw Exception(
        'Google Drive backup is not set up yet — add your OAuth client ID/secret '
        'in google_drive_backup_service.dart (see the setup note at the top of that file).',
      );
    }

    final client = await clientViaUserConsent(
      ClientId(_clientId, _clientSecret),
      [drive.DriveApi.driveFileScope],
      (url) async {
        final uri = Uri.parse(url);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw Exception('Could not open the browser for Google sign-in. Visit this URL manually: $url');
        }
      },
    );

    try {
      final api = drive.DriveApi(client);
      final folderId = await _findOrCreateBackupFolder(api);

      final backupFile = await BackupService().createBackupFile();
      final driveFile = drive.File()
        ..name = basename(backupFile.path)
        ..parents = [folderId];

      final uploaded = await api.files.create(
        driveFile,
        uploadMedia: drive.Media(backupFile.openRead(), await backupFile.length()),
        $fields: 'id,webViewLink',
      );

      return uploaded.webViewLink ?? 'Uploaded (file id: ${uploaded.id})';
    } finally {
      client.close();
    }
  }

  Future<String> _findOrCreateBackupFolder(drive.DriveApi api) async {
    final existing = await api.files.list(
      q: "name = '$_backupFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      $fields: 'files(id,name)',
    );
    if (existing.files != null && existing.files!.isNotEmpty) {
      return existing.files!.first.id!;
    }

    final folder = drive.File()
      ..name = _backupFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await api.files.create(folder, $fields: 'id');
    return created.id!;
  }
}
