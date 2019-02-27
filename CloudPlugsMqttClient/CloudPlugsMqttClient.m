/*
 Copyright 2019 CloudPlugs Inc.
 
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
*/

#define LOG(...) if(self.logEnabled) NSLog(__VA_ARGS__)

#include <stdlib.h>
#import <Foundation/Foundation.h>
#import "CloudPlugsMqttClient.h"
#include <CFNetwork/CFNetwork.h>

#define PREFIX          @"data"
#define ERRORDOMAIN     @"CloudPlugsMqttClient"
#define EXCEPTION_NAME  @"CloudPlugsException"

@interface CloudPlugsMqttClient ()

@property (strong, nonatomic) NSString* idModel;
@property (nonatomic)         BOOL enrolling;
@property (nonatomic)         BOOL auth;
@property (strong, nonatomic) NSMutableDictionary* callbacks;
@property (strong, nonatomic) NSString* baseUrl;
@property (strong, nonatomic) NSMutableDictionary* subscriptionMap;
@end

@implementation CloudPlugsMqttClient

@synthesize plugId, host, port, tls, enrolling;
#define RECONNECT_TIMER_MAX_DEFAULT 64.0
-(void)initWithPersistence {
  
  
  self.manager = [[MQTTSessionManager alloc] initWithPersistence:YES
                                                   maxWindowSize:MQTT_MAX_WINDOW_SIZE
                                                     maxMessages:MQTT_MAX_MESSAGES
                                                         maxSize:MQTT_MAX_SIZE
                                      maxConnectionRetryInterval:RECONNECT_TIMER_MAX_DEFAULT
                                             connectInForeground:YES
                                                  streamSSLLevel:(NSString *)kCFStreamSocketSecurityLevelNegotiatedSSL
                                                           queue:dispatch_get_main_queue()];
}

-(id)initWithPersistence:(BOOL)persistence {
  
  self = [super init];
  
  if (self) {
    if (persistence) {
      self.manager = [[MQTTSessionManager alloc] init];
    } else {
      [self initWithPersistence];
    }
    self.host = DEFAULT_URL;
    self.tls = DEFAULT_TLS;
    self.enrolling = NO;
    self.callbacks = [[NSMutableDictionary alloc] init];
    self.logEnabled = YES;
    self.qos = MQTTQosLevelAtMostOnce;
    self.allowInvalidCertificates = YES;
    self.subscriptionMap = [[NSMutableDictionary alloc] init];
    self.CPDelegate = nil;
    self.port = 0;
  }
  return self;
}

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
   withHandler:(MQTTPublishHandler)handler {
  
  [self publish:message onTopic:topic ttl:0 of:NULL withHandler:handler];
}

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
           ttl:(uint32_t)seconds
   withHandler:(MQTTPublishHandler)handler {
  [self publish:message onTopic:topic ttl:seconds of:NULL withHandler:handler];
}

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
            of:(NSString*)plugIdOf
   withHandler:(MQTTPublishHandler)handler {
  [self publish:message onTopic:topic ttl:0 of:plugIdOf withHandler:handler];
}

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
           ttl:(uint32_t)seconds
            of:(NSString*)plugIdOf
   withHandler:(MQTTPublishHandler)handler {
  
  NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
  
  if (plugIdOf) {
    [payload setObject:plugIdOf forKey:@"of"];
  }
  if (seconds) {
    [payload setObject:[NSNumber numberWithInteger:seconds] forKey:@"ttl"];
  }
  
  [payload setObject:message forKey:@"data"];
  
  NSError *error;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                     options:NSJSONWritingPrettyPrinted // Pass 0 if you don't care about the readability of the generated string
                                                       error:&error];
  
  NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  
  
  
  NSString* topicComposed = [NSString stringWithFormat:@"%@/%@/%@", plugId, PREFIX, topic];
  
  LOG(@"Publishing: %@ - %@", topicComposed, jsonString);
  
  [self.manager.session publishData:jsonData
                            onTopic:topicComposed
                             retain:NO
                                qos:self.qos
                     publishHandler:handler];
}

-(void)unsubscribe:(NSString *)plugId from:(NSString *)topic {
  
  NSString* topicToUnsubscribe = [NSString stringWithFormat:@"%@/data/%@", plugId, topic];
  [self.subscriptionMap removeObjectForKey:topicToUnsubscribe];
}
-(void)unsubscribeFrom:(NSString *)topic {
  
  [self.subscriptionMap removeObjectForKey:topic];
  [self setSubscriptionMap:self.subscriptionMap];
}

-(void)subscribeTo:(NSString*)topic
          toPlugId:(NSString*)toPlugId
        withPrefix:(BOOL)usePrefix
  subscribeHandler:(MQTTSubscribeHandler) handler {
  
  if(!toPlugId) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  NSString* topicComposed;
  if (usePrefix) {
    topicComposed = [NSString stringWithFormat:@"%@/%@/%@", toPlugId, PREFIX, topic];
  } else {
    topicComposed = topic;
  }
  
  [self.subscriptionMap setObject:[NSNumber numberWithInt:self.qos] forKey:topicComposed];
  
  [self.manager setSubscriptions:self.subscriptionMap];
  
}

-(void)subscribeTo:(NSString*)topic
        withPrefix:(BOOL)usePrefix
  subscribeHandler:(MQTTSubscribeHandler) handler {
  
  [self subscribeTo:topic toPlugId:self.plugId withPrefix:usePrefix subscribeHandler:handler];
}

-(void)subscribeTo:(NSString*)topic
  subscribeHandler:(MQTTSubscribeHandler) handler {
  [self subscribeTo:topic toPlugId:self.plugId withPrefix:YES subscribeHandler:handler];
}

-(void)respondToEnroll:(NSData*)data topic:(NSString*)topic {
  
  NSError* localError = nil;
  NSError* error = nil;
  
  NSDictionary* dataDict = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&localError];
  if (localError) { //json is broken
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"json malformed", nil)};
    error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
    ((CloudPlugsEnrollHandler)[self.callbacks objectForKey:topic])(error, @"");
  } else {
    if ([dataDict objectForKey:@"err"]!=nil) { //json is ok but the enroll failed
      NSString* errMsg = [NSString stringWithFormat:@"enroll failed: %@", [dataDict objectForKey:@"err"] ];
      NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(errMsg, nil)};
      error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
      ((CloudPlugsEnrollHandler)[self.callbacks objectForKey:topic])(error, [dataDict objectForKey:@"msg"]);
    } else { //json is ok and the enroll was ok too
      NSString* message = [NSString stringWithUTF8String:[data bytes]];
      ((CloudPlugsEnrollHandler)[self.callbacks objectForKey:topic])(NULL, message);
    }
  }
  [self.callbacks removeObjectForKey:topic];
}

-(void)respondToSetProperty:(NSData*)data topic:(NSString*)topic {
  
  if (![data length]) {
    ((CloudPlugsSetPropertyHandler)[self.callbacks objectForKey:topic])(NULL);
  } else {
    NSError* localError = nil;
    NSError* error = nil;
    NSDictionary* dataDict = [NSJSONSerialization JSONObjectWithData:data
                                                             options:0
                                                               error:&localError];
    if (localError) {
      NSString* errMsg = [NSString stringWithFormat:@"json malformed"];
      NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(errMsg, nil)};
      error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
    } else {
      NSString* errMsg = [NSString stringWithFormat:@"enroll failed: %@", [dataDict objectForKey:@"err"] ];
      NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(errMsg, nil)};
      error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
    }
    ((CloudPlugsSetPropertyHandler)[self.callbacks objectForKey:topic])(error);
  }
}

-(void)respondToGetProperty:(NSData*)data topic:(NSString*)topic {
  
  NSError* localError = nil;
  NSError* error = nil;
  NSDictionary* dataDict = [NSJSONSerialization JSONObjectWithData:data
                                                           options:0
                                                             error:&localError];
  if (localError) {
    NSString* errMsg = [NSString stringWithFormat:@"json malformed"];
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(errMsg, nil)};
    error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
  } else {
    if ([dataDict objectForKey:@"err"]!=nil) {
      NSString* errMsg = [NSString stringWithFormat:@"get property failed: %@", [dataDict objectForKey:@"err"] ];
      NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(errMsg, nil)};
      error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
    } else {
      NSString* msg = [NSString stringWithUTF8String:[data bytes]];
      ((CloudPlugsGetPropertyHandler)[self.callbacks objectForKey:topic])(NULL, msg);
    }
  }
}

-(BOOL)intercept:(NSData*)data topic:(NSString*)topic {
  
  if ([self.callbacks valueForKey:topic]!=nil) {
    NSString* topicToCheck = [NSString stringWithFormat:@"%@/thing/%@", self.idModel, self.password];
    if ([topic rangeOfString:topicToCheck].location!=NSNotFound) {
      [self respondToEnroll:data topic:topic];
      return YES;
    }
    topicToCheck = [NSString stringWithFormat:@"%@/ag/prop/set", plugId];
    if ([topic rangeOfString:topicToCheck].location!=NSNotFound) {
      [self respondToSetProperty:data topic:topic];
    }
    topicToCheck = [NSString stringWithFormat:@"%@/ag/prop/get", plugId];
    if ([topic rangeOfString:topicToCheck].location!=NSNotFound) {
      [self respondToGetProperty:data topic:topic];
    }
    return YES;
  }
  return NO;
}

-(MQTTSessionManager*)getMqttSessionManager {
  return self.manager;
}

-(void)enroll:(NSString*)hwid
      idModel:(NSString*)idModel
     password:(NSString*)password
       asCtrl:(BOOL)ctrl
     ctrlHwid:(NSString*)hwidCtrl
  withHandler:(CloudPlugsEnrollHandler)enrollHandler {
  
  if(!hwid || !idModel || !password || !hwidCtrl) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  self.clientId = hwid;
  self.idModel = idModel;
  
  self.auth = NO;
  self.plugId = @"";
  self.password = @"";
  __weak CloudPlugsMqttClient *weakSelf = self;
  [self connectWithHandler:^(NSError *error) {
    
    if (error) {
      LOG(@"enroll connection failed:%@", error.localizedDescription);
    } else {
      NSString* topic;
      if (ctrl) {
        topic = [NSString stringWithFormat:@"%@/ctrl/%@/%@", idModel, hwid, password];
      } else {
        topic = [NSString stringWithFormat:@"%@/thing/%@", idModel, password];
      }
      [weakSelf.callbacks setObject:[enrollHandler copy] forKey:topic];
      
      [weakSelf subscribeTo:topic withPrefix:NO subscribeHandler:^(NSError *error, NSArray<NSNumber *> *gQoss) {
        if(error) {
          LOG(@"enroll subscription failed");
        } else {
          LOG(@"enroll subscription succeded");
        }
      }];
    }
  }];
}

-(void)enrollCtrl:(NSString*)hwid
          idModel:(NSString*)idModel
         password:(NSString*)password
         ctrlHwid:(NSString*)hwidCtrl
      withHandler:(CloudPlugsEnrollHandler)handler {
  
  if(!hwid || !idModel || !password || !hwidCtrl) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  [self enroll:hwid idModel:idModel password:password asCtrl:YES ctrlHwid:hwidCtrl withHandler:handler];
}

-(void)enroll:(NSString*)hwid
      idModel:(NSString*)idModel
     password:(NSString*)password
  withHandler:(CloudPlugsEnrollHandler)enrollHandler {
  
  if(!hwid || !idModel || !password ) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  [self enroll:hwid idModel:idModel password:password asCtrl:NO ctrlHwid:@"" withHandler:enrollHandler];
}

-(void)setProperty:(NSString *)property
             value:(NSString *)value
          toDevice:(NSString*)toPlugId
       withHandler:(CloudPlugsSetPropertyHandler)handler {
  
  if(!property || !value || !toPlugId ) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  NSString* topic = [NSString stringWithFormat:@"%@/ag/prop/set", toPlugId];
  NSString* payloadStr = [NSString stringWithFormat:@"{\"%@\":\"%@\"}", property, value];
  
  NSData* payload = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
  __weak CloudPlugsMqttClient *weakSelf = self;
  [self.manager.session publishData:payload
                            onTopic:topic
                             retain:NO
                                qos:self.qos
                     publishHandler:^(NSError* error) {
                       if (error) {
                         NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"request failed", nil)};
                         error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
                         handler(error);
                       } else {
                         [weakSelf.callbacks setObject:[handler copy] forKey:topic];
                       }
                     }];
}

-(void)setProperty:(NSString *)property
             value:(NSString *)value
       withHandler:(CloudPlugsSetPropertyHandler)handler {
  
  if(!property || !value) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  [self setProperty:property value:value toDevice:self.plugId withHandler:handler];
}

-(void)getProperty:(NSString *)property fromDevice:(NSString *)fromPlugId withHandler:(CloudPlugsGetPropertyHandler)handler {
  
  if(!property || !fromPlugId) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  NSString* topic = [NSString stringWithFormat:@"%@/ag/prop/get", fromPlugId];
  NSString* payloadStr = [NSString stringWithFormat:@"[\"%@\"]", property];
  
  NSData* payload = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
  
  __weak CloudPlugsMqttClient *weakSelf = self;
  [self.manager.session publishData:payload
                            onTopic:topic
                             retain:NO
                                qos:self.qos
                     publishHandler:^(NSError* error) {
                       if (error) {
                         NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"request failed", nil)};
                         error = [NSError errorWithDomain:ERRORDOMAIN code:1 userInfo:userInfo];
                         handler(error, @"");
                       } else {
                         [weakSelf.callbacks setObject:[handler copy] forKey:topic];
                       }
                     }];
}

-(void)getProperty:(NSString *)property withHandler:(CloudPlugsGetPropertyHandler)handler {
  
  if(!property) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  [self getProperty:property fromDevice:self.plugId withHandler:handler];
}

-(void)setUsername:(NSString*)username
          password:(NSString*)password
          clientId:(NSString*)clientId {
  
  if(!username || !password) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  self.auth = YES;
  self.plugId = username;
  self.password = password;
  if (!clientId || ![clientId length]) {
    self.clientId = username;
  }
}

-(void)connectWithHandler:(MQTTConnectHandler)connectionHandler  {
  
  self.manager.delegate = self;
  
  uint32_t portToUse = port?port:tls?DEFAULT_PORT_TLS:DEFAULT_PORT;
  
  if (!self.plugId || !self.password || !self.clientId) @throw [NSException exceptionWithName:EXCEPTION_NAME reason:@"INVALID PARAMETER" userInfo:nil];
  
  [self.manager connectTo:host
                     port:portToUse
                      tls:self.tls
                keepalive:60
                    clean:YES
                     auth:self.auth
                     user:self.plugId
                     pass:self.password
                     will:NO
                willTopic:nil
                  willMsg:nil
                  willQos:self.qos
           willRetainFlag:NO
             withClientId:self.clientId
           securityPolicy:nil
             certificates:nil
            protocolLevel:MQTTProtocolVersion311
           connectHandler:connectionHandler];
  
  [self.manager addObserver:self
                 forKeyPath:@"state"
                    options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                    context:nil];
}

-(void)handleMessage:(NSData*)data onTopic:(NSString*)topic retained:(BOOL)retained {
  
  NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  LOG(@"Message: %@", dataString);
  
  if (![self intercept:data topic:topic]) {
    if (self.CPDelegate) {
      [self.CPDelegate mqttMessageDidArrive:data onTopic:topic retained:retained];
    }
  }
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  
  switch (self.manager.state) {
    case MQTTSessionManagerStateClosed:
      LOG(@"\nCLOSED\n");
      break;
    case MQTTSessionManagerStateClosing:
      LOG(@"\nCLOSING\n");
      break;
    case MQTTSessionManagerStateConnected:
      LOG(@"\nCONNECTED\n");
      break;
    case MQTTSessionManagerStateConnecting:
      LOG(@"\nCONNECTING\n");
      break;
    case MQTTSessionManagerStateError:
      LOG(@"\nERROR\n");
      break;
    case MQTTSessionManagerStateStarting:
      LOG(@"\nSTARTING\n");
    default:
      break;
  }
}

@end

