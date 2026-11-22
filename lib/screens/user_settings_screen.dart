import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:country_flags/country_flags.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/session_provider.dart';
import '../providers/user_settings_provider.dart';
import '../utils/error_localization.dart';

/// Screen for configuring user profile settings.
/// Works whether user is signed in or not.
class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  late TextEditingController _nameController;
  String? _selectedCountry;

  static const _countries = [
    'JP', 'US', 'GB', 'CN', 'KR', 'DE', 'FR', 'IT', 'ES', 'BR',
    'IN', 'AU', 'CA', 'MX', 'RU', 'TW', 'SG', 'TH', 'VN', 'PH',
  ];

  @override
  void initState() {
    super.initState();
    final userSettings = context.read<UserSettingsProvider>();
    _nameController = TextEditingController(text: userSettings.displayName);
    _selectedCountry = userSettings.countryCode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back, color: Theme.of(context).appBarTheme.foregroundColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          l10n.profileSettings,
          style: TextStyle(
            color: Theme.of(context).appBarTheme.foregroundColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer2<UserSettingsProvider, AuthProvider>(
        builder: (context, userSettings, auth, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar section
                _buildAvatarSection(context, userSettings, auth),
                const SizedBox(height: 32),

                // Display name section
                _buildSectionTitle(l10n.displayName),
                const SizedBox(height: 12),
                _buildNameField(context, userSettings),
                const SizedBox(height: 24),

                // Country section
                _buildSectionTitle(l10n.country),
                const SizedBox(height: 12),
                _buildCountrySelector(context, userSettings),
                const SizedBox(height: 32),

                // Theme section
                _buildSectionTitle(AppLocalizations.of(context)!.theme),
                const SizedBox(height: 12),
                _buildThemeSelector(context, userSettings),
                const SizedBox(height: 32),

                // Auth section
                _buildAuthSection(context, auth),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildAvatarSection(
    BuildContext context,
    UserSettingsProvider userSettings,
    AuthProvider auth,
  ) {
    final photoUrl = googleAvatarUrl(auth, userSettings);
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final avatarToggleColor = isDark ? primaryColor : const Color(0xFF1A237E);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar display
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          width: 94,
                          height: 94,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildJdenticon(
                            userSettings.iconSeed,
                            94,
                          ),
                        )
                      : _buildJdenticon(userSettings.iconSeed, 94),
                ),
              ),
              // Country badge
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cardColor, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                child: ClipOval(
                  child: Container(
                    color: Colors.white,
                    child: CountryFlag.fromCountryCode(
                      userSettings.countryCode,
                      height: 28,
                      width: 28,
                    ),
                  ),
                ),
              ),
            ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            userSettings.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          if (auth.isSignedIn) ...[
            const SizedBox(height: 4),
            Text(
              auth.email,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Avatar type toggle (only when signed in with Google photo available)
          if (auth.isSignedIn && auth.photoUrl != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        userSettings.useGoogleAvatar 
                            ? Icons.account_circle 
                            : Icons.auto_awesome,
                        color: avatarToggleColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        userSettings.useGoogleAvatar 
                            ? AppLocalizations.of(context)!.useGoogleAvatar 
                            : AppLocalizations.of(context)!.useAutoGeneratedAvatar,
                        style: TextStyle(
                          fontSize: 14,
                          color: avatarToggleColor,
                        ),
                      ),
                    ],
                  ),
                  Switch(
                    value: userSettings.useGoogleAvatar,
                    onChanged: (value) async {
                      await userSettings.setUseGoogleAvatar(value);
                      // Sync immediately so other users see the change
                      if (context.mounted) {
                        await context.read<SessionProvider>().forceSync();
                      }
                    },
                    activeThumbColor: avatarToggleColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Regenerate icon button (only when using auto-generated icon)
          if (photoUrl == null)
            OutlinedButton.icon(
              onPressed: () async {
                await userSettings.regenerateIcon();
                // Sync immediately so other users see the new icon
                if (!context.mounted) return;
                await context.read<SessionProvider>().forceSync();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.iconRegenerated),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context)!.regenerateIcon),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJdenticon(String seed, double size) {
    return SvgPicture.string(
      Jdenticon.toSvg(seed, size: size.toInt()),
      width: size,
      height: size,
    );
  }

  Widget _buildNameField(BuildContext context, UserSettingsProvider userSettings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _nameController,
        maxLength: UserSettingsProvider.maxDisplayNameLength,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.displayNameHint,
          hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: cardColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon: IconButton(
            tooltip: AppLocalizations.of(context)!.saveDisplayName,
            icon: Icon(Icons.check, color: primaryColor),
            onPressed: () async {
              await userSettings.setDisplayName(_nameController.text);
              if (context.mounted) {
                FocusScope.of(context).unfocus();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.displayNameSaved),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ),
        onSubmitted: (value) async {
          await userSettings.setDisplayName(value);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.displayNameSaved),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildCountrySelector(BuildContext context, UserSettingsProvider userSettings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedCountry,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: cardColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        dropdownColor: cardColor,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 16,
        ),
        isExpanded: true,
        items: _countries.map((country) {
          return DropdownMenuItem<String>(
            value: country,
            child: Row(
              children: [
                Container(
                  color: Colors.white,
                  child: CountryFlag.fromCountryCode(
                    country,
                    height: 20,
                    width: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(AppLocalizations.of(context)!.countryName(country))),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) async {
          if (value != null) {
            setState(() => _selectedCountry = value);
            await userSettings.setCountryCode(value);
          }
        },
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context, UserSettingsProvider userSettings) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment<ThemeMode>(
            value: ThemeMode.system,
            label: Text(l10n.themeSystem),
            icon: const Icon(Icons.brightness_auto),
          ),
          ButtonSegment<ThemeMode>(
            value: ThemeMode.light,
            label: Text(l10n.themeLight),
            icon: const Icon(Icons.light_mode),
          ),
          ButtonSegment<ThemeMode>(
            value: ThemeMode.dark,
            label: Text(l10n.themeDark),
            icon: const Icon(Icons.dark_mode),
          ),
        ],
        selected: {userSettings.themeMode},
        onSelectionChanged: (Set<ThemeMode> newSelection) {
          userSettings.setThemeMode(newSelection.first);
        },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? primaryColor.withValues(alpha: 0.2) : const Color(0xFFE8EAF6);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? primaryColor : const Color(0xFF1A237E);
            }
            return isDark ? Colors.grey.shade400 : Colors.grey.shade700;
          }),
        ),
      ),
    );
  }

  Widget _buildAuthSection(BuildContext context, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.account,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 12),
          if (auth.isSignedIn) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  AppLocalizations.of(context)!.signedInWithGoogle,
                  style: TextStyle(
                     color: isDark ? Colors.white : Colors.black,
                  ),
                )),
                TextButton(
                  onPressed: () async {
                    await auth.signOut();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(context)!.signedOutSuccessfully)),
                      );
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.signOut),
                ),
              ],
            ),
          ] else ...[
            Text(
              AppLocalizations.of(context)!.historySignInNotice,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: auth.isLoading
                    ? null
                    : () async {
                        final success = await auth.signInWithGoogle();
                        if (context.mounted) {
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!.signedInSuccess),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (auth.error != null) {
                            final l10n = AppLocalizations.of(context)!;
                            final errorMessage =
                                localizeErrorKey(l10n, auth.error!);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                icon: auth.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(auth.isLoading
                    ? AppLocalizations.of(context)!.signingIn
                    : AppLocalizations.of(context)!.signInWithGoogle),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
