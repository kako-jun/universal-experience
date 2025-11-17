import 'package:flutter/foundation.dart';
import 'package:color_vision_filter/color_vision_filter.dart';
import '../models/disability_type.dart';
import '../core/color_vision_simulator.dart';

/// Service managing disability simulation filters
class FilterService extends ChangeNotifier {
  ColorVisionType _currentFilter = ColorVisionType.none;
  double _intensity = 1.0;
  bool _isActive = false;
  bool _hasPermission = false;

  ColorVisionType get currentFilter => _currentFilter;
  double get intensity => _intensity;
  bool get isActive => _isActive;
  bool get hasPermission => _hasPermission;

  /// Get the current color matrix for preview purposes
  List<double> get colorMatrix {
    return ColorVisionSimulator.toColorMatrix(_currentFilter, _intensity);
  }

  /// Check and request permissions if needed
  Future<bool> checkPermissions() async {
    try {
      _hasPermission = await ColorVisionFilter.hasPermission();

      if (!_hasPermission) {
        _hasPermission = await ColorVisionFilter.requestPermission();
      }

      notifyListeners();
      return _hasPermission;
    } catch (e) {
      debugPrint('Permission check failed: $e');
      return false;
    }
  }

  /// Apply a color vision filter
  Future<void> applyFilter(ColorVisionType type, {double intensity = 1.0}) async {
    _currentFilter = type;
    _intensity = intensity.clamp(0.0, 1.0);
    _isActive = type != ColorVisionType.none;

    if (_isActive) {
      try {
        // Apply system-wide filter via native plugin
        final success = await ColorVisionFilter.apply(type.id, _intensity);

        if (!success) {
          debugPrint('Failed to apply filter: ${type.id}');
          _isActive = false;
        }
      } catch (e) {
        debugPrint('Error applying filter: $e');
        _isActive = false;
      }
    } else {
      await deactivate();
    }

    notifyListeners();
  }

  /// Update filter intensity
  Future<void> setIntensity(double intensity) async {
    _intensity = intensity.clamp(0.0, 1.0);

    if (_isActive && _currentFilter != ColorVisionType.none) {
      try {
        await ColorVisionFilter.setIntensity(_intensity);
      } catch (e) {
        debugPrint('Error updating intensity: $e');
      }
    }

    notifyListeners();
  }

  /// Deactivate current filter
  Future<void> deactivate() async {
    _isActive = false;

    try {
      await ColorVisionFilter.remove();
    } catch (e) {
      debugPrint('Error removing filter: $e');
    }

    notifyListeners();
  }

  /// Reactivate last used filter
  Future<void> reactivate() async {
    if (_currentFilter != ColorVisionType.none) {
      _isActive = true;

      try {
        await ColorVisionFilter.apply(_currentFilter.id, _intensity);
      } catch (e) {
        debugPrint('Error reactivating filter: $e');
        _isActive = false;
      }

      notifyListeners();
    }
  }

  /// Get current filter state from native plugin
  Future<void> syncState() async {
    try {
      final state = await ColorVisionFilter.getState();

      _isActive = state['isActive'] ?? false;
      _intensity = (state['intensity'] ?? 1.0).toDouble();

      // Find matching ColorVisionType
      final typeId = state['type'] ?? 'none';
      _currentFilter = ColorVisionType.values.firstWhere(
        (type) => type.id == typeId,
        orElse: () => ColorVisionType.none,
      );

      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing state: $e');
    }
  }
}
