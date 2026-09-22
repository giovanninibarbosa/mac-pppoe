#import <Cocoa/Cocoa.h>

typedef enum _TitleStatus {
	kUnknownTitle = 0,
	kConnectTitle = 1,
	kCancelTitle = 2,
	kDisconnectTitle = 3
} TitleStatus;

typedef enum _PPPStatus {
	kPPPInvalid = 0, 
	kPPPDisconnected = 1,
	kPPPConnecting = 2,
	kPPPConnected = 3
} PPPStatus;

typedef enum _PPPCMD {
	kPPPConnect = 0,
	kPPPDisconnect = 1
} PPPCMD;

typedef struct _Parameters {
	char* uName;
	char* pwd;
	char* sName;
    int connectType;
	PPPCMD cmd;
} DialParas;

@interface pppoeGUI:NSObject <NSApplicationDelegate> {
@private
	NSWindow* _window;
	NSButton* acCheckBox;
	NSButton* cButton;
	NSProgressIndicator* pBar;
	NSTextField* pwdTF;
	NSTextField* sNameTF;
	NSTextField* statusTF;
	NSTextField* uNameTF;
	NSButton* eRadioButton;
	NSButton* aRadioButton;
	NSTextField* updateAction;
	NSTextField* updateLabel;
	
	NSOperationQueue* queue;
	TitleStatus tStatus;
	PPPStatus pppStatus;
	NSTimer *theTimer;
	int count;
}
- (IBAction)cButtonAction:(id)sender;
- (IBAction)ethernetAction:(id)sender;
- (IBAction)airportAction:(id)sender;
- (void)theTimerControl:(NSTimer*)aTimer;
- (IBAction)qButtonAction:(id)sender;
- (IBAction)helpAction:(id)sender;
- (void)addOperation:(PPPCMD)cmd;
- (void)settingRestore;
- (void)settingSave;
+ (instancetype)shared;
- (void)setPPPStatus:(NSNumber*)num;
-(NSAttributedString *)stringFromHTML:(NSString *)html withFont:(NSFont *)font;
- (void)checkUpdate:(const NSString *)url version:(int)currVesion;
- (void)buildUserInterface;
- (void)buildMenuBar;
@end