//
//  ALMQTTConversationService.m
//  Applozic
//
//  Created by Applozic Inc on 11/27/15.
//  Copyright © 2015 applozic Inc. All rights reserved.
//

#import "ALMQTTConversationService.h"
#import "MQTTSession.h"
#import "ALUserDefaultsHandler.h"
#import "ALConstant.h"
#import "ALMessage.h"
#import "ALMessageDBService.h"
#import "ALUserDetail.h"
#import "ALPushAssist.h"
#import "ALChannelService.h"
#import "ALContactDBService.h"
#import "ALMessageService.h"

@implementation ALMQTTConversationService

/*
 MESSAGE_RECEIVED("APPLOZIC_01"), MESSAGE_SENT("APPLOZIC_02"),
 MESSAGE_SENT_UPDATE("APPLOZIC_03"), MESSAGE_DELIVERED("APPLOZIC_04"),
 MESSAGE_DELETED("APPLOZIC_05"), CONVERSATION_DELETED("APPLOZIC_06"),
 MESSAGE_READ("APPLOZIC_07"), MESSAGE_DELIVERED_AND_READ("APPLOZIC_08"),
 CONVERSATION_READ("APPLOZIC_09"), CONVERSATION_DELIVERED_AND_READ("APPLOZIC_10"),
 USER_CONNECTED("APPLOZIC_11"), USER_DISCONNECTED("APPLOZIC_12"),
 GROUP_DELETED("APPLOZIC_13"), GROUP_LEFT("APPLOZIC_14");
 */

+(ALMQTTConversationService *)sharedInstance
{
    static ALMQTTConversationService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ALMQTTConversationService alloc] init];
        sharedInstance.alSyncCallService = [[ALSyncCallService alloc] init];
    });
    return sharedInstance;
}

-(void) subscribeToConversation
{
   dispatch_async(dispatch_get_main_queue (),^{

    @try {
        if (![ALUserDefaultsHandler isLoggedIn]) {
            return;
        }
        
        if(self.session && self.session.status == MQTTSessionEventConnected)
        {
            NSLog(@"MQTT : IGNORING REQUEST, ALREADY CONNECTED");
            return;
        }
        
        NSLog(@"connecting to mqtt server");
        
        _session = [[MQTTSession alloc] initWithClientId:[NSString stringWithFormat:@"%@-%f",
                                                        [ALUserDefaultsHandler getUserKeyString],fmod([[NSDate date] timeIntervalSince1970], 10.0)]];
        _session.willFlag = TRUE;
        _session.willTopic = @"status";
        _session.willMsg = [[NSString stringWithFormat:@"%@,%@", [ALUserDefaultsHandler getUserKeyString], @"0"] dataUsingEncoding:NSUTF8StringEncoding];
        _session.willQoS = MQTTQosLevelAtMostOnce;
        [_session setDelegate:self];
        NSLog(@"waiting for connect...");
        
        [_session connectToHost:MQTT_URL port:[MQTT_PORT intValue] withConnectionHandler:^(MQTTSessionEvent event) {
            if (event == MQTTSessionEventConnected) {
                [_session publishAndWaitData:[[NSString stringWithFormat:@"%@,%@", [ALUserDefaultsHandler getUserKeyString], @"1"] dataUsingEncoding:NSUTF8StringEncoding]
                                    onTopic:@"status"
                                     retain:NO
                                        qos:MQTTQosLevelAtMostOnce];
                
                NSLog(@"MQTT: Subscribing to conversation topics.");
                [_session subscribeToTopic:[ALUserDefaultsHandler getUserKeyString] atLevel:MQTTQosLevelAtMostOnce];
                [_session subscribeToTopic:[NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], [ALUserDefaultsHandler getUserId]] atLevel:MQTTQosLevelAtMostOnce];
                [ALUserDefaultsHandler setLoggedInUserSubscribedMQTT:YES];
            }
        } messageHandler:^(NSData *data, NSString *topic) {
            
        }];
        
        NSLog(@"MQTT: connected...");
        
        /*if (session.status == MQTTSessionStatusConnected) {
         [session subscribeToTopic:[ALUserDefaultsHandler getUserKeyString] atLevel:MQTTQosLevelAtMostOnce];
         }*/
        
    }
    @catch (NSException * e) {
        NSLog(@"Exception: %@", e);
    }
    });
}

- (void)session:(MQTTSession*)session newMessage:(NSData*)data onTopic:(NSString*)topic {
    NSLog(@"MQTT got new message");
}

- (void)newMessage:(MQTTSession *)session data:(NSData *)data onTopic:(NSString *)topic qos:(MQTTQosLevel)qos retained:(BOOL)retained mid:(unsigned int)mid
{
    NSString *fullMessage = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSLog(@"MQTT_GOT_NEW_MESSAGE : %@", fullMessage);
    
    NSError *error = nil;
    NSDictionary *theMessageDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    NSString *type = [theMessageDict objectForKey:@"type"];
    NSLog(@"MQTT_NOTIFICATION_TYPE :: %@",type);
    NSString *notificationId = (NSString* )[theMessageDict valueForKey:@"id"];
    
    ALPushAssist *top = [[ALPushAssist alloc] init];
    if([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground || !top.isOurViewOnTop)
    {
        NSLog(@"Returing coz Application State is Background OR Our View is NOT on Top");
         if ([topic hasPrefix:@"typing"])
         {
             [self subProcessTyping:fullMessage];
         }
        return;
    }
    
    if(notificationId && [ALUserDefaultsHandler isNotificationProcessd:notificationId])
    {
        NSLog(@"NotificationId is already processed...MQTT :: %@",notificationId);
        return;
    }
    
    if ([topic hasPrefix:@"typing"])
    {
        [self subProcessTyping:fullMessage];
    }
    else
    {
        if ([type isEqualToString: @"MESSAGE_RECEIVED"] || [type isEqualToString:@"APPLOZIC_01"])
        {
            ALPushAssist* assistant = [[ALPushAssist alloc] init];
            ALMessage *alMessage = [[ALMessage alloc] initWithDictonary:[theMessageDict objectForKey:@"message"]];
            
            if([alMessage isHiddenMessage])
            {
                NSLog(@"< HIDDEN MESSAGE RECEIVED >");
                [ALMessageService getLatestMessageForUser:[ALUserDefaultsHandler getDeviceKeyString]
                                           withCompletion:^(NSMutableArray *message, NSError *error) { }];
            }
            else
            {
                NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
                [dict setObject:[alMessage getNotificationText] forKey:@"alertValue"];
                [dict setObject:[NSNumber numberWithInt:APP_STATE_BACKGROUND] forKey:@"updateUI"];
                
                [ALMessageService getLatestMessageForUser:[ALUserDefaultsHandler getDeviceKeyString] withCompletion:^(NSMutableArray *message, NSError *error) {

                    NSLog(@"ALMQTTConversationService SYNC CALL");
                    if(!assistant.isOurViewOnTop)
                    {
                        [assistant assist:alMessage.contactIds and:dict ofUser:alMessage.contactIds];
                        [dict setObject:@"mqtt" forKey:@"Calledfrom"];
                    }
                    else
                    {
                        [self.alSyncCallService syncCall:alMessage];
                        [self.mqttConversationDelegate syncCall:alMessage andMessageList:nil];
                    }
                }];
            }
        }
        else if ([type isEqualToString:@"MESSAGE_SENT"] || [type isEqualToString:@"APPLOZIC_02"])
        {
            NSDictionary * message = [theMessageDict objectForKey:@"message"];
            ALMessage *alMessage = [[ALMessage alloc] initWithDictonary:message];
            
            NSLog(@"Message's DKey:%@ \n DeviceKey:%@",alMessage.deviceKey,[ALUserDefaultsHandler getDeviceKeyString]);
            
            if(alMessage.deviceKey && [alMessage.deviceKey isEqualToString:[ALUserDefaultsHandler getDeviceKeyString]]){
                NSLog(@"Returning because message SENT BY SAME DEVICE");
                return;
            }
            
            [ALMessageService getMessageSENT:alMessage withCompletion:^(NSMutableArray * messageArray, NSError *error) {
                
                if(messageArray.count > 0)
                {
                    [self.alSyncCallService syncCall:alMessage];
                    [self.mqttConversationDelegate syncCall:alMessage andMessageList:nil];
                }
            }];
            
            NSString * key = [message valueForKey:@"pairedMessageKey"];
            NSString * contactID = [message valueForKey:@"contactIds"];
            [self.alSyncCallService updateMessageDeliveryReport:key withStatus:SENT];
            [self.mqttConversationDelegate delivered:key contactId:contactID withStatus:SENT];
            
        }
        else if ([type isEqualToString:@"MESSAGE_DELIVERED"] || [type isEqualToString:@"APPLOZIC_04"]) {
            
            NSArray *deliveryParts = [[theMessageDict objectForKey:@"message"] componentsSeparatedByString:@","];
            NSString * pairedKey = deliveryParts[0];
            NSString * contactId = (deliveryParts.count > 1) ? deliveryParts[1] : nil;
            
            [self.alSyncCallService updateMessageDeliveryReport:pairedKey withStatus:DELIVERED];
            [self.mqttConversationDelegate delivered:pairedKey contactId:contactId withStatus:DELIVERED];
        }
        else if([type isEqualToString:@"MESSAGE_DELETED"] || [type isEqualToString:@"APPLOZIC_05"])
        {
            NSString * messageKey = [[theMessageDict valueForKey:@"message"] componentsSeparatedByString:@","][0];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NOTIFY_MESSAGE_DELETED" object:messageKey];
        }
        else if ([type isEqualToString:@"MESSAGE_DELIVERED_READ"] || [type isEqualToString:@"APPLOZIC_08"])
        {
            NSArray  * deliveryParts = [[theMessageDict objectForKey:@"message"] componentsSeparatedByString:@","];
            NSString * pairedKey = deliveryParts[0];
            NSString * contactId = deliveryParts.count>1 ? deliveryParts[1]:nil;
            
            [self.alSyncCallService updateMessageDeliveryReport:pairedKey withStatus:DELIVERED_AND_READ];
            [self.mqttConversationDelegate delivered:pairedKey contactId:contactId withStatus:DELIVERED_AND_READ];
        }
        else if ([type isEqualToString:@"CONVERSATION_DELIVERED_AND_READ"] || [type isEqualToString:@"APPLOZIC_10"])
        {
            NSString *contactId = [theMessageDict objectForKey:@"message"];
            [self.alSyncCallService updateDeliveryStatusForContact: contactId withStatus:DELIVERED_AND_READ];
            [self.mqttConversationDelegate updateStatusForContact:contactId withStatus:DELIVERED_AND_READ];
        }
        else if ([type isEqualToString:@"USER_CONNECTED"]||[type isEqualToString: @"APPLOZIC_11"])
        {
            ALUserDetail *alUserDetail = [[ALUserDetail alloc] init];
            alUserDetail.userId = [theMessageDict objectForKey:@"message"];
            alUserDetail.lastSeenAtTime = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] * 1000];
            alUserDetail.connected = YES;
            [self.alSyncCallService updateConnectedStatus: alUserDetail];
            [self.mqttConversationDelegate updateLastSeenAtStatus: alUserDetail];
        }
        else if ([type isEqualToString:@"APPLOZIC_12"])
        {
            NSArray *parts = [[theMessageDict objectForKey:@"message"] componentsSeparatedByString:@","];
            
            ALUserDetail *alUserDetail = [[ALUserDetail alloc] init];
            alUserDetail.userId = parts[0];
            alUserDetail.lastSeenAtTime = [NSNumber numberWithDouble:[parts[1] doubleValue]];
            alUserDetail.connected = NO;
            [self.alSyncCallService updateConnectedStatus: alUserDetail];
            [self.mqttConversationDelegate updateLastSeenAtStatus: alUserDetail];
        }
        else if ([type isEqualToString:@"APPLOZIC_15"]) //Added or removed by admin
        {
            ALChannelService *channelService = [[ALChannelService alloc] init];
            [channelService syncCallForChannel];
            // TODO HANDLE
        }
        else if ([type isEqualToString:@"APPLOZIC_06"])
        {
            // TODO HANDLE
            // IF CONTACT ID THE DELETE USER
            // IF CHANNEL KEY then DELETE CHANNEL
        }
        else if ([type isEqualToString:@"APPLOZIC_16"])
        {
            [self processUserBlockNotification:theMessageDict andUserBlockFlag:YES];
        }
        else if ([type isEqualToString:@"APPLOZIC_17"])
        {
            [self processUserBlockNotification:theMessageDict andUserBlockFlag:NO];
        }
        else
        {
             NSLog(@"MQTT NOTIFICATION \"%@\" IS NOT HANDLED",type);
        }
    }
}

-(void)subProcessTyping:(NSString *)fullMessage
{
    NSArray *typingParts = [fullMessage componentsSeparatedByString:@","];
    NSString *applicationKey = typingParts[0]; //Note: will get used once we support messaging from one app to another
    NSString *userId = typingParts[1];
    BOOL typingStatus = [typingParts[2] boolValue];
    [self.mqttConversationDelegate updateTypingStatus:applicationKey userId:userId status:typingStatus];
}

-(void)processUserBlockNotification:(NSDictionary *)theMessageDict andUserBlockFlag:(BOOL)flag
{
    NSArray *mqttMSGArray = [[theMessageDict valueForKey:@"message"] componentsSeparatedByString:@":"];
    NSString *BlockType = mqttMSGArray[0];
    NSString *userId = mqttMSGArray[1];
    if(![BlockType isEqualToString:@"BLOCKED_BY"] && ![BlockType isEqualToString:@"UNBLOCKED_BY"])
    {
        return;
    }

    ALContactDBService *dbService = [ALContactDBService new];
    [dbService setBlockByUser:userId andBlockedByState:flag];
    [self.mqttConversationDelegate reloadDataForUserBlockNotification:userId andBlockFlag:flag];
}

- (void)subAckReceived:(MQTTSession *)session msgID:(UInt16)msgID grantedQoss:(NSArray *)qoss
{
    NSLog(@"subscribed");
}

- (void)connected:(MQTTSession *)session {
    
}

- (void)connectionClosed:(MQTTSession *)session {
    NSLog(@"MQTT connection closed");
    [self.mqttConversationDelegate mqttConnectionClosed];
    
    //Todo: inform controller about connection closed.
}

- (void)handleEvent:(MQTTSession *)session
              event:(MQTTSessionEvent)eventCode
              error:(NSError *)error {
}

- (void)received:(MQTTSession *)session type:(int)type qos:(MQTTQosLevel)qos retained:(BOOL)retained duped:(BOOL)duped mid:(UInt16)mid data:(NSData *)data {
    
}

-(void) sendTypingStatus:(NSString *) applicationKey userID:(NSString *) userId andChannelKey:(NSNumber *)channelKey typing: (BOOL) typing;
{
    if(!_session){
        return;
    }
    NSLog(@"Sending typing status %d to: %@", typing, userId);

    NSString * dataString = [NSString stringWithFormat:@"%@,%@,%i", [ALUserDefaultsHandler getApplicationKey],
                             [ALUserDefaultsHandler getUserId], typing ? 1 : 0];
     
    NSString * topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], userId];
     
    if(channelKey)
    {
        topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], channelKey];
    }
    NSLog(@"MQTT_PUBLISH :: %@",topicString);
     
    NSData * data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
    [_session publishDataAtMostOnce:data onTopic:topicString];
    
}

-(void) unsubscribeToConversation {
    NSString *userKey = [ALUserDefaultsHandler getUserKeyString];
    [self unsubscribeToConversation: userKey];
}

-(void) unsubscribeToConversation: (NSString *) userKey
{
    dispatch_async(dispatch_get_main_queue (),^{
        
        if (_session == nil) {
            return;
        }
        [_session publishAndWaitData:[[NSString stringWithFormat:@"%@,%@", userKey, @"0"] dataUsingEncoding:NSUTF8StringEncoding]
                            onTopic:@"status"
                             retain:NO
                                qos:MQTTQosLevelAtMostOnce];
        [_session unsubscribeTopic:[ALUserDefaultsHandler getUserKeyString]];
        [_session unsubscribeTopic:[NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], [ALUserDefaultsHandler getUserId]]];
        [_session close];
        NSLog(@"Disconnected from mqtt");
    });
}

-(void)subscribeToChannelConversation:(NSNumber *)channelKey
{
    NSLog(@"MQTT_CHANNEL/USER_SUBSCRIBING");
    dispatch_async(dispatch_get_main_queue (),^{

    @try
    {
        if (!_session && _session.status == MQTTSessionStatusConnected) {
             NSLog(@"MQTT_SESSION_NULL");
            return;
        }
        NSString * topicString = @"";
        if(channelKey)
        {
            topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], channelKey];
        }
        else
        {
            topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], [ALUserDefaultsHandler getUserId]];
            [ALUserDefaultsHandler setLoggedInUserSubscribedMQTT:YES];
        }
        [_session subscribeToTopic:topicString atLevel:MQTTQosLevelAtMostOnce]; 
        NSLog(@"MQTT_CHANNEL/USER_SUBSCRIBING_COMPLETE");
    }
    @catch (NSException * exp) {
        NSLog(@"Exception in subscribing channel :: %@", exp.description);
    }
    });

}

-(void)unSubscribeToChannelConversation:(NSNumber *)channelKey
{
     NSLog(@"MQTT_CHANNEL/USER_UNSUBSCRIBING");
       dispatch_async(dispatch_get_main_queue (),^{
        if (!_session) {
            NSLog(@"MQTT_SESSION_NULL");
            return;
        }
         NSString * topicString = @"";
         if(channelKey)
         {
             topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], channelKey];
         }else
         {
             topicString = [NSString stringWithFormat:@"typing-%@-%@", [ALUserDefaultsHandler getApplicationKey], [ALUserDefaultsHandler getUserId]];
             [ALUserDefaultsHandler setLoggedInUserSubscribedMQTT:NO];
         }
        [_session unsubscribeTopic:topicString];
         NSLog(@"MQTT_CHANNEL/USER_UNSUBSCRIBED_COMPLETE");
      });
}

@end
