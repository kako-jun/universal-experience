import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/disability_type.dart';
import '../../services/filter_service.dart';
import '../widgets/filter_selector.dart';
import '../widgets/intensity_slider.dart';
import '../widgets/filter_catalog_selector.dart';
import '../widgets/filter_param_panel.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Universal Experience'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(context),
            tooltip: 'About',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildHeaderSection(),
              const SizedBox(height: 32),
              _buildFilterSection(),
              const SizedBox(height: 24),
              _buildControlsSection(),
              const SizedBox(height: 32),
              _buildAdvancedSection(),
              const SizedBox(height: 32),
              _buildInfoSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'すべての感覚を、すべての人に。',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.indigo.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Experience every perspective, understand every challenge.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.visibility, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                const Text(
                  'Color Vision Simulation',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const FilterSelector(),
            const SizedBox(height: 16),
            Text(
              'フィルタの見え方は sensus（色覚アルゴリズムの正本）で計算します。'
              'ライブ画面への適用は画面キャプチャ経路の実装後に対応予定です。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                const Text(
                  'Filter Intensity',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const IntensitySlider(),
          ],
        ),
      ),
    );
  }

  /// Advanced（sensus 全 30 フィルタ）セクション。既存の色覚 7 種 UI とは別系統。
  Widget _buildAdvancedSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, color: Colors.indigo.shade600),
                const SizedBox(width: 12),
                Expanded(
                  // TODO(#18): i18n - extract to key
                  // `home.advancedSectionTitle`. English fallback for now;
                  // actual translations are out of scope for #16.
                  child: Text(
                    'Advanced (all sensus filters)',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'sensus が公開する全 30 種の見え方を、カテゴリ別に選んでパラメータを'
              '調整できます。実描画/ライブ適用は別 Issue（#11/#1/#3/#4）で対応します。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
            const FilterCatalogSelector(),
            const Divider(height: 32),
            const FilterParamPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection() {
    return Consumer<FilterService>(
      builder: (context, filterService, _) {
        final filter = filterService.currentFilter;

        if (filter == ColorVisionType.none) {
          return const SizedBox.shrink();
        }

        return Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        filter.displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  filter.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Prevalence: ${filter.prevalence}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Universal Experience',
      applicationVersion: '0.1.0',
      applicationIcon: const Icon(Icons.accessibility_new, size: 48),
      children: [
        const Text(
          'Universal Experience is a comprehensive accessibility simulation tool '
          'designed to help people understand and empathize with various disabilities.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Phase 1: Color Vision Deficiency Simulation\n'
          'Phase 2: Hearing Impairment Simulation (Coming Soon)\n'
          'Phase 3: Additional Disability Simulations (Planned)',
        ),
      ],
    );
  }
}
