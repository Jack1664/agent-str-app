import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class TopNotice {
  const TopNotice._();

  static Future<bool?> show(
    String message, {
    Color backgroundColor = const Color(0xFF00D1C1),
    Color textColor = Colors.white,
    Toast length = Toast.LENGTH_SHORT,
  }) {
    return Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.TOP,
      toastLength: length,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }
}
