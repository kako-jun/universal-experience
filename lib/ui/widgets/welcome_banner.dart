import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import 'image_source_picker.dart' show pickAndLoadUserImage;

/// First-run empty-state banner (#78): shown once, points at the two things
/// a first-time visitor can do next — pick a different way of seeing, or try
/// it with their own photo. Dismissing it (the close button, or a
/// successful action) persists via `SettingsService.dismissWelcomeBanner`
/// and it never reappears (`SettingsService.welcomeBannerDismissed`).
///
/// - "Choose another way of seeing" moves focus to the colour-vision chips
///   ([onChooseOtherView], #78 レビュー S8) and dismisses — the chips are
///   already visible on the same screen, so no navigation is needed, just a
///   focus handoff. `home_screen.dart` wires this to
///   `FilterSelectorState.focusSelectedChip` (via a `GlobalKey`), which moves
///   focus to a specific chip (visibly, with Material's focus ring) and
///   scrolls it into view with `Scrollable.ensureVisible` — not just to an
///   inert container `FocusNode` (#78 レビュー nit: the handoff must be
///   visible, not just logically correct).
/// - "Try it with your photo" opens the file picker ([pickAndLoadUserImage],
///   the exact same path `ImageSourcePicker`'s own button uses) and
///   dismisses **only if a photo was actually loaded** (#78 レビュー Q3):
///   cancelling the picker, or a decode failure, leaves the banner up so the
///   person can try again.
///
/// Colours come only from `colorScheme` roles (repo convention, no
/// hardcoded values).
class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({super.key, this.onChooseOtherView});

  /// Called for "choose another way of seeing" (#78 レビュー S8/nit), before
  /// dismissing. `null` (e.g. in isolated widget tests) just skips the
  /// handoff — the banner still dismisses.
  final VoidCallback? onChooseOtherView;

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
                      onPressed: () {
                        onChooseOtherView?.call();
                        settings.dismissWelcomeBanner();
                      },
                      child: Text(l10n.welcomeBannerChooseOtherAction),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final loaded = await pickAndLoadUserImage(context);
                        if (loaded && context.mounted) {
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
