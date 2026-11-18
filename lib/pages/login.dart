import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../services/device_registration.dart';
import '../services/models.dart';
import 'chat_log.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.db});

  final Database db;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 32.0, left: 16.0, right: 16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: SizedBox(
                  height: 56.0,
                  child: FilledButton(
                    // make this button look diffrent when hovered or pressed
                    // style: AppButtonStyles.primaryWithHoverBorder(context),
                    onPressed: () async {
                      print("Initiate new encrypted session button pressed");
                      final db = await DatabaseService().database;
                      await DeviceRegistrationService.registerDevice(db);

                      // Navigate to ChatLogPage after registration
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatLogPage(db: db),
                        ),
                      );
                    },
                    child: Text(
                      "Initiate new encrypted session",
                      style: TextStyle(color: colorScheme.onPrimary),
                    ),
                  ),
                ),
              ),

              SizedBox(
                height: 56.0,
                child: FilledButton(
                  // style: AppButtonStyles.primaryWithHoverBorder(context),
                  onPressed: () {
                    print("Pair with existing device button pressed");
                  },
                  child: Text(
                    "Pair with existing device",
                    style: TextStyle(color: colorScheme.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
