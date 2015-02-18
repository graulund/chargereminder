//
//  AppDelegate.m
//  Charge Reminder
//
//  Created by Andreas Graulund on 29/01/15.
//  Copyright (c) 2015 Pongsocket. All rights reserved.
//

#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/usb/USBSpec.h>
#import "AppDelegate.h"

#define USB_VENDOR_ID_STORAGE_KEY @"vendorid"
#define USB_DEVICE_ID_STORAGE_KEY @"deviceid"
#define FIRST_HOUR_STORAGE_KEY @"firsthour"
#define ALERT_HOURS_STORAGE_KEY @"alerthours"
#define ALERT_MINUTES_STORAGE_KEY @"alertminutes"

@interface AppDelegate ()

-(void)setDefaultSettings;
-(NSDate *)firstAlertTime;
-(NSDate *)lastAlertTime;
-(NSDate *)tomorrow;
-(void)alertIfDeviceNotPresent;
-(void)scheduleAlerting;
-(void)startAlerting;
-(void)continueAlerting;
-(void)finishAlerting;
-(BOOL)isDevicePresent;

@property (nonatomic, strong) NSTimer *timer;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    [self setDefaultSettings];
    
    NSLog(@"Is device present right now? %d", [self isDevicePresent]);
    
    [self scheduleAlerting];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

#pragma mark - Tools

-(void)setDefaultSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSInteger devicekey = [defaults integerForKey:USB_DEVICE_ID_STORAGE_KEY];
    
    if (devicekey <= 0) {
        // TODO: Display UI alert that you have to define your settings
        
        // USB Vendor ID for device to detect
        [defaults setInteger:0x05ac forKey:USB_VENDOR_ID_STORAGE_KEY];
        
        // USB Device ID for device to detect
        [defaults setInteger:0x12a8 forKey:USB_DEVICE_ID_STORAGE_KEY];
        
        // Hour for when to start alerting that you need to charge it
        [defaults setInteger:22 forKey:FIRST_HOUR_STORAGE_KEY];
        
        // Amount of hours for when we will keep trying to alert you
        [defaults setDouble:1.5 forKey:ALERT_HOURS_STORAGE_KEY];
        
        // Amount of minutes between alerts
        [defaults setDouble:10.0 forKey:ALERT_MINUTES_STORAGE_KEY];
        
        // Save settings
        [defaults synchronize];
    }
}

-(NSDate *)firstAlertTime {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSCalendar* myCalendar = [NSCalendar currentCalendar];
    NSDateComponents* components = [myCalendar components: NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                 fromDate:[NSDate date]];
    [components setHour: [defaults integerForKey:FIRST_HOUR_STORAGE_KEY]];
    [components setMinute: 0];
    [components setSecond: 0];
    return [myCalendar dateFromComponents:components];
}

-(NSDate *)lastAlertTime {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [NSDate dateWithTimeInterval:3600.0*[defaults doubleForKey:ALERT_HOURS_STORAGE_KEY] sinceDate:[self firstAlertTime]];
}

-(NSDate *)tomorrow {
    NSDate *now = [NSDate date];
    NSCalendar* myCalendar = [NSCalendar currentCalendar];
    NSDateComponents* components = [myCalendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay
                                                 fromDate:now];
    [components setHour:0];
    [components setMinute:0];
    [components setSecond:0];
    NSDate *today = [myCalendar dateFromComponents:components];
    return [NSDate dateWithTimeInterval:86400 sinceDate:today];
}

-(void)alertIfDeviceNotPresent {
    if (![self isDevicePresent]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Dismiss"];
        [alert setMessageText:@"Reminder: Please charge your device!"];
        [alert setInformativeText:@"There's another day tomorrow..."];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert runModal];
    }
}

-(void)scheduleAlerting {
    
    NSDate *firstAlertTime = [self firstAlertTime];
    NSDate *lastAlertTime = [self lastAlertTime];
    NSDate *now = [NSDate date];
    
    NSLog(@"Scheduling at first alert time: %@", firstAlertTime);
    
    if ([firstAlertTime compare:now] == NSOrderedDescending) {
        // If first alert time is in the future
        [NSTimer scheduledTimerWithTimeInterval:[firstAlertTime timeIntervalSinceNow]
                                         target:self
                                       selector:@selector(startAlerting)
                                       userInfo:nil
                                        repeats:NO];
    } else {
        if ([lastAlertTime compare:now] == NSOrderedDescending) {
            // Last alert time is in the future, alert now
            [self startAlerting];
        }
    }
    
}

-(void)startAlerting {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:60*[defaults doubleForKey:ALERT_MINUTES_STORAGE_KEY]
                                                  target:self
                                                selector:@selector(alertIfDeviceNotPresent)
                                                userInfo:nil
                                                 repeats:YES];
}

-(void)continueAlerting {
    NSDate *lastAlertTime = [self lastAlertTime];
    NSDate *now = [NSDate date];
    if ([lastAlertTime compare:now] != NSOrderedDescending) {
        // We're done!
        [self finishAlerting];
    } else {
        // Continue alerting
        [self alertIfDeviceNotPresent];
    }
}

-(void)finishAlerting {
    
    NSLog(@"Finishing alerting...");
    
    // Invalidate the timer to prevent further repeating
    [self.timer invalidate];
    
    // Re-schedule for tomorrow
    NSDate *firstAlertTime = [self firstAlertTime];
    NSDate *now = [NSDate date];
    if ([firstAlertTime compare:now] == NSOrderedDescending) {
        // If finish alert time is in the future once again, it must already be tomorrow.
        [self scheduleAlerting];
    } else {
        // Otherwise schedule a look at this again tomorrow.
        NSDate *tomorrow = [self tomorrow];
        [NSTimer scheduledTimerWithTimeInterval:[tomorrow timeIntervalSinceNow]
                                         target:self
                                       selector:@selector(scheduleAlerting)
                                       userInfo:nil
                                        repeats:NO];
    }
}

-(BOOL)isDevicePresent {
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    CFMutableDictionaryRef matchingDictionary = NULL;
    SInt32 idVendor = (int)[defaults integerForKey:USB_VENDOR_ID_STORAGE_KEY];
    SInt32 idProduct = (int)[defaults integerForKey:USB_DEVICE_ID_STORAGE_KEY];
    io_iterator_t iterator = 0;
    io_service_t usbRef;
    BOOL present = NO;
    
    matchingDictionary = IOServiceMatching(kIOUSBDeviceClassName);
    
    CFDictionaryAddValue(matchingDictionary,
                         CFSTR(kUSBVendorID),
                         CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberSInt32Type, &idVendor));
    CFDictionaryAddValue(matchingDictionary,
                         CFSTR(kUSBProductID),
                         CFNumberCreate(kCFAllocatorDefault,
                                        kCFNumberSInt32Type, &idProduct));
    
    IOServiceGetMatchingServices(kIOMasterPortDefault,
                                 matchingDictionary, &iterator);
    
    usbRef = IOIteratorNext(iterator);
    present = usbRef != 0;
    IOObjectRelease(iterator);
    
    // https://delog.wordpress.com/2012/04/27/access-usb-device-on-mac-os-x-using-io-kit/
    
    return present;
}


@end
