import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

const kLocalExtension = '1000';
const kLocalPassword   = 'zyvr_local_pass';
const kSipWssUrl       = 'ws://127.0.0.1:8090/asterisk/sip';
const kSipDomain       = '127.0.0.1';

enum SipCallState { idle, ringing, incoming, active, ended }

class SipService extends ChangeNotifier implements SipUaHelperListener {
  final SIPUAHelper _helper = SIPUAHelper();

  bool isRegistered = false;
  bool _isStarting = false;
  SipCallState callState = SipCallState.idle;
  String? callerId;
  bool isMuted = false;
  bool isSpeaker = false;

  Call? _session;

  SipService() {
    _helper.addSipUaHelperListener(this);
  }

  // ---------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------

  void register() {
    if (_isStarting || isRegistered) return;
    _isStarting = true;
    final settings = UaSettings();
    settings.webSocketUrl = kSipWssUrl;
    settings.webSocketSettings.allowBadCertificate = true;
    settings.uri = 'sip:$kLocalExtension@$kSipDomain';
    settings.authorizationUser = kLocalExtension;
    settings.password = kLocalPassword;
    settings.displayName = 'Zyvr';
    settings.userAgent = 'Zyvr/1.0';
    _helper.start(settings).catchError((e) {
      debugPrint('SIP start failed: $e');
      _isStarting = false;
    });
  }

  void unregister() {
    _isStarting = false;
    _helper.stop();
  }

  // ---------------------------------------------------------------------------
  // Call control
  // ---------------------------------------------------------------------------

  void call(String ext) {
    _helper.call('sip:$ext@$kSipDomain', voiceOnly: true);
  }

  void answer() {
    _session?.answer(_helper.buildCallOptions());
  }

  void hangup() => _session?.hangup();

  void toggleMute() {
    if (_session == null) return;
    isMuted = !isMuted;
    if (isMuted) {
      _session!.mute();
    } else {
      _session!.unmute();
    }
    notifyListeners();
  }

  void toggleSpeaker() {
    isSpeaker = !isSpeaker;
    Helper.setSpeakerphoneOn(isSpeaker);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // SipUaHelperListener callbacks
  // ---------------------------------------------------------------------------

  @override
  void callStateChanged(Call call, CallState state) {
    _session = call;
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        if (call.direction == 'INCOMING') {
          callState = SipCallState.incoming;
          callerId = call.remote_identity;
        } else {
          callState = SipCallState.ringing;
        }
      case CallStateEnum.PROGRESS:
        callState = SipCallState.ringing;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        callState = SipCallState.active;
        isMuted = false;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        callState = SipCallState.idle;
        _session = null;
        callerId = null;
        isMuted = false;
        isSpeaker = false;
        _isStarting = false;
      default:
        break;
    }
    notifyListeners();
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    isRegistered = state.state == RegistrationStateEnum.REGISTERED;
    if (state.state == RegistrationStateEnum.REGISTERED) {
      _isStarting = false;
    } else if (state.state == RegistrationStateEnum.UNREGISTERED ||
               state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      _isStarting = false;
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void dispose() {
    _helper.removeSipUaHelperListener(this);
    super.dispose();
  }
}
