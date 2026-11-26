import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReleaseInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;

  ReleaseInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
  });
}

class UpdateService {
  static const String _repoOwner = 'Ahmad142300';
  static const String _repoName = 'chatlog';

  static Map<String, String> get _headers => {
    'Accept': 'application/vnd.github+json',
  };

  /// Checks GitHub Releases for a newer version than currently installed
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "1.0.0"

      final uri = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final String tagName = (data['tag_name'] as String).replaceFirst('v', '');

      if (!_isNewerVersion(currentVersion, tagName)) return null;

      // Pick the matching asset for the current OS
      final List<dynamic> assets = data['assets'] ?? [];
      final String targetExtension = Platform.isAndroid ? '.apk' : '.tar.gz';

      final asset = assets.firstWhere(
        (a) => (a['name'] as String).endsWith(targetExtension),
        orElse: () => null,
      );

      if (asset == null) return null;

      return ReleaseInfo(
        version: tagName,
        downloadUrl: asset['browser_download_url'],
        releaseNotes: data['body'] ?? '',
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Downloads the release artifact and triggers installation
  static Future<void> downloadAndInstall(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = Platform.isAndroid
        ? 'update_${release.version}.apk'
        : 'update_${release.version}.tar.gz';
    final filePath = p.join(tempDir.path, fileName);

    final request = http.Request('GET', Uri.parse(release.downloadUrl));
    request.headers.addAll(_headers);
    final streamedResponse = await request.send();

    final totalBytes = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;

    final file = File(filePath);
    final sink = file.openWrite();

    await for (final chunk in streamedResponse.stream) {
      receivedBytes += chunk.length;
      sink.add(chunk);
      if (totalBytes > 0 && onProgress != null) {
        onProgress(receivedBytes / totalBytes);
      }
    }

    await sink.flush();
    await sink.close();

    if (Platform.isAndroid) {
      // Launches native Android package installer UI over the running app
      await OpenFilex.open(filePath);
    } else if (Platform.isLinux) {
      // Replace running Linux executable directory and restart
      await _installLinuxTarball(filePath);
    }
  }

  /// Extracts tarball over the current executable folder and restarts process
  static Future<void> _installLinuxTarball(String tarPath) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // Extract updated bundle files into the installation directory
    final result = await Process.run('tar', ['-xzf', tarPath, '-C', exeDir]);
    if (result.exitCode != 0) {
      throw Exception('Failed to extract update: ${result.stderr}');
    }

    // Relaunch the updated binary and exit the old process
    await Process.start(
      Platform.resolvedExecutable,
      [],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  /// Compares SemVer strings (e.g., "1.0.0" vs "1.1.0")
  static bool _isNewerVersion(String current, String latest) {
    final currParts = current.split('.').map(int.parse).toList();
    final latParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < latParts.length ? latParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
