//
//  ALChannelClientService.h
//  Applozic
//
//  Created by devashish on 28/12/2015.
//  Copyright © 2015 applozic Inc. All rights reserved.
//  class for server calls

#import <Foundation/Foundation.h>
#import "ALConstant.h"
#import "ALRequestHandler.h"
#import "ALResponseHandler.h"
#import "ALChannel.h"
#import "ALChannelUserX.h"
#import "ALChannelDBService.h"
#import "ALChannelFeed.h"
#import "ALChannelCreateResponse.h"
#import "ALChannelSyncResponse.h"

@interface ALChannelClientService : NSObject

+(void)getChannelInfo:(NSNumber *)channelKey orClientChannelKey:(NSString *)clientChannelKey withCompletion:(void(^)(NSError *error, ALChannel *channel)) completion;

+(void)createChannel:(NSString *)channelName orClientChannelKey:(NSString *)clientChannelKey andMembersList:(NSMutableArray *)memberArray andImageLink:(NSString *)imageLink  withCompletion:(void(^)(NSError *error, ALChannelCreateResponse *response))completion;

+(void)addMemberToChannel:(NSString *)userId orClientChannelKey:(NSString *)clientChannelKey andChannelKey:(NSNumber *)channelKey withComletion:(void(^)(NSError *error, ALAPIResponse *response))completion;

+(void)removeMemberFromChannel:(NSString *)userId orClientChannelKey:(NSString *)clientChannelKey andChannelKey:(NSNumber *)channelKey withComletion:(void(^)(NSError *error, ALAPIResponse *response))completion;

+(void)deleteChannel:(NSNumber *)channelKey orClientChannelKey:(NSString *)clientChannelKey withComletion:(void(^)(NSError *error, ALAPIResponse *response))completion;

+(void)leaveChannel:(NSNumber *)channelKey orClientChannelKey:(NSString *)clientChannelKey withUserId:(NSString *)userId andCompletion:(void(^)(NSError *error, ALAPIResponse *response))completion;


+(void)renameChannel:(NSNumber *)channelKey orClientChannelKey:(NSString *)clientChannelKey andNewName:(NSString *)newName andCompletion:(void(^)(NSError *error, ALAPIResponse *response))completion;

+(void)syncCallForChannel:(NSNumber *)channelKey andCompletion:(void(^)(NSError *error, ALChannelSyncResponse *response))completion;

-(void)markConversationAsRead:(NSNumber *)channelKey withCompletion:(void (^)(NSString *, NSError *))completion;
@end
