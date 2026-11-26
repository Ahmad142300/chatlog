import 'package:flutter/material.dart';
import 'update_service.dart';

class UpdateUI {
  /// Triggers a manual update check with SnackBar feedback and progress dialog
  static Future<void> checkWithFeedback(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking for updates...'),
        duration: Duration(seconds: 1),
      ),
    );

    final release = await UpdateService.checkForUpdate();
    if (!context.mounted) return;

    if (release == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are on the latest version.')),
      );
      return;
    }

    _showUpdateDialog(context, release);
  }

  static void _showUpdateDialog(BuildContext context, ReleaseInfo release) {
    double progress = 0.0;
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.grey.shade900,
              title: Text(
                'Update Available (v${release.version})',
                style: const TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (release.releaseNotes.isNotEmpty)
                    Text(
                      release.releaseNotes,
                      style: TextStyle(color: Colors.grey.shade300),
                    ),
                  if (isDownloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text(
                      'Downloading: ${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (!isDownloading)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Later'),
                  ),
                if (!isDownloading)
                  ElevatedButton(
                    onPressed: () async {
                      setDialogState(() => isDownloading = true);
                      try {
                        await UpdateService.downloadAndInstall(
                          release,
                          onProgress: (p) {
                            setDialogState(() => progress = p);
                          },
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (e) {
                        setDialogState(() => isDownloading = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Update failed: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Update Now'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
