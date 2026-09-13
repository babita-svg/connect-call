# ConnectCall - Architecture Documentation

## Overview

ConnectCall follows **Clean Architecture** principles with clear separation between business logic, state management, and UI.

## Architecture Layers

```
┌─────────────────────────────────────────────────┐
│   UI Layer (Screens & Widgets)                  │
│   (LoginScreen, VideoCallScreen, ContactsList)  │
├─────────────────────────────────────────────────┤
│   Provider Layer (State Management)             │
│   (AuthProvider, UserProvider, CallProvider)    │
├─────────────────────────────────────────────────┤
│   Service Layer (Business Logic)                │
│   (AuthService, UserService, CallService)       │
├─────────────────────────────────────────────────┤
│   Data Layer (Firebase & Agora SDKs)            │
│   (Firestore, Firebase Auth, Agora RTC)         │
└─────────────────────────────────────────────────┘
```

## Why This Architecture?

### 1. **Separation of Concerns**
- Services know nothing about UI
- Providers orchestrate services
- Screens only care about display

### 2. **Testability**
- Services can be tested with mock Firebase
- Providers can be tested with mock services
- Easy to write unit tests

### 3. **Reusability**
- Services used by multiple providers
- Providers used by multiple screens
- Custom exceptions reused across layers

### 4. **Scalability**
- Easy to add new features
- Minimal changes to existing code
- Clear patterns to follow

### 5. **Maintainability**
- Clear data flow
- Easy to debug
- Well-documented patterns

## Component Deep Dive

### Services Layer

**AuthService** - Handles Firebase authentication

```
signUp(email, password, name)
     ↓
Firebase Auth (create user)
     ↓
Firestore (save profile)
     ↓
Return UserModel or throw exception
```

**UserService** - Manages Firestore user operations

```
getAllUsers()
     ↓
Query Firestore 'users' collection
     ↓
Filter out current user
     ↓
Sort by online status, then name
     ↓
Return List<UserModel>
```

**CallService** - Agora RTC engine management

```
initiateAudioCall(recipientId)
     ↓
Request microphone permission
     ↓
Initialize Agora engine
     ↓
Join RTC channel
     ↓
Emit CallState.calling
     ↓
Wait for recipient to join
     ↓
Emit CallState.connected
```

### Provider Layer

**AuthProvider** - Owns authentication state

```
Properties:

* currentUser: UserModel?
* isLoading: bool
* error: String?
* isAuthenticated: bool

Methods:

* signUp(email, password, name)
* signIn(email, password)
* logout()
* clearError()
```

**CallProvider** - Manages active call

```
Properties:

* currentCall: CallModel?
* callState: CallState (enum)
* isAudioMuted: bool
* isVideoEnabled: bool
* callDuration: Duration

Methods:

* initiateAudioCall(...)
* initiateVideoCall(...)
* acceptCall(...)
* rejectCall(...)
* endCall()
* toggleAudio()
* toggleVideo()
```

### Screen Layer

**Screens** watch providers and respond to changes

```dart
Consumer<CallProvider>(
  builder: (context, callProvider, _) {
    if (callProvider.callState == CallState.connected) {
      return VideoCallControls(...);
    }
    return CircularProgressIndicator();
  }
)
```

## Data Flow

### Making an Audio Call

```
1. User taps "Call" button in ContactsScreen
         ↓
2. ContactsScreen calls context.read<CallProvider>().initiateAudioCall(...)
         ↓
3. CallProvider updates state and calls CallService.initiateAudioCall()
         ↓
4. CallService requests permission and joins Agora channel
         ↓
5. CallService emits CallState.calling
         ↓
6. CallProvider listens to stream and updates UI
         ↓
7. Screen automatically navigates to AudioCallScreen
         ↓
8. Recipient receives incoming call notification
         ↓
9. Recipient sees IncomingCallScreen and taps "Accept"
         ↓
10. Both sides now have active call with audio flowing
```

## State Management: Why Provider?

### Alternatives Considered

| Pattern | Pros | Cons | Verdict |
|---------|------|------|---------|
| **Provider** ✅ | Simple, lightweight, easy to learn | Less powerful than BLoC | **BEST** for this app |
| BLoC | Powerful, industry standard | Boilerplate-heavy, steep learning curve | Overkill here |
| GetX | All-in-one solution | Over-engineered, too many features | Not needed |
| Riverpod | Modern, compile-safe | Newer, less documentation | Too experimental |

### Provider Advantages

1. **Low Boilerplate**: No events/states/bloc classes
2. **Easy to Test**: Mock providers trivially
3. **Rebuilds Only Affected Widgets**: `Consumer` ensures efficiency
4. **Clear Dependency Injection**: Services injected in providers
5. **Stream Support**: Easy to listen to Agora/Firebase streams

## Permission Handling

```dart
// Flow:
1. Request permission
2. If granted → proceed with feature
3. If denied → show user-friendly message
4. If permanently denied → show "Go to Settings" button
5. If user goes to settings → check again on return
```

Example: Video call permission flow
```dart
await Permission.camera.request();

// Results:
- granted → start video call
- denied → show "Camera permission required" banner
- permanentlyDenied → show settings link
- restricted → explain restriction (iOS)
```

## Call State Machine

```
                User initiates
                      ↓
                  [CALLING]
                (loading state)
                      ↓
      ┌─────────────────┬─────────────────┐
      ↓                 ↓                 ↓
  [RINGING]      [REJECTED]      [MISSED]
```

(60s timeout) (user declined) (timeout)
         ↓
     [CONNECTED]
  (audio/video flows)
         ↓
     [ENDED]
  (call terminated)

```

## Error Handling Strategy

### Custom Exceptions

```dart
// Base class
class AuthException implements Exception {
  final String message;
}

// Specific exceptions
class WeakPasswordException extends AuthException
class UserNotFoundException extends AuthException
class EmailAlreadyExistsException extends AuthException
```

### Error Flow

```
Service layer detects error
         ↓
Throws custom exception
         ↓
Provider catches and stores error
         ↓
Provider notifies listeners
         ↓
Screen displays user-friendly message
         ↓
User can retry or go back
```

## How to Extend

### Adding a New Feature (e.g., Block User)

1. **Add to UserModel**: `List<String> blockedUserIds`
2. **Add to UserService**: `blockUser(userId)` method
3. **Add to UserProvider**: `blockUser()` method
4. **Add to ContactsScreen**: Block button in tile
5. **Filter in Service**: Exclude blocked users from list

### Adding Push Notifications

1. **Add NotificationService**: Handle Firebase Cloud Messaging
2. **Initialize in main()**: `await NotificationService().initialize()`
3. **Trigger from CallService**: Send notification when call received
4. **Handle in UI**: Navigate to incoming call screen

## Performance Considerations

### Widget Rebuilds
- Only use `Consumer` widgets that need to rebuild
- Use `context.read()` when you don't need to rebuild
- Avoid watching entire provider if only one field changes

### Memory Management
- All StreamSubscriptions disposed in providers
- Controllers cancelled in dispose()
- Large lists are filtered, not loaded entirely

### Network Optimization
- Firestore queries use proper pagination
- Agora uses optimal video codec settings
- Background tasks properly managed

## Security

### Data Protection
- User passwords never stored in app
- Firebase Security Rules enforce access control
- Calls encrypted by Agora

### Secrets Management
- API keys in constants file
- Not committed to git (.gitignore)
- Deployed via environment variables in production

## Future Architecture Decisions

### If Adding Group Calling
- Extend CallModel to support multiple participants
- Modify call channel naming to support groups
- Add participant management in UI

### If Adding End-to-End Encryption
- Integrate TweetNaCl or equivalent
- Encrypt payloads before sending to Firestore
- Decrypt on receive

### If Adding Offline Mode
- Implement local SQLite database
- Sync with Firestore when online
- Handle conflicts gracefully

---

*This architecture has been validated for the assignment requirements and can scale beyond the initial 1-to-1 calling feature.*