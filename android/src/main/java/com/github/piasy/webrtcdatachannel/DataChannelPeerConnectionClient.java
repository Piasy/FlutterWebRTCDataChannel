package com.github.piasy.webrtcdatachannel;

import android.content.Context;
import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.LinkedList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.appspot.apprtc.AppRTCClient;
import org.appspot.apprtc.PeerConnectionClient;
import org.webrtc.DataChannel;
import org.webrtc.IceCandidate;
import org.webrtc.Logging;
import org.webrtc.MediaConstraints;
import org.webrtc.MediaStream;
import org.webrtc.PeerConnection;
import org.webrtc.PeerConnectionFactory;
import org.webrtc.RtpReceiver;
import org.webrtc.SdpObserver;
import org.webrtc.SessionDescription;

/**
 * Created by Piasy{github.com/Piasy} on 14/08/2017.
 */
public class DataChannelPeerConnectionClient
        implements PeerConnection.Observer, DataChannel.Observer, SdpObserver {
    private static final String TAG = "DataChannelPeerConnectionClient";

    private final ExecutorService mExecutor;
    private final Context mAppContext;

    private Events mEvents;
    private boolean mIsInitiator;
    private LinkedList<IceCandidate> mQueuedRemoteCandidates;

    private PeerConnectionFactory mPeerConnectionFactory;
    private PeerConnection mPeerConnection;
    private DataChannel mDataChannel;
    private MediaConstraints mSdpConstraints;
    private SessionDescription mLocalSdp;

    public DataChannelPeerConnectionClient(Context appContext) {
        mAppContext = appContext;
        mExecutor = Executors.newSingleThreadExecutor();
    }

    public void createPcFactory() {
        mExecutor.execute(this::createPcFactoryInternal);
    }

    public void createPc(AppRTCClient.SignalingParameters params, Events events) {
        mEvents = events;
        mExecutor.execute(() -> createPcInternal(params));
    }

    public void createOffer() {
        mExecutor.execute(() -> {
            Logging.d(TAG, "createOffer");
            mIsInitiator = true;
            mPeerConnection.createOffer(DataChannelPeerConnectionClient.this, mSdpConstraints);
        });
    }

    public void setRemoteDescription(SessionDescription sdp) {
        mExecutor.execute(() -> {
            Logging.d(TAG, "setRemoteDescription " + sdp);
            mPeerConnection.setRemoteDescription(DataChannelPeerConnectionClient.this, sdp);
        });
    }

    public void createAnswer() {
        mExecutor.execute(() -> {
            Logging.d(TAG, "createAnswer");
            mIsInitiator = false;
            mPeerConnection.createAnswer(DataChannelPeerConnectionClient.this, mSdpConstraints);
        });
    }

    public void addRemoteIceCandidate(IceCandidate iceCandidate) {
        mExecutor.execute(() -> {
            if (mPeerConnection != null) {
                if (mQueuedRemoteCandidates != null) {
                    mQueuedRemoteCandidates.add(iceCandidate);
                } else {
                    mPeerConnection.addIceCandidate(iceCandidate);
                }
            }
        });
    }

    public void sendMessage(String message) {
        Logging.d(TAG, "sendMessage " + message);
        mExecutor.execute(() -> sendMessageInternal(message));
    }

    public void close() {
        mExecutor.execute(this::closeInternal);
    }

    private void closeInternal() {
        if (mDataChannel != null) {
            mDataChannel.dispose();
            mDataChannel = null;
        }
        if (mPeerConnection != null) {
            mPeerConnection.dispose();
            mPeerConnection = null;
        }
        if (mPeerConnectionFactory != null) {
            mPeerConnectionFactory.dispose();
            mPeerConnectionFactory = null;
        }
        Logging.d(TAG, "Closing peer connection done.");
        mEvents.onPeerConnectionClosed();
        mEvents = null;
    }

    private void createPcFactoryInternal() {
        PeerConnectionFactory.initialize(
                PeerConnectionFactory.InitializationOptions.builder(mAppContext)
                        .setEnableInternalTracer(true)
                        .createInitializationOptions());
        mPeerConnectionFactory = PeerConnectionFactory.builder()
                .createPeerConnectionFactory();
    }

    private void createPcInternal(AppRTCClient.SignalingParameters params) {
        mQueuedRemoteCandidates = new LinkedList<>();

        PeerConnection.RTCConfiguration rtcConfig =
                new PeerConnection.RTCConfiguration(params.iceServers);
        // TCP candidates are only useful when connecting to a server that supports
        // ICE-TCP.
        rtcConfig.tcpCandidatePolicy = PeerConnection.TcpCandidatePolicy.DISABLED;
        rtcConfig.bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE;
        rtcConfig.rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE;
        rtcConfig.continualGatheringPolicy
                = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY;
        // Use ECDSA encryption.
        rtcConfig.keyType = PeerConnection.KeyType.ECDSA;

        mPeerConnection = mPeerConnectionFactory.createPeerConnection(rtcConfig, this);

        DataChannel.Init init = new DataChannel.Init();
        init.ordered = true;
        init.negotiated = false;
        init.maxRetransmits = -1;
        init.maxRetransmitTimeMs = -1;
        init.id = 0;
        mDataChannel = mPeerConnection.createDataChannel("P2P MSG DC", init);
        mDataChannel.registerObserver(this);

        mSdpConstraints = new MediaConstraints();
        mSdpConstraints.mandatory.add(
                new MediaConstraints.KeyValuePair("OfferToReceiveVideo", "false"));
    }

    private void sendMessageInternal(String message) {
        byte[] msg = message.getBytes();
        DataChannel.Buffer buffer = new DataChannel.Buffer(ByteBuffer.wrap(msg), false);
        mDataChannel.send(buffer);
    }

    private void drainIceCandidates() {
        if (mQueuedRemoteCandidates != null) {
            Logging.d(TAG, "Add " + mQueuedRemoteCandidates.size() + " remote candidates");
            for (IceCandidate candidate : mQueuedRemoteCandidates) {
                mPeerConnection.addIceCandidate(candidate);
            }
            mQueuedRemoteCandidates = null;
        }
    }

    @Override
    public void onSignalingChange(PeerConnection.SignalingState newState) {
        Logging.d(TAG, "onSignalingChange " + newState);
    }

    @Override
    public void onIceConnectionChange(PeerConnection.IceConnectionState newState) {
        Logging.d(TAG, "onIceConnectionChange " + newState);
    }

    @Override
    public void onIceConnectionReceivingChange(boolean receiving) {
        Logging.d(TAG, "onIceConnectionReceivingChange " + receiving);
    }

    @Override
    public void onIceGatheringChange(PeerConnection.IceGatheringState newState) {
        Logging.d(TAG, "onIceGatheringChange " + newState);
    }

    @Override
    public void onIceCandidate(IceCandidate candidate) {
        Logging.d(TAG, "onIceCandidate " + candidate);
        mEvents.onIceCandidate(candidate);
    }

    @Override
    public void onIceCandidatesRemoved(IceCandidate[] candidates) {
        Logging.d(TAG, "onIceCandidatesRemoved " + Arrays.toString(candidates));
    }

    @Override
    public void onAddStream(MediaStream stream) {
        Logging.d(TAG, "onAddStream " + stream);
    }

    @Override
    public void onRemoveStream(MediaStream stream) {
        Logging.d(TAG, "onRemoveStream " + stream);
    }

    @Override
    public void onDataChannel(DataChannel dataChannel) {
        Logging.d(TAG, "onDataChannel " + dataChannel);
    }

    @Override
    public void onRenegotiationNeeded() {
        Logging.d(TAG, "onRenegotiationNeeded");
    }

    @Override
    public void onAddTrack(RtpReceiver receiver, MediaStream[] mediaStreams) {
        Logging.d(TAG, "onAddTrack");
    }

    @Override
    public void onBufferedAmountChange(long previousAmount) {
        Logging.d(TAG, "onBufferedAmountChange");
    }

    @Override
    public void onStateChange() {
        Logging.d(TAG, "onStateChange");
    }

    @Override
    public void onMessage(DataChannel.Buffer buffer) {
        ByteBuffer data = buffer.data;
        final byte[] bytes = new byte[data.capacity()];
        data.get(bytes);
        String msg = new String(bytes);
        Logging.d(TAG, "onMessage " + msg);
        mEvents.onMessage(msg);
    }

    @Override
    public void onCreateSuccess(SessionDescription sdp) {
        Logging.d(TAG, "onCreateSuccess " + sdp);
        mExecutor.execute(() -> {
            mLocalSdp = sdp;
            Logging.d(TAG, "setLocalDescription " + sdp);
            mPeerConnection.setLocalDescription(DataChannelPeerConnectionClient.this, sdp);
        });
    }

    @Override
    public void onSetSuccess() {
        Logging.d(TAG, "onSetSuccess");

        mExecutor.execute(() -> {
            if (mIsInitiator) {
                if (mPeerConnection.getRemoteDescription() == null) {
                    mEvents.onLocalDescription(mLocalSdp);
                } else {
                    drainIceCandidates();
                }
            } else {
                if (mPeerConnection.getLocalDescription() != null) {
                    mEvents.onLocalDescription(mLocalSdp);
                    drainIceCandidates();
                }
            }
        });
    }

    @Override
    public void onCreateFailure(String error) {
    }

    @Override
    public void onSetFailure(String error) {
    }

    public interface Events extends PeerConnectionClient.PeerConnectionEvents {
        void onMessage(String message);
    }
}
