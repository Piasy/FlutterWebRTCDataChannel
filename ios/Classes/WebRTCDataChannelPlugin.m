//
/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2017 Piasy
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
//


#import "WebRTC/RTCLogging.h"
#import "WebRTCDataChannelPlugin.h"

#import "WDCPAppClient.h"

static NSString* const kWDCPMethodChannelName =
    @"com.github.piasy/webrtc_data_channel.method";
static NSString* const kWDCPEventChannelName =
    @"com.github.piasy/webrtc_data_channel.event";
static NSString* const kWDCPMethodConnectToRoom = @"connectToRoom";
static NSString* const kWDCPMethodSendMessage = @"sendMessage";
static NSString* const kWDCPMethodDisconnect = @"disconnect";

static int const kEventTypeSignalingState = 1;
static int const kEventTypeIceState = 2;
static int const kEventTypeMessage = 3;

@interface WebRTCDataChannelPlugin ()<FlutterStreamHandler,
                                      WDCPAppClientDelegate>
@end

@implementation WebRTCDataChannelPlugin {
    WDCPAppClient* _client;
    volatile FlutterEventSink _eventSink;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    WebRTCDataChannelPlugin* plugin = [[WebRTCDataChannelPlugin alloc] init];

    FlutterMethodChannel* methodChannel =
        [FlutterMethodChannel methodChannelWithName:kWDCPMethodChannelName
                                    binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:plugin channel:methodChannel];

    FlutterEventChannel* eventChannel =
        [FlutterEventChannel eventChannelWithName:kWDCPEventChannelName
                                  binaryMessenger:[registrar messenger]];
    [eventChannel setStreamHandler:plugin];
}

- (instancetype)init {
    if (self = [super init]) {
        _client = nil;
        _eventSink = nil;
    }
    return self;
}

#pragma mark - Flutter delegate

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([kWDCPMethodConnectToRoom isEqualToString:call.method]) {
        NSDictionary* arguments = call.arguments;
        [self connectToRoom:[arguments objectForKey:@"roomUrl"]
                     roomId:[arguments objectForKey:@"roomId"]];
        result(@0);
    } else if ([kWDCPMethodSendMessage isEqualToString:call.method]) {
        NSDictionary* arguments = call.arguments;
        [self sendMessage:[arguments objectForKey:@"message"]];
        result(@0);
    } else if ([kWDCPMethodDisconnect isEqualToString:call.method]) {
        [self disconnect];
        result(@0);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:
                                           (nonnull FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

#pragma mark - API

- (void)connectToRoom:(NSString*)roomUrl roomId:(NSString*)roomId {
    _client = [[WDCPAppClient alloc] initWithDelegate:self];
    [_client connectToRoomWithRoomUrl:roomUrl roomId:roomId];
}

- (void)sendMessage:(NSString*)message {
    WDCPAppClient* client = _client;
    if (client) {
        [client sendMessage:message];
    }
}

- (void)disconnect {
    WDCPAppClient* client = _client;
    if (client) {
        [client disconnect];
    }
    _client = nil;
}

#pragma mark - WDCP delegate

- (void)appClient:(WDCPAppClient*)client
    didChangeConnectionState:(RTCIceConnectionState)state {
    [self notifyEvent:kEventTypeIceState key:@"state" value:@(state)];
}

- (void)appClient:(WDCPAppClient*)client
    didChangeState:(WDCPAppClientState)state {
    if (state == kWDCPAppClientStateDisconnected) {
        _client = nil;
    }
    [self notifyEvent:kEventTypeSignalingState key:@"state" value:@(state)];
}

- (void)appClient:(WDCPAppClient*)client didError:(NSError*)error {
    [self notifyError:[error.userInfo objectForKey:NSLocalizedDescriptionKey]];
}

- (void)appClient:(WDCPAppClient*)client didGetStats:(NSArray*)stats {
}

- (void)appClient:(WDCPAppClient*)client onMessage:(NSString*)message {
    [self notifyEvent:kEventTypeMessage key:@"message" value:message];
}

- (void)notifyEvent:(int)type key:(NSString*)key value:(NSObject*)value {
    FlutterEventSink sink = _eventSink;
    if (sink) {
        sink(@{@"type": @(type), key: value});
    }
}

- (void)notifyError:(NSString*)error {
    FlutterEventSink sink = _eventSink;
    _eventSink = nil;

    if (sink) {
        sink([FlutterError errorWithCode:@"" message:error details:nil]);
    }
}

@end
