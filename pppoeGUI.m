#import "pppoeGUI.h"
#import "pppoeOperation.h"

const NSString *curl=@"http://dev.cppfun.com/pppoe.txt";
const int ccurrVesion=1;

@implementation pppoeGUI
static pppoeGUI* sharedSingleton = nil;

+ (instancetype)shared {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		if (!sharedSingleton) sharedSingleton = [[pppoeGUI alloc] init];
	});
	return sharedSingleton;
}

- (instancetype)init {
	if (sharedSingleton) return sharedSingleton;
	self = [super init];
	if (self) {
		queue = [[NSOperationQueue alloc] init];
		tStatus = kConnectTitle;
		pppStatus = kPPPDisconnect;
		theTimer = nil;
		sharedSingleton = self;
	}
	return self;
}

- (void)dealloc {
	[theTimer invalidate];
}

- (IBAction)helpAction:(id)sender {
	NSAlert* alert = [[NSAlert alloc] init];
	[alert addButtonWithTitle:NSLocalizedString(@"OK", NULL)];
	[alert setMessageText:NSLocalizedString(@"A special ppp dialup program for special people.\n\nFirst two characters \"\\r\\n\" of real name not displayed.", NULL)];
	[alert setAlertStyle:NSAlertStyleInformational];
	[alert runModal];
}

- (IBAction)cButtonAction:(id)sender {
/*	if (pppStatus == kPPPInvalid) {		//wont't reach here, comment out
		NSAlert* alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:NSLocalizedString(@"OK", NULL)];
		[alert setMessageText:NSLocalizedString(@"Usable ppp service not found.", NULL)];
		[alert setAlertStyle:NSWarningAlertStyle];
		[alert runModal];
		[alert release];
		return;
	} */
	if (tStatus == kConnectTitle) {
		[cButton setTitle:NSLocalizedString(@"cancel", NULL)];
		tStatus = kCancelTitle;
		pppStatus = kPPPConnecting;
		[pBar setDoubleValue:0.0];
		[statusTF setStringValue:NSLocalizedString(@"connecting...", NULL)];
		[self addOperation:kPPPConnect];
		count = 0;
		theTimer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(theTimerControl:) userInfo:nil repeats:YES];
	} else {
		if (theTimer) [theTimer invalidate];
		theTimer = nil;
		if (queue) [queue cancelAllOperations];
		[self addOperation:kPPPDisconnect];
		
		[cButton setTitle:NSLocalizedString(@"connect", NULL)];
		tStatus = kConnectTitle;
		pppStatus = kPPPDisconnected;
		[pBar setDoubleValue:0.0];
		[statusTF setStringValue:NSLocalizedString(@"not connected", NULL)];
	}
}
- (IBAction)ethernetAction:(id)sender
{
    [eRadioButton setState:(NSControlStateValueOn)];
    [aRadioButton setState:(NSControlStateValueOff)];
}
- (IBAction)airportAction:(id)sender
{
    [eRadioButton setState:(NSControlStateValueOff)];
    [aRadioButton setState:(NSControlStateValueOn)];
}
-(NSAttributedString *)stringFromHTML:(NSString *)html withFont:(NSFont *)font
{
    if (!font) font = [NSFont systemFontOfSize:0.0];  // Default font
    html = [NSString stringWithFormat:@"<span style=\"font-family:'%@'; font-size:%dpx;\">%@</span>", [font fontName], (int)[font pointSize], html];
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *docAttributes = nil;
    NSAttributedString* string = [[NSAttributedString alloc] initWithHTML:data options:@{} documentAttributes:&docAttributes];
    return string;
}

- (void)checkUpdate:(const NSString *)url version:(int)currVesion {
    // osx can make the app with 32bit and 64bit together
    // so we do need the Ostype request field on osx
    // http://dev.cppfun.com/pppoe.txt?CurrVersion=1
    NSString *realUrl = [NSString stringWithFormat:@"%@?CurrVersion=%d", url, currVesion];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:[NSURL URLWithString:realUrl]
            completionHandler:^(NSData *data,
                                NSURLResponse *response,
                                NSError *error) {
                // handle response
                if (!data) {
                    NSLog(@"fetch failed: %@", [error localizedDescription]);
                    return;
                }
                NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSArray *results = [result componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
                NSMutableDictionary *all = [[NSMutableDictionary alloc] init];
                for (NSString *str in results) {
                    NSArray *keyAndValue = [str componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
                    int len = (int)[keyAndValue count];
                    if (len<2) {
                        [all setObject:@"" forKey:keyAndValue[0]];
                    } else {
                        [all setObject:keyAndValue[1] forKey:keyAndValue[0]];
                    }
                }
                /*
                VersionId=2
                VersionName=appname
                Size=8907
                Filenum=1
                Link=http://url/mac_client.zip
                */
                // compare two version
                int VersionId=[all[@"VersionId"] intValue];
                if (VersionId > currVesion) {
                    // wait me
                    [updateAction setAllowsEditingTextAttributes: YES];
                    [updateAction setSelectable:YES];
                    [updateLabel setStringValue:NSLocalizedString(@"updateLabel", NULL)];
                    NSString *updateUrl = [NSString stringWithFormat:@"<a href=\"%@\" style='color:red;'>Update!</a>", all[@"Link"]];
                    [updateAction setAttributedStringValue:[self stringFromHTML:updateUrl withFont:[updateAction font]]];
                }
            }] resume];
    
}
- (void)theTimerControl:(NSTimer *)aTimer {
	if ((pppStatus == kPPPConnecting) || (pppStatus == kPPPInvalid)) {
        //theoretically won't be kPPPInvalid, but...
        [cButton setEnabled:NO];
		count++;
		double val = [aTimer timeInterval] * count;
		[statusTF setStringValue:[NSString stringWithFormat:NSLocalizedString(@"connecting time: %2.0fs", NULL), val]];
		while (val > 10) val -= 10;
		[pBar setDoubleValue:(val * 100.0 / 10.0)];
	} else {
        [cButton setEnabled:YES];
			if (queue) [queue cancelAllOperations];
			if (theTimer) [theTimer invalidate];
			theTimer = nil;
			if (pppStatus == kPPPConnected) {
				[cButton setTitle:NSLocalizedString(@"Disconnect", NULL)];
				tStatus = kDisconnectTitle;
				[pBar setDoubleValue:100.0];
				[statusTF setStringValue:NSLocalizedString(@"connected", NULL)];
                // here do some update check
                [self checkUpdate:curl version:ccurrVesion];
			} else {
				[cButton setTitle:NSLocalizedString(@"connect", NULL)];
				tStatus = kConnectTitle;
				[pBar setDoubleValue:0.0];
				[statusTF setStringValue:NSLocalizedString(@"connect failed", NULL)];
			}
	}
}

- (IBAction)qButtonAction:(id)sender {
    // update for cancel begin
    if (queue) [queue cancelAllOperations];
    if (tStatus == kDisconnectTitle || tStatus == kCancelTitle) {
        [self addOperation:kPPPDisconnect];
    }
    // update for cancel endl
	[[NSApplication sharedApplication] terminate:sender];
}

- (void)addOperation:(PPPCMD)cmd {
	DialParas data;
	char* uName = (char*) [[uNameTF stringValue] UTF8String];
	data.uName = uName;
	data.pwd = (char*) [[pwdTF stringValue] UTF8String];
	data.sName = (char*) [[sNameTF stringValue] UTF8String];
    data.connectType=[eRadioButton intValue];
    printf("connectType %d\n",data.connectType);
	data.cmd = cmd;
	pppoeOperation* dialOp = [[pppoeOperation alloc] initWithData:&data];
	if (queue&&dialOp) [queue addOperation:dialOp];
}

- (void) settingRestore {
	NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
	
	NSString* str;
	str = [defaults stringForKey:@"userName"];
	if (str != nil) [uNameTF setStringValue:str];
	str = [defaults stringForKey:@"serviceName"];
	if (str != nil) [sNameTF setStringValue:str];
	str = [defaults stringForKey:@"password"];
	if (str != nil) [pwdTF setStringValue:str];
	[acCheckBox setIntValue:(int)[defaults integerForKey:@"autoConnect"]];
    [eRadioButton setIntValue:(int)[defaults integerForKey:@"ethernetType"]];
    [aRadioButton setIntValue:(int)[defaults integerForKey:@"airportType"]];
}

- (void) settingSave {
	NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
	
	[defaults setObject:[uNameTF stringValue] forKey:@"userName"];
	[defaults setObject:[sNameTF stringValue] forKey:@"serviceName"];
	[defaults setObject:[pwdTF stringValue] forKey:@"password"];
	[defaults setInteger:[acCheckBox intValue] forKey:@"autoConnect"];
    [defaults setInteger:[eRadioButton intValue] forKey:@"ethernetType"];
    [defaults setInteger:[aRadioButton intValue] forKey:@"airportType"];
}

- (void)buildUserInterface {
	NSRect contentRect = NSMakeRect(0, 0, 380, 420);
	_window = [[NSWindow alloc] initWithContentRect:contentRect
										   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
											 backing:NSBackingStoreBuffered
											   defer:NO];
	_window.title = NSLocalizedString(@"PPPoE", NULL);
	_window.backgroundColor = [NSColor windowBackgroundColor];
	_window.releasedWhenClosed = NO;
	_window.contentView = [[NSView alloc] initWithFrame:contentRect];

	NSView* content = _window.contentView;

	NSTextField* uLabel = [NSTextField labelWithString:NSLocalizedString(@"User Name", NULL)];
	uNameTF = [NSTextField textFieldWithString:@""];
	uNameTF.placeholderString = NSLocalizedString(@"User Name", NULL);

	uLabel.textColor = [NSColor labelColor];
	uLabel.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	NSStackView* uRow = [NSStackView stackViewWithViews:@[uLabel, uNameTF]];
	uRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	uRow.alignment = NSLayoutAttributeCenterY;
	[uLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
	[uLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSTextField* pLabel = [NSTextField labelWithString:NSLocalizedString(@"Password", NULL)];
	pLabel.textColor = [NSColor labelColor];
	pLabel.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	pwdTF = [[NSSecureTextField alloc] init];
	pwdTF.placeholderString = NSLocalizedString(@"Password", NULL);
	NSStackView* pRow = [NSStackView stackViewWithViews:@[pLabel, pwdTF]];
	pRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	pRow.alignment = NSLayoutAttributeCenterY;
	[pLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
	[pLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

	NSTextField* sLabel = [NSTextField labelWithString:NSLocalizedString(@"Service Name", NULL)];
	sLabel.textColor = [NSColor labelColor];
	sLabel.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	sNameTF = [NSTextField textFieldWithString:@""];
	sNameTF.placeholderString = NSLocalizedString(@"Service Name", NULL);
	NSStackView* sRow = [NSStackView stackViewWithViews:@[sLabel, sNameTF]];
	sRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	sRow.alignment = NSLayoutAttributeCenterY;
	[sLabel setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
	[sLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];

	eRadioButton = [NSButton radioButtonWithTitle:NSLocalizedString(@"Ethernet", NULL) target:self action:@selector(ethernetAction:)];
	aRadioButton = [NSButton radioButtonWithTitle:NSLocalizedString(@"AirPort", NULL) target:self action:@selector(airportAction:)];
	eRadioButton.tag = 1;
	aRadioButton.tag = 2;
	NSStackView* typeRow = [NSStackView stackViewWithViews:@[eRadioButton, aRadioButton]];
	typeRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;

	acCheckBox = [NSButton checkboxWithTitle:NSLocalizedString(@"Auto connect", NULL) target:nil action:NULL];

	pBar = [[NSProgressIndicator alloc] init];
	pBar.indeterminate = NO;
	[pBar setStyle:NSProgressIndicatorStyleBar];
	pBar.minValue = 0.0;
	pBar.maxValue = 100.0;
	pBar.doubleValue = 0.0;

	statusTF = [NSTextField labelWithString:NSLocalizedString(@"not connected", NULL)];
	statusTF.textColor = [NSColor labelColor];
	statusTF.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	statusTF.selectable = NO;

	cButton = [NSButton buttonWithTitle:NSLocalizedString(@"connect", NULL)
								 target:self
								action:@selector(cButtonAction:)];
	cButton.bezelStyle = NSBezelStyleRounded;
	cButton.keyEquivalent = @"\r";

	NSButton* qButton = [NSButton buttonWithTitle:NSLocalizedString(@"Quit", NULL)
										   target:self
										  action:@selector(qButtonAction:)];
	qButton.bezelStyle = NSBezelStyleRounded;

	updateLabel = [NSTextField labelWithString:@""];
	updateLabel.textColor = [NSColor labelColor];
	updateLabel.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	updateLabel.hidden = YES;

	updateAction = [NSTextField labelWithString:@""];
	updateAction.textColor = [NSColor labelColor];
	updateAction.font = [NSFont systemFontOfSize:[NSFont labelFontSize]];
	updateAction.hidden = YES;

	NSStackView* buttonRow = [NSStackView stackViewWithViews:@[qButton, cButton]];
	buttonRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	buttonRow.spacing = 12;

	NSArray<NSView*>* views = @[uRow, pRow, sRow, typeRow, acCheckBox, pBar, statusTF, buttonRow, updateLabel, updateAction];

	NSStackView* root = [NSStackView stackViewWithViews:views];
	root.orientation = NSUserInterfaceLayoutOrientationVertical;
	root.spacing = 8;
	root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
	root.translatesAutoresizingMaskIntoConstraints = NO;

	[content addSubview:root];
	[root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:0].active = YES;
	[root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:0].active = YES;
	[root.topAnchor constraintEqualToAnchor:content.topAnchor constant:0].active = YES;
	[root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:0].active = YES;
}

- (void)buildMenuBar {
	NSMenu* menubar = [[NSMenu alloc] init];
	NSString* appName = NSLocalizedString(@"PPPoE", NULL);

	NSMenuItem* appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:NULL keyEquivalent:@""];
	[menubar addItem:appMenuItem];
	NSMenu* appMenu = [[NSMenu alloc] init];
	[appMenuItem setSubmenu:appMenu];
	NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Quit %@", NULL), appName]
													 action:@selector(terminate:) keyEquivalent:@"q"];
	[appMenu addItem:quitItem];

	NSMenuItem* helpMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Help", NULL) action:NULL keyEquivalent:@""];
	[menubar addItem:helpMenuItem];
	NSMenu* helpMenu = [[NSMenu alloc] init];
	[helpMenuItem setSubmenu:helpMenu];
	NSMenuItem* helpItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"PPPoE Client Help", NULL)
													  action:@selector(helpAction:) keyEquivalent:@""];
	helpItem.target = [pppoeGUI shared];
	[helpMenu addItem:helpItem];

	[NSApplication sharedApplication].mainMenu = menubar;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[self buildUserInterface];
	[self buildMenuBar];
	[_window center];
	[_window makeKeyAndOrderFront:self];
	[self settingRestore];
	if ([acCheckBox intValue]) [self cButtonAction:NULL];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (queue) [queue cancelAllOperations];
	[self settingSave];
}

- (void)setPPPStatus:(NSNumber*)num {
	pppStatus = (PPPStatus) [num intValue];
}
@end
