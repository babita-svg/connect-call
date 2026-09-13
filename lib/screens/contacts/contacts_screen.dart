import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/call_exceptions.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/user_provider.dart';
import '../../widgets/user_tile.dart';
import '../calling/audio_call_screen.dart';
import '../calling/video_call_screen.dart';

/// Contacts tab content (AppBar is provided by the Home shell).
///
/// Stateless: the active search query and contact data live in [UserProvider],
/// so the screen only reads and reacts. Tap opens a profile sheet; long-press
/// opens a context menu. Permission failures surface as snackbars.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.read<UserProvider>();

    // Safety net: if this tab is the first thing on screen and contacts have
    // never been fetched, load them once. [hasLoadedUsers] flips in `finally`,
    // so a failed first fetch does not re-trigger this in a loop.
    if (!userProvider.hasLoadedUsers && !userProvider.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<UserProvider>().fetchAllUsers();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: const _ContactsSearchBar(),
        ),
        Expanded(
          child: Consumer<UserProvider>(
            builder: (context, userProvider, _) {
              // Online users first, then alphabetically.
              final users = [...userProvider.allUsers]..sort(_compareUsers);
              final loading = userProvider.isLoading && users.isEmpty;
              final noResults =
                  userProvider.searchQuery.isNotEmpty && users.isEmpty;

              return RefreshIndicator(
                onRefresh: () async {
                  final q = userProvider.searchQuery;
                  await userProvider.fetchAllUsers();
                  if (q.isNotEmpty) await userProvider.searchUsers(q);
                },
                child: _ContactsBody(
                  users: users,
                  loading: loading,
                  error: userProvider.error,
                  noResults: noResults,
                  onAudioCall: (u) => _startCallFlow(context, u, video: false),
                  onVideoCall: (u) => _startCallFlow(context, u, video: true),
                  showProfile: _showProfile,
                  showMenu: _showContextMenu,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Sorts online users first, then alphabetically by name.
int _compareUsers(UserModel a, UserModel b) {
  if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

// ============================================================================
// Call flow (single place for permission handling + navigation)
// ============================================================================

Future<void> _startCallFlow(
  BuildContext context,
  UserModel user, {
  required bool video,
}) async {
  final me = context.read<AuthProvider>().user;
  if (me == null) return;

  final callProvider = context.read<CallProvider>();
  try {
    if (video) {
      await callProvider.initiateVideoCall(
        recipientId: user.uid,
        recipientName: user.name,
        currentUserId: me.uid,
        currentUserName: me.name,
      );
    } else {
      await callProvider.initiateAudioCall(
        recipientId: user.uid,
        recipientName: user.name,
        currentUserId: me.uid,
        currentUserName: me.name,
      );
    }
  } on CallException catch (e) {
    // Permission denied (camera/mic) or engine failure — reset any partial
    // call state the provider set before the service threw, then inform the
    // user instead of navigating.
    callProvider.clearCallState();
    if (!context.mounted) return;
    _showSnack(context, e.message);
    return;
  } catch (e) {
    callProvider.clearCallState();
    if (!context.mounted) return;
    _showSnack(context, 'Could not start the call. Please try again.');
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          video ? const VideoCallScreen() : const AudioCallScreen(),
    ),
  );
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ============================================================================
// Profile sheet (tap / "View profile")
// ============================================================================

void _showProfile(BuildContext context, UserModel user) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => _UserProfileSheet(
      user: user,
      onAudioCall: () {
        Navigator.of(sheetCtx).pop();
        _startCallFlow(context, user, video: false);
      },
      onVideoCall: () {
        Navigator.of(sheetCtx).pop();
        _startCallFlow(context, user, video: true);
      },
    ),
  );
}

class _UserProfileSheet extends StatelessWidget {
  final UserModel user;
  final VoidCallback onAudioCall;
  final VoidCallback onVideoCall;

  const _UserProfileSheet({
    required this.user,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: hasPhoto
                  ? CachedNetworkImageProvider(user.photoUrl!)
                  : null,
              child: hasPhoto
                  ? null
                  : Text(
                      user.name.isEmpty
                          ? '?'
                          : user.name.trim()[0].toUpperCase(),
                      style: const TextStyle(fontSize: 32),
                    ),
            ),
            const SizedBox(height: 12),
            Text(user.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              user.email,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              user.isOnline ? 'Online now' : 'Offline',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: user.isOnline ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SheetCallButton(
                  icon: Icons.call,
                  label: 'Call',
                  color: const Color(0xFF2563EB),
                  onPressed: onAudioCall,
                ),
                _SheetCallButton(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.green.shade600,
                  onPressed: onVideoCall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _SheetCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: label,
          onPressed: onPressed,
          iconSize: 26,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
          icon: Icon(icon),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

// ============================================================================
// Context menu (long-press)
// ============================================================================

void _showContextMenu(BuildContext context, UserModel user) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundImage: (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(user.photoUrl!)
                  : null,
              child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(user.name),
            subtitle: Text(user.isOnline ? 'Online' : 'Offline'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.call),
            title: const Text('Audio call'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _startCallFlow(context, user, video: false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam),
            title: const Text('Video call'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _startCallFlow(context, user, video: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('View profile'),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _showProfile(context, user);
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('Block',
                style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _confirmBlock(context, user);
            },
          ),
        ],
      ),
    ),
  );
}

/// Blocking needs a per-user blocklist in the backend; for now it is offered
/// in the UI but flagged as unavailable.
Future<void> _confirmBlock(BuildContext context, UserModel user) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dlgCtx) => AlertDialog(
      title: const Text('Block user'),
      content: Text('Block ${user.name}? Blocked contacts will no longer be '
          'able to call you.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dlgCtx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dlgCtx).pop(true),
          child: const Text('Block'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  _showSnack(
    context,
    'Blocking requires backend support and is not enabled yet.',
  );
}

// ============================================================================
// Search bar
// ============================================================================

/// Material 3 search bar. Owns its controller so the clear button can reset
/// both the field text and the provider's active search.
class _ContactsSearchBar extends StatefulWidget {
  const _ContactsSearchBar();

  @override
  State<_ContactsSearchBar> createState() => _ContactsSearchBarState();
}

class _ContactsSearchBarState extends State<_ContactsSearchBar> {
  final TextEditingController _controller = TextEditingController();

  void _onChanged(String query) {
    context.read<UserProvider>().searchUsers(query);
  }

  void _clear() {
    _controller.clear();
    context.read<UserProvider>().clearSearch();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        return SearchBar(
          controller: _controller,
          hintText: 'Search contacts',
          leading: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(Icons.search),
          ),
          trailing: [
            if (userProvider.searchQuery.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: _clear,
              ),
          ],
          onChanged: _onChanged,
        );
      },
    );
  }
}

// ============================================================================
// List body (all states scrollable so pull-to-refresh always works)
// ============================================================================

class _ContactsBody extends StatelessWidget {
  final List<UserModel> users;
  final bool loading;
  final String? error;
  final bool noResults;
  final void Function(UserModel user) onAudioCall;
  final void Function(UserModel user) onVideoCall;
  final void Function(BuildContext context, UserModel user) showProfile;
  final void Function(BuildContext context, UserModel user) showMenu;

  const _ContactsBody({
    required this.users,
    required this.loading,
    required this.error,
    required this.noResults,
    required this.onAudioCall,
    required this.onVideoCall,
    required this.showProfile,
    required this.showMenu,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const _ShimmerList();

    if (error != null && users.isEmpty) {
      return _centerScrollable(_ErrorView(message: error!));
    }

    if (users.isEmpty) {
      return _centerScrollable(
        _EmptyView(
          icon: noResults ? Icons.search_off : Icons.people_outline,
          message: noResults ? 'No matching users' : 'No contacts yet',
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = users[index];
        return UserTile(
          user: user,
          onAudioCall: () => onAudioCall(user),
          onVideoCall: () => onVideoCall(user),
          onTap: () => showProfile(context, user),
          onLongPress: () => showMenu(context, user),
        );
      },
    );
  }

  Widget _centerScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(child: child),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Empty / error states
// ============================================================================

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyView({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(fontSize: 16, color: Colors.grey)),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () {
            context.read<UserProvider>().fetchAllUsers();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

// ============================================================================
// Skeleton loading list
// ============================================================================

/// Pulsing placeholder rows shown while contacts load.
class _ShimmerList extends StatefulWidget {
  const _ShimmerList();

  @override
  State<_ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<_ShimmerList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(begin: 0.35, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 8,
        itemBuilder: (_, __) => const _SkeletonTile(),
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final grey = Colors.grey.shade300;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(radius: 25, backgroundColor: grey),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140,
                  height: 14,
                  decoration: BoxDecoration(
                    color: grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 11,
                  decoration: BoxDecoration(
                    color: grey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.call, color: Colors.grey.shade300),
          const SizedBox(width: 14),
          Icon(Icons.videocam, color: Colors.grey.shade300),
        ],
      ),
    );
  }
}