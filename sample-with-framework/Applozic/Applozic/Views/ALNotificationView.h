//
//  ALNotificationView.h
//  ChatApp
//
//  Created by Devashish on 06/10/15.
//  Copyright © 2015 AppLogic. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ALNotificationView : UILabel


@property (retain ,nonatomic) NSString * contactId;

@property (retain ,nonatomic) NSString * checkContactId;

-(instancetype)initWithContactId:(NSString*) contactId withAlertMessage: (NSString *) alertMessage andContentType:(short)type;

-(void)displayNotification:(id)delegate;
-(void)displayNotificationNew:(id)delegate;
@end