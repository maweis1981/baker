//
//  RootViewController.m
//  Baker
//
//  ==========================================================================================
//  
//  Copyright (c) 2010, Davide Casali, Marco Colombo, Alessandro Morandi
//  All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without modification, are 
//  permitted provided that the following conditions are met:
//  
//  Redistributions of source code must retain the above copyright notice, this list of 
//  conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this list of 
//  conditions and the following disclaimer in the documentation and/or other materials 
//  provided with the distribution.
//  Neither the name of the Baker Framework nor the names of its contributors may be used to 
//  endorse or promote products derived from this software without specific prior written 
//  permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
//  SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
//  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE 
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//  

#import <QuartzCore/QuartzCore.h>
#import "RootViewController.h"
#import "Downloader.h"
#import "SSZipArchive.h"
#import "NSDictionary_JSONExtensions.h"


// LOADER STYLE
// Configure this to change the color of the loader
#define SCROLLVIEW_BGCOLOR blackColor
#define PAGE_NUMBERS_COLOR whiteColor
#define PAGE_NUMBERS_ALPHA 0.3

// PINCH-TO-ZOOM
// Enable pinch-to-zoom on the book page.
//   NO (Default) - Because it creates a more uniform reading experience: you should zoom only specific items with JavaScript.
//   YES - Not recommended. You have to manually set the zoom in EACH of your HTML files.
#define PAGE_ZOOM_GESTURE NO

// VERTICAL BOUNCE
// Enable bounce effect on vertical scrolls.
// Should be set to NO only when the book pages don't need any vertical scrolling.
#define PAGE_VERTICAL_BOUNCE YES

// MEDIA PLAYBACK REQUIRES USER ACTION
// Enable automatic HTML5 media playback
//   YES (Default) - Media required user action to be started.
//   NO - Media can be played automatically.
#define MEDIA_PLAYBACK_REQUIRES_USER_ACTION YES

// TEXT LABELS
#define OPEN_BOOK_MESSAGE @"Do you want to download "
#define OPEN_BOOK_CONFIRM @"Open book"

#define CLOSE_BOOK_MESSAGE @"Do you want to close this book?"
#define CLOSE_BOOK_CONFIRM @"Close book"

#define ZERO_PAGES_TITLE @"Whoops!"
#define ZERO_PAGES_MESSAGE @"Sorry, that book had no pages."

#define ERROR_FEEDBACK_TITLE @"Whoops!"
#define ERROR_FEEDBACK_MESSAGE @"There was a problem downloading the book."
#define ERROR_FEEDBACK_CONFIRM @"Retry"

#define EXTRACT_FEEDBACK_TITLE @"Extracting..."

#define ALERT_FEEDBACK_CANCEL @"Cancel"

// AVAILABLE ORIENTATION
// Define the available orientation of the book
//	@"Any" (Default) - Book is available in both orientation
//	@"Portrait" - Book is available only in portrait orientation
//	@"Landscape" - Book is available only in landscape orientation
#define	AVAILABLE_ORIENTATION @"Any"

#define INDEX_FILE_NAME @"index.html"


@implementation RootViewController

#pragma mark - SYNTHESIS
@synthesize scrollView;
@synthesize currPage;
@synthesize currentPageNumber;

#pragma mark - INIT
- (id)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // ****** DEVICE SCREEN BOUNDS
        screenBounds = [[UIScreen mainScreen] bounds];
        NSLog(@"Device Width: %f", screenBounds.size.width);
        NSLog(@"Device Height: %f", screenBounds.size.height);
        
        // ****** BOOK DIRECTORIES
        NSArray *documentsPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsPath = [NSString stringWithString:[documentsPaths objectAtIndex:0]];
        documentsBookPath = [[documentsPath stringByAppendingPathComponent:@"book"] retain];
        bundleBookPath = [[[NSBundle mainBundle] pathForResource:@"book" ofType:nil] retain];
        
        pages = [[NSMutableArray array] retain];
        toLoad = [[NSMutableArray array] mutableCopy];
        pageDetails = [[NSMutableArray array] retain];

        pageNameFromURL = nil;
        anchorFromURL = nil;
                
        tapNumber = 0;
        stackedScrollingAnimations = 0;
        
        currentPageFirstLoading = YES;
        currentPageIsDelayingLoading = YES;
        discardNextStatusBarToggle = NO;
                
        // ****** LISTENER FOR DOWNLOAD NOTIFICATION
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadBook:) name:@"downloadNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleDownloadResult:) name:@"handleDownloadResult" object:nil];
        
        [self checkPageSize];
        [self hideStatusBar];
        
        // ****** SCROLLVIEW INIT
        scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, pageWidth, pageHeight)];
        scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        scrollView.backgroundColor = [UIColor SCROLLVIEW_BGCOLOR];
        scrollView.showsHorizontalScrollIndicator = YES;
        scrollView.showsVerticalScrollIndicator = NO;
        scrollView.delaysContentTouches = NO;
        scrollView.pagingEnabled = YES;
        scrollView.delegate = self;
        [self.view addSubview:scrollView];
        
        // ****** CURR WEBVIEW INIT
        currPage = [[UIWebView alloc] init];
        [self setupWebView:currPage];
        
        // ****** NEXT WEBVIEW INIT
        nextPage = [[UIWebView alloc] init];
        [self setupWebView:nextPage];
        
        // ****** PREV WEBVIEW INIT
        prevPage = [[UIWebView alloc] init];
        [self setupWebView:prevPage];
        
        // ****** INDEX WEBVIEW INIT
        indexViewController = [[IndexViewController alloc] initWithBookBundlePath:bundleBookPath documentsBookPath:documentsBookPath fileName:INDEX_FILE_NAME webViewDelegate:self];
        [self.view addSubview:indexViewController.view];
        
        // ****** BOOK INIT
        if ([[NSFileManager defaultManager] fileExistsAtPath:documentsBookPath]) {
            [self initBook:documentsBookPath];
        } else {
            if ([[NSFileManager defaultManager] fileExistsAtPath:bundleBookPath]) {
                [self initBook:bundleBookPath];
            } /* else {
               Do something if there are no books available to show...   
            } */
        }
	}
	return self;
}
- (void)setupWebView:(UIWebView *)webView {
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	webView.mediaPlaybackRequiresUserAction = MEDIA_PLAYBACK_REQUIRES_USER_ACTION;
	webView.scalesPageToFit = PAGE_ZOOM_GESTURE;
    webView.delegate = self;
	webView.alpha = 0.5;
	if (!PAGE_VERTICAL_BOUNCE) {
		for (id subview in webView.subviews)
			if ([[subview class] isSubclassOfClass: [UIScrollView class]])
				((UIScrollView *)subview).bounces = NO;
	}        
}
- (void)checkPageSize {
    if ([AVAILABLE_ORIENTATION isEqualToString:@"Portrait"] || [AVAILABLE_ORIENTATION isEqualToString:@"Landscape"]) {
		[self setPageSize:AVAILABLE_ORIENTATION];
	} else {
		UIDeviceOrientation orientation = [self interfaceOrientation];
		// WARNING!!! Seems like checking [[UIDevice currentDevice] orientation] against "UIInterfaceOrientationPortrait" is broken (return FALSE with the device in portrait orientation)
		// Safe solution: always check if the device is in landscape orientation, if FALSE then it's in portrait.
        [self setPageSize:@"Portrait"];
		if (orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight) {
			[self setPageSize:@"Landscape"];
        }
	}
}
- (void)setPageSize:(NSString *)orientation {	
	NSLog(@"Set size for orientation: %@", orientation);
    
    pageWidth = screenBounds.size.width;
    pageHeight = screenBounds.size.height;
	if ([orientation isEqualToString:@"Landscape"]) {
		pageWidth = screenBounds.size.height;
		pageHeight = screenBounds.size.width;
	}
}
- (void)resetScrollView {
	for (id subview in scrollView.subviews) {
		if (![subview isKindOfClass:[UIWebView class]]) {
			[subview removeFromSuperview];
		}
	}

	scrollView.contentSize = CGSizeMake(pageWidth * totalPages, pageHeight);
	
	int scrollViewY = 0;
	if (![UIApplication sharedApplication].statusBarHidden) {
		scrollViewY = -20;
	}
    
    [UIView animateWithDuration:0.2 animations:^{
        scrollView.frame = CGRectMake(0, scrollViewY, pageWidth, pageHeight);
    }];
	
	[self initPageNumbersForPages:totalPages];
    
    if (prevPage.superview == scrollView) {
        prevPage.frame = [self frameForPage:currentPageNumber - 1];
        [scrollView bringSubviewToFront:prevPage];
    }
    
    if (nextPage.superview == scrollView) {
        nextPage.frame = [self frameForPage:currentPageNumber + 1];
        [scrollView bringSubviewToFront:nextPage];
    }
    
    currPage.frame = [self frameForPage:currentPageNumber];
    [scrollView bringSubviewToFront:currPage];
	[scrollView scrollRectToVisible:[self frameForPage:currentPageNumber] animated:NO];

	// ****** TAPPABLE AREAS
	int tappableAreaSize = screenBounds.size.width/16;
	if (screenBounds.size.width < 768) {
		tappableAreaSize = screenBounds.size.width/8;
    }
	
	upTapArea = CGRectMake(tappableAreaSize, 0, pageWidth - (tappableAreaSize * 2), tappableAreaSize);
	downTapArea = CGRectMake(tappableAreaSize, pageHeight - tappableAreaSize, pageWidth - (tappableAreaSize * 2), tappableAreaSize);
	leftTapArea = CGRectMake(0, tappableAreaSize, tappableAreaSize, pageHeight - (tappableAreaSize * 2));
	rightTapArea = CGRectMake(pageWidth - tappableAreaSize, tappableAreaSize, tappableAreaSize, pageHeight - (tappableAreaSize * 2));
}
- (void)initBook:(NSString *)path {	
	// Count pages
    [pages removeAllObjects];
    [pageDetails removeAllObjects];
	
	NSArray *dirContent = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
	for (NSString *fileName in dirContent) {
		if ([[fileName pathExtension] isEqualToString:@"html"] && ![fileName isEqualToString:INDEX_FILE_NAME]) {
			[pages addObject:[path stringByAppendingPathComponent:fileName]];
        }
	}
		
	totalPages = [pages count];
	NSLog(@"Pages in this book: %d", totalPages);
	
	if (totalPages > 0) {
		// Check if there is a saved starting page        
		NSString *currPageToLoad = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastPageViewed"];
		
		if (currentPageFirstLoading && currPageToLoad != nil) {
			currentPageNumber = [currPageToLoad intValue];
		} else {
			currentPageNumber = 1;
			if (pageNameFromURL != nil) {
                pageNameFromURL = nil;
				NSString *fileNameFromURL = [path stringByAppendingPathComponent:pageNameFromURL];
				for (int i = 0; i < totalPages; i++) {
					if ([[pages objectAtIndex:i] isEqualToString:fileNameFromURL]) {
						currentPageNumber = i + 1;
						break;
					}
				}
			}
		}
		
        currentPageIsDelayingLoading = YES;
        [toLoad removeAllObjects];
		
        [self resetScrollView];        
        [scrollView addSubview:currPage];
        [self addPageLoading:0];
        
        if (currentPageNumber != totalPages) {
            if (nextPage.superview != scrollView) {
                [scrollView addSubview:nextPage];
            }
            [self addPageLoading:+1];
        } else if (currentPageNumber == totalPages && nextPage.superview == scrollView) {
            [nextPage removeFromSuperview];
        }
        
        if (currentPageNumber != 1) {
            if (prevPage.superview != scrollView) {
                [scrollView addSubview:prevPage];
            }
            [self addPageLoading:-1];
        } else if (currentPageNumber == 1 && prevPage.superview == scrollView) {
            [prevPage removeFromSuperview];
        }
        
        [self handlePageLoading];
        [indexViewController loadContentFromBundle:[path isEqualToString:bundleBookPath]];
		
	} else {
		
		[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
 		feedbackAlert = [[UIAlertView alloc] initWithTitle:ZERO_PAGES_TITLE
												   message:ZERO_PAGES_MESSAGE
												  delegate:self
										 cancelButtonTitle:ALERT_FEEDBACK_CANCEL
										 otherButtonTitles:nil];
		[feedbackAlert show];
		[feedbackAlert release];
		
		[self initBook:bundleBookPath];
	}
}
- (void)initPageNumbersForPages:(int)count {
    
	for (int i = 0; i < count; i++) {
		
        if (pageDetails.count > i && [pageDetails objectAtIndex:i] != nil) {
            
            NSDictionary *details = [NSDictionary dictionaryWithDictionary:[pageDetails objectAtIndex:i]];        
            for (NSString *key in details) {
                UIView *value = [details objectForKey:key];
                if (value != nil) {
                    
                    CGRect frame = value.frame;
                    if ([key isEqualToString:@"spinner"]) {
                        
                        frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
                        frame.origin.y = (pageHeight - frame.size.height) / 2;
                        
                    } else if ([key isEqualToString:@"number"]) {
                        
                        frame.origin.x = pageWidth * i + (pageWidth - 115) / 2;
                        frame.origin.y = pageHeight / 2 - 55;

                        
                    } else if ([key isEqualToString:@"title"]) {
                        
                        frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
                        frame.origin.y = pageHeight / 2 + 20;
                    }
                    
                    value.frame = frame;
                    [scrollView addSubview:value];
                }
            }
                        
        } else {
        
            // ****** Spinners
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            spinner.backgroundColor = [UIColor clearColor];
            
            CGRect frame = spinner.frame;
            frame.origin.x = pageWidth * i + (pageWidth - frame.size.width) / 2;
            frame.origin.y = (pageHeight - frame.size.height) / 2;        
            spinner.frame = frame;
                    
            [scrollView addSubview:spinner];
            [spinner startAnimating];
            [spinner release];
            
            // ****** Numbers
            UILabel *number = [[UILabel alloc] initWithFrame:CGRectMake(pageWidth * i + (pageWidth - 115) / 2, pageHeight / 2 - 55, 115, 30)];
            number.backgroundColor = [UIColor clearColor];
            number.font = [UIFont fontWithName:@"Helvetica" size:40.0];
            number.textColor = [UIColor PAGE_NUMBERS_COLOR];
            number.textAlignment = UITextAlignmentCenter;
            number.alpha = PAGE_NUMBERS_ALPHA;                    
            number.text = [NSString stringWithFormat:@"%d", i + 1];
            
            [scrollView addSubview:number];
            [number release];
            
            // ****** Title
            UILabel *title = nil;
            NSRegularExpression *titleRegex = [NSRegularExpression regularExpressionWithPattern:@"<title>(.*)</title>" options:NSRegularExpressionCaseInsensitive error:NULL];
            NSString *fileContent = [NSString stringWithContentsOfFile:[pages objectAtIndex: i] encoding:NSUTF8StringEncoding error:NULL];
            NSRange matchRange = [[titleRegex firstMatchInString:fileContent options:0 range:NSMakeRange(0, [fileContent length])] rangeAtIndex:1];
            if (!NSEqualRanges(matchRange, NSMakeRange(NSNotFound, 0))) {
                            
                NSString *titleText = [fileContent substringWithRange:matchRange];
                                        
                CGSize titleDimension = CGSizeMake(672, 330);
                UIFont *titleFont = [UIFont fontWithName:@"Helvetica" size:24.0];
                if (screenBounds.size.width < 768) {
                    titleDimension = CGSizeMake(280, 134);
                    titleFont = [UIFont fontWithName:@"Helvetica" size:15.0];
                }
                
                CGSize titleTextSize = [titleText sizeWithFont:titleFont constrainedToSize:titleDimension lineBreakMode:UILineBreakModeTailTruncation];            
                CGRect titleFrame = CGRectMake(pageWidth * i + (pageWidth - titleTextSize.width) / 2, pageHeight / 2 + 20, titleTextSize.width, titleTextSize.height);
                
                title = [[UILabel alloc] initWithFrame:titleFrame];         
                title.backgroundColor = [UIColor clearColor];
                title.alpha = PAGE_NUMBERS_ALPHA;            
                title.font = titleFont;
                title.textColor = [UIColor PAGE_NUMBERS_COLOR];
                title.textAlignment = UITextAlignmentCenter;
                title.lineBreakMode = UILineBreakModeTailTruncation;
                title.numberOfLines = 0;
                title.text = titleText;
                
                [scrollView addSubview:title];
                [title release];
            }
            
            NSMutableDictionary *details = [NSMutableDictionary dictionaryWithObjectsAndKeys:spinner, @"spinner", number, @"number", title, @"title", nil];
            [pageDetails insertObject:details atIndex:i];
        }
	}
}

#pragma mark - LOADING
- (NSDictionary*)loadManifest:(NSString*)file {
    /****************************************************************************************************
	 * Reads a JSON file from Application Bundle to a NSDictionary.
     *
     * Requires TouchJSON with the inclusion of: #import "NSDictionary_JSONExtensions.h"
     *
     * Use normal NSDictionary and NSArray lookups to find elements.
     *   [json objectForKey:@"name"]
     *   [[json objectForKey:@"items"] objectAtIndex:1]
	 */
    NSDictionary *ret;
    
    NSString *filePath = [[NSBundle mainBundle] pathForResource:file ofType:@"json"];  
    if (filePath) {  
        NSString *fileJSON = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        
        NSError *e = NULL;
        ret = [NSDictionary dictionaryWithJSONString:fileJSON error:&e];
    }
    
     /* // Testing logs
     NSLog(@"%@", e);
     NSLog(@"%@", ret);
     
     NSLog(@"Lookup, string: %@", [ret objectForKey:@"title"]);
     NSLog(@"Lookup, sub-array: %@", [[ret objectForKey:@"pages"] objectAtIndex:1]); */
    
    return ret;
}
- (BOOL)changePage:(int)page {
    
    BOOL pageChanged = NO;
	
    if (page < 1) {
		currentPageNumber = 1;
	} else if (page > totalPages) {
		currentPageNumber = totalPages;
	} else if (page != currentPageNumber) {
                
        lastPageNumber = currentPageNumber;
		currentPageNumber = page;
        
        tapNumber = tapNumber + (lastPageNumber - currentPageNumber);
        
        // While we are tapping, we don't want scrolling event to get in the way
        scrollView.scrollEnabled = NO;
        stackedScrollingAnimations++;
        
        [self hideStatusBar];
        [scrollView scrollRectToVisible:[self frameForPage:currentPageNumber] animated:YES];
        [self gotoPageDelayer];
        
        pageChanged = YES;
	}
	
	return pageChanged;	
}
- (void)gotoPageDelayer {
	// This delay is required in order to avoid stuttering when the animation runs.
	// The animation lasts 0.5 seconds: so we start loading after that.
	
	if (currentPageIsDelayingLoading) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(gotoPage) object:nil];
    }
	
	currentPageIsDelayingLoading = YES;
	[self performSelector:@selector(gotoPage) withObject:nil afterDelay:0.5];
}
- (void)gotoPage {
	
    /****************************************************************************************************
	 * Opens a specific page
	 */
    
	//NSString *file = [NSString stringWithFormat:@"%d", currentPageNumber];
	//NSString *path = [[NSBundle mainBundle] pathForResource:file ofType:@"html" inDirectory:@"book"];
            
    NSString *path = [NSString stringWithString:[pages objectAtIndex:currentPageNumber - 1]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] && tapNumber != 0) {
        
        NSLog(@"Goto Page: book/%@", [[NSFileManager defaultManager] displayNameAtPath:path]);
        
        // ****** THREE CARD VIEW METHOD
        // ****** Calculate move direction and normalize tapNumber
        int direction = 1;
        if (tapNumber < 0) {
            direction = -direction;
            tapNumber = -tapNumber;
        }
        
        NSLog(@">>>>> TAP NUMBER: %d <<<<<", tapNumber);
        
        if (tapNumber > 2) {
            
            [toLoad removeAllObjects];
            
            // ****** Moved away for more than 2 pages: RELOAD ALL pages
            tapNumber = 0;
            
            [self addPageLoading:0];
            if (currentPageNumber < totalPages)
                [self addPageLoading:+1];
            if (currentPageNumber > 1)
                [self addPageLoading:-1];
                        
        } else {
            
            int tmpSlot = 0;
            if (tapNumber == 2) {
            
                // ****** Moved away for 2 pages: RELOAD CURRENT page

                if (direction < 0) {
                    // ****** Move LEFT <<<
                    UIWebView *tmpView = prevPage;
                    prevPage = nextPage;
                    nextPage = tmpView;
                } else {
                    // ****** Move RIGHT >>>
                    UIWebView *tmpView = nextPage; 
                    nextPage = prevPage;
                    prevPage = tmpView;
                }
                
                // Adjust pages slot in the stack to reflect the webviews pointer change
                for (int i = 0; i < [toLoad count]; i++) {
                    tmpSlot =  -1 * [[[toLoad objectAtIndex:i] valueForKey:@"slot"] intValue];
                    [[toLoad objectAtIndex:i] setObject:[NSNumber numberWithInt:tmpSlot] forKey:@"slot"];
                }
                
                [self addPageLoading:0];
            
            } else if (tapNumber == 1) {
                                
                if (direction < 0) { 
                    // ****** Move LEFT <<<
                    UIWebView *tmpView = prevPage;
                    prevPage = currPage;
                    currPage = nextPage;
                    nextPage = tmpView;
                } else { 
                    // ****** Move RIGHT >>>
                    UIWebView *tmpView = nextPage;
                    nextPage = currPage;
                    currPage = prevPage;
                    prevPage = tmpView;
                }
                
                // Adjust pages slot in the stack to reflect the webviews pointer change
                for (int i = 0; i < [toLoad count]; i++) {
                    tmpSlot = [[[toLoad objectAtIndex:i] valueForKey:@"slot"] intValue];
                    if (direction < 0) {
                        if (tmpSlot == +1) {
                            tmpSlot = 0;
                        } else if (tmpSlot == 0) {
                            tmpSlot = -1;
                        } else if (tmpSlot == -1) {
                            tmpSlot = +1;
                        }
                    } else {
                        if (tmpSlot == -1) {
                            tmpSlot = 0;
                        } else if (tmpSlot == 0) {
                            tmpSlot = +1;
                        } else if (tmpSlot == +1) {
                            tmpSlot = -1;
                        }
                    }
                    [[toLoad objectAtIndex:i] setObject:[NSNumber numberWithInt:tmpSlot] forKey:@"slot"];
                }
                
                // Since we are not loading anything we have to reset the delayer flag
                currentPageIsDelayingLoading = NO;                
                [scrollView bringSubviewToFront:currPage];
            }
            
            [self getPageHeight];
            
            tapNumber = 0;
            if (direction < 0) {
                
                // REMOVE OTHER NEXT page from toLoad stack
                for (int i = 0; i < [toLoad count]; i++) {
                    if ([[[toLoad objectAtIndex:i] valueForKey:@"slot"] intValue] == +1) {
                        [toLoad removeObjectAtIndex:i];
                    }   
                }
                
                // PRELOAD NEXT page
                if (currentPageNumber < totalPages)
                    [self addPageLoading:+1];
                
            } else {
                
                // REMOVE OTHER PREV page from toLoad stack
                for (int i = 0; i < [toLoad count]; i++) {
                    if ([[[toLoad objectAtIndex:i] valueForKey:@"slot"] intValue] == -1) {
                        [toLoad removeObjectAtIndex:i];
                    }   
                }
                
                // PRELOAD PREV page
                if (currentPageNumber > 1)
                    [self addPageLoading:-1];
            }
        }
        
        if (currentPageNumber != totalPages && nextPage.superview != scrollView) {
            [scrollView addSubview:nextPage];
        } else if (currentPageNumber == totalPages && nextPage.superview == scrollView) {
            [nextPage removeFromSuperview];
        }
        
        if (currentPageNumber != 1 && prevPage.superview != scrollView) {
            [scrollView addSubview:prevPage];
        } else if (currentPageNumber == 1 && prevPage.superview == scrollView) {
            [prevPage removeFromSuperview];
        }
        
        [self handlePageLoading];
    }
}
- (void)addPageLoading:(int)slot {
    
    NSArray *objs = [NSArray arrayWithObjects:[NSNumber numberWithInt:slot], [NSNumber numberWithInt:currentPageNumber + slot], nil];
    NSArray *keys = [NSArray arrayWithObjects:@"slot", @"page", nil];
    
    if (slot == 0) {
        [toLoad insertObject:[NSMutableDictionary dictionaryWithObjects:objs forKeys:keys] atIndex:0];
    } else {
        [toLoad addObject:[NSMutableDictionary dictionaryWithObjects:objs forKeys:keys]];
    }
}
- (void)handlePageLoading {
    if ([toLoad count] != 0) {
                
        int slot = [[[toLoad objectAtIndex:0] valueForKey:@"slot"] intValue];
        int page = [[[toLoad objectAtIndex:0] valueForKey:@"page"] intValue];
        
        NSLog(@">>>>> HANDLE LOADING OF SLOT %d WITH PAGE %d <<<<<", slot, page);
        
        [toLoad removeObjectAtIndex:0];
        [self loadSlot:slot withPage:page];
    }
}
- (void)loadSlot:(int)slot withPage:(int)page {
	
	UIWebView *webView = nil;
	
	// ****** SELECT
	if (slot == 0) {
		webView = currPage;
	} else if (slot == +1) {
		webView = nextPage;
	} else if (slot == -1) {
		webView = prevPage;
	}
    
    if ([webView isLoading]) {
        [webView stopLoading];
    }
    
    webView.frame = [self frameForPage:page];
	[self loadWebView:webView withPage:page];
}
- (BOOL)loadWebView:(UIWebView*)webView withPage:(int)page {
	
	NSString *path = [NSString stringWithString:[pages objectAtIndex:page-1]];
		
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
		NSLog(@"[+] Loading: book/%@", [[NSFileManager defaultManager] displayNameAtPath:path]);
		webView.hidden = YES; // use direct property instead of [self webView:hidden:animating:] otherwise it won't work
		[webView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:path]]];
		return YES;
	}
	return NO;
}

#pragma mark - SCROLLVIEW
- (CGRect)frameForPage:(int)page {
	return CGRectMake(pageWidth * (page - 1), 0, pageWidth, pageHeight);
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll {
	// This is called because this controller is the delegate for UIScrollView
	[self hideStatusBar];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate {
	// Nothing to do here...
}
- (void)scrollViewWillBeginDecelerating:(UIScrollView *)scroll {
	// Nothing to do here either...
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll {
    
    int page = (int)(scroll.contentOffset.x / pageWidth) + 1;
	NSLog(@" <<< Swiping to page: %d >>>", page);
    
    if (currentPageNumber != page) {        
        lastPageNumber = currentPageNumber;
        currentPageNumber = page;
        
        tapNumber = tapNumber + (lastPageNumber - currentPageNumber);
        [self gotoPageDelayer];
    }
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scroll {
	stackedScrollingAnimations--;
    if (stackedScrollingAnimations == 0) {
		scroll.scrollEnabled = YES;
	}
}

#pragma mark - WEBVIEW
- (void)webViewDidStartLoad:(UIWebView *)webView {
	// Sent before a web view begins loading content.
}
- (void)webViewDidFinishLoad:(UIWebView *)webView {
	// Sent after a web view finishes loading content.	
	
	if ([webView isEqual:currPage]) {
		// Get current page max scroll offset
		[self getPageHeight];
		
        [scrollView bringSubviewToFront:currPage];
        
		// If is the first time i load something in the currPage web view...
		if (currentPageFirstLoading) {			
			// ...check if there is a saved starting scroll index and set it
			NSString *currPageScrollIndex = [[NSUserDefaults standardUserDefaults] objectForKey:@"lastScrollIndex"];
			if (currPageScrollIndex != nil) {
                [self goDownInPage:currPageScrollIndex animating:NO];
            }
			currentPageFirstLoading = NO;
		}
		
		// Handle saved hash reference (if any)
		[self handleAnchor:NO];
	}
	
	// /!\ hack to make it load at the right time and not too early
	// source: http://stackoverflow.com/questions/1422146/webviewdidfinishload-firing-too-soon
	//NSString *javaScript = @"<script type=\"text/javascript\">function myFunction(){return 1+1;}</script>";
	//[webView stringByEvaluatingJavaScriptFromString:javaScript];
	
	[self performSelector:@selector(revealWebView:) withObject:webView afterDelay:0.1]; // This seems fixing the WebView-Flash-Of-Old-Content-webBug    
    [self handlePageLoading];
}
- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
	// Sent if a web view failed to load content.
    if (webView == currPage) {
		NSLog(@"currPage failed to load content with error: %@", error);
	} else if (webView == prevPage) {
		NSLog(@"prevPage failed to load content with error: %@", error);
	} else if (webView == nextPage) {
		NSLog(@"nextPage failed to load content with error: %@", error);
    }
}
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
	// Sent before a web view begins loading content, useful to trigger actions before the WebView.	
	
    if ([webView isEqual:prevPage]) {
        NSLog(@"Loading Prev Page --> load page");
        return YES;
    } else if ([webView isEqual:nextPage]) {
        NSLog(@"Loading Next Page --> load page");
        return YES;
    } else if (currentPageIsDelayingLoading) {		
		NSLog(@"Current Page IS delaying loading --> load page");
		currentPageIsDelayingLoading = NO;
		return YES;
	} else {
		
		[self hideStatusBarDiscardingToggle:YES];
		
		NSURL *url = [request URL];
		NSLog(@"Current Page IS NOT delaying loading --> handle clicked link: %@", [url absoluteString]);
		
		// ****** Handle URI schemes
		if (url) {
			// Existing, checking schemes...
			if([[url lastPathComponent] isEqualToString:INDEX_FILE_NAME]){
                NSLog(@"Matches index file name.");
                return YES; // Let the index view load
            }
			if ([[url scheme] isEqualToString:@"file"]) {
				// ****** Handle: file://
				NSLog(@"file:// ->");
				
				anchorFromURL = [[url fragment] retain];
				NSString *file = [[url relativePath] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				
                int page = (int)[pages indexOfObject:file] + 1;
                
				if (![self changePage:page]) {
					[self handleAnchor:NO];
				}
				
			} else if ([[url scheme] isEqualToString:@"book"]) {
				// ****** Handle: book://
				NSLog(@"book:// ->");
				
				if ([[url host] isEqualToString:@"local"] && [[NSFileManager defaultManager] fileExistsAtPath:bundleBookPath]) {
					// *** Back to bundled book
					feedbackAlert = [[UIAlertView alloc] initWithTitle:@""
															   message:[NSString stringWithFormat:CLOSE_BOOK_MESSAGE]
															  delegate:self
													 cancelButtonTitle:ALERT_FEEDBACK_CANCEL
													 otherButtonTitles:CLOSE_BOOK_CONFIRM, nil];
					[feedbackAlert show];
					[feedbackAlert release];
                    
				} else {
					
					if ([[url pathExtension] isEqualToString:@"html"]) {
						anchorFromURL = [[url fragment] retain];
						pageNameFromURL = [[[url lastPathComponent] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] retain];
						NSString *tmpUrl = [[url URLByDeletingLastPathComponent] absoluteString];
						url = [NSURL URLWithString:[tmpUrl stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]];						
					}
					
					// *** Download book
					URLDownload = [[@"http:" stringByAppendingString:[url resourceSpecifier]] retain];
					
					if ([[[NSURL URLWithString:URLDownload] pathExtension] isEqualToString:@""]) {
						URLDownload = [[URLDownload stringByAppendingString:@".hpub"] retain];
					}
					
					[self downloadBook:nil];
				}
			} else {
				// ****** Handle: *
				[[UIApplication sharedApplication] openURL:[request URL]];
			}
		}
		
		return NO;
	}
}
- (void)webView:(UIWebView *)webView hidden:(BOOL)status animating:(BOOL)animating {
	NSLog(@"- webview hidden:%d animating:%d", status, animating);
	
	if (animating) {
		webView.alpha = 0.0;
		webView.hidden = NO;
		
		[UIView beginAnimations:@"webViewVisibility" context:nil]; {
			//[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
			[UIView setAnimationDuration:0.5];
			//[UIView setAnimationDelegate:self];
			//[UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:)];
			
			webView.alpha = 1.0;	
		}
		[UIView commitAnimations];		
	} else {
		webView.alpha = 1.0;
		webView.hidden = NO;
	}
}
- (void)revealWebView:(UIWebView *)webView {
	[self webView:webView hidden:NO animating:YES];  // Delayed run to fix the WebView-Flash-Of-Old-Content-Bug
}

#pragma mark - GESTURES
- (void)userDidTap:(UITouch *)touch {
	CGPoint tapPoint = [touch locationInView:self.view];
	NSLog(@"User tap at [%f, %f]", tapPoint.x, tapPoint.y);
	
	// ...and swipe or scroll the page.
	if (CGRectContainsPoint(upTapArea, tapPoint)) {
		NSLog(@" /\\ TAP up!");
		[self goUpInPage:@"1004" animating:YES];
	} else if (CGRectContainsPoint(downTapArea, tapPoint)) {
		NSLog(@" \\/ TAP down!");
		[self goDownInPage:@"1004" animating:YES];
	} else if (CGRectContainsPoint(leftTapArea, tapPoint) || CGRectContainsPoint(rightTapArea, tapPoint)) {
		int page = 0;
		if (CGRectContainsPoint(leftTapArea, tapPoint)) {
			NSLog(@"<-- TAP left!");
			page = currentPageNumber - 1;
		} else if (CGRectContainsPoint(rightTapArea, tapPoint)) {
			NSLog(@"--> TAP right!");
			page = currentPageNumber + 1;
		}
        [self changePage:page];
        
	} else if (touch.tapCount == 2) {
		[self performSelector:@selector(toggleStatusBar) withObject:nil];
	}
}
- (void)userDidScroll:(UITouch *)touch {
	NSLog(@"User did scroll");
	[self hideStatusBar];
}

#pragma mark - PAGE SCROLLING
- (void)getPageHeight {
	for (id subview in currPage.subviews) {
		if ([[subview class] isSubclassOfClass:[UIScrollView class]]) {
			CGSize size = ((UIScrollView *)subview).contentSize;
			NSLog(@"Changing current page height: %d --> %f", currentPageHeight, size.height);
			currentPageHeight = size.height;
		}
	}
}
- (void)goUpInPage:(NSString *)offset animating:(BOOL)animating {
	
	NSString *currPageOffset = [currPage stringByEvaluatingJavaScriptFromString:@"window.scrollY;"];
	
	int currentPageOffset = [currPageOffset intValue];
	if (currentPageOffset > 0) {
		
		int targetOffset = currentPageOffset-[offset intValue];
		if (targetOffset < 0)
			targetOffset = 0;
		
		NSLog(@"Scrolling page up to %d", targetOffset);
		
		offset = [NSString stringWithFormat:@"%d", targetOffset];
		[self scrollPage:currPage to:offset animating:animating];
	}
}
- (void)goDownInPage:(NSString *)offset animating:(BOOL)animating {
	
	NSString *currPageOffset = [currPage stringByEvaluatingJavaScriptFromString:@"window.scrollY;"];
	
	int currentPageMaxScroll = currentPageHeight - pageHeight;
	int currentPageOffset = [currPageOffset intValue];
	
	if (currentPageOffset < currentPageMaxScroll) {
		
		int targetOffset = currentPageOffset+[offset intValue];
		if (targetOffset > currentPageMaxScroll)
			targetOffset = currentPageMaxScroll;
		
		NSLog(@"Scrolling page down to %d", targetOffset);
		
		offset = [NSString stringWithFormat:@"%d", targetOffset];
		[self scrollPage:currPage to:offset animating:animating];
	}

}
- (void)scrollPage:(UIWebView *)webView to:(NSString *)offset animating:(BOOL)animating {
	[self hideStatusBar];
	
	NSString *jsCommand = [NSString stringWithFormat:@"window.scrollTo(0,%@);", offset];
	
	if (animating) {
		
		[UIView beginAnimations:@"scrollPage" context:nil]; {
			//[UIView setAnimationCurve:UIViewAnimationCurveEaseInOut];
			[UIView setAnimationDuration:0.35];
			//[UIView setAnimationDelegate:self];
			//[UIView setAnimationDidStopSelector:@selector(animationDidStop:finished:)];
		
			[webView stringByEvaluatingJavaScriptFromString:jsCommand];
		}
		[UIView commitAnimations];
	
	} else {
		[webView stringByEvaluatingJavaScriptFromString:jsCommand];
	}
}
- (void)handleAnchor:(BOOL)animating {
	if (anchorFromURL != nil) {
		
		NSString *jsAnchorHandler = [NSString stringWithFormat:@"(function() {\
									 var target = '%@';\
									 var elem = document.getElementById(target);\
									 if (!elem) elem = document.getElementsByName(target)[0];\
									 return elem.offsetTop;\
									 })();", anchorFromURL];
		
		NSString *offset = [currPage stringByEvaluatingJavaScriptFromString:jsAnchorHandler];
		
		if (![offset isEqualToString:@""]) {
			[self goDownInPage:offset animating:animating];
        }
		anchorFromURL = nil;
	}
}

#pragma mark - STATUS BAR
- (void)toggleStatusBar {
	if (discardNextStatusBarToggle) {
		// do nothing, but reset the variable
		discardNextStatusBarToggle = NO;
	} else {
		NSLog(@"TOGGLE status bar");
		UIApplication *sharedApplication = [UIApplication sharedApplication];
		[sharedApplication setStatusBarHidden:!sharedApplication.statusBarHidden withAnimation:UIStatusBarAnimationSlide];
        if(![indexViewController isDisabled]) {
            [indexViewController setIndexViewHidden:![indexViewController isIndexViewHidden] withAnimation:YES];
        }
	}
}
- (void)hideStatusBar {
	[self hideStatusBarDiscardingToggle:NO];
}
- (void)hideStatusBarDiscardingToggle:(BOOL)discardToggle {
	NSLog(@"HIDE status bar %@", (discardToggle ? @"discarding toggle" : @""));
	discardNextStatusBarToggle = discardToggle;
	[[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    if(![indexViewController isDisabled]) {
        [indexViewController setIndexViewHidden:YES withAnimation:YES];
    }
}

#pragma mark - DOWNLOAD NEW BOOKS
- (void)downloadBook:(NSNotification *)notification {
	
	if (notification != nil) {
		URLDownload = [[NSString stringWithString:(NSString *)[notification object]] retain];
    }	
	NSLog(@"Download file %@", URLDownload);
	
	feedbackAlert = [[UIAlertView alloc] initWithTitle:@""
											   message:[OPEN_BOOK_MESSAGE stringByAppendingFormat:@"%@?", URLDownload]
											  delegate:self
									 cancelButtonTitle:ALERT_FEEDBACK_CANCEL
									 otherButtonTitles:OPEN_BOOK_CONFIRM, nil];
	[feedbackAlert show];
	[feedbackAlert release];
}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex != alertView.cancelButtonIndex) {
		if ([[alertView buttonTitleAtIndex:buttonIndex] isEqualToString:CLOSE_BOOK_CONFIRM]){
            currentPageIsDelayingLoading = YES;
			[self initBook:bundleBookPath];
        }
		else{
			[self startDownloadRequest];
        }
	}
}
- (void)startDownloadRequest {	
	downloader = [[Downloader alloc] initDownloader:@"handleDownloadResult"];
	[downloader makeHTTPRequest:URLDownload];
}
- (void)handleDownloadResult:(NSNotification *)notification {
	
	NSDictionary *requestSummary = [NSDictionary dictionaryWithDictionary:(NSMutableDictionary *)[notification object]];	
	[downloader release];
		
	if ([requestSummary objectForKey:@"error"] != nil) {
		
		NSLog(@"Error while downloading data");
		feedbackAlert = [[UIAlertView alloc] initWithTitle:ERROR_FEEDBACK_TITLE
												   message:ERROR_FEEDBACK_MESSAGE
												  delegate:self
										 cancelButtonTitle:ALERT_FEEDBACK_CANCEL
										 otherButtonTitles:ERROR_FEEDBACK_CONFIRM, nil];
		[feedbackAlert show];
		[feedbackAlert release];
			
	} else if ([requestSummary objectForKey:@"data"] != nil) {
		
		NSLog(@"Data received succesfully");
		feedbackAlert = [[UIAlertView alloc] initWithTitle:EXTRACT_FEEDBACK_TITLE
												   message:nil
												  delegate:self
										 cancelButtonTitle:nil
										 otherButtonTitles:nil];
				
		UIActivityIndicatorView *extractingWheel = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(124,50,37,37)];
		extractingWheel.activityIndicatorViewStyle = UIActivityIndicatorViewStyleWhiteLarge;
		[extractingWheel startAnimating];
		
		[feedbackAlert addSubview:extractingWheel];
		[feedbackAlert show];
		
		[extractingWheel release];
		[feedbackAlert release];
		
		[self performSelector:@selector(manageDownloadData:) withObject:[requestSummary objectForKey:@"data"] afterDelay:0.1];
	}
}
- (void)manageDownloadData:(NSData *)data {
			
	NSArray *URLSections = [NSArray arrayWithArray:[URLDownload pathComponents]];
	NSString *targetPath = [NSTemporaryDirectory() stringByAppendingString:[URLSections lastObject]];
		
	[data writeToFile:targetPath atomically:YES];
			
	if ([[NSFileManager defaultManager] fileExistsAtPath:targetPath]) {
		NSLog(@"File create successfully! Path: %@", targetPath);
		NSString *destinationPath = documentsBookPath;
		NSLog(@"Book destination path: %@", destinationPath);
		
		// If a "book" directory already exists remove it (quick solution, improvement needed) 
		if ([[NSFileManager defaultManager] fileExistsAtPath:destinationPath]) {
			[[NSFileManager defaultManager] removeItemAtPath:destinationPath error:NULL];
        }
    
		[SSZipArchive unzipFileAtPath:targetPath toDestination:destinationPath];
		NSLog(@"Book successfully unzipped. Removing .hpub file");
		[[NSFileManager defaultManager] removeItemAtPath:targetPath error:NULL];
				
		[feedbackAlert dismissWithClickedButtonIndex:feedbackAlert.cancelButtonIndex animated:YES];
		[self initBook:destinationPath];
	} /* else {
	   Do something if it was not possible to write the book file on the iPhone/iPad file system...
	} */
}

#pragma mark - ORIENTATION
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	// Overriden to allow any orientation.
	if ([AVAILABLE_ORIENTATION isEqualToString:@"Portrait"]) {
		return (interfaceOrientation == UIInterfaceOrientationPortrait || interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
	} else if ([AVAILABLE_ORIENTATION isEqualToString:@"Landscape"]) {
		return (interfaceOrientation == UIInterfaceOrientationLandscapeRight || interfaceOrientation == UIInterfaceOrientationLandscapeLeft);
	} else {
		return YES;
	}	
}
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    // Notify the index view
    [indexViewController willRotate];
    
    // Since the UIWebView doesn't handle orientationchange events correctly we have to do handle them ourselves 
    // 1. Set the correct value for window.orientation property
    NSString *jsOrientationGetter;
    switch (toInterfaceOrientation) {
        case UIDeviceOrientationPortrait:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 0; });";
            break;
        case UIDeviceOrientationLandscapeLeft:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 90; });";
            break;
        case UIDeviceOrientationLandscapeRight:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return -90; });";
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            jsOrientationGetter = @"window.__defineGetter__('orientation', function() { return 180; });";
            break;
        default:
            break;
    }
    
    // 2. Create and dispatch a orientationchange event    
    NSString *jsOrientationChange = @"if (typeof bakerOrientationChangeEvent === 'undefined') {\
                                          var bakerOrientationChangeEvent = document.createEvent('Events');\
                                              bakerOrientationChangeEvent.initEvent('orientationchange', true, false);\
                                      }; window.dispatchEvent(bakerOrientationChangeEvent)";
    
    // 3. Merge the scripts and load them on the current UIWebView
    NSString *jsCommand = [jsOrientationGetter stringByAppendingString:jsOrientationChange];
    [currPage stringByEvaluatingJavaScriptFromString:jsCommand];
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    UIDeviceOrientation orientation = [self interfaceOrientation];
    [indexViewController rotateFromOrientation:fromInterfaceOrientation toOrientation:orientation];
     
	[self checkPageSize];
	[self getPageHeight];
	[self resetScrollView];
}

#pragma mark - MEMORY
- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}
- (void)viewDidUnload {
    
	[super viewDidUnload];
	
	// Set web views delegates to nil, mandatory before releasing UIWebview instances
    currPage.delegate = nil;
	nextPage.delegate = nil;
	prevPage.delegate = nil;
}
- (void)dealloc {
    
    [indexViewController release];
    [scrollView release];
    [currPage release];
	[nextPage release];
	[prevPage release];
    
    [super dealloc];
}

@end
