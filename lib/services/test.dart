// import 'package:device_info_plus/device_info_plus.dart';

// void main() async {
//   final deviceInfoPlugin = DeviceInfoPlugin();
//   final deviceInfo = await deviceInfoPlugin.deviceInfo;
//   print('Device Info: $deviceInfo');
// }

// Future<void> _promptDeviceName(BuildContext context) async {
//   final controller = TextEditingController();

//   final String? deviceName = await showDialog<String>(
//     context: context,
//     barrierDismissible: true, // Prevents closing by tapping outside the dialog
//     builder: (dialogContext) {
//       // Use StatefulBuilder so error text updates dynamically inside the dialog
//       String? errorMessage;
//       return StatefulBuilder(
//         builder: (context, setDialogState) {
//           return AlertDialog(
//             title: const Text('Enter Device Name'),
//             content: TextField(
//               controller: controller,
//               autofocus: true,
//               decoration: InputDecoration(
//                 hintText: 'e.g. Alice Mobile',
//                 errorText: errorMessage, // Displays inline validation error
//               ),
//               onChanged: (_) {
//                 // Clear error message when the user starts typing again
//                 if (errorMessage != null) {
//                   setDialogState(() => errorMessage = null);
//                 }
//               },
//             ),

//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(dialogContext, null),
//                 child: const Text('Cancel'),
//               ),
//               FilledButton(
//                 onPressed: () {
//                   final text = controller.text.trim();
//                   if (text.isEmpty) {
//                     // Trigger rebuild of dialog to show error, dialog stays open
//                     setDialogState(() {
//                       errorMessage = 'Device name cannot be empty';
//                     });
//                     return;
//                   }
//                   // Input is valid; close dialog and return text
//                   Navigator.pop(dialogContext, text);
//                 },
//                 child: const Text('Continue'),
//               ),
//             ],
//           );
//         },
//       );
//     },
//   );

//   // User explicitly tapped Cancel
//   if (deviceName == null) return;

//   // Key generation and database setup guaranteed to run with valid deviceName
//   print("Initializing session for: $deviceName");
// }
