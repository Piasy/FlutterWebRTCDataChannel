package com.github.piasy.webrtcdatachannel;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import org.appspot.apprtc.AppRTCClient;
import org.appspot.apprtc.WebSocketRTCClient;
import org.webrtc.IceCandidate;
import org.webrtc.SessionDescription;
import org.webrtc.StatsReport;

/**
 * WebrtcDataChannelPlugin
 */
public class WebrtcDataChannelPlugin
        implements MethodCallHandler, EventChannel.StreamHandler, AppRTCClient.SignalingEvents,
        DataChannelPeerConnectionClient.Events {

    public static final String METHOD_CHANNEL_NAME = "com.github.piasy/webrtc_data_channel.method";
    public static final String EVENT_CHANNEL_NAME = "com.github.piasy/webrtc_data_channel.event";

    public static final String METHOD_CONNECT_TO_ROOM = "connectToRoom";
    public static final String METHOD_SEND_MESSAGE = "sendMessage";

    private final AppRTCClient mAppRTCClient;
    private final DataChannelPeerConnectionClient mConnectionClient;
    private final Registrar mRegistrar;

    private boolean mInitiator;

    private volatile EventChannel.EventSink mEventSink;

    public WebrtcDataChannelPlugin(final Registrar registrar) {
        mRegistrar = registrar;

        mConnectionClient = new DataChannelPeerConnectionClient(mRegistrar.context());
        mConnectionClient.createPcFactory();

        mAppRTCClient = new WebSocketRTCClient(this);
    }

    /**
     * Plugin registration.
     */
    public static void registerWith(Registrar registrar) {
        WebrtcDataChannelPlugin plugin = new WebrtcDataChannelPlugin(registrar);
        new MethodChannel(registrar.messenger(), METHOD_CHANNEL_NAME)
                .setMethodCallHandler(plugin);
        new EventChannel(registrar.messenger(), EVENT_CHANNEL_NAME)
                .setStreamHandler(plugin);
    }

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        switch (call.method) {
            case METHOD_CONNECT_TO_ROOM:
                connectToRoom(call.argument("roomUrl"), call.argument("roomId"));
                result.success(true);
                break;
            case METHOD_SEND_MESSAGE:
                sendMessage(call.argument("message"));
                result.success(true);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    @Override
    public void onListen(final Object arguments, final EventChannel.EventSink events) {
        mEventSink = events;
    }

    @Override
    public void onCancel(final Object arguments) {
        mEventSink = null;
    }

    public void connectToRoom(String roomUrl, String roomId) {
        AppRTCClient.RoomConnectionParameters params = new AppRTCClient.RoomConnectionParameters(
                roomUrl, roomId, false, "");
        mAppRTCClient.connectToRoom(params);
    }

    public void sendMessage(String message) {
        mConnectionClient.sendMessage(message);
    }

    @Override
    public void onMessage(String message) {
        EventChannel.EventSink eventSink = mEventSink;
        if (eventSink != null) {
            eventSink.success(message);
        }
    }

    @Override
    public void onConnectedToRoom(AppRTCClient.SignalingParameters params) {
        mInitiator = params.initiator;
        mConnectionClient.createPc(params, this);

        if (params.initiator) {
            mConnectionClient.createOffer();
        } else {
            if (params.offerSdp != null) {
                mConnectionClient.setRemoteDescription(params.offerSdp);
                // Create answer. Answer SDP will be sent to offering client in
                // PeerConnectionEvents.onLocalDescription event.
                mConnectionClient.createAnswer();
            }
            if (params.iceCandidates != null) {
                // Add remote ICE candidates from room.
                for (IceCandidate iceCandidate : params.iceCandidates) {
                    mConnectionClient.addRemoteIceCandidate(iceCandidate);
                }
            }
        }
    }

    @Override
    public void onRemoteDescription(SessionDescription sdp) {
        mConnectionClient.setRemoteDescription(sdp);
        if (!mInitiator) {
            mConnectionClient.createAnswer();
        }
    }

    @Override
    public void onRemoteIceCandidate(IceCandidate candidate) {
        mConnectionClient.addRemoteIceCandidate(candidate);
    }

    @Override
    public void onRemoteIceCandidatesRemoved(IceCandidate[] candidates) {
    }

    @Override
    public void onChannelClose() {
    }

    @Override
    public void onChannelError(String description) {
    }

    @Override
    public void onLocalDescription(SessionDescription sdp) {
        if (mInitiator) {
            mAppRTCClient.sendOfferSdp(sdp);
        } else {
            mAppRTCClient.sendAnswerSdp(sdp);
        }
    }

    @Override
    public void onIceCandidate(IceCandidate candidate) {
        mAppRTCClient.sendLocalIceCandidate(candidate);
    }

    @Override
    public void onIceCandidatesRemoved(IceCandidate[] candidates) {
    }

    @Override
    public void onIceConnected() {
    }

    @Override
    public void onIceDisconnected() {
    }

    @Override
    public void onPeerConnectionClosed() {
    }

    @Override
    public void onPeerConnectionStatsReady(StatsReport[] reports) {
    }

    @Override
    public void onPeerConnectionError(String description) {
    }
}
