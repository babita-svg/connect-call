import 'package:flutter/material.dart';

/// Validate user input before submitting forms.
class Validators {
  Validators._();

  /// Returns a non-null error message when [value] is not a valid email.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email address';
    }
    final pattern = RegExp(r'^[\w\.-]+@[\w-]+(\.[\w-]+)+$');
    if (!pattern.hasMatch(value.trim())) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Returns a non-null error message when [value] is not a valid password.
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  /// Returns a non-null error message when [value] is empty.
  static String? validateRequired(String? value, {String message = 'This field is required'}) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  /// Returns a non-null error message when [value] is not a valid name.
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    return null;
  }
}