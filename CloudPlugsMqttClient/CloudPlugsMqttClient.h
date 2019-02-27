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

#ifndef CloudPlugsMqttClient_h
#define CloudPlugsMqttClient_h

#define DEFAULT_TLS       NO
#define DEFAULT_PORT_TLS  8883
#define DEFAULT_PORT      1883
#define DEFAULT_URL       @"api.cloudplugs.com"

#import <MQTTClient/MQTTClient.h>
#import <MQTTClient/MQTTSessionManager.h>

@protocol CloudPlugsDelegate <NSObject>

- (void)mqttMessageDidArrive:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained;

@end

typedef void (^CloudPlugsEnrollHandler)       (NSError *error, NSString* msg);
typedef void (^CloudPlugsSetPropertyHandler)  (NSError *error);
typedef void (^CloudPlugsGetPropertyHandler)  (NSError *error, NSString* value);

@interface CloudPlugsMqttClient : NSObject <MQTTSessionManagerDelegate>

/**
 Mqtt broker endpoint.
 */
@property (strong, nonatomic) NSString* host;
/**
 Mqtt broker port.
 */
@property (nonatomic) uint32_t port;
/**
 The device's PlugId
 */
@property (strong, nonatomic) NSString* plugId;
/**
 The device's password/auth
 */
@property (strong, nonatomic) NSString* password;
/**
 The device's clientId (its serial number)
 */
@property (strong, nonatomic) NSString* clientId;
/**
 Enables the class' log
 */
@property (nonatomic) BOOL logEnabled;
/**
 MQTT Quality of Service levels
 */
@property (nonatomic) uint8_t qos;
/**
 Whether or not to trust servers with an invalid or expired SSL certificates. Defaults to `NO`.
 */
@property (nonatomic) BOOL allowInvalidCertificates;
/**
 Whether or not use Tls. Defaults to `NO`.
 */
@property (nonatomic) BOOL tls;

/**
 This method inits with or without persistence
 */
-(id)initWithPersistence:(BOOL)persistence;

/**
 This method sets credentials to connect
 
 @param username  The device's PlugId
 @param password  The device's password/auth
 @param clientId  The device's serial number
 */
-(void)setUsername:(NSString*)username
          password:(NSString*)password
          clientId:(NSString*)clientId;

/**
 This method connects to the broker
 
 @param connectionHandler  The completion block of the connection, if error is NULL, the connection went fine
 */
-(void)connectWithHandler:(MQTTConnectHandler)connectionHandler;

/**
 This method publishes messages
 
 @param message   The string to publish
 @param topic     The topic where to publish the message to
 @param seconds   How long this data entry will live (if "expire_at" is present, then field ignored implemented)
 @param plugIdOf  Plug-ID the Thing that will publish this data record.
 @param handler   The completion block of publishing, if error is NULL, the publishing went fine
 */
-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
           ttl:(uint32_t)seconds
            of:(NSString*)plugIdOf
   withHandler:(MQTTPublishHandler)handler;

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
   withHandler:(MQTTPublishHandler)handler;

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
           ttl:(uint32_t)seconds
   withHandler:(MQTTPublishHandler)handler;

-(void)publish:(NSString*)message
       onTopic:(NSString*)topic
            of:(NSString*)plugIdOf
   withHandler:(MQTTPublishHandler)handler;

/**
 This method subscribes to a topic
 
 @param topic    The topic where to subscribe to
 @param handler  The completion block of subscription, if error is NULL, the publishing went fine
 */
-(void)subscribeTo:(NSString*)topic
  subscribeHandler:(MQTTSubscribeHandler) handler;

-(void)subscribeTo:(NSString*)topic
        withPrefix:(BOOL)usePrefix
  subscribeHandler:(MQTTSubscribeHandler) handler;

/**
 This method subscribes to a topic of a different device specifying the relative PlugId
 
 @param topic    The topic where to subscribe to
 @param handler  The completion block of subscription, if error is NULL, the publishing went fine
 */
-(void)subscribeTo:(NSString*)topic
          toPlugId:(NSString*)toPlugId
        withPrefix:(BOOL)usePrefix
  subscribeHandler:(MQTTSubscribeHandler)handler;

/**
 This method unsubscribes from a topic
 */
-(void)unsubscribeFrom:(NSString*)topic;

/**
 This method unsubscribes a specific device from a topic
 */
-(void)unsubscribe:(NSString*)plugId from:(NSString*)topic;

/**
 This method sets a property in the platform of a different device specifying the relative PlugId
 
 @param property  The property key
 @param value     The property value
 @param handler   The completion block of set, if error is NULL, the propery is successfully set
 */
-(void)setProperty:(NSString*)property
             value:(NSString*)value
          toDevice:(NSString*)toPlugId
       withHandler:(CloudPlugsSetPropertyHandler)handler;

/**
 This method sets a property in the platform
 
 @param property  The property key
 @param value     The property value
 @param handler   The completion block of set, if error is NULL, the propery is successfully set
 */
-(void)setProperty:(NSString*)property
             value:(NSString*)value
       withHandler:(CloudPlugsSetPropertyHandler)handler;

/**
 This method retrieves a property from the platform of a different device specifying the relative PlugId
 
 @param property  The property key
 @param handler   The completion block of get, if error is NULL, the value is succesufully retrieved and it's in the block
 */
-(void)getProperty:(NSString*)property
        fromDevice:(NSString*)fromPlugId
       withHandler:(CloudPlugsGetPropertyHandler)handler;

/**
 This method retrieves a property from the platform
 
 @param property  The property key
 @param handler   The completion block of get, if error is NULL, the value is succesufully retrieved and it's in the block
 */
-(void)getProperty:(NSString*)property
       withHandler:(CloudPlugsGetPropertyHandler)handler;

/**
 This function performs a request to the server for enrolling a new production device.
 
 @param idModel   The Plug-ID of the Thing's Production Template.
 @param hwid      The hardware-id or serial number of the Thing.
 @param password  The enrollment password of the Thing.
 @param handler   The completion block of enrolling, if error is NULL, the block will contain plugId and auth.
 */
-(void)enroll:(NSString*)hwid
      idModel:(NSString*)idModel
     password:(NSString*)password
  withHandler:(CloudPlugsEnrollHandler)handler;

/**
 This function performs an request to the server for enrolling a new or already existent controller device.
 
 @param hwid      The thing hardware-id or serial number.
 @param idModel   The ID of the Production Template of the thing to control.
 @param hwidCtrl  The controller hardware-id.
 @param password  The control password of the controller as defined in the thing Production Template.
 @param handler   The completion block of enrolling, if error is NULL, the block will contain plugId and auth.
 */
-(void)enrollCtrl:(NSString*)hwid
          idModel:(NSString*)idModel
         password:(NSString*)password
         ctrlHwid:(NSString*)hwidCtrl
      withHandler:(CloudPlugsEnrollHandler)handler;

/**
 This function returns a MQTTSessionManager in case you want some custom configuration, or add an observer
 */
-(MQTTSessionManager*)getMqttSessionManager;

@property (strong, nonatomic) MQTTSessionManager *manager;

@property (weak, nonatomic) id<CloudPlugsDelegate> CPDelegate;

/**
 MQTTSessionManager's delegate
 */
-(void)handleMessage:(NSData *)data onTopic:(NSString *)topic retained:(BOOL)retained;

@end

#endif /* CloudPlugsMqttClient_h */
