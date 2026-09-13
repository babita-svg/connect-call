import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/call_history_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/user_provider.dart';
import '../calling/audio_call_screen.dart';
import '../calling/video_call_screen.dart';
import '../contacts/contacts_screen.dart';
import '../history/call_history_screen.dart';
import '../profile/profile_screen.dart';

/// App shell with bottom navigation and a Home overview tab.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _tabLabels = ['Home', 'Contacts', 'Calls', 'Profile'];

  int _currentIndex = 0;

  String? _uid;
  late UserProvider _userProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _userProvider = context.read<UserProvider>();
    _uid = context.read<AuthProvider>().user?.uid;

    // Reflect online presence while the app is foregrounded.
    if (_uid != null) _userProvider.updateOnlineStatus(_uid!, true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final uid = _uid;
    if (uid == null) return;
    final online = state == AppLifecycleState.resumed;
    _userProvider.updateOnlineStatus(uid, online);
  }

  @override
  void dispose() {
    if (_uid != null) {
      _userProvider.updateOnlineStatus(_uid!, false);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Quick search (AppBar icon + FAB)
  // --------------------------------------------------------------------------

  void _openQuickSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _QuickSearchSheet(),
    );
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userName = auth.user?.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? (userName == null || userName.isEmpty
                  ? 'ConnectCall'
                  : userName)
              : _tabLabels[_currentIndex],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openQuickSearch,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _HomeTab(
            onGoToContacts: () => setState(() => _currentIndex = 1),
            onGoToCalls: () => setState(() => _currentIndex = 2),
          ),
          const ContactsScreen(),
          const CallHistoryScreen(),
          const ProfileScreen(),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _openQuickSearch,
              tooltip: 'Quick search',
              child: const Icon(Icons.search),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_outlined),
            selectedIcon: Icon(Icons.call),
            label: 'Calls',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Home overview tab
// ============================================================================

class _HomeTab extends StatefulWidget {
  final VoidCallback onGoToContacts;
  final VoidCallback onGoToCalls;

  const _HomeTab({required this.onGoToContacts, required this.onGoToCalls});

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final userProvider = context.read<UserProvider>();
    final callProvider = context.read<CallProvider>();
    final uid = context.read<AuthProvider>().user?.uid;

    await userProvider.fetchAllUsers();
    userProvider.listenToPresence();
    if (uid != null) await callProvider.fetchCallHistory(uid);
  }

  Future<void> _refresh() async {
    final userProvider = context.read<UserProvider>();
    final callProvider = context.read<CallProvider>();
    final uid = context.read<AuthProvider>().user?.uid;

    await Future.wait([
      userProvider.fetchAllUsers(),
      if (uid != null) callProvider.fetchCallHistory(uid),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, CallProvider>(
      builder: (context, userProvider, callProvider, _) {
        final recentContacts = userProvider.allUsers.take(5).toList();
        final recentCalls =
            callProvider.callHistory.take(5).map(CallHistoryModel.fromCall).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // Quick call buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    _QuickCallButton(
                      icon: Icons.call,
                      label: 'Quick Audio',
                      onTap: () => _showQuickSearchSheet(context),
                    ),
                    const SizedBox(width: 12),
                    _QuickCallButton(
                      icon: Icons.videocam,
                      label: 'Quick Video',
                      onTap: () => _showQuickSearchSheet(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Recent contacts
              _SectionHeader(
                title: 'Recent Contacts',
                onSeeAll: widget.onGoToContacts,
              ),
              SizedBox(
                height: 96,
                child: recentContacts.isEmpty
                    ? const Center(child: Text('No contacts yet'))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: recentContacts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                        itemBuilder: (context, index) =>
                            _RecentContactChip(user: recentContacts[index]),
                      ),
              ),
              const SizedBox(height: 16),

              // Recent calls
              _SectionHeader(
                title: 'Recent Calls',
                onSeeAll: widget.onGoToCalls,
              ),
              if (recentCalls.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No calls yet'),
                )
              else
                ...recentCalls.map((call) => _RecentCallRow(call: call)),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// Opens the shared quick-search sheet.
void _showQuickSearchSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _QuickSearchSheet(),
  );
}

// ============================================================================
// Quick call launching (shared by tiles, recent rows, and the search sheet)
// ============================================================================

/// Initiates an outgoing call to [userId]/[userName] and navigates to the
/// matching call screen. Providers must be captured by the caller before any
/// route is popped.
Future<void> _startOutgoingCall({
  required UserModel? me,
  required CallProvider callProvider,
  required NavigatorState navigator,
  required String userId,
  required String userName,
  required bool video,
}) async {
  if (me == null) return;
  if (video) {
    await callProvider.initiateVideoCall(
      recipientId: userId,
      recipientName: userName,
      currentUserId: me.uid,
      currentUserName: me.name,
    );
  } else {
    await callProvider.initiateAudioCall(
      recipientId: userId,
      recipientName: userName,
      currentUserId: me.uid,
      currentUserName: me.name,
    );
  }
  navigator.push(
    MaterialPageRoute(
      builder: (_) => video ? const VideoCallScreen() : const AudioCallScreen(),
    ),
  );
}

/// Quick-search bottom sheet: type a name, then pick a result to call.
class _QuickSearchSheet extends StatefulWidget {
  const _QuickSearchSheet();

  @override
  State<_QuickSearchSheet> createState() => _QuickSearchSheetState();
}

class _QuickSearchSheetState extends State<_QuickSearchSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _pick(UserModel user, bool video) {
    // Capture everything while the sheet context is still valid.
    final me = context.read<AuthProvider>().user;
    final callProvider = context.read<CallProvider>();
    final userProvider = context.read<UserProvider>();
    final navigator = Navigator.of(context);
    final searchCleared = _searchController.text.isEmpty;
    Navigator.of(context).pop();

    if (searchCleared) userProvider.searchUsers('');

    _startOutgoingCall(
      me: me,
      callProvider: callProvider,
      navigator: navigator,
      userId: user.uid,
      userName: user.name,
      video: video,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (query) =>
                    context.read<UserProvider>().searchUsers(query),
              ),
            ),
            Flexible(
              child: Consumer<UserProvider>(
                builder: (context, userProvider, _) {
                  final users = userProvider.allUsers;
                  if (users.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No contacts found'),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final user in users.take(20))
                        ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (user.photoUrl != null &&
                                    user.photoUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(user.photoUrl!)
                                : null,
                            child:
                                (user.photoUrl == null || user.photoUrl!.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                          ),
                          title: Text(user.name),
                          subtitle: Text(user.isOnline ? 'Online' : 'Offline'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.call),
                                onPressed: () => _pick(user, false),
                              ),
                              IconButton(
                                icon: const Icon(Icons.videocam),
                                onPressed: () => _pick(user, true),
                              ),
                            ],
                          ),
                          onTap: () => _pick(user, false),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Home tab building blocks
// ============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
    );
  }
}

class _QuickCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickCallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(icon, color: scheme.primary),
        label: Text(label),
      ),
    );
  }
}

class _RecentContactChip extends StatelessWidget {
  final UserModel user;
  const _RecentContactChip({required this.user});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final me = context.read<AuthProvider>().user;
        final callProvider = context.read<CallProvider>();
        _startOutgoingCall(
          me: me,
          callProvider: callProvider,
          navigator: Navigator.of(context),
          userId: user.uid,
          userName: user.name,
          video: false,
        );
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage:
                (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                    ? CachedNetworkImageProvider(user.photoUrl!)
                    : null,
            child: (user.photoUrl == null || user.photoUrl!.isEmpty)
                ? const Icon(Icons.person)
                : null,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 72,
            child: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentCallRow extends StatelessWidget {
  final CallHistoryModel call;
  const _RecentCallRow({required this.call});

  @override
  Widget build(BuildContext context) {
    final otherId = call.isIncoming ? call.callerId : call.calleeId;
    final otherName = call.isIncoming ? call.callerName : call.calleeName;

    return ListTile(
      dense: true,
      leading: Icon(call.icon, color: call.isMissed ? Colors.red : null),
      title: Text(otherName.isEmpty ? 'Unknown' : otherName),
      trailing: Text(
        call.isMissed ? 'Missed' : call.durationString,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () {
        final me = context.read<AuthProvider>().user;
        final callProvider = context.read<CallProvider>();
        _startOutgoingCall(
          me: me,
          callProvider: callProvider,
          navigator: Navigator.of(context),
          userId: otherId,
          userName: otherName,
          video: false,
        );
      },
    );
  }
}