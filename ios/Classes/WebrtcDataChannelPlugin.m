
#import "WebrtcDataChannelPlugin.h"

#import "WDCPAppClient.h"

static NSString* const kWDCPMethodChannelName =
    @"com.github.piasy/webrtc_data_channel.method";
static NSString* const kWDCPEventChannelName =
    @"com.github.piasy/webrtc_data_channel.event";
static NSString* const kWDCPMethodConnectToRoom = @"connectToRoom";
static NSString* const kWDCPMethodSendMessage = @"sendMessage";

@interface WebrtcDataChannelPlugin ()<FlutterStreamHandler,
                                      WDCPAppClientDelegate>
@end

@implementation WebrtcDataChannelPlugin {
    WDCPAppClient* _client;
    FlutterEventSink _eventSink;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    WebrtcDataChannelPlugin* plugin = [[WebrtcDataChannelPlugin alloc] init];

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
        _client = [[WDCPAppClient alloc] initWithDelegate:self];
    }
    return self;
}

#pragma mark - Flutter delegate

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([kWDCPMethodConnectToRoom isEqualToString:call.method]) {
        NSDictionary* arguments = call.arguments;
        [self connectToRoom:[arguments objectForKey:@"roomUrl"]
                     roomId:[arguments objectForKey:@"roomId"]];
        result(@true);
    } else if ([kWDCPMethodSendMessage isEqualToString:call.method]) {
        NSDictionary* arguments = call.arguments;
        [self sendMessage:[arguments objectForKey:@"message"]];
        result(@true);
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
    [_client connectToRoomWithRoomUrl:roomUrl roomId:roomId];
}

- (void)sendMessage:(NSString*)message {
    [_client sendMessage:message];
}

#pragma mark - WDCP delegate

- (void)appClient:(WDCPAppClient*)client
    didChangeConnectionState:(RTCIceConnectionState)state {
}

- (void)appClient:(WDCPAppClient*)client
    didChangeState:(WDCPAppClientState)state {
}

- (void)appClient:(WDCPAppClient*)client didError:(NSError*)error {
}

- (void)appClient:(WDCPAppClient*)client didGetStats:(NSArray*)stats {
}

- (void)appClient:(WDCPAppClient*)client onMessage:(NSString*)message {
    if (_eventSink) {
        _eventSink(message);
    }
}

@end
