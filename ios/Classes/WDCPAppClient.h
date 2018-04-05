/*
 *  Copyright 2014 The WebRTC Project Authors. All rights reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import <Foundation/Foundation.h>
#import "WebRTC/RTCPeerConnection.h"
#import "WebRTC/RTCDataChannel.h"

#import "ARDSignalingChannel.h"

typedef NS_ENUM(NSInteger, WDCPAppClientState) {
    // Disconnected from servers.
    kWDCPAppClientStateDisconnected,
    // Connecting to servers.
    kWDCPAppClientStateConnecting,
    // Connected to servers.
    kWDCPAppClientStateConnected,
};

@class WDCPAppClient;

// The delegate is informed of pertinent events and will be called on the
// main queue.
@protocol WDCPAppClientDelegate<NSObject>

- (void)appClient:(WDCPAppClient*)client
    didChangeState:(WDCPAppClientState)state;

- (void)appClient:(WDCPAppClient*)client
    didChangeConnectionState:(RTCIceConnectionState)state;

- (void)appClient:(WDCPAppClient*)client onMessage:(NSString*)message;

- (void)appClient:(WDCPAppClient*)client didError:(NSError*)error;

- (void)appClient:(WDCPAppClient*)client didGetStats:(NSArray*)stats;

@end

@interface WDCPAppClient
    : NSObject<RTCPeerConnectionDelegate, RTCDataChannelDelegate,
               ARDSignalingChannelDelegate>

- (instancetype)initWithDelegate:(id<WDCPAppClientDelegate>)delegate;

- (void)connectToRoomWithRoomUrl:(NSString*)roomUrl roomId:(NSString*)roomId;

- (void)sendMessage:(NSString*)message;

- (void)disconnect;

@end
