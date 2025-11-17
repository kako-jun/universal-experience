import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/disability_type.dart';
import '../../services/filter_service.dart';

class FilterSelector extends StatelessWidget {
  const FilterSelector({super.key});

  @override
  Widget build(BuildContext context) {
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
                  label: Text(type.displayName),
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
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                  label: const Text('Clear Filter'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
