package com.github.piasy.webrtcdatachannel;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.util.HashMap;
import java.util.Map;
import org.appspot.apprtc.AppRTCClient;
import org.appspot.apprtc.WebSocketRTCClient;
import org.webrtc.IceCandidate;
import org.webrtc.PeerConnection;
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
    public static final String METHOD_DISCONNECT = "disconnect";

    public static final int EVENT_TYPE_SIGNALING_STATE = 1;
    public static final int EVENT_TYPE_ICE_STATE = 2;
    public static final int EVENT_TYPE_MESSAGE = 3;

    public static final int SIGNALING_STATE_DISCONNECTED = 0;
    public static final int SIGNALING_STATE_CONNECTED = 2;

    private final Registrar mRegistrar;

    private AppRTCClient mAppRTCClient;
    private DataChannelPeerConnectionClient mConnectionClient;
    private boolean mInitiator;

    private volatile EventChannel.EventSink mEventSink;

    public WebrtcDataChannelPlugin(final Registrar registrar) {
        mRegistrar = registrar;
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
                result.success(0);
                break;
            case METHOD_SEND_MESSAGE:
                sendMessage(call.argument("message"));
                result.success(0);
                break;
            case METHOD_DISCONNECT:
                disconnect();
                result.success(0);
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
        mConnectionClient = new DataChannelPeerConnectionClient(mRegistrar.context());
        mConnectionClient.createPcFactory();
        mAppRTCClient = new WebSocketRTCClient(this);

        AppRTCClient.RoomConnectionParameters params = new AppRTCClient.RoomConnectionParameters(
                roomUrl, roomId, false, "");
        mAppRTCClient.connectToRoom(params);
    }

    public void sendMessage(String message) {
        DataChannelPeerConnectionClient connectionClient = mConnectionClient;
        if (connectionClient != null) {
            connectionClient.sendMessage(message);
        }
    }

    public void disconnect() {
        AppRTCClient appRTCClient = mAppRTCClient;
        if (appRTCClient != null) {
            appRTCClient.disconnectFromRoom();
        }
        mAppRTCClient = null;

        DataChannelPeerConnectionClient connectionClient = mConnectionClient;
        if (connectionClient != null) {
            connectionClient.close();
        }
        mConnectionClient = null;
    }

    @Override
    public void onConnectedToRoom(AppRTCClient.SignalingParameters params) {
        DataChannelPeerConnectionClient connectionClient = mConnectionClient;
        if (connectionClient == null) {
            return;
        }

        notifyEvent(EVENT_TYPE_SIGNALING_STATE, "state", SIGNALING_STATE_CONNECTED);

        mInitiator = params.initiator;
        connectionClient.createPc(params, this);

        if (params.initiator) {
            connectionClient.createOffer();
        } else {
            if (params.offerSdp != null) {
                connectionClient.setRemoteDescription(params.offerSdp);
                // Create answer. Answer SDP will be sent to offering client in
                // PeerConnectionEvents.onLocalDescription event.
                connectionClient.createAnswer();
            }
            if (params.iceCandidates != null) {
                // Add remote ICE candidates from room.
                for (IceCandidate iceCandidate : params.iceCandidates) {
                    connectionClient.addRemoteIceCandidate(iceCandidate);
                }
            }
        }
    }

    @Override
    public void onRemoteDescription(SessionDescription sdp) {
        DataChannelPeerConnectionClient connectionClient = mConnectionClient;
        if (connectionClient == null) {
            return;
        }

        connectionClient.setRemoteDescription(sdp);
        if (!mInitiator) {
            connectionClient.createAnswer();
        }
    }

    @Override
    public void onRemoteIceCandidate(IceCandidate candidate) {
        DataChannelPeerConnectionClient connectionClient = mConnectionClient;
        if (connectionClient != null) {
            connectionClient.addRemoteIceCandidate(candidate);
        }
    }

    @Override
    public void onRemoteIceCandidatesRemoved(IceCandidate[] candidates) {
    }

    @Override
    public void onChannelClose() {
        disconnect();
    }

    @Override
    public void onChannelError(String description) {
        notifyError(description);
    }

    @Override
    public void onLocalDescription(SessionDescription sdp) {
        AppRTCClient appRTCClient = mAppRTCClient;
        if (appRTCClient != null) {
            if (mInitiator) {
                appRTCClient.sendOfferSdp(sdp);
            } else {
                appRTCClient.sendAnswerSdp(sdp);
            }
        }
    }

    @Override
    public void onIceCandidate(IceCandidate candidate) {
        AppRTCClient appRTCClient = mAppRTCClient;
        if (appRTCClient != null) {
            appRTCClient.sendLocalIceCandidate(candidate);
        }
    }

    @Override
    public void onIceCandidatesRemoved(IceCandidate[] candidates) {
    }

    @Override
    public void onIceConnected() {
        notifyEvent(EVENT_TYPE_ICE_STATE, "state",
                PeerConnection.IceConnectionState.CONNECTED.ordinal());
    }

    @Override
    public void onIceDisconnected() {
        notifyEvent(EVENT_TYPE_ICE_STATE, "state",
                PeerConnection.IceConnectionState.DISCONNECTED.ordinal());
    }

    @Override
    public void onPeerConnectionClosed() {
        notifyEvent(EVENT_TYPE_SIGNALING_STATE, "state", SIGNALING_STATE_DISCONNECTED);
    }

    @Override
    public void onPeerConnectionStatsReady(StatsReport[] reports) {
    }

    @Override
    public void onPeerConnectionError(String description) {
        notifyError(description);
    }

    @Override
    public void onMessage(String message) {
        notifyEvent(EVENT_TYPE_MESSAGE, "message", message);
    }

    private void notifyEvent(int type, String key, Object value) {
        EventChannel.EventSink eventSink = mEventSink;
        if (eventSink != null) {
            Map<String, Object> event = new HashMap<>();
            event.put("type", type);
            event.put(key, value);
            eventSink.success(event);
        }
    }

    private void notifyError(String error) {
        EventChannel.EventSink eventSink = mEventSink;
        if (eventSink != null) {
            eventSink.error("", error, null);
            eventSink.endOfStream();
        }
    }
}
