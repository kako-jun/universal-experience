import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/disability_type.dart';
import '../../services/filter_service.dart';

class IntensitySlider extends StatelessWidget {
  const IntensitySlider({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<FilterService>(
      builder: (context, filterService, _) {
        final isEnabled = filterService.currentFilter != ColorVisionType.none;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.intensityValue((filterService.intensity * 100).toInt()),
                  style: TextStyle(
                    fontSize: 16,
                    color: isEnabled ? Colors.black87 : Colors.grey,
                  ),
                ),
                if (isEnabled)
                  Text(
                    filterService.isActive
                        ? l10n.intensityActive
                        : l10n.intensityInactive,
                    style: TextStyle(
                      fontSize: 14,
                      color: filterService.isActive
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: filterService.intensity,
              onChanged: isEnabled
                  ? (value) => filterService.setIntensity(value)
                  : null,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '${(filterService.intensity * 100).toInt()}%',
            ),
            if (!isEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.intensityHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
