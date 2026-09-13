import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/call_history_model.dart';
import '../../models/call_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';

/// Recent Calls tab content (AppBar is provided by the Home shell).
///
/// Pure build output: all data comes from [CallProvider] and it holds no
/// local state. Pull-to-refresh and the first-load safety net are triggered
/// as side effects of build, guarded by provider flags so they never loop.
class CallHistoryScreen extends StatelessWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthProvider>().user?.uid;

    // Safety net: if this tab is the first thing on screen and history has
    // never been fetched, load it once. Guarded by provider flags so an
    // already-running fetch or an already-loaded (even if empty) list never
    // re-triggers.
    final cp = context.read<CallProvider>();
    if (!cp.hasLoadedHistory && !cp.isLoadingHistory && uid != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<CallProvider>().fetchCallHistory(uid);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Recent Calls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Expanded(
          child: Consumer<CallProvider>(
            builder: (context, callProvider, _) {
              // Newest first.
              final history = [...callProvider.callHistory]
                ..sort((a, b) => b.startTime.compareTo(a.startTime));
              final loading = callProvider.isLoadingHistory && history.isEmpty;
              final error = callProvider.fetchError;

              return RefreshIndicator(
                onRefresh: () async {
                  final id = context.read<AuthProvider>().user?.uid;
                  if (id != null) await callProvider.fetchCallHistory(id);
                },
                child: _HistoryBody(
                  history: history,
                  loading: loading,
                  error: error,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Body (always scrollable so pull-to-refresh works in every state)
// ============================================================================

class _HistoryBody extends StatelessWidget {
  final List<CallModel> history;
  final bool loading;
  final String? error;

  const _HistoryBody({
    required this.history,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _centerScrollable(const CircularProgressIndicator());
    }

    if (error != null && history.isEmpty) {
      return _centerScrollable(_ErrorView(message: error!));
    }

    if (history.isEmpty) {
      return _centerScrollable(const _EmptyView());
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final call = CallHistoryModel.fromCall(history[index]);
        return _SwipeableTile(
          call: call,
          onDeleted: () =>
              context.read<CallProvider>().deleteCallHistoryItem(call.id),
        );
      },
    );
  }

  /// Scrollable wrapper that centers a fixed-size child, so RefreshIndicator
  /// still receives the overscroll gesture in empty/error/loading states.
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
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Text(
          'No call history',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
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
            final uid = context.read<AuthProvider>().user?.uid;
            if (uid == null) return;
            context.read<CallProvider>().fetchCallHistory(uid);
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

// ============================================================================
// History row
// ============================================================================

/// A single history row wrapped in a swipe-to-delete Dismissible.
class _SwipeableTile extends StatelessWidget {
  final CallHistoryModel call;
  final VoidCallback onDeleted;

  const _SwipeableTile({required this.call, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(call.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDeleted(),
      child: _CallHistoryTile(call: call),
    );
  }
}

/// A single row in the call history list.
class _CallHistoryTile extends StatelessWidget {
  final CallHistoryModel call;
  const _CallHistoryTile({required this.call});

  String get _otherParty =>
      call.isIncoming ? call.callerName : call.calleeName;

  bool get _isVideo => call.callType == CallType.video;

  /// What to show instead of the countdown: for calls that never connected,
  /// an outcome label is clearer than `00:00`.
  String get _outcomeLabel {
    switch (call.status) {
      case CallStatus.missed:
        return 'Missed';
      case CallStatus.rejected:
        return 'Declined';
      case CallStatus.busy:
        return 'Busy';
      case CallStatus.calling:
      case CallStatus.ringing:
      case CallStatus.connected:
      case CallStatus.ended:
        return _formatOutcome();
    }
  }

  String _formatOutcome() {
    final s = call.duration < 0 ? 0 : call.duration;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final missed = call.isMissed;
    final red = Colors.red;
    final name = _otherParty.isEmpty ? 'Unknown' : _otherParty;

    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: missed
            ? red.shade100
            : (_isVideo ? const Color(0xFFE3EDFF) : Colors.grey.shade200),
        child: Icon(
          _isVideo ? Icons.videocam : Icons.call,
          color: missed
              ? red
              : (_isVideo ? const Color(0xFF2563EB) : Colors.grey.shade700),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: missed ? FontWeight.w600 : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            call.isIncoming ? Icons.call_received : Icons.call_made,
            size: 14,
            color: missed ? red : Colors.grey.shade500,
          ),
        ],
      ),
      subtitle: Text(_formatWhen(call.startTime)),
      trailing: Text(
        _outcomeLabel,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: missed ? red : null,
        ),
      ),
      onTap: () => _showDetails(context),
    );

    return Container(
      color: missed ? red.shade50 : null,
      child: tile,
    );
  }

  /// "Today, 2:35 PM" / "Yesterday, 8:05 AM" / "Sep 12, 2025, 3:20 PM".
  String _formatWhen(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final time = DateFormat('h:mm a').format(t);
    if (day == today) return 'Today, $time';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $time';
    }
    return '${DateFormat.yMMMd().format(t)}, $time';
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CallDetailsSheet(call: call),
    );
  }
}

// ============================================================================
// Details bottom sheet
// ============================================================================

class _CallDetailsSheet extends StatelessWidget {
  final CallHistoryModel call;
  const _CallDetailsSheet({required this.call});

  @override
  Widget build(BuildContext context) {
    final name = call.isIncoming ? call.callerName : call.calleeName;
    final type = call.callType == CallType.video ? 'Video' : 'Audio';
    final direction = call.isIncoming ? 'Incoming' : 'Outgoing';
    final status = switch (call.status) {
      CallStatus.connected => 'Connected',
      CallStatus.ended => 'Ended',
      CallStatus.rejected => 'Declined',
      CallStatus.missed => 'Missed',
      CallStatus.busy => 'Busy',
      CallStatus.calling => 'Calling',
      CallStatus.ringing => 'Ringing',
    };
    final started = DateFormat.yMMMMd().add_Hms().format(call.startTime);
    final duration = call.isMissed
        ? '—'
        : '${(call.duration ~/ 60).toString().padLeft(2, '0')}:${(call.duration % 60).toString().padLeft(2, '0')}';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Call Details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _DetailRow(icon: Icons.person, label: 'Contact', value: name.isEmpty ? 'Unknown' : name),
            _DetailRow(icon: Icons.swap_calls, label: 'Direction', value: direction),
            _DetailRow(
              icon: call.callType == CallType.video ? Icons.videocam : Icons.call,
              label: 'Type',
              value: type,
            ),
            _DetailRow(icon: Icons.info_outline, label: 'Status', value: status),
            _DetailRow(icon: Icons.schedule, label: 'Started', value: started),
            _DetailRow(icon: Icons.timer_outlined, label: 'Duration', value: duration),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}