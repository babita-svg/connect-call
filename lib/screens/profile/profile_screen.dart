import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/user_provider.dart';
import 'edit_profile_screen.dart';

/// Profile tab content (AppBar is provided by the Home shell).
///
/// Stateless: the signed-in user's profile and its loading/error flags live in
/// [UserProvider], so the screen only reads and reacts. A single-shot safety
/// net fetches the profile the first time this tab is shown.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final auth = context.watch<AuthProvider>();
    final uid = auth.user?.uid;

    // Safety net: fetch the profile once on first view. [hasLoadedProfile]
    // flips in `finally`, so a failed fetch does not loop.
    if (uid != null && !userProvider.hasLoadedProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<UserProvider>().fetchCurrentUserProfile(uid);
      });
    }

    // Prefer the Firestore profile; fall back to the auth user while loading.
    final profile = userProvider.currentUser ?? auth.user;

    if (userProvider.isLoadingProfile && profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (profile == null) {
      return _ErrorState(
        onRetry: () {
          final u = context.read<AuthProvider>().user?.uid;
          if (u != null) {
            context.read<UserProvider>().fetchCurrentUserProfile(u);
          }
        },
      );
    }

    final error = userProvider.profileError;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Profile photo (120x120, circular)
        Center(
          child: _ProfilePhoto(user: profile),
        ),
        const SizedBox(height: 24),
        Text(
          profile.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          profile.email,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        // Phone (only when provided)
        if (profile.phone != null && profile.phone!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            profile.phone!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 8),
        _PresenceLine(user: profile),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 32),
        // Full-width secondary action buttons
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(user: profile),
                ),
              ),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _handleLogout(context),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Signs the user out and clears per-user provider state. Captures providers
/// before the await so no context is used after the root swaps to the login
/// screen.
Future<void> _handleLogout(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final userProvider = context.read<UserProvider>();
  final callProvider = context.read<CallProvider>();

  await auth.logout();
  userProvider.reset();
  callProvider.reset();
}

/// 120x120 circular profile photo with an initial-letter fallback.
class _ProfilePhoto extends StatelessWidget {
  final UserModel user;
  const _ProfilePhoto({required this.user});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: 60,
      backgroundColor: Colors.grey.shade200,
      backgroundImage:
          hasPhoto ? CachedNetworkImageProvider(user.photoUrl!) : null,
      child: hasPhoto
          ? null
          : Text(
              user.name.isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
              style: const TextStyle(fontSize: 40),
            ),
    );
  }
}

/// Online now (green) when [user.isOnline], otherwise the last-seen time.
class _PresenceLine extends StatelessWidget {
  final UserModel user;
  const _PresenceLine({required this.user});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Text(
      user.isOnline
          ? 'Online now'
          : 'Last seen ${DateFormat.yMMMMd(locale.languageCode).format(user.lastSeen)}',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: user.isOnline ? Colors.green : Colors.grey,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Could not load your profile.'),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}