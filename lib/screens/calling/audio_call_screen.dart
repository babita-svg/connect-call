import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/call_provider.dart';
import '../../services/call_service.dart';

/// Audio-only call UI driven by [CallProvider]'s streams.
class AudioCallScreen extends StatelessWidget {
  const AudioCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<CallProvider>(
          builder: (context, callProvider, _) {
            final call = callProvider.currentCall;
            final state = callProvider.callState;
            final connected = state == CallState.connected;

            final name = call == null
                ? ''
                : call.isIncoming
                    ? call.callerName
                    : call.calleeName;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Call party
                const CircleAvatar(
                  radius: 48,
                  child: Icon(Icons.person, size: 48),
                ),
                const SizedBox(height: 16),
                Text(
                  name.isEmpty ? 'Audio Call' : name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _statusLabel(state),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (connected) ...[
                  const SizedBox(height: 4),
                  Text(
                    callProvider.durationString,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
                const SizedBox(height: 48),

                // Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundButton(
                      icon: callProvider.isAudioMuted
                          ? Icons.mic_off
                          : Icons.mic,
                      onPressed: () => callProvider.toggleAudio(),
                    ),
                    _RoundButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onPressed: connected
                          ? () async {
                              await callProvider.endCall();
                              if (context.mounted) Navigator.of(context).pop();
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _statusLabel(CallState state) {
    switch (state) {
      case CallState.calling:
      case CallState.ringing:
        return 'Ringing…';
      case CallState.connected:
        return 'Connected';
      case CallState.rejected:
        return 'Call rejected';
      case CallState.missed:
        return 'Call missed';
      case CallState.busy:
        return 'Line busy';
      case CallState.ended:
        return 'Call ended';
      case CallState.failed:
        return 'Call failed';
      case CallState.idle:
        return '';
    }
  }
}

/// Circular control button used on the call UI.
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const _RoundButton({required this.icon, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: color ?? Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      child: Icon(icon),
    );
  }
}