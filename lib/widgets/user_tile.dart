import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';

/// Displays a contact: 50px circular photo, name, online indicator
/// (green/gray dot), and audio/video call actions.
///
/// Call actions are wired through callbacks so the owning screen controls
/// permission handling, error snackbars, and navigation.
class UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onAudioCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UserTile({
    super.key,
    required this.user,
    this.onAudioCall,
    this.onVideoCall,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: hasPhoto
                ? CachedNetworkImageProvider(user.photoUrl!)
                : null,
            child: hasPhoto ? null : const Icon(Icons.person),
          ),
          // Presence indicator: green when online, gray when offline.
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: user.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(user.isOnline ? 'Online' : 'Offline'),
      onTap: onTap,
      onLongPress: onLongPress,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Audio call',
            icon: const Icon(Icons.call),
            onPressed: onAudioCall,
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam),
            onPressed: onVideoCall,
          ),
        ],
      ),
    );
  }
}