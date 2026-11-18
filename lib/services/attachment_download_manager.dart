import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

enum AttachmentStatus {
  notStarted,
  pendingManual, // Requires user tap (> 10MB)
  downloading,
  completed,
  failed,
}

class AttachmentTask {
  final String attachmentId;
  final String messageId;
  final String remoteUrl; // Or peer connection download endpoint
  final String localPath;
  final int fileSizeInBytes;
  AttachmentStatus status;
  double progress; // 0.0 to 1.0

  AttachmentTask({
    required this.attachmentId,
    required this.messageId,
    required this.remoteUrl,
    required this.localPath,
    required this.fileSizeInBytes,
    this.status = AttachmentStatus.notStarted,
    this.progress = 0.0,
  });
}

class AttachmentDownloadManager {
  // Singleton pattern for global access
  static final AttachmentDownloadManager _instance =
      AttachmentDownloadManager._internal();
  factory AttachmentDownloadManager() => _instance;
  AttachmentDownloadManager._internal();

  // 10 MB Threshold for automatic downloads
  static const int autoDownloadThresholdBytes = 10 * 1024 * 1024;

  // Queues and Active Tasks Tracking
  final List<AttachmentTask> _queue = [];
  final Map<String, AttachmentTask> _tasks = {};
  bool _isProcessing = false;

  // StreamController to broadcast task state updates to Flutter UI
  final _statusController = StreamController<AttachmentTask>.broadcast();
  Stream<AttachmentTask> get statusStream => _statusController.stream;

  /// Entry point called when a database sync introduces new attachments
  void enqueue(AttachmentTask task) {
    _tasks[task.attachmentId] = task;

    // Policy Check: Auto-queue small files; flag large files for manual tap
    if (task.fileSizeInBytes <= autoDownloadThresholdBytes) {
      task.status = AttachmentStatus.notStarted;
      _queue.add(task);
      _statusController.add(task);
      _processQueue();
    } else {
      task.status = AttachmentStatus.pendingManual;
      _statusController.add(task);
    }
  }

  /// User explicitly tapped 'Download' on a large attachment card
  void forceDownload(String attachmentId) {
    final task = _tasks[attachmentId];
    if (task != null &&
        (task.status == AttachmentStatus.pendingManual ||
            task.status == AttachmentStatus.failed)) {
      task.status = AttachmentStatus.notStarted;
      _queue.add(task);
      _statusController.add(task);
      _processQueue();
    }
  }

  /// Processes queued tasks sequentially
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      await _downloadFile(task);
    }

    _isProcessing = false;
  }

  /// Handles the physical chunked download and state updates
  Future<void> _downloadFile(AttachmentTask task) async {
    task.status = AttachmentStatus.downloading;
    task.progress = 0.0;
    _statusController.add(task);

    // Enforce timeouts to handle peers disconnecting mid-transfer
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 10);

    IOSink? sink;
    int lastProgressUpdateMillis = 0;

    try {
      final request = await client.getUrl(Uri.parse(task.remoteUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'Peer responded with status ${response.statusCode}',
        );
      }

      final file = File(task.localPath);

      // Ensure parent directory exists before writing
      await file.parent.create(recursive: true);
      sink = file.openWrite();

      int bytesReceived = 0;
      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : task.fileSizeInBytes;

      await for (final chunk in response) {
        bytesReceived += chunk.length;
        sink.add(chunk);

        // Throttle UI updates to max once every 100ms to preserve 60 FPS
        final now = DateTime.now().millisecondsSinceEpoch;
        if (totalBytes > 0 && (now - lastProgressUpdateMillis > 100)) {
          lastProgressUpdateMillis = now;
          task.progress = bytesReceived / totalBytes;
          _statusController.add(task);
        }
      }

      // Ensure all bytes are flushed to disk before closing
      await sink.flush();
      await sink.close();
      sink = null; // Mark closed

      task.status = AttachmentStatus.completed;
      task.progress = 1.0;
      _statusController.add(task);
    } catch (e) {
      debugPrint(
        'Device-to-device transfer failed for ${task.attachmentId}: $e',
      );

      // Clean up partial file on failure to prevent corrupted media
      final partialFile = File(task.localPath);
      if (await partialFile.exists()) {
        await partialFile.delete().catchError((_) {});
      }

      task.status = AttachmentStatus.failed;
      _statusController.add(task);
    } finally {
      // Safely close sink if an error occurred before completion
      if (sink != null) {
        await sink.close().catchError((_) {});
      }
      client.close(force: true);
    }
  }

  void dispose() {
    _statusController.close();
  }
}
