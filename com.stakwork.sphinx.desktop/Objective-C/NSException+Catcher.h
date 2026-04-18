//
//  NSException+Catcher.h
//  sphinx
//
//  Allows Swift code to safely catch Objective-C exceptions that would otherwise
//  propagate through C++ libdispatch frames and trigger std::terminate.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSExceptionCatcher : NSObject

/// Executes block inside @try/@catch. Returns YES on success, NO if an ObjC
/// exception was raised. The exception reason is written to `outExceptionReason`
/// when provided.
+ (BOOL)tryExecute:(void (^)(void))block
      exceptionReason:(NSString * _Nullable * _Nullable)outExceptionReason;

@end

NS_ASSUME_NONNULL_END
