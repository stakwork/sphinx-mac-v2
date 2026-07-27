//
//  NSException+Catcher.m
//  sphinx
//

#import "NSException+Catcher.h"

@implementation NSExceptionCatcher

+ (BOOL)tryExecute:(void (^)(void))block
      exceptionReason:(NSString **)outExceptionReason {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outExceptionReason) {
            *outExceptionReason = exception.reason ?: exception.name;
        }
        return NO;
    }
}

@end
