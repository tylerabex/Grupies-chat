//
//  ALChatViewController.m
//  ChatApp
//
//  Copyright (c) 2015 AppLozic. All rights reserved.
//

#import "ALChatViewController.h"
#import "ALChatCell.h"
#import "ALMessageService.h"
#import "ALUtilityClass.h"
#import <CoreGraphics/CoreGraphics.h>
#import "ALJson.h"
#import <CoreData/CoreData.h>
#import "ALDBHandler.h"
#import "DB_Message.h"
#import "ALMessagesViewController.h"
#import "ALNewContactsViewController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import "UIImage+Utility.h"
#import "ALChatCell_Image.h"
#import "ALFileMetaInfo.h"
#import "DB_FileMetaInfo.h"
#import "UIImageView+WebCache.h"
#import "ALConnection.h"
#import "ALConnectionQueueHandler.h"
#import "ALRequestHandler.h"
#import "ALParsingHandler.h"
#import "ALUserDefaultsHandler.h"
#import "ALMessageDBService.h"
#import "ALImagePickerHandler.h"

@interface ALChatViewController ()<ALChatCellImageDelegate,NSURLConnectionDataDelegate,NSURLConnectionDelegate>

@property (nonatomic, assign) NSInteger startIndex;

@property (nonatomic,assign) int rp;

@property (nonatomic,assign) NSUInteger mTotalCount;

@property (nonatomic,retain) UIImagePickerController * mImagePicker;

@end

@implementation ALChatViewController

//------------------------------------------------------------------------------------------------------------------
    #pragma mark - View lifecycle
//------------------------------------------------------------------------------------------------------------------

- (void)viewDidLoad {

    [super viewDidLoad];

    [self initialSetUp];
    [self fetchMessageFromDB];
    [self loadChatView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}
-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

//------------------------------------------------------------------------------------------------------------------
    #pragma mark - SetUp/Theming
//------------------------------------------------------------------------------------------------------------------

-(void)initialSetUp {
    self.rp = 20;
    self.startIndex = 0 ;
    self.mMessageListArray = [NSMutableArray new];
    self.mImagePicker = [[UIImagePickerController alloc] init];
    self.mImagePicker.delegate = self;

    self.mSendMessageTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter message here" attributes:@{NSForegroundColorAttributeName:[UIColor lightGrayColor]}];

    [self.mTableView registerClass:[ALChatCell class] forCellReuseIdentifier:@"ChatCell"];
    [self.mTableView registerClass:[ALChatCell_Image class] forCellReuseIdentifier:@"ChatCell_Image"];

    self.navigationItem.title = self.mLatestMessage.contactIds;
}

-(void)fetchMessageFromDB {

    ALDBHandler * theDbHandler = [ALDBHandler sharedInstance];
    NSFetchRequest * theRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
    theRequest.predicate = [NSPredicate predicateWithFormat:@"contactId = %@",self.mLatestMessage.contactIds];
    self.mTotalCount = [theDbHandler.managedObjectContext countForFetchRequest:theRequest error:nil];
    NSLog(@"%lu",(unsigned long)self.mTotalCount);
}


-(void)refreshTable:(id)sender {

    NSLog(@"calling refresh from server....");
    //TODO: get the user name, devicekey String and make server call...

    NSString *deviceKeyString =[ALUserDefaultsHandler getDeviceKeyString ] ;
    NSString *lastSyncTime =[ALUserDefaultsHandler
                              getLastSyncTime ];
    if ( lastSyncTime == NULL ){
        lastSyncTime = @"0";
    }

    [ ALMessageService getLatestMessageForUser: deviceKeyString lastSyncTime: lastSyncTime withCompletion:^(ALMessageList *messageListResponse, NSError *error) {
        if (error) {
            NSLog(@"%@",error);
            return ;
        }else {
            if (messageListResponse.messageList.count > 0 ){
                NSString *createdAt =[(ALMessage*) [ messageListResponse.messageList firstObject] createdAtTime ];
                long val = [createdAt longLongValue]+1;
                [ALUserDefaultsHandler
                 setLastSyncTime:[NSString stringWithFormat:@"%ld", val]];
                
            }
            NSLog(@" message jason from client ::%@",[ALUserDefaultsHandler
                                                      getLastSyncTime ] );

            [self.mTableView reloadData];

        }
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

//------------------------------------------------------------------------------------------------------------------
    #pragma mark - IBActions
//------------------------------------------------------------------------------------------------------------------

-(void) postMessage
{
    ALMessage * theMessage = [self getMessageToPost];
    [self.mMessageListArray addObject:theMessage];
    [self.mTableView reloadData];
    dispatch_async(dispatch_get_main_queue(), ^{
        [super scrollTableViewToBottomWithAnimation:YES];
    });
    // save message to db
    [self.mSendMessageTextField setText:nil];
    self.mTotalCount = self.mTotalCount+1;
    self.startIndex = self.startIndex + 1;
    [ALMessageService sendMessages:theMessage withCompletion:^(NSString *message, NSError *error) {
        if (error) {
            NSLog(@"%@",error);
            return ;
        }
        theMessage.sent = [NSNumber numberWithBool:YES];
        theMessage.keyString = message;
        [self.mTableView reloadData];
    }];
}


//------------------------------------------------------------------------------------------------------------------
    #pragma mark - TableView Datasource
//------------------------------------------------------------------------------------------------------------------

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    return self.mMessageListArray.count > 0 ? self.mMessageListArray.count : 0;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    ALMessage * theMessage = self.mMessageListArray[indexPath.row];

    if (theMessage.fileMetas.thumbnailUrl == nil ) { // textCell
        
        ALChatCell *theCell = (ALChatCell *)[tableView dequeueReusableCellWithIdentifier:@"ChatCell"];
        theCell.tag = indexPath.row;
        [theCell populateCell:theMessage viewSize:self.view.frame.size ];
        return theCell;
        
    }
    else
    {
        ALChatCell_Image *theCell = (ALChatCell_Image *)[tableView dequeueReusableCellWithIdentifier:@"ChatCell_Image"];
        theCell.tag = indexPath.row;
        theCell.delegate = self;
        theCell.backgroundColor = [UIColor clearColor];
        [theCell populateCell:theMessage viewSize:self.view.frame.size ];
        [self.view layoutIfNeeded];
        return theCell;
       
    }
}

//------------------------------------------------------------------------------------------------------------------
    #pragma mark - TableView Delegate
//------------------------------------------------------------------------------------------------------------------

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ALMessage * theMessage = self.mMessageListArray[indexPath.row];
    if (theMessage.fileMetas.thumbnailUrl == nil) {
        CGSize theTextSize = [ALUtilityClass getSizeForText:theMessage.message maxWidth:self.view.frame.size.width-115 font:@"Helvetica-Bold" fontSize:15];
        int extraSpace = 40 ;
        return theTextSize.height+21+extraSpace;
    }
    else
    {
        return self.view.frame.size.width-110+40;
    }
}

//------------------------------------------------------------------------------------------------------------------
    #pragma mark - Helper Method
//------------------------------------------------------------------------------------------------------------------

-(ALMessage *) getMessageToPost
{
    ALMessage * theMessage = [ALMessage new];

    theMessage.type = @"5";

    theMessage.contactIds = self.mLatestMessage.contactIds;//1

    theMessage.to = self.mLatestMessage.to;//2

    theMessage.createdAtTime = [NSString stringWithFormat:@"%ld",(long)[[NSDate date] timeIntervalSince1970]*1000];

    theMessage.deviceKeyString = @"agpzfmFwcGxvemljciYLEgZTdVVzZXIYgICAgK_hmQoMCxIGRGV2aWNlGICAgICAgIAKDA";

    theMessage.message = self.mSendMessageTextField.text;//3

    theMessage.sendToDevice = NO;

    theMessage.sent = NO;

    theMessage.shared = NO;

    theMessage.fileMetas = nil;

    theMessage.read = NO;

    theMessage.storeOnDevice = NO;

    theMessage.keyString = @"test keystring";
    theMessage.delivered=NO;

    theMessage.fileMetaKeyStrings = @[];//4

    return theMessage;
}

-(ALFileMetaInfo *) getFileMetaInfo {

    ALFileMetaInfo *info = [ALFileMetaInfo new];

    info.blobKeyString = @"";
    info.contentType = @"";
    info.createdAtTime = @"";
    info.keyString = @"";
    info.name = @"";
    info.size = @"";
    info.suUserKeyString = @"";
    info.thumbnailUrl = @"";
    info.progressValue = 0;

    return info;
}


#pragma mark helper methods

-(void) loadChatView
{
    BOOL isLoadEarlierTapped = self.mMessageListArray.count == 0 ? NO : YES ;
    ALDBHandler * theDbHandler = [ALDBHandler sharedInstance];
    NSFetchRequest * theRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
    [theRequest setFetchLimit:self.rp];
    theRequest.predicate = [NSPredicate predicateWithFormat:@"contactId = %@",self.mLatestMessage.contactIds];
    [theRequest setFetchOffset:self.startIndex];
    [theRequest setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]]];

    NSArray * theArray = [theDbHandler.managedObjectContext executeFetchRequest:theRequest error:nil];
    ALMessageDBService* messageDBService = [[ALMessageDBService alloc]init];

    for (DB_Message * theEntity in theArray) {
        ALMessage * theMessage = [ messageDBService createMessageForSMSEntity:theEntity];
        [self.mMessageListArray insertObject:theMessage atIndex:0];
    }

    [self.mTableView reloadData];

    if (isLoadEarlierTapped) {
        if ((theArray != nil && theArray.count < self.rp )|| self.mMessageListArray.count == self.mTotalCount) {
            self.mTableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectZero];
        }
        self.startIndex = self.startIndex + theArray.count;
        [self.mTableView reloadData];
        if (theArray.count != 0) {
            CGRect theFrame = [self.mTableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:theArray.count-1 inSection:0]];
            [self.mTableView setContentOffset:CGPointMake(0, theFrame.origin.y-60)];
        }
    }
    else
    {
        if (theArray.count < self.rp || self.mMessageListArray.count == self.mTotalCount) {
            self.mTableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectZero];
        }
        else
        {
            self.mTableView.tableHeaderView = self.mTableHeaderView;
        }
        self.startIndex = theArray.count;

        if (self.mMessageListArray.count != 0) {
            CGRect theFrame = [self.mTableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:theArray.count-1 inSection:0]];
            [self.mTableView setContentOffset:CGPointMake(0, theFrame.origin.y)];
        }

    }
}


#pragma mark IBActions

-(void) attachmentAction
{
    // check os , show sheet or action controller

    NSLog(@"%@",[UIDevice currentDevice].systemVersion);

    if ([UIDevice currentDevice].systemVersion.floatValue < 8.0 ) { // ios 7 and previous

        [self showActionSheet];

    }
    else // ios 8
    {

        [self showActionAlert];
    }


}

#pragma mark chatCellImageDelegate

-(void)downloadRetryButtonActionDelegate:(int)index andMessage:(ALMessage *)message
{
    ALChatCell_Image *imageCell = (ALChatCell_Image *)[self.mTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
    imageCell.progresLabel.alpha = 1;
    imageCell.mMessage.fileMetas.progressValue = 0;
    imageCell.mDowloadRetryButton.alpha = 0;
    message.inProgress = YES;

    NSMutableArray * theCurrentConnectionsArray = [[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue];
    NSArray * theFiletredArray = [theCurrentConnectionsArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"keystring == %@", message.fileMetas.keyString]];
    if ([message.type isEqualToString:@"5"]) { // retry or cancel
        if (theFiletredArray.count == 0) { // retry
            message.isUploadFailed = NO;
            NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.thumbnailUrl == %@",message.fileMetas.thumbnailUrl];
            NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];
            DB_Message  * smsEntity = theArray[0];
            smsEntity.inProgress = [NSNumber numberWithBool:YES];
            smsEntity.isUploadFailed = [NSNumber numberWithBool:NO];
            [[ALDBHandler sharedInstance].managedObjectContext save:nil];
            [self uploadImage:message];
        }
    }
    else // download or cancel
    {
        if (theFiletredArray.count == 0) { // download
            NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.keyString == %@",message.fileMetas.keyString];
            NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];
            DB_Message  * smsEntity = theArray[0];
            smsEntity.inProgress = [NSNumber numberWithBool:YES];

            [[ALDBHandler sharedInstance].managedObjectContext save:nil];
            [self processImageDownloadforMessage:message withTag:index];
        }
    }
}

-(void)stopDownloadForIndex:(int)index andMessage:(ALMessage *)message {

    ALChatCell_Image *imageCell = (ALChatCell_Image *)[self.mTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
    imageCell.progresLabel.alpha = 0;
    imageCell.mDowloadRetryButton.alpha = 1;
    message.inProgress = NO;

    NSMutableArray * theCurrentConnectionsArray = [[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue];
    NSArray * theFiletredArray = nil;

    if ([message.type isEqualToString:@"5"]) { // retry or cancel
        theFiletredArray = [theCurrentConnectionsArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"connectionTag == %d", index]];
        if (theFiletredArray.count != 0) { // cancel
            message.isUploadFailed = YES;
            [imageCell.mDowloadRetryButton setTitle:[message.fileMetas getTheSize] forState:UIControlStateNormal];
            [imageCell.mDowloadRetryButton setImage:[UIImage imageNamed:@"ic_upload.png"] forState:UIControlStateNormal];

            ALDBHandler *theDBHandler = [ALDBHandler sharedInstance];
            NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.thumbnailUrl == %@",message.fileMetas.thumbnailUrl];

            NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];

            DB_Message  * smsEntity = theArray[0];
            smsEntity.isUploadFailed = [NSNumber numberWithBool:YES];
            smsEntity.inProgress = [NSNumber numberWithBool:NO];
            [theDBHandler.managedObjectContext save:nil];

            [self cancelImageDownloadForMessage:message withtag:index];
        }

    }
    else // download or cancel
    {
        theFiletredArray = [theCurrentConnectionsArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"keystring == %@", message.fileMetas.keyString]];
        if (theFiletredArray.count != 0) { // cancel
            NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.keyString == %@",message.fileMetas.keyString];
            NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];
            DB_Message  * smsEntity = theArray[0];
            smsEntity.inProgress = [NSNumber numberWithBool:YES];
            [[ALDBHandler sharedInstance].managedObjectContext save:nil];
            [self cancelImageDownloadForMessage:message withtag:index];
        }
    }
}

-(void) processImageDownloadforMessage:(ALMessage *) message withTag:(int) tag
{
    NSString * urlString = [NSString stringWithFormat:@"%@/%@",APPLOGIC_IMAGEDOWNLOAD_BASEURL,message.fileMetas.keyString];
    NSMutableURLRequest * theRequest = [ALRequestHandler createGETRequestWithUrlString:urlString paramString:nil];
    ALConnection * connection = [[ALConnection alloc] initWithRequest:theRequest delegate:self startImmediately:YES];
    connection.keystring = message.fileMetas.keyString;
    connection.connectionTag = tag;
    connection.connectionType = @"Image Downloading";
    [[[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue] addObject:connection];
}

-(void) cancelImageDownloadForMessage:(ALMessage *) message withtag:(int) tag
{
    // cancel connection
    NSMutableArray * theConnectionArray =  [[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue];
    ALConnection * connection = [[theConnectionArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"connectionTag == %d",tag]] objectAtIndex:0];
    [connection cancel];
    [[[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue] removeObject:connection];
}



#pragma mark connection delegates

-(void)connection:(ALConnection *)connection didReceiveData:(NSData *)data
{
    
    NSLog(@"###connection didReceiveData :didReceiveData");
    
    [connection.mData appendData:data];
    if ([connection.connectionType isEqualToString:@"Image Posting"]) {

    }else {
        NSIndexPath *path = [NSIndexPath indexPathForRow:connection.connectionTag inSection:0];
        ALChatCell_Image *cell = (ALChatCell_Image *)[self.mTableView cellForRowAtIndexPath:path];
        cell.mMessage.fileMetas.progressValue = [self bytesConvertsToDegree:[cell.mMessage.fileMetas.size floatValue] comingBytes:(CGFloat)connection.mData.length];
        NSLog(@"%lu %f",(unsigned long)connection.mData.length,[cell.mMessage.fileMetas.size floatValue]);
    }
}

-(CGFloat)bytesConvertsToDegree:(CGFloat)totalBytesExpectedToWrite comingBytes:(CGFloat)totalBytesWritten {
    CGFloat  totalBytes = totalBytesExpectedToWrite;
    CGFloat writtenBytes = totalBytesWritten;
    CGFloat divergence = totalBytes/360;
    CGFloat degree = writtenBytes/divergence;
    return degree;
}

-(void)connectionDidFinishLoading:(ALConnection *)connection {
    NSLog(@"###connection didReceiveData :didReceiveData");


    if ([connection.connectionType isEqualToString:@"Image Posting"]) {
        NSLog(@"%@",[[NSString alloc] initWithData:connection.mData encoding:NSUTF8StringEncoding]);
        [[[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue] removeObject:connection];
        NSError * theJsonError = nil;
        NSDictionary *theJson = [NSJSONSerialization JSONObjectWithData:connection.mData options:NSJSONReadingMutableLeaves error:&theJsonError];
        NSDictionary *fileInfo = [theJson objectForKey:@"fileMeta"];

        ALMessage *theMessage = [self.mMessageListArray objectAtIndex:connection.connectionTag];
        NSLog(@"%@",[fileInfo objectForKey:@"blobKeyString"]);
        NSString *localFileURL = theMessage.fileMetas.thumbnailUrl;
        theMessage.fileMetas.blobKeyString = [fileInfo objectForKey:@"blobKeyString"];
        theMessage.fileMetas.contentType = [fileInfo objectForKey:@"contentType"];
        theMessage.fileMetas.createdAtTime = [fileInfo objectForKey:@"createdAtTime"];
        theMessage.fileMetas.keyString = [fileInfo objectForKey:@"keyString"];
        theMessage.fileMetas.name = [fileInfo objectForKey:@"name"];
        theMessage.fileMetas.size = [fileInfo objectForKey:@"size"];
        theMessage.fileMetas.suUserKeyString = [fileInfo objectForKey:@"suUserKeyString"];
        theMessage.fileMetas.thumbnailUrl = [fileInfo objectForKey:@"thumbnailUrl"];
        theMessage.fileMetaKeyStrings = @[theMessage.fileMetas.keyString];

        DB_FileMetaInfo * theFileMetaInfo = connection.fileMetaInfo;
        theFileMetaInfo.blobKeyString = theMessage.fileMetas.blobKeyString;
        theFileMetaInfo.contentType = theMessage.fileMetas.contentType;
        theFileMetaInfo.createdAtTime = theMessage.fileMetas.createdAtTime;
        theFileMetaInfo.keyString = theMessage.fileMetas.keyString;
        theFileMetaInfo.name = theMessage.fileMetas.name;
        theFileMetaInfo.size = theMessage.fileMetas.size;
        theFileMetaInfo.suUserKeyString = theMessage.fileMetas.suUserKeyString;

        ALDBHandler * theDBHandler = [ALDBHandler sharedInstance];
        
        [ALMessageService sendMessages:theMessage withCompletion:^(NSString *message, NSError *error) {

            if (error) {

                NSLog(@"%@",error);

                return ;
            }
            theMessage.sent = YES;
            theMessage.keyString = message;
            theMessage.fileMetas.thumbnailUrl = localFileURL;
            theMessage.inProgress = NO;
            theMessage.isUploadFailed = NO;
            NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
            fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.keyString == %@",theMessage.fileMetas.keyString];
            NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];
            DB_Message  * smsEntity = theArray[0];
            smsEntity.isSent = [NSNumber numberWithBool:YES];
            smsEntity.keyString = message;
            smsEntity.inProgress = [NSNumber numberWithBool:NO];
            smsEntity.isUploadFailed = [NSNumber numberWithBool:NO];
            [theDBHandler.managedObjectContext save:nil];

            [self.mTableView reloadData];
        }];

    }else {
        // remove connection
        [[[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue] removeObject:connection];
        // save file to doc
        NSString * docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString * filePath = [docPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.local",connection.keystring]];
        [connection.mData writeToFile:filePath atomically:YES];
        // update db
        NSFetchRequest * fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"DB_Message"];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fileMetaInfo.keyString == %@",connection.keystring];
        NSArray * theArray = [[ALDBHandler sharedInstance].managedObjectContext executeFetchRequest:fetchRequest error:nil];
        DB_Message  * smsEntity = theArray[0];
        smsEntity.isStoredOnDevice = [NSNumber numberWithBool:YES];
        smsEntity.inProgress = [NSNumber numberWithBool:NO];
        smsEntity.filePath = [NSString stringWithFormat:@"%@.local",connection.keystring];;
        [[ALDBHandler sharedInstance].managedObjectContext save:nil];
        // reload tableview
        NSArray * filteredArray = [self.mMessageListArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"fileMetas.keyString == %@",connection.keystring]];

        if (filteredArray.count > 0) {
            ALMessage * message = filteredArray[0];
            message.storeOnDevice = YES;
            message.inProgress = NO;
            message.imageFilePath = [NSString stringWithFormat:@"%@.local",connection.keystring];
        }
        [self.mTableView reloadData];
    }
}

-(void)connection:(ALConnection *)connection didFailWithError:(NSError *)error
{
    NSLog(@"%@",error);
    [[[ALConnectionQueueHandler sharedConnectionQueueHandler] getCurrentConnectionQueue] removeObject:connection];
}

-(void)connection:(ALConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite {
    NSLog(@"###connection didSendBodyData :didSendBodyData");

    NSLog(@"bytesWritten %ld",(long)bytesWritten);
    NSLog(@"totalBytesWritten %ld",(long)totalBytesWritten);
    NSLog(@"totalBytesExpectedToWrite %ld",(long)totalBytesExpectedToWrite);

    NSIndexPath *path = [NSIndexPath indexPathForRow:connection.connectionTag inSection:0];
    ALChatCell_Image *cell = (ALChatCell_Image *)[self.mTableView cellForRowAtIndexPath:path];
    //[self bytesConvertsToDegree:totalBytesExpectedToWrite comingBytes:totalBytesWritten];
    cell.mMessage.fileMetas.progressValue = [self bytesConvertsToDegree:totalBytesExpectedToWrite comingBytes:totalBytesWritten];
    NSLog(@"###frogressValue : %f",cell.mMessage.fileMetas.progressValue);
    NSLog(@"%lu %f",(unsigned long)connection.mData.length,[cell.mMessage.fileMetas.size floatValue]);
}

#pragma mark image picker delegates

-(void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    [self dismissViewControllerAnimated:YES completion:nil];

    UIImage * image = [info valueForKey:UIImagePickerControllerOriginalImage];
    image = [image getCompressedImageLessThanSize:5];

    // save image to doc
    NSString * filePath = [ALImagePickerHandler saveImageToDocDirectory:image];
    // create message object
    ALMessage * theMessage = [self getMessageToPost];
    theMessage.fileMetas = [self getFileMetaInfo];
    theMessage.imageFilePath = filePath.lastPathComponent;
    NSData *imageSize = [NSData dataWithContentsOfFile:filePath];
    theMessage.fileMetas.size = [NSString stringWithFormat:@"%lu",(unsigned long)imageSize.length];
    //theMessage.fileMetas.thumbnailUrl = filePath.lastPathComponent;

    // save msg to db
    
    [self.mMessageListArray addObject:theMessage];
    [self.mTableView reloadData];
    ALDBHandler * theDBHandler = [ALDBHandler sharedInstance];
    ALMessageDBService* messageDBService = [[ALMessageDBService alloc]init];
    DB_Message * theSmsEntity = [messageDBService createSMSEntityForDBInsertionWithMessage:theMessage];
    theMessage.msgDBObjectId = [theSmsEntity objectID];
    [theDBHandler.managedObjectContext save:nil];
    dispatch_async(dispatch_get_main_queue(), ^{

              [UIView animateWithDuration:.50 animations:^{
            [self scrollTableViewToBottomWithAnimation:YES];
        } completion:^(BOOL finished) {
            [self uploadImage:theMessage];
        }];
    });
}

-(void)uploadImage:(ALMessage *)theMessage {
   
    if (theMessage.fileMetas && [theMessage.type isEqualToString:@"5"]) {
        NSDictionary * userInfo = [theMessage dictionary];
        [self.mSendMessageTextField setText:nil];
        self.mTotalCount = self.mTotalCount+1;
        self.startIndex = self.startIndex + 1;
        
        ALChatCell_Image *imageCell = (ALChatCell_Image *)[self.mTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:[self.mMessageListArray indexOfObject:theMessage] inSection:0]];
        if (imageCell == nil) {
            //            [self performSelector:@selector(uploadImage:)
            //                       withObject:objects
            //                       afterDelay:1];
            [UIView animateWithDuration:.50 animations:^{
                [self scrollTableViewToBottomWithAnimation:YES];
            } completion:^(BOOL finished) {
                [self uploadImage:theMessage];
            }];
            return;
        }
        imageCell.progresLabel.alpha = 1;
        imageCell.mMessage.fileMetas.progressValue = 0;
        imageCell.mDowloadRetryButton.alpha = 0;
        imageCell.mMessage.inProgress = YES;
        NSError *error=nil;
        ALMessageDBService  * dbService = [[ALMessageDBService alloc] init];
        DB_Message *dbMessage =(DB_Message*)[dbService getMeesageById:theMessage.msgDBObjectId error:&error];
        dbMessage.inProgress = [NSNumber numberWithBool:YES];
        [[ALDBHandler sharedInstance].managedObjectContext save:nil];

        // post image
        [ALMessageService sendPhotoForUserInfo:userInfo withCompletion:^(NSString *message, NSError *error) {
            if (error) {
                NSLog(@"%@",error);
                return ;
            }
            NSInteger tag = [self.mMessageListArray indexOfObject:theMessage];
            //Move this to service class....
            [ALMessageService proessUploadImageForMessage:theMessage databaseObj:dbMessage.fileMetaInfo uploadURL:message withTag:tag withdelegate:self];
        }];
    }
}
//------------------------------------------------------------------------------------------------------------------
#pragma mark - ActionsSheet Methods
//------------------------------------------------------------------------------------------------------------------

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"photo library"])
        [self openGallery];

    else if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"take photo"])
        [self openCamera];
}

-(void) showActionSheet
{
    UIActionSheet * actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:@"cancel" destructiveButtonTitle:nil otherButtonTitles:@"take photo",@"photo library", nil];
    [actionSheet showInView:self.view];
}

-(void) showActionAlert
{
    UIAlertController * theController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [theController addAction:[UIAlertAction actionWithTitle:@"cancel" style:UIAlertActionStyleCancel handler:nil]];
    [theController addAction:[UIAlertAction actionWithTitle:@"take photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openCamera];
    }]];
    [theController addAction:[UIAlertAction actionWithTitle:@"photo library" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openGallery];

    }]];
    [self presentViewController:theController animated:YES completion:nil];
}


-(void) openCamera
{
    if ([UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        _mImagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        [self presentViewController:_mImagePicker animated:YES completion:nil];
    }
    else
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Alert" message:@"Camera is not available in device." delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil];
        [alert show];
    }
}

-(void) openGallery
{
    _mImagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:_mImagePicker animated:YES completion:nil];
}


@end
