import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/disability_type.dart';
import '../../services/filter_service.dart';

class FilterSelector extends StatelessWidget {
  const FilterSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<FilterService>(
      builder: (context, filterService, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ColorVisionType.values.map((type) {
                final isSelected = filterService.currentFilter == type;

                return FilterChip(
                  label: Text(colorVisionTypeName(l10n, type)),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      filterService.applyFilter(type);
                    }
                  },
                  selectedColor: Colors.indigo.shade100,
                  checkmarkColor: Colors.indigo.shade700,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.indigo.shade900
                        : Colors.grey.shade700,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: filterService.isActive
                      ? () => filterService.deactivate()
                      : null,
                  icon: const Icon(Icons.clear),
                  label: Text(l10n.clearFilter),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
