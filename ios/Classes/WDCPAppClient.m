/*
 *  Copyright 2014 The WebRTC Project Authors. All rights reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import "WDCPAppClient.h"

#import "WebRTC/RTCPeerConnection.h"
#import "WebRTC/RTCConfiguration.h"
#import "WebRTC/RTCFileLogger.h"
#import "WebRTC/RTCIceServer.h"
#import "WebRTC/RTCLogging.h"
#import "WebRTC/RTCMediaConstraints.h"
#import "WebRTC/RTCPeerConnectionFactory.h"
#import "WebRTC/RTCVideoCodecFactory.h"
#import "WebRTC/RTCTracing.h"
#import "WebRTC/RTCDataChannelConfiguration.h"

#import "ARDAppEngineClient.h"
#import "ARDJoinResponse.h"
#import "ARDMessageResponse.h"
#import "ARDSignalingMessage.h"
#import "ARDTURNClient.h"
#import "ARDUtilities.h"
#import "ARDWebSocketChannel.h"
#import "RTCIceCandidate+JSON.h"
#import "RTCSessionDescription+JSON.h"
#import "ARDTimerProxy.h"
#import "ARDRoomServerClient.h"
#import "ARDTURNClient.h"

static NSString* const kWDCPAppClientErrorDomain = @"WDCPAppClient";
static NSInteger const kWDCPAppClientErrorUnknown = -1;
static NSInteger const kWDCPAppClientErrorRoomFull = -2;
static NSInteger const kWDCPAppClientErrorCreateSDP = -3;
static NSInteger const kWDCPAppClientErrorSetSDP = -4;
static NSInteger const kWDCPAppClientErrorInvalidClient = -5;
static NSInteger const kWDCPAppClientErrorInvalidRoom = -6;

static BOOL const kWDCPAppClientEnableTracing = NO;
static BOOL const kWDCPAppClientEnableRtcEventLog = YES;
static int64_t const kWDCPAppClientRtcEventLogMaxSizeInBytes = 5e6;  // 5 MB.

@implementation WDCPAppClient {
    RTCFileLogger* _fileLogger;
    ARDTimerProxy* _statsTimer;

    id<WDCPAppClientDelegate> _delegate;
    WDCPAppClientState _state;

    id<ARDRoomServerClient> _roomServerClient;
    id<ARDSignalingChannel> _channel;
    ARDTURNClient* _turnClient;

    RTCPeerConnection* _peerConnection;
    RTCPeerConnectionFactory* _factory;
    RTCDataChannel* _dataChannel;
    NSMutableArray* _messageQueue;

    BOOL _isTurnComplete;
    BOOL _hasReceivedSdp;
    BOOL _hasJoinedRoomServerRoom;

    NSString* _roomUrl;
    NSString* _roomId;
    NSString* _clientId;
    BOOL _isInitiator;
    NSMutableArray* _iceServers;
    NSURL* _websocketURL;
    NSURL* _websocketRestURL;

    RTCMediaConstraints* _defaultPeerConnectionConstraints;
}

- (instancetype)initWithDelegate:(id<WDCPAppClientDelegate>)delegate {
    if (self = [super init]) {
        _delegate = delegate;
        
        _roomServerClient = [[ARDAppEngineClient alloc] init];
        _turnClient = [[ARDTURNClient alloc] init];
        _messageQueue = [NSMutableArray array];
        _iceServers = [NSMutableArray array];
        
        _fileLogger = [[RTCFileLogger alloc] init];
        [_fileLogger start];
    }
    return self;
}

- (void)dealloc {
    [self disconnect];
}

- (void)connectToRoomWithRoomUrl:(NSString*)roomUrl roomId:(NSString*)roomId {
    NSParameterAssert(roomUrl.length);
    NSParameterAssert(roomId.length);
    NSParameterAssert(_state == kWDCPAppClientStateDisconnected);

    [self setState:kWDCPAppClientStateConnecting];
    _roomUrl = roomUrl;
    _roomId = roomId;

      RTCDefaultVideoDecoderFactory *decoderFactory = [[RTCDefaultVideoDecoderFactory alloc] init];
      RTCDefaultVideoEncoderFactory *encoderFactory = [[RTCDefaultVideoEncoderFactory alloc] init];
      _factory = [[RTCPeerConnectionFactory alloc] initWithEncoderFactory:encoderFactory
                                                           decoderFactory:decoderFactory];

    if (kWDCPAppClientEnableTracing) {
        NSString* filePath =
            [self documentsFilePathForFileName:@"webrtc-trace.txt"];
        RTCStartInternalCapture(filePath);
    }

    // Join room on room server.
    __weak WDCPAppClient* weakSelf = self;
    [_roomServerClient
        joinRoomWithRoomUrl:roomUrl
                     roomId:roomId
          completionHandler:^(ARDJoinResponse* response, NSError* error) {
              WDCPAppClient* strongSelf = weakSelf;
              if (error) {
                  [strongSelf->_delegate appClient:strongSelf didError:error];
                  return;
              }
              NSError* joinError =
                  [[strongSelf class] errorForJoinResultType:response.result];
              if (joinError) {
                  RTCLogError(@"Failed to join room:%@ on room server.",
                              roomId);
                  [strongSelf disconnect];
                  [strongSelf->_delegate appClient:strongSelf
                                          didError:joinError];
                  return;
              }
              RTCLog(@"Joined room:%@ on room server.", roomId);
              strongSelf->_clientId = response.clientId;
              strongSelf->_isInitiator = response.isInitiator;
              for (ARDSignalingMessage* message in response.messages) {
                  if (message.type == kARDSignalingMessageTypeOffer ||
                      message.type == kARDSignalingMessageTypeAnswer) {
                      strongSelf->_hasReceivedSdp = YES;
                      [strongSelf->_messageQueue insertObject:message
                                                      atIndex:0];
                  } else {
                      [strongSelf->_messageQueue addObject:message];
                  }
              }
              strongSelf->_websocketURL = response.webSocketURL;
              strongSelf->_websocketRestURL = response.webSocketRestURL;
              [strongSelf registerWithColliderIfReady];
              [strongSelf requestTurn:response.iceServerURL];
          }];
}

- (void)sendMessage:(NSString*)message {
    RTCDataBuffer* buffer = [[RTCDataBuffer alloc]
        initWithData:[message dataUsingEncoding:NSUTF8StringEncoding]
            isBinary:NO];
    [_dataChannel sendData:buffer];
}

- (void)disconnect {
    if (_state == kWDCPAppClientStateDisconnected) {
        return;
    }
    if ([self hasJoinedRoomServerRoom]) {
        [_roomServerClient leaveRoomWithRoomUrl:_roomUrl
                                         roomId:_roomId
                                       clientId:_clientId
                              completionHandler:nil];
    }
    if (_channel) {
        if (_channel.state == kARDSignalingChannelStateRegistered) {
            // Tell the other client we're hanging up.
            ARDByeMessage* byeMessage = [[ARDByeMessage alloc] init];
            [_channel sendMessage:byeMessage];
        }
        // Disconnect from collider.
        _channel = nil;
    }
    if (_dataChannel) {
        [_dataChannel close];
    }
    _clientId = nil;
    _roomId = nil;
    _isInitiator = NO;
    _hasReceivedSdp = NO;
    _messageQueue = [NSMutableArray array];
    [_peerConnection stopRtcEventLog];
    [_peerConnection close];
    _peerConnection = nil;
    [self setState:kWDCPAppClientStateDisconnected];
}

#pragma mark - ARDSignalingChannelDelegate

- (void)channel:(id<ARDSignalingChannel>)channel
    didReceiveMessage:(ARDSignalingMessage*)message {
    switch (message.type) {
        case kARDSignalingMessageTypeOffer:
        case kARDSignalingMessageTypeAnswer:
            // Offers and answers must be processed before any other message, so
            // we
            // place them at the front of the queue.
            _hasReceivedSdp = YES;
            [_messageQueue insertObject:message atIndex:0];
            break;
        case kARDSignalingMessageTypeCandidate:
        case kARDSignalingMessageTypeCandidateRemoval:
            [_messageQueue addObject:message];
            break;
        case kARDSignalingMessageTypeBye:
            // Disconnects can be processed immediately.
            [self processSignalingMessage:message];
            return;
    }
    [self drainMessageQueueIfReady];
}

- (void)channel:(id<ARDSignalingChannel>)channel
    didChangeState:(ARDSignalingChannelState)state {
    switch (state) {
        case kARDSignalingChannelStateOpen:
            break;
        case kARDSignalingChannelStateRegistered:
            break;
        case kARDSignalingChannelStateClosed:
        case kARDSignalingChannelStateError:
            // TODO(tkchin): reconnection scenarios. Right now we just
            // disconnect
            // completely if the websocket connection fails.
            [self disconnect];
            break;
    }
}

#pragma mark - RTCPeerConnectionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didChangeSignalingState:(RTCSignalingState)stateChanged {
    RTCLog(@"Signaling state changed: %ld", (long)stateChanged);
}

- (void)peerConnectionShouldNegotiate:(RTCPeerConnection*)peerConnection {
    RTCLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didChangeIceConnectionState:(RTCIceConnectionState)newState {
    RTCLog(@"ICE state changed: %ld", (long)newState);

    __weak WDCPAppClient* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        WDCPAppClient* strongSelf = weakSelf;
        [strongSelf->_delegate appClient:strongSelf
                didChangeConnectionState:newState];
    });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didChangeIceGatheringState:(RTCIceGatheringState)newState {
    RTCLog(@"ICE gathering state changed: %ld", (long)newState);
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didGenerateIceCandidate:(RTCIceCandidate*)candidate {
    dispatch_async(dispatch_get_main_queue(), ^{
        ARDICECandidateMessage* message =
            [[ARDICECandidateMessage alloc] initWithCandidate:candidate];
        [self sendSignalingMessage:message];
    });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didRemoveIceCandidates:(NSArray<RTCIceCandidate*>*)candidates {
    dispatch_async(dispatch_get_main_queue(), ^{
        ARDICECandidateRemovalMessage* message =
            [[ARDICECandidateRemovalMessage alloc]
                initWithRemovedCandidates:candidates];
        [self sendSignalingMessage:message];
    });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel {
    RTCLog(@"peerConnection:didOpenDataChannel");
}

- (void)peerConnection:(nonnull RTCPeerConnection*)peerConnection
          didAddStream:(nonnull RTCMediaStream*)stream {
}

- (void)peerConnection:(nonnull RTCPeerConnection*)peerConnection
       didRemoveStream:(nonnull RTCMediaStream*)stream {
}

#pragma mark - RTCDataChannelDelegate

- (void)dataChannel:(nonnull RTCDataChannel*)dataChannel
    didReceiveMessageWithBuffer:(nonnull RTCDataBuffer*)buffer {
    [_delegate appClient:self
               onMessage:[[NSString alloc] initWithData:buffer.data
                                               encoding:NSUTF8StringEncoding]];
}

- (void)dataChannelDidChangeState:(nonnull RTCDataChannel*)dataChannel {
    RTCLog(@"dataChannelDidChangeState");
}

#pragma mark - RTCSessionDescriptionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didCreateSessionDescription:(RTCSessionDescription*)sdp
                          error:(NSError*)error {
    __weak WDCPAppClient* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        WDCPAppClient* strongSelf = weakSelf;
        if (error) {
            RTCLogError(@"Failed to create session description. Error: %@",
                        error);
            [self disconnect];
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    @"Failed to create session description.",
            };
            NSError* sdpError =
                [[NSError alloc] initWithDomain:kWDCPAppClientErrorDomain
                                           code:kWDCPAppClientErrorCreateSDP
                                       userInfo:userInfo];
            [strongSelf->_delegate appClient:self didError:sdpError];
            return;
        }
        
        [strongSelf->_peerConnection
            setLocalDescription:sdp
              completionHandler:^(NSError* error) {
                  WDCPAppClient* strongSelf2 = weakSelf;
                  [strongSelf2 peerConnection:strongSelf2->_peerConnection
                      didSetSessionDescriptionWithError:error];
              }];
        ARDSessionDescriptionMessage* message =
            [[ARDSessionDescriptionMessage alloc] initWithDescription:sdp];
        [self sendSignalingMessage:message];
    });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didSetSessionDescriptionWithError:(NSError*)error {
    __weak WDCPAppClient* weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        WDCPAppClient* strongSelf = weakSelf;
        if (error) {
            RTCLogError(@"Failed to set session description. Error: %@", error);
            [self disconnect];
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey :
                    @"Failed to set session description.",
            };
            NSError* sdpError =
                [[NSError alloc] initWithDomain:kWDCPAppClientErrorDomain
                                           code:kWDCPAppClientErrorSetSDP
                                       userInfo:userInfo];
            [strongSelf->_delegate appClient:self didError:sdpError];
            return;
        }
        // If we're answering and we've just set the remote offer we need to
        // create
        // an answer and set the local description.
        if (!strongSelf->_isInitiator &&
            !strongSelf->_peerConnection.localDescription) {
            RTCMediaConstraints* constraints = [self defaultAnswerConstraints];
            [strongSelf->_peerConnection
                answerForConstraints:constraints
                   completionHandler:^(RTCSessionDescription* sdp,
                                       NSError* error) {
                       WDCPAppClient* strongSelf2 = weakSelf;
                       [strongSelf2 peerConnection:strongSelf2->_peerConnection
                           didCreateSessionDescription:sdp
                                                 error:error];
                   }];
        }
    });
}

#pragma mark - Private

- (NSString*)documentsFilePathForFileName:(NSString*)fileName {
    NSParameterAssert(fileName.length);
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString* documentsDirPath = paths.firstObject;
    NSString* filePath =
        [documentsDirPath stringByAppendingPathComponent:fileName];
    return filePath;
}

- (void)setState:(WDCPAppClientState)state {
  if (_state == state) {
    return;
  }
  _state = state;
  [_delegate appClient:self didChangeState:_state];
}

- (BOOL)hasJoinedRoomServerRoom {
    return _clientId.length;
}

- (void)requestTurn:(NSURL*)iceServerUrl {
    // Request TURN.
    __weak WDCPAppClient* weakSelf = self;
    [_turnClient
        requestServersWithURL:iceServerUrl
            completionHandler:^(NSArray* turnServers, NSError* error) {
                WDCPAppClient* strongSelf = weakSelf;
                if (error) {
                    RTCLogError("Error retrieving TURN servers: %@",
                                error.localizedDescription);
                }
                [strongSelf->_iceServers addObjectsFromArray:turnServers];
                strongSelf->_isTurnComplete = YES;
                [strongSelf startSignalingIfReady];
            }];
}

// Begins the peer connection connection process if we have both joined a room
// on the room server and tried to obtain a TURN server. Otherwise does nothing.
// A peer connection object will be created with a stream that contains local
// audio and video capture. If this client is the caller, an offer is created as
// well, otherwise the client will wait for an offer to arrive.
- (void)startSignalingIfReady {
    if (!_isTurnComplete || ![self hasJoinedRoomServerRoom]) {
        return;
    }
    [self setState:kWDCPAppClientStateConnected];

    // Create peer connection.
    RTCMediaConstraints* constraints = [self defaultPeerConnectionConstraints];
    RTCConfiguration* config = [[RTCConfiguration alloc] init];
    config.iceServers = _iceServers;
    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
    _peerConnection = [_factory peerConnectionWithConfiguration:config
                                                    constraints:constraints
                                                       delegate:self];

    RTCDataChannelConfiguration* dcConfig =
        [[RTCDataChannelConfiguration alloc] init];
    dcConfig.isOrdered = YES;
    dcConfig.isNegotiated = NO;
    dcConfig.maxRetransmits = -1;
    dcConfig.maxPacketLifeTime = -1;
    dcConfig.channelId = 0;
    _dataChannel = [_peerConnection dataChannelForLabel:@"P2P MSG DC"
                                          configuration:dcConfig];
    _dataChannel.delegate = self;

    if (_isInitiator) {
        // Send offer.
        __weak WDCPAppClient* weakSelf = self;
        [_peerConnection
            offerForConstraints:[self defaultOfferConstraints]
              completionHandler:^(RTCSessionDescription* sdp, NSError* error) {
                  WDCPAppClient* strongSelf = weakSelf;
                  [strongSelf peerConnection:strongSelf->_peerConnection
                      didCreateSessionDescription:sdp
                                            error:error];
              }];
    } else {
        // Check if we've received an offer.
        [self drainMessageQueueIfReady];
    }
    // Start event log.
    if (kWDCPAppClientEnableRtcEventLog) {
        NSString* filePath =
            [self documentsFilePathForFileName:@"webrtc-rtceventlog"];
        if (![_peerConnection
                startRtcEventLogWithFilePath:filePath
                              maxSizeInBytes:
                                  kWDCPAppClientRtcEventLogMaxSizeInBytes]) {
            RTCLogError(@"Failed to start event logging.");
        }
    }
}

// Processes the messages that we've received from the room server and the
// signaling channel. The offer or answer message must be processed before other
// signaling messages, however they can arrive out of order. Hence, this method
// only processes pending messages if there is a peer connection object and
// if we have received either an offer or answer.
- (void)drainMessageQueueIfReady {
    if (!_peerConnection || !_hasReceivedSdp) {
        return;
    }
    for (ARDSignalingMessage* message in _messageQueue) {
        [self processSignalingMessage:message];
    }
    [_messageQueue removeAllObjects];
}

// Processes the given signaling message based on its type.
- (void)processSignalingMessage:(ARDSignalingMessage*)message {
    NSParameterAssert(_peerConnection ||
                      message.type == kARDSignalingMessageTypeBye);
    switch (message.type) {
        case kARDSignalingMessageTypeOffer:
        case kARDSignalingMessageTypeAnswer: {
            ARDSessionDescriptionMessage* sdpMessage =
                (ARDSessionDescriptionMessage*)message;
            RTCSessionDescription* description = sdpMessage.sessionDescription;
            __weak WDCPAppClient* weakSelf = self;
            [_peerConnection
                setRemoteDescription:description
                   completionHandler:^(NSError* error) {
                       WDCPAppClient* strongSelf = weakSelf;
                       [strongSelf peerConnection:strongSelf->_peerConnection
                           didSetSessionDescriptionWithError:error];
                   }];
            break;
        }
        case kARDSignalingMessageTypeCandidate: {
            ARDICECandidateMessage* candidateMessage =
                (ARDICECandidateMessage*)message;
            [_peerConnection addIceCandidate:candidateMessage.candidate];
            break;
        }
        case kARDSignalingMessageTypeCandidateRemoval: {
            ARDICECandidateRemovalMessage* candidateMessage =
                (ARDICECandidateRemovalMessage*)message;
            [_peerConnection removeIceCandidates:candidateMessage.candidates];
            break;
        }
        case kARDSignalingMessageTypeBye:
            // Other client disconnected.
            // TODO(tkchin): support waiting in room for next client.
            // For now just disconnect.
            [self disconnect];
            break;
    }
}

// Sends a signaling message to the other client. The caller will send messages
// through the room server, whereas the callee will send messages over the
// signaling channel.
- (void)sendSignalingMessage:(ARDSignalingMessage*)message {
    if (_isInitiator) {
        __weak WDCPAppClient* weakSelf = self;
        [_roomServerClient
                  sendMessage:message
                   forRoomUrl:_roomUrl
                       roomId:_roomId
                     clientId:_clientId
            completionHandler:^(ARDMessageResponse* response, NSError* error) {
                WDCPAppClient* strongSelf = weakSelf;
                if (error) {
                    [strongSelf->_delegate appClient:strongSelf didError:error];
                    return;
                }
                NSError* messageError = [[strongSelf class]
                    errorForMessageResultType:response.result];
                if (messageError) {
                    [strongSelf->_delegate appClient:strongSelf
                                            didError:messageError];
                    return;
                }
            }];
    } else {
        [_channel sendMessage:message];
    }
}

#pragma mark - Collider methods

- (void)registerWithColliderIfReady {
    if (![self hasJoinedRoomServerRoom]) {
        return;
    }
    // Open WebSocket connection.
    if (!_channel) {
        _channel = [[ARDWebSocketChannel alloc] initWithURL:_websocketURL
                                                    restURL:_websocketRestURL
                                                   delegate:self];
    }
    [_channel registerForRoomId:_roomId clientId:_clientId];
}

#pragma mark - Defaults

- (RTCMediaConstraints*)defaultMediaAudioConstraints {
    NSDictionary* mandatoryConstraints = @{};
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
        initWithMandatoryConstraints:mandatoryConstraints
                 optionalConstraints:nil];
    return constraints;
}

- (RTCMediaConstraints*)defaultAnswerConstraints {
    return [self defaultOfferConstraints];
}

- (RTCMediaConstraints*)defaultOfferConstraints {
    NSDictionary* mandatoryConstraints =
        @{ @"OfferToReceiveAudio" : @"true",
           @"OfferToReceiveVideo" : @"true" };
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
        initWithMandatoryConstraints:mandatoryConstraints
                 optionalConstraints:nil];
    return constraints;
}

- (RTCMediaConstraints*)defaultPeerConnectionConstraints {
    if (_defaultPeerConnectionConstraints) {
        return _defaultPeerConnectionConstraints;
    }
    NSDictionary* optionalConstraints = @{ @"DtlsSrtpKeyAgreement" : @"true" };
    RTCMediaConstraints* constraints = [[RTCMediaConstraints alloc]
        initWithMandatoryConstraints:nil
                 optionalConstraints:optionalConstraints];
    return constraints;
}

#pragma mark - Errors

+ (NSError*)errorForJoinResultType:(ARDJoinResultType)resultType {
    NSError* error = nil;
    switch (resultType) {
        case kARDJoinResultTypeSuccess:
            break;
        case kARDJoinResultTypeUnknown: {
            error = [[NSError alloc]
                initWithDomain:kWDCPAppClientErrorDomain
                          code:kWDCPAppClientErrorUnknown
                      userInfo:@{
                          NSLocalizedDescriptionKey : @"Unknown error.",
                      }];
            break;
        }
        case kARDJoinResultTypeFull: {
            error = [[NSError alloc]
                initWithDomain:kWDCPAppClientErrorDomain
                          code:kWDCPAppClientErrorRoomFull
                      userInfo:@{
                          NSLocalizedDescriptionKey : @"Room is full.",
                      }];
            break;
        }
    }
    return error;
}

+ (NSError*)errorForMessageResultType:(ARDMessageResultType)resultType {
    NSError* error = nil;
    switch (resultType) {
        case kARDMessageResultTypeSuccess:
            break;
        case kARDMessageResultTypeUnknown:
            error = [[NSError alloc]
                initWithDomain:kWDCPAppClientErrorDomain
                          code:kWDCPAppClientErrorUnknown
                      userInfo:@{
                          NSLocalizedDescriptionKey : @"Unknown error.",
                      }];
            break;
        case kARDMessageResultTypeInvalidClient:
            error = [[NSError alloc]
                initWithDomain:kWDCPAppClientErrorDomain
                          code:kWDCPAppClientErrorInvalidClient
                      userInfo:@{
                          NSLocalizedDescriptionKey : @"Invalid client.",
                      }];
            break;
        case kARDMessageResultTypeInvalidRoom:
            error = [[NSError alloc]
                initWithDomain:kWDCPAppClientErrorDomain
                          code:kWDCPAppClientErrorInvalidRoom
                      userInfo:@{
                          NSLocalizedDescriptionKey : @"Invalid room.",
                      }];
            break;
    }
    return error;
}

@end
