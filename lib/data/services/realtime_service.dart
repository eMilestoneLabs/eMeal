import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';

/// Connection lifecycle state for the realtime socket.
enum RealtimeConnectionState { disconnected, connecting, connected }

/// A single server→client realtime frame.
///
/// [name] is one of the `.v1` event names in [RealtimeEvents]; [data] is the
/// decoded JSON payload (always a `Map<String, dynamic>`, empty when the server
/// emits a bare event).
@immutable
class RealtimeMessage {
  const RealtimeMessage(this.name, this.data);

  final String name;
  final Map<String, dynamic> data;

  @override
  String toString() => 'RealtimeMessage($name, $data)';
}

// ── RealtimeService ─────────────────────────────────────────────────────────────

/// Socket.IO client for the eMeal backend's realtime gateway (Phase B10/B7).
///
/// ## Contract (locked — mirrors `attendance.gateway.ts`)
///
/// - Namespace `/`, transports `websocket` (falls back to polling server-side).
/// - JWT is sent in the **handshake `auth.token`** field — exactly where
///   `WsJwtGuard.validateConnection` reads it.
/// - On connect the server auto-joins `user:{id}`, `organization:{orgId}`, and
///   `admin:{orgId}` (admins). Group rooms are opt-in via [joinGroup].
/// - Server→client events are versioned (`*.v1`) and additive-safe; subscribe
///   through the broadcast [events] stream or the filtered [on] helper.
///
/// ## Usage
///
/// ```dart
/// final rt = RealtimeService.instance;
/// await rt.connect();                       // after a successful login
/// rt.joinGroup(groupId);                    // when entering a group screen
///
/// final sub = rt.on(RealtimeEvents.attendanceMarked).listen((msg) {
///   // refresh today's attendance view from msg.data
/// });
/// // ...
/// await sub.cancel();
/// rt.leaveGroup(groupId);
/// await rt.disconnect();                     // on logout
/// ```
class RealtimeService with WidgetsBindingObserver {
  RealtimeService._();

  /// App-wide singleton — mirrors the `DioApiService.instance` pattern.
  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;

  final StreamController<RealtimeMessage> _controller =
      StreamController<RealtimeMessage>.broadcast();

  /// Observable connection state — drive reconnect banners / live indicators.
  final ValueNotifier<RealtimeConnectionState> connectionState =
      ValueNotifier<RealtimeConnectionState>(
    RealtimeConnectionState.disconnected,
  );

  /// Group rooms we want to be in. Re-joined automatically after a reconnect.
  final Set<String> _joinedGroups = <String>{};

  Timer? _heartbeat;

  /// Battery: true while the socket is intentionally down because the app is
  /// backgrounded (see [didChangeAppLifecycleState]). Distinct from a logout
  /// [disconnect] — group rooms are preserved for the resume reconnect.
  bool _pausedByLifecycle = false;
  bool _observerRegistered = false;

  /// True once the underlying socket reports a live connection.
  bool get isConnected =>
      connectionState.value == RealtimeConnectionState.connected;

  /// Broadcast stream of every known server→client event.
  Stream<RealtimeMessage> get events => _controller.stream;

  /// Filtered stream for a single [eventName] (use the [RealtimeEvents] consts).
  Stream<RealtimeMessage> on(String eventName) =>
      _controller.stream.where((m) => m.name == eventName);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Opens the socket using the stored JWT. Safe to call repeatedly — a live
  /// socket is reused. No-op when no valid session exists.
  Future<void> connect() async {
    // Battery: pause/resume the socket with the APP lifecycle — an open
    // websocket + 25s heartbeat in the background is pure battery drain (FCM
    // push covers background delivery; realtime events only refresh visible
    // UI). Registered once for the app-lifetime singleton.
    if (!_observerRegistered) {
      _observerRegistered = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _pausedByLifecycle = false;
    if (_socket != null && _socket!.connected) return;

    final session = await AuthStorageService.instance.loadSession();
    if (session == null || !session.isValid) {
      // No usable token — nothing to authenticate the handshake with.
      return;
    }

    // Tear down any half-open socket before building a fresh one.
    _disposeSocket();

    connectionState.value = RealtimeConnectionState.connecting;

    final socket = io.io(
      EnvConfig.current.wsBaseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setAuth(<String, dynamic>{'token': session.accessToken})
          .build(),
    );

    _bindCoreHandlers(socket);
    _bindEventHandlers(socket);

    _socket = socket;
    socket.connect();
  }

  /// Closes the socket and clears tracked group rooms. Call on logout.
  Future<void> disconnect() async {
    _joinedGroups.clear();
    _stopHeartbeat();
    _disposeSocket();
    connectionState.value = RealtimeConnectionState.disconnected;
  }

  /// Refreshes the handshake token from storage and reconnects. Use after a
  /// token rotation if the server has dropped the socket with an auth error.
  Future<void> reconnectWithFreshToken() async {
    await disconnect();
    await connect();
  }

  /// Battery: tear the socket down while backgrounded, restore it on resume.
  /// Only `paused`/`resumed` are acted on — `inactive`/`hidden` fire for
  /// dialogs and the notification shade and must not thrash the connection.
  /// Rooms are preserved; [connect]'s onConnect handler re-joins them.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_socket != null) {
          _pausedByLifecycle = true;
          _stopHeartbeat();
          _disposeSocket();
          connectionState.value = RealtimeConnectionState.disconnected;
          _log('paused (app backgrounded)');
        }
      case AppLifecycleState.resumed:
        if (_pausedByLifecycle) {
          _log('resuming socket after background');
          unawaited(connect()); // clears _pausedByLifecycle, re-joins rooms
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ── Rooms ──────────────────────────────────────────────────────────────────

  /// Joins the `group:{groupId}` room (server validates org + membership).
  /// Remembered so it is re-joined automatically after any reconnect.
  void joinGroup(String groupId) {
    if (groupId.isEmpty) return;
    _joinedGroups.add(groupId);
    _socket?.emit(RealtimeEvents.joinGroup, <String, dynamic>{
      'groupId': groupId,
    });
  }

  /// Leaves a previously joined `group:{groupId}` room.
  void leaveGroup(String groupId) {
    if (groupId.isEmpty) return;
    _joinedGroups.remove(groupId);
    _socket?.emit(RealtimeEvents.leaveGroup, <String, dynamic>{
      'groupId': groupId,
    });
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  void _bindCoreHandlers(io.Socket socket) {
    socket.onConnect((_) {
      connectionState.value = RealtimeConnectionState.connected;
      _log('connected');
      // Re-join any rooms requested before/while disconnected.
      for (final groupId in _joinedGroups) {
        socket.emit(RealtimeEvents.joinGroup, <String, dynamic>{
          'groupId': groupId,
        });
      }
      _startHeartbeat();
    });

    socket.onReconnect((_) {
      connectionState.value = RealtimeConnectionState.connected;
      _log('reconnected');
    });

    socket.onReconnectAttempt((_) {
      connectionState.value = RealtimeConnectionState.connecting;
    });

    socket.onDisconnect((_) {
      connectionState.value = RealtimeConnectionState.disconnected;
      _stopHeartbeat();
      _log('disconnected');
    });

    socket.onConnectError((err) => _log('connect_error: $err'));
    socket.onError((err) => _log('error: $err'));
  }

  void _bindEventHandlers(io.Socket socket) {
    for (final name in RealtimeEvents.all) {
      socket.on(name, (data) => _emit(name, data));
    }
    // Server error frames (rate-limit, etc.) — surfaced under the same stream.
    socket.on(RealtimeEvents.error, (data) => _emit(RealtimeEvents.error, data));
  }

  void _emit(String name, dynamic data) {
    if (_controller.isClosed) return;
    _controller.add(RealtimeMessage(name, _asMap(data)));
  }

  /// Normalises a socket payload into a `Map<String, dynamic>`.
  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data == null) return const <String, dynamic>{};
    return <String, dynamic>{'value': data};
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _socket?.emit(RealtimeEvents.ping, <String, dynamic>{
        'clientTime': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _disposeSocket() {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.clearListeners();
      socket.dispose();
    } catch (_) {
      // Disposing a never-connected socket can throw — ignore.
    }
    _socket = null;
  }

  void _log(String message) {
    if (EnvConfig.current.enableVerboseLogging) {
      debugPrint('[RealtimeService] $message');
    }
  }
}
