// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../services/device_registration.dart';
import '../services/models.dart';
import '../services/device_identity.dart';
import 'login.dart';

class ChatLogPage extends StatefulWidget {
  const ChatLogPage({super.key, required this.db});

  final Database db;

  @override
  State<ChatLogPage> createState() => _ChatLogPageState();
}

class _ChatLogPageState extends State<ChatLogPage> {
  final TextEditingController _textController = TextEditingController();
  // final ImagePicker _picker = ImagePicker();
  List<File> _selectedFiles = [];

  ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMessages(limit: 30, offset: 0); // Load the latest 30 messages on init
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final pixels = _scrollController.position.pixels;
    const threshold = 300.0;

    if (pixels <= threshold && !_isLoadingMore && _hasMore) {
      print("printing more!!!");
      _loadMessages(limit: 30, offset: _messages.length);
    }
  }

  Future<void> _loadMessages({int limit = 30, int offset = 0}) async {
    _isLoadingMore = true;

    final List<Map<String, dynamic>> rawMessages = await widget.db.rawQuery(
      '''
    SELECT 
      m.*, 
      d.device_name 
    FROM messages m
    LEFT JOIN devices d ON m.sender_device_id = d.device_id
    ORDER BY m.timestamp DESC
    LIMIT ? OFFSET ?
    ''',
      [limit, offset],
    );

    // Convert immutable QueryRow items into mutable Maps
    final List<Map<String, dynamic>> mutableMessages = [];

    for (final msg in rawMessages) {
      // 1. Create a mutable copy of the row
      final Map<String, dynamic> mutableMsg = Map<String, dynamic>.from(msg);

      // 2. Fetch attachments for this message
      final List<Map<String, dynamic>> attachments = await widget.db.query(
        'attachments',
        where: 'message_id = ?',
        whereArgs: [mutableMsg['message_id']],
      );

      // 3. Attach mutable attachments list
      mutableMsg['attachments'] = attachments;
      mutableMessages.add(mutableMsg);
    }

    setState(() {
      if (offset == 0) {
        _messages = mutableMessages;
      } else {
        _messages.addAll(mutableMessages);
        _hasMore = !(rawMessages.length < limit);
      }
    });

    _isLoadingMore = false;
  }

  Future<void> _pickFiles() async {
    // Returns List<PlatformFile> directly in latest file_picker versions
    final List<PlatformFile> pickedFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        // Images
        'png', 'jpg', 'jpeg', 'webp', 'gif',
        // Documents
        'pdf', 'csv', 'txt', 'docx', 'xlsx', 'json',
      ],
    );

    if (pickedFiles.isNotEmpty) {
      setState(() {
        for (final platformFile in pickedFiles) {
          if (platformFile.path != null) {
            final file = File(platformFile.path!);

            // Prevent adding duplicate files to the attachment list
            if (!_selectedFiles.any((f) => f.path == file.path)) {
              _selectedFiles.add(file);
            }
          }
        }
      });
    }
  }

  IconData _getFileIcon(String extension) {
    switch (extension) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.csv':
      case '.xlsx':
      case '.xls':
        return Icons.table_chart;
      case '.txt':
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.zip':
      case '.tar':
      case '.gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Handles clipboard paste with exact separation between image files (e.g. Nemo),
  /// raw image data (e.g. screenshots), and plain text.
  Future<void> _handleClipboardPaste() async {
    // 1. Check for File URIs copied from file managers like Nemo (Pasteboard.files() is a method)
    final List<String> files = await Pasteboard.files();
    if (files.isNotEmpty) {
      final String filePath = files.first;
      final String extension = p.extension(filePath).toLowerCase();

      if ([
        '.png',
        '.jpg',
        '.jpeg',
        '.webp',
        '.gif',
        '.bmp',
      ].contains(extension)) {
        final imageFile = File(filePath);
        if (await imageFile.exists()) {
          setState(() {
            _selectedFiles.add(imageFile);
          });
          return;
        }
      }
    }

    // 2. Check for raw image bytes (e.g., screenshots or web browser "Copy Image")
    final Uint8List? imageBytes = await Pasteboard.image;
    if (imageBytes != null) {
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/pasted_image_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(imageBytes);

      setState(() {
        _selectedFiles.add(tempFile);
      });
      return;
    }

    // 3. Fallback to Plain Text
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final String? rawText = data?.text;

    if (rawText != null && rawText.isNotEmpty) {
      _insertTextAtCursor(rawText);
    }
  }

  /// Inserts text into the text field at the current cursor location
  void _insertTextAtCursor(String text) {
    final currentText = _textController.text;
    final selection = _textController.selection;

    if (selection.start >= 0) {
      final newText = currentText.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      );
    } else {
      _textController.text += text;
    }
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _selectedFiles.isEmpty) return;

    final String msgID = const Uuid().v4();
    final String type = _selectedFiles.isNotEmpty && text.isNotEmpty
        ? 'mixed'
        : _selectedFiles.isNotEmpty
        ? 'media'
        : 'text';

    final Map<String, dynamic> msg = {
      'message_id': msgID,
      'sender_device_id': DeviceRegistrationService.deviceId,
      'recipient_device_id': null,
      'content_type': type,
      'body': text.isNotEmpty ? text : null,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'delivery_status': 'pending',
      'device_name': Platform.localHostname,
      'attachments': <Map<String, dynamic>>[],
    };

    // 1. Insert message into SQLCipher
    await widget.db.insert('messages', {
      'message_id': msg['message_id'],
      'sender_device_id': msg['sender_device_id'],
      'recipient_device_id': msg['recipient_device_id'],
      'content_type': msg['content_type'],
      'body': msg['body'],
      'timestamp': msg['timestamp'],
      'delivery_status': msg['delivery_status'],
    });

    // 2. Process and copy attached files to app media directory
    if (_selectedFiles.isNotEmpty) {
      final Directory mediaDir = await getAppMediaDirectory();
      final List<Map<String, dynamic>> attachmentList = [];

      for (final file in _selectedFiles) {
        final String extension = p.extension(file.path).toLowerCase();
        final String attachmentId = const Uuid().v4();
        final String savedFileName = '$attachmentId$extension';
        final String destinationPath = p.join(mediaDir.path, savedFileName);

        // Copy file from temporary/picker location to persistent app media folder
        final File savedFile = await file.copy(destinationPath);
        final int fileSize = await savedFile.length();

        final Map<String, dynamic> attachmentData = {
          'attachment_id': attachmentId,
          'message_id': msgID,
          'file_path': destinationPath, // Fixed: point to persistent media path
          'file_name': p.basename(file.path),
          'file_type': extension,
          'file_size': fileSize,
        };

        // Save row to SQLCipher
        await widget.db.insert('attachments', attachmentData);
        attachmentList.add(attachmentData);
      }

      // Attach to message map so optimistic UI rendering has access immediately
      msg['attachments'] = attachmentList;
    }

    // 3. Update local state and clear input field
    setState(() {
      _messages.insert(0, msg);
      _selectedFiles.clear();
    });

    _textController.clear();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Log'),
        actions: resetButton(context),
      ),
      backgroundColor: Colors.grey.shade800,
      body: Column(
        children: [
          // Chat Log Area
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              controller: _scrollController,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final String senderDeviceId = msg['sender_device_id'] ?? '';
                final bool isCurrentDevice =
                    senderDeviceId == DeviceRegistrationService.deviceId;
                final String type = msg['content_type'] ?? 'text';

                final String deviceName =
                    msg['device_name'] ??
                    (senderDeviceId.length >= 8
                        ? senderDeviceId.substring(0, 8)
                        : senderDeviceId);

                final List<Map<String, dynamic>> attachments =
                    (msg['attachments'] as List?)
                        ?.cast<Map<String, dynamic>>() ??
                    [];

                // Separate attachments into images vs general files
                final List<Map<String, dynamic>> imageAttachments = [];
                final List<Map<String, dynamic>> fileAttachments = [];

                if (type == 'media' || type == 'mixed') {
                  for (final att in attachments) {
                    final ext = (att['file_type'] as String? ?? '')
                        .toLowerCase();
                    if ([
                      '.png',
                      '.jpg',
                      '.jpeg',
                      '.webp',
                      '.gif',
                      '.bmp',
                    ].contains(ext)) {
                      imageAttachments.add(att);
                    } else {
                      fileAttachments.add(att);
                    }
                  }
                }

                return Align(
                  alignment: Alignment.center,
                  child: Container(
                    constraints: BoxConstraints(
                      minWidth: 120,
                      maxWidth: MediaQuery.of(context).size.width > 600
                          ? 500
                          : MediaQuery.of(context).size.width * 0.75,
                    ),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 6.0,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrentDevice
                          ? Colors.blue.shade700
                          : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Device Name Header
                        Text(
                          deviceName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isCurrentDevice
                                ? Colors.blue.shade100
                                : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 2. Text Content (text and mixed)
                        if ((type == 'text' || type == 'mixed') &&
                            msg['body'] != null &&
                            (msg['body'] as String).isNotEmpty)
                          SelectableText(
                            msg['body'],
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.3,
                              color: Colors.white,
                            ),
                            showCursor: false,
                          ),

                        // 3. Image Attachments Grid
                        if (imageAttachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6.0, // Horizontal spacing between images
                            runSpacing: 6.0, // Vertical spacing between rows
                            children: imageAttachments.map((att) {
                              final String path = att['file_path'] ?? '';
                              final File file = File(path);

                              if (!file.existsSync()) {
                                return Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.black26,
                                  child: const Icon(
                                    Icons.broken_image,
                                    color: Colors.white38,
                                  ),
                                );
                              }

                              // Auto-scale grid sizes: full width for 1 image, half-width for multiple
                              final double imageWidth =
                                  imageAttachments.length == 1 ? 200 : 140;

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8.0),
                                child: Image.file(
                                  file,
                                  width: imageWidth,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              );
                            }).toList(),
                          ),
                        ],

                        // 4. Non-Image Document Cards (PDFs, TXT, XLSX, etc.)
                        if (fileAttachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Column(
                            children: fileAttachments.map((att) {
                              final String fileName =
                                  att['file_name'] ?? 'File';
                              final String ext =
                                  (att['file_type'] as String? ?? '')
                                      .toLowerCase();

                              return Container(
                                margin: const EdgeInsets.only(top: 4.0),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10.0,
                                  vertical: 8.0,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getFileIcon(ext),
                                      color: Colors.white70,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Attached / Pasted Image Preview Bar
          if (_selectedFiles.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                itemCount: _selectedFiles.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 8.0),
                itemBuilder: (context, index) {
                  final file = _selectedFiles[index];
                  final extension = p.extension(file.path).toLowerCase();
                  final bool isImage = [
                    '.png',
                    '.jpg',
                    '.jpeg',
                    '.webp',
                    '.gif',
                    '.bmp',
                  ].contains(extension);

                  return Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: isImage
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12.0),
                                child: Image.file(
                                  file,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _getFileIcon(extension),
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    const SizedBox(height: 4),
                                    Tooltip(
                                      message: p.basename(
                                        file.path,
                                      ), // Full filename shown on hover
                                      waitDuration: const Duration(
                                        milliseconds: 300,
                                      ), // Delay before showing tooltip
                                      child: Text(
                                        p.basename(file.path),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedFiles.removeAt(index);
                            });
                          },
                          child: const CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          // Input Control Area
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                    _handleClipboardPaste,
                const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                    _handleClipboardPaste,
              },
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      cursorColor: Colors.white,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: IconButton(
                          icon: Icon(
                            Icons.attach_file,
                            color: Colors.grey.shade400,
                          ),
                          onPressed: _pickFiles,
                          style: ButtonStyle(
                            overlayColor: WidgetStateProperty.resolveWith((
                              states,
                            ) {
                              if (states.contains(WidgetState.hovered) ||
                                  states.contains(WidgetState.pressed)) {
                                return Colors.grey.shade600;
                              }
                              return null;
                            }),
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blueAccent),
                    onPressed: _sendMessage,
                    // make it more shiny when hovered or pressed
                    style: ButtonStyle(
                      overlayColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.pressed)) {
                          return Colors.grey.shade700;
                        }
                        return null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> resetButton(BuildContext context) {
  return [
    IconButton(
      icon: const Icon(Icons.cleaning_services, color: Colors.red),
      tooltip: 'Reset App Identity',
      onPressed: () async {
        final db = await DatabaseService().database;

        try {
          // 1. Wipe database tables in child-to-parent order
          await db.transaction((txn) async {
            await txn.delete('attachments');
            await txn.delete('messages');
            await txn.delete('devices');
          });

          // 2. Clear secure storage and RAM cache only after DB succeeds
          await DeviceRegistrationService.clearDeviceRegistration();

          if (context.mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => LoginPage(db: db)),
            );
          }
        } catch (e) {
          debugPrint('Failed to reset app identity: $e');
        }
        // 3. Optionally, you can also delete the media directory to free up space
        final Directory mediaDir = await getAppMediaDirectory();
        if (await mediaDir.exists()) {
          await mediaDir.delete(recursive: true).catchError((_) {});
        }
      },
    ),
  ];
}
