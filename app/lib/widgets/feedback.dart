// Standard result toasts for every workflow: green success, red failure.
// Floating behavior + bottom margin keeps them off submit buttons.
library;

import 'package:flutter/material.dart';

void _show(BuildContext context, String msg, Color bg, IconData icon) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
        backgroundColor: bg,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
}

/// Success toast on every completed save/add/print-queue outcome.
void showOk(BuildContext context, String msg) =>
    _show(context, msg, Colors.green.shade800, Icons.check_circle);

/// Failure toast on every failed save/add outcome (inline _err keeps detail).
void showErr(BuildContext context, String msg) =>
    _show(context, msg, Colors.red.shade800, Icons.error);
