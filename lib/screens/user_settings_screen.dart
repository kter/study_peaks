import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:country_flags/country_flags.dart';
import '../providers/auth_provider.dart';
import '../providers/user_settings_provider.dart';

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

  static const List<Map<String, String>> _countries = [
    {'code': 'JP', 'name': 'Japan'},
    {'code': 'US', 'name': 'United States'},
    {'code': 'GB', 'name': 'United Kingdom'},
    {'code': 'CN', 'name': 'China'},
    {'code': 'KR', 'name': 'South Korea'},
    {'code': 'DE', 'name': 'Germany'},
    {'code': 'FR', 'name': 'France'},
    {'code': 'IT', 'name': 'Italy'},
    {'code': 'ES', 'name': 'Spain'},
    {'code': 'BR', 'name': 'Brazil'},
    {'code': 'IN', 'name': 'India'},
    {'code': 'AU', 'name': 'Australia'},
    {'code': 'CA', 'name': 'Canada'},
    {'code': 'MX', 'name': 'Mexico'},
    {'code': 'RU', 'name': 'Russia'},
    {'code': 'TW', 'name': 'Taiwan'},
    {'code': 'SG', 'name': 'Singapore'},
    {'code': 'TH', 'name': 'Thailand'},
    {'code': 'VN', 'name': 'Vietnam'},
    {'code': 'PH', 'name': 'Philippines'},
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Profile Settings',
          style: TextStyle(
            color: Color(0xFF1A237E),
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
                _buildSectionTitle('Display Name'),
                const SizedBox(height: 12),
                _buildNameField(context, userSettings),
                const SizedBox(height: 24),

                // Country section
                _buildSectionTitle('Country'),
                const SizedBox(height: 12),
                _buildCountrySelector(context, userSettings),
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
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1A237E),
      ),
    );
  }

  Widget _buildAvatarSection(
    BuildContext context,
    UserSettingsProvider userSettings,
    AuthProvider auth,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
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
                    color: const Color(0xFF1A237E).withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: ClipOval(
                  child: auth.isSignedIn && auth.photoUrl != null
                      ? Image.network(
                          auth.photoUrl!,
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
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: CountryFlag.fromCountryCode(
                      userSettings.countryCode,
                      height: 28,
                      width: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            userSettings.displayName,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A237E),
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
          // Regenerate icon button (only when not using Google photo)
          if (!auth.isSignedIn || auth.photoUrl == null)
            OutlinedButton.icon(
              onPressed: () async {
                await userSettings.regenerateIcon();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Icon regenerated!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Regenerate Icon'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A237E),
                side: const BorderSide(color: Color(0xFF1A237E)),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        decoration: InputDecoration(
          hintText: 'Enter your display name',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF1A237E)),
            onPressed: () async {
              await userSettings.setDisplayName(_nameController.text);
              if (mounted) {
                FocusScope.of(context).unfocus();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Name saved!'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ),
        onSubmitted: (value) async {
          await userSettings.setDisplayName(value);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Name saved!'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildCountrySelector(BuildContext context, UserSettingsProvider userSettings) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        value: _selectedCountry,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        items: _countries.map((country) {
          return DropdownMenuItem<String>(
            value: country['code'],
            child: Row(
              children: [
                CountryFlag.fromCountryCode(
                  country['code']!,
                  height: 20,
                  width: 28,
                ),
                const SizedBox(width: 12),
                Text(country['name']!),
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

  Widget _buildAuthSection(BuildContext context, AuthProvider auth) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
          const Text(
            'Account',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A237E),
            ),
          ),
          const SizedBox(height: 12),
          if (auth.isSignedIn) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                const Text('Signed in with Google'),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    await auth.signOut();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Signed out successfully')),
                      );
                    }
                  },
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Sign in to sync your study progress across devices.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
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
                        if (mounted) {
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Signed in successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (auth.error != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Sign in failed: ${auth.error}'),
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
                label: Text(auth.isLoading ? 'Signing in...' : 'Sign in with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
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
