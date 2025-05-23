#import "String+Geometrics.h"

/*
 To use this file in a non-ARC target, #define NO_ARC 1 in a prefix
 file, or for smart ARC-or-not detection, include our super whiz bang
 SSY_ARC_OR_NO_ARC.h in your project and #import "SSY_ARC_OR_NO_ARC.h"
 in your prefix file.
 */

NSInteger gNSStringGeometricsTypesetterBehavior = NSTypesetterLatestBehavior ;

@implementation NSAttributedString (Geometrics) 

#pragma mark * Measure Attributed String

- (NSSize)sizeForWidth:(CGFloat)width 
                height:(CGFloat)height {
    NSSize answer = NSZeroSize ;
    if ([self length] > 0) {
        // Checking for empty string is necessary since Layout Manager will give the nominal
        // height of one line if length is 0.  Our API specifies 0.0 for an empty string.
        NSSize size = NSMakeSize(width, height) ;
        NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:size] ;
        NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:self] ;
        NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init] ;
        [layoutManager addTextContainer:textContainer] ;
        [textStorage addLayoutManager:layoutManager] ;
        [layoutManager usesDefaultHyphenation] ;
        if (gNSStringGeometricsTypesetterBehavior != NSTypesetterLatestBehavior) {
            [layoutManager setTypesetterBehavior:gNSStringGeometricsTypesetterBehavior] ;
        }
        // NSLayoutManager is lazy, so we need the following kludge to force layout:
        [layoutManager glyphRangeForTextContainer:textContainer] ;
        
        answer = [layoutManager usedRectForTextContainer:textContainer].size ;
#if !__has_feature(objc_arc)
        [textStorage release] ;
        [textContainer release] ;
#endif
        // Adjust if there is extra height for the cursor
        NSSize extraLineSize = [layoutManager extraLineFragmentRect].size ;
        if (extraLineSize.height > 0) {
            answer.height -= extraLineSize.height ;
        }
        
#if !__has_feature(objc_arc)
        [layoutManager release] ;
#endif
        // In case we changed it above, set typesetterBehavior back
        // to the default value.
        gNSStringGeometricsTypesetterBehavior = NSTypesetterLatestBehavior ;
    }
    
    return answer ;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    return [self sizeForWidth:width
                       height:FLT_MAX].height ;
}

- (CGFloat)widthForHeight:(CGFloat)height {
    return [self sizeForWidth:FLT_MAX
                       height:height].width ;
}

- (NSAttributedString*)attributedStringTruncatedToWidth:(CGFloat)width
                                                 height:(CGFloat)height {
    NSAttributedString* answer = self ;
    if ([self length] > 2) {
        if (([self widthForHeight:height] > width) || ([self heightForWidth:width] > height)) {
            NSMutableAttributedString* attributedString = [self mutableCopy] ;
            [attributedString replaceCharactersInRange:NSMakeRange([attributedString length] - 1, 1)
                                            withString:@"…"] ;
            
            while (
                   (([attributedString widthForHeight:height] > width) || ([attributedString heightForWidth:width] > height))
                   &&
                   ([attributedString length] > 1)
                   ) {
                [attributedString replaceCharactersInRange:NSMakeRange([attributedString length] - 2, 2)
                                                withString:@"…"] ;
            }
            
            answer = [attributedString copy] ;
        }
    }

    return answer ;
}

@end


@implementation NSString (Geometrics)

#pragma mark * Given String with Attributes

- (NSSize)sizeForWidth:(CGFloat)width 
                height:(CGFloat)height
            attributes:(NSDictionary*)attributes {
    NSSize answer ;
    
    NSAttributedString *astr = [[NSAttributedString alloc] initWithString:self
                                                               attributes:attributes] ;
    answer = [astr sizeForWidth:width
                         height:height] ;
#if !__has_feature(objc_arc)
    [astr release] ;
#endif
    
    return answer ;
}

- (CGFloat)heightForWidth:(CGFloat)width
             attributes:(NSDictionary*)attributes {
    return [self sizeForWidth:width
                       height:FLT_MAX
                   attributes:attributes].height ;
}

- (CGFloat)widthForHeight:(CGFloat)height
             attributes:(NSDictionary*)attributes {
    return [self sizeForWidth:FLT_MAX
                       height:height
                   attributes:attributes].width ;
}

#pragma mark * Given String with Font

- (NSSize)sizeForWidth:(CGFloat)width 
                height:(CGFloat)height
                  font:(NSFont*)font {
    NSSize answer = NSZeroSize ;
    
    if (font == nil) {
        NSLog(@"[%@ %@]: Internal Error 561-3810: Nil font", [self class], NSStringFromSelector(_cmd)) ;
    }
    else {
        NSDictionary* attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    font, NSFontAttributeName, nil] ;
        answer = [self sizeForWidth:width
                             height:height
                         attributes:attributes] ;
    }
    
    return answer ;
}

- (CGFloat)heightForWidth:(CGFloat)width
                   font:(NSFont*)font {
    return [self sizeForWidth:width
                       height:FLT_MAX
                         font:font].height ;
}

- (CGFloat)widthForHeight:(CGFloat)height
                   font:(NSFont*)font {
    return [self sizeForWidth:FLT_MAX
                       height:height
                         font:font].width ;
}

@end
