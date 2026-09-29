import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import 'image_source_picker.dart' show pickAndLoadUserImage;

/// First-run empty-state banner (#78): shown once, points at the two things
/// a first-time visitor can do next — pick a different way of seeing, or try
/// it with their own photo. Dismissing it (the close button or either
/// action) persists via `SettingsService.dismissWelcomeBanner` and it never
/// reappears (`SettingsService.welcomeBannerDismissed`).
///
/// This is purely a guide/nudge, not a required step: both action buttons
/// dismiss the banner once pressed (the filter chips and the sample/photo
/// picker it points at are already visible on the same screen — no
/// additional navigation to wire up), except the "try your photo" action
/// also opens the file picker ([pickAndLoadUserImage], the exact same path
/// `ImageSourcePicker`'s own button uses) so it's a real shortcut, not just
/// a label.
///
/// Colours come only from `colorScheme` roles (repo convention, no
/// hardcoded values).
class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Consumer<SettingsService>(
      builder: (context, settings, _) {
        if (settings.welcomeBannerDismissed) return const SizedBox.shrink();

        final onContainer = theme.colorScheme.onSecondaryContainer;
        return Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.welcomeBannerTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: onContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: onContainer),
                      tooltip: l10n.welcomeBannerDismiss,
                      onPressed: settings.dismissWelcomeBanner,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.welcomeBannerBody,
                  style: theme.textTheme.bodyMedium?.copyWith(color: onContainer),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: settings.dismissWelcomeBanner,
                      child: Text(l10n.welcomeBannerChooseOtherAction),
                    ),
                    FilledButton(
                      onPressed: () async {
                        await pickAndLoadUserImage(context);
                        if (context.mounted) {
                          await settings.dismissWelcomeBanner();
                        }
                      },
                      child: Text(l10n.welcomeBannerTryPhotoAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
