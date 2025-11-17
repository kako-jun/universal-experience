import 'dart:async';
import 'package:flutter/services.dart';

/// Platform plugin for applying color vision deficiency filters
class ColorVisionFilter {
  static const MethodChannel _channel =
      MethodChannel('color_vision_filter');

  /// Apply a color vision filter system-wide
  ///
  /// [type] - The type of color vision deficiency (e.g., 'protanopia')
  /// [intensity] - Filter intensity from 0.0 to 1.0
  static Future<bool> apply(String type, double intensity) async {
    try {
      final bool? result = await _channel.invokeMethod('apply', {
        'type': type,
        'intensity': intensity,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to apply filter: ${e.message}');
      return false;
    }
  }

  /// Update the intensity of the current filter
  ///
  /// [intensity] - New intensity from 0.0 to 1.0
  static Future<bool> setIntensity(double intensity) async {
    try {
      final bool? result = await _channel.invokeMethod('setIntensity', {
        'intensity': intensity,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to set intensity: ${e.message}');
      return false;
    }
  }

  /// Remove the current filter
  static Future<bool> remove() async {
    try {
      final bool? result = await _channel.invokeMethod('remove');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to remove filter: ${e.message}');
      return false;
    }
  }

  /// Get the current filter state
  ///
  /// Returns a Map with keys:
  /// - 'type': String - Current filter type
  /// - 'intensity': double - Current intensity
  /// - 'isActive': bool - Whether a filter is currently active
  static Future<Map<String, dynamic>> getState() async {
    try {
      final Map<dynamic, dynamic>? result =
          await _channel.invokeMethod('getState');
      return Map<String, dynamic>.from(result ?? {});
    } on PlatformException catch (e) {
      print('Failed to get state: ${e.message}');
      return {
        'type': 'none',
        'intensity': 0.0,
        'isActive': false,
      };
    }
  }

  /// Check if the plugin has necessary permissions
  static Future<bool> hasPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('hasPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to check permission: ${e.message}');
      return false;
    }
  }

  /// Request necessary permissions
  static Future<bool> requestPermission() async {
    try {
      final bool? result = await _channel.invokeMethod('requestPermission');
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to request permission: ${e.message}');
      return false;
    }
  }
}
