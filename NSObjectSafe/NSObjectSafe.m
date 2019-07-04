//
//  NSMutableArray+Hook.m
//  test
//
//  Created by jasenhuang on 15/12/21.
//  Copyright © 2015年 tencent. All rights reserved.
//

#import "NSObjectSafe.h"
#import <objc/runtime.h>
#import <objc/message.h>

#if __has_feature(objc_arc)
#error This file must be compiled with MRC. Use -fno-objc-arc flag.
#endif

/**
 * 1: negative value
 *  - NSUInteger  > NSIntegerMax
 * 2: overflow
 *  - (a+ b) > a
 */
NS_INLINE NSUInteger NSSafeMaxRange(NSRange range) {
    // negative or reach limit
    if (range.location >= NSNotFound
        || range.length >= NSNotFound){
        return NSNotFound;
    }
    // overflow
    if ((range.location + range.length) < range.location){
        return NSNotFound;
    }
    return (range.location + range.length);
}

NSString *const NSSafeNotification = @"_NSSafeNotification_";

#define SFAssert(condition, ...) \
if (!(condition)){ SFLog(__FILE__, __FUNCTION__, __LINE__, __VA_ARGS__);} \
NSAssert(condition, @"%@", __VA_ARGS__);

void SFLog(const char* file, const char* func, int line, NSString* fmt, ...)
{
    va_list args; va_start(args, fmt);
    NSLog(@"%s|%s|%d|%@", file, func, line, [[[NSString alloc] initWithFormat:fmt arguments:args] autorelease]);
    va_end(args);
}
@interface NSSafeProxy : NSObject
@end

@implementation NSSafeProxy
- (void)dealException:(NSString*)info
{
    NSString* msg = [NSString stringWithFormat:@"NSSafeProxy: %@", info];
    SFAssert(0, msg);
}
@end

void swizzleClassMethod(Class cls, SEL origSelector, SEL newSelector)
{
    if (!cls) return;
    Method originalMethod = class_getClassMethod(cls, origSelector);
    Method swizzledMethod = class_getClassMethod(cls, newSelector);
    
    Class metacls = objc_getMetaClass(NSStringFromClass(cls).UTF8String);
    if (class_addMethod(metacls,
                        origSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)) ) {
        /* swizzing super class method, added if not exist */
        class_replaceMethod(metacls,
                            newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
        
    } else {
        /* swizzleMethod maybe belong to super */
        class_replaceMethod(metacls,
                            newSelector,
                            class_replaceMethod(metacls,
                                                origSelector,
                                                method_getImplementation(swizzledMethod),
                                                method_getTypeEncoding(swizzledMethod)),
                            method_getTypeEncoding(originalMethod));
    }
}

void swizzleInstanceMethod(Class cls, SEL origSelector, SEL newSelector)
{
    if (!cls) {
        return;
    }
    /* if current class not exist selector, then get super*/
    Method originalMethod = class_getInstanceMethod(cls, origSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, newSelector);
    
    /* add selector if not exist, implement append with method */
    if (class_addMethod(cls,
                        origSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)) ) {
        /* replace class instance method, added if selector not exist */
        /* for class cluster , it always add new selector here */
        class_replaceMethod(cls,
                            newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
        
    } else {
        /* swizzleMethod maybe belong to super */
        class_replaceMethod(cls,
                            newSelector,
                            class_replaceMethod(cls,
                                                origSelector,
                                                method_getImplementation(swizzledMethod),
                                                method_getTypeEncoding(swizzledMethod)),
                            method_getTypeEncoding(originalMethod));
    }
}

@implementation NSObject(Swizzle)
+ (void)swizzleClassMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    swizzleClassMethod(self.class, origSelector, newSelector);
}

- (void)swizzleInstanceMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    swizzleInstanceMethod(self.class, origSelector, newSelector);
}
@end

@implementation NSObject(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod([NSObject class], @selector(addObserver:forKeyPath:options:context:), @selector(hookAddObserver:forKeyPath:options:context:));
        swizzleInstanceMethod([NSObject class], @selector(removeObserver:forKeyPath:), @selector(hookRemoveObserver:forKeyPath:));
        swizzleInstanceMethod([NSObject class], @selector(methodSignatureForSelector:), @selector(hookMethodSignatureForSelector:));
        swizzleInstanceMethod([NSObject class], @selector(forwardInvocation:), @selector(hookForwardInvocation:));
    });
}
- (void) hookAddObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
    if (!observer || !keyPath.length) {
        SFAssert(NO, @"hookAddObserver invalid args: %@", self);
        return;
    }
    @try {
        [self hookAddObserver:observer forKeyPath:keyPath options:options context:context];
    }
    @catch (NSException *exception) {
        NSLog(@"hookAddObserver ex: %@", [exception callStackSymbols]);
    }
}
- (void) hookRemoveObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    if (!observer || !keyPath.length) {
        SFAssert(NO, @"hookRemoveObserver invalid args: %@", self);
        return;
    }
    @try {
        [self hookRemoveObserver:observer forKeyPath:keyPath];
    }
    @catch (NSException *exception) {
        NSLog(@"hookRemoveObserver ex: %@", [exception callStackSymbols]);
    }
}

- (NSMethodSignature*)hookMethodSignatureForSelector:(SEL)aSelector {
    /* 如果 当前类有methodSignatureForSelector实现，NSObject的实现直接返回nil
     * 子类实现如下：
     *          NSMethodSignature* sig = [super methodSignatureForSelector:aSelector];
     *          if (!sig) {
     *              //当前类的methodSignatureForSelector实现
     *              //如果当前类的methodSignatureForSelector也返回nil
     *          }
     *          return sig;
     */
    NSMethodSignature* sig = [self hookMethodSignatureForSelector:aSelector];
    if (!sig){
        if (class_getMethodImplementation([NSObject class], @selector(methodSignatureForSelector:))
            != class_getMethodImplementation(self.class, @selector(methodSignatureForSelector:)) ){
            return nil;
        }
        return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
    }
    return sig;
}

- (void)hookForwardInvocation:(NSInvocation*)invocation
{
    NSString* info = [NSString stringWithFormat:@"unrecognized selector [%@] sent to %@", NSStringFromSelector(invocation.selector), NSStringFromClass(self.class)];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSSafeNotification object:self userInfo:@{@"invocation":invocation}];
    [[[NSSafeProxy new] autorelease] dealException:info];
}

@end

#pragma mark - NSString
@implementation NSString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法不用在NSMutableString里再swizz一次 */
        [NSString swizzleClassMethod:@selector(stringWithUTF8String:) withMethod:@selector(hookStringWithUTF8String:)];
        [NSString swizzleClassMethod:@selector(stringWithCString:encoding:) withMethod:@selector(hookStringWithCString:encoding:)];
        
        /* init方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderString"), @selector(initWithString:), @selector(hookInitWithString:));
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderString"), @selector(initWithUTF8String:), @selector(hookInitWithUTF8String:));
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderString"), @selector(initWithCString:encoding:), @selector(hookInitWithCString:encoding:));
        
        /* _NSCFConstantString */
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(stringByAppendingString:), @selector(hookStringByAppendingString:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringFromIndex:), @selector(hookSubstringFromIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringToIndex:), @selector(hookSubstringToIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringWithRange:), @selector(hookSubstringWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(rangeOfString:options:range:locale:), @selector(hookRangeOfString:options:range:locale:));
        
        /* NSTaggedPointerString */
        swizzleInstanceMethod(NSClassFromString(@"NSTaggedPointerString"), @selector(stringByAppendingString:), @selector(hookStringByAppendingString:));
        swizzleInstanceMethod(NSClassFromString(@"NSTaggedPointerString"), @selector(substringFromIndex:), @selector(hookSubstringFromIndex:));
        swizzleInstanceMethod(NSClassFromString(@"NSTaggedPointerString"), @selector(substringToIndex:), @selector(hookSubstringToIndex:));
        swizzleInstanceMethod(NSClassFromString(@"NSTaggedPointerString"), @selector(substringWithRange:), @selector(hookSubstringWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSTaggedPointerString"), @selector(rangeOfString:options:range:locale:), @selector(hookRangeOfString:options:range:locale:));
        
    });
}
+ (NSString*) hookStringWithUTF8String:(const char *)nullTerminatedCString
{
    if (NULL != nullTerminatedCString) {
        return [self hookStringWithUTF8String:nullTerminatedCString];
    }
    SFAssert(NO, @"NSString invalid args hookStringWithUTF8String nil cstring");
    return nil;
}
+ (nullable instancetype) hookStringWithCString:(const char *)cString encoding:(NSStringEncoding)enc
{
    if (NULL != cString){
        return [self hookStringWithCString:cString encoding:enc];
    }
    SFAssert(NO, @"NSString invalid args hookStringWithCString nil cstring");
    return nil;
}
- (nullable instancetype) hookInitWithString:(NSString *)aString
{
    if (aString){
        return [self hookInitWithString:aString];
    }
    SFAssert(NO, @"NSString invalid args hookInitWithString nil aString");
    return nil;
}
- (nullable instancetype) hookInitWithUTF8String:(const char *)nullTerminatedCString
{
    if (NULL != nullTerminatedCString) {
        return [self hookInitWithUTF8String:nullTerminatedCString];
    }
    SFAssert(NO, @"NSString invalid args hookInitWithUTF8String nil aString");
    return nil;
}
- (nullable instancetype) hookInitWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding
{
    if (NULL != nullTerminatedCString){
        return [self hookInitWithCString:nullTerminatedCString encoding:encoding];
    }
    SFAssert(NO, @"NSString invalid args hookInitWithCString nil cstring");
    return nil;
}
- (NSString *)hookStringByAppendingString:(NSString *)aString
{
    @synchronized (self) {
        if (aString){
            return [self hookStringByAppendingString:aString];
        }
        return self;
    }
}
- (NSString *)hookSubstringFromIndex:(NSUInteger)from
{
    @synchronized (self) {
        if (from <= self.length) {
            return [self hookSubstringFromIndex:from];
        }
        return nil;
    }
}
- (NSString *)hookSubstringToIndex:(NSUInteger)to
{
    @synchronized (self) {
        if (to <= self.length) {
            return [self hookSubstringToIndex:to];
        }
        return self;
    }
}
- (NSString *)hookSubstringWithRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            return [self hookSubstringWithRange:range];
        }else if (range.location < self.length){
            return [self hookSubstringWithRange:NSMakeRange(range.location, self.length-range.location)];
        }
        return nil;
    }
}
- (NSRange)hookRangeOfString:(NSString *)searchString options:(NSStringCompareOptions)mask range:(NSRange)range locale:(nullable NSLocale *)locale
{
    @synchronized (self) {
        if (searchString){
            if (NSSafeMaxRange(range) <= self.length) {
                return [self hookRangeOfString:searchString options:mask range:range locale:locale];
            }else if (range.location < self.length){
                return [self hookRangeOfString:searchString options:mask range:NSMakeRange(range.location, self.length-range.location) locale:locale];
            }
            return NSMakeRange(NSNotFound, 0);
        }else{
            SFAssert(NO, @"hookRangeOfString:options:range:locale: searchString is nil");
            return NSMakeRange(NSNotFound, 0);
        }
    }
}
@end

@implementation NSMutableString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderMutableString"), @selector(initWithString:), @selector(hookInitWithString:));
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderMutableString"), @selector(initWithUTF8String:), @selector(hookInitWithUTF8String:));
        swizzleInstanceMethod(NSClassFromString(@"NSPlaceholderMutableString"), @selector(initWithCString:encoding:), @selector(hookInitWithCString:encoding:));
        
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(appendString:), @selector(hookAppendString:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(insertString:atIndex:), @selector(hookInsertString:atIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(deleteCharactersInRange:), @selector(hookDeleteCharactersInRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(stringByAppendingString:), @selector(hookStringByAppendingString:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringFromIndex:), @selector(hookSubstringFromIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringToIndex:), @selector(hookSubstringToIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringWithRange:), @selector(hookSubstringWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(rangeOfString:options:range:locale:), @selector(hookRangeOfString:options:range:locale:));
    });
    
}
- (nullable instancetype) hookInitWithString:(NSString *)aString
{
    if (aString){
        return [self hookInitWithString:aString];
    }
    SFAssert(NO, @"NSString invalid args hookInitWithString nil aString");
    return nil;
}
- (nullable instancetype) hookInitWithUTF8String:(const char *)nullTerminatedCString
{
    if (NULL != nullTerminatedCString) {
        return [self hookInitWithUTF8String:nullTerminatedCString];
    }
    SFAssert(NO, @"NSString invalid args hookInitWithUTF8String nil aString");
    return nil;
}
- (nullable instancetype) hookInitWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding
{
    if (NULL != nullTerminatedCString){
        return [self hookInitWithCString:nullTerminatedCString encoding:encoding];
    }
    SFAssert(NO, @"NSMutableString invalid args hookInitWithCString nil cstring");
    return nil;
}
- (void) hookAppendString:(NSString *)aString
{
    @synchronized (self) {
        if (aString){
            [self hookAppendString:aString];
        }else{
            SFAssert(NO, @"NSMutableString invalid args hookAppendString:[%@]", aString);
        }
    }
}
- (void) hookInsertString:(NSString *)aString atIndex:(NSUInteger)loc
{
    @synchronized (self) {
        if (aString && loc <= self.length) {
            [self hookInsertString:aString atIndex:loc];
        }else{
            SFAssert(NO, @"NSMutableString invalid args hookInsertString:[%@] atIndex:[%@]", aString, @(loc));
        }
    }
}
- (void) hookDeleteCharactersInRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length){
            [self hookDeleteCharactersInRange:range];
        }else{
            SFAssert(NO, @"NSMutableString invalid args hookDeleteCharactersInRange:[%@]", NSStringFromRange(range));
        }
    }
}
- (NSString *)hookStringByAppendingString:(NSString *)aString
{
    @synchronized (self) {
        if (aString){
            return [self hookStringByAppendingString:aString];
        }
        return self;
    }
}
- (NSString *)hookSubstringFromIndex:(NSUInteger)from
{
    @synchronized (self) {
        if (from <= self.length) {
            return [self hookSubstringFromIndex:from];
        }
        return nil;
    }
}
- (NSString *)hookSubstringToIndex:(NSUInteger)to
{
    @synchronized (self) {
        if (to <= self.length) {
            return [self hookSubstringToIndex:to];
        }
        return self;
    }
}
- (NSString *)hookSubstringWithRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            return [self hookSubstringWithRange:range];
        }else if (range.location < self.length){
            return [self hookSubstringWithRange:NSMakeRange(range.location, self.length-range.location)];
        }
        return nil;
    }
}
@end

#pragma mark - NSAttributedString
@implementation NSAttributedString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(initWithString:), @selector(hookInitWithString:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(initWithString:attributes:), @selector(hookInitWithString:attributes:));
        
        /* 普通方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(attributedSubstringFromRange:), @selector(hookAttributedSubstringFromRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(attribute:atIndex:effectiveRange:), @selector(hookAttribute:atIndex:effectiveRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(enumerateAttribute:inRange:options:usingBlock:), @selector(hookEnumerateAttribute:inRange:options:usingBlock:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteAttributedString"), @selector(enumerateAttributesInRange:options:usingBlock:), @selector(hookEnumerateAttributesInRange:options:usingBlock:));
        
    });
}
- (id)hookInitWithString:(NSString*)str {
    if (str){
        return [self hookInitWithString:str];
    }
    return nil;
}
- (id)hookInitWithString:(NSString*)str attributes:(nullable NSDictionary*)attributes{
    if (str){
        return [self hookInitWithString:str attributes:attributes];
    }
    return nil;
}
- (id)hookAttribute:(NSAttributedStringKey)attrName atIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range
{
    @synchronized (self) {
        if (location < self.length){
            return [self hookAttribute:attrName atIndex:location effectiveRange:range];
        }else{
            return nil;
        }
    }
}
- (NSAttributedString *)hookAttributedSubstringFromRange:(NSRange)range {
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            return [self hookAttributedSubstringFromRange:range];
        }else if (range.location < self.length){
            return [self hookAttributedSubstringFromRange:NSMakeRange(range.location, self.length-range.location)];
        }
        return nil;
    }
}
- (void)hookEnumerateAttribute:(NSString *)attrName inRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(id _Nullable, NSRange, BOOL * _Nonnull))block
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookEnumerateAttribute:attrName inRange:range options:opts usingBlock:block];
        }else if (range.location < self.length){
            [self hookEnumerateAttribute:attrName inRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
        }
    }
}
- (void)hookEnumerateAttributesInRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(NSDictionary<NSString*,id> * _Nonnull, NSRange, BOOL * _Nonnull))block
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookEnumerateAttributesInRange:range options:opts usingBlock:block];
        }else if (range.location < self.length){
            [self hookEnumerateAttributesInRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
        }
    }
}
@end

#pragma mark - NSMutableAttributedString
@implementation NSMutableAttributedString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"), @selector(initWithString:), @selector(hookInitWithString:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"), @selector(initWithString:attributes:), @selector(hookInitWithString:attributes:));
        
        /* 普通方法 */
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(attributedSubstringFromRange:), @selector(hookAttributedSubstringFromRange:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(attribute:atIndex:effectiveRange:), @selector(hookAttribute:atIndex:effectiveRange:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(addAttribute:value:range:), @selector(hookAddAttribute:value:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(addAttributes:range:), @selector(hookAddAttributes:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(addAttributes:range:), @selector(hookAddAttributes:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(setAttributes:range:), @selector(hookSetAttributes:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(removeAttribute:range:), @selector(hookRemoveAttribute:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(deleteCharactersInRange:), @selector(hookDeleteCharactersInRange:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(replaceCharactersInRange:withString:), @selector(hookReplaceCharactersInRange:withString:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(replaceCharactersInRange:withAttributedString:), @selector(hookReplaceCharactersInRange:withAttributedString:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(enumerateAttribute:inRange:options:usingBlock:), @selector(hookEnumerateAttribute:inRange:options:usingBlock:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableAttributedString"),
                              @selector(enumerateAttributesInRange:options:usingBlock:), @selector(hookEnumerateAttributesInRange:options:usingBlock:));
        
    });
}
- (id)hookInitWithString:(NSString*)str {
    if (str){
        return [self hookInitWithString:str];
    }
    return nil;
}
- (id)hookInitWithString:(NSString*)str attributes:(nullable NSDictionary*)attributes{
    if (str){
        return [self hookInitWithString:str attributes:attributes];
    }
    return nil;
}
- (NSAttributedString *)hookAttributedSubstringFromRange:(NSRange)range {
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            return [self hookAttributedSubstringFromRange:range];
        }else if (range.location < self.length){
            return [self hookAttributedSubstringFromRange:NSMakeRange(range.location, self.length-range.location)];
        }
        return nil;
    }
}
- (id)hookAttribute:(NSAttributedStringKey)attrName atIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range
{
    @synchronized (self) {
        if (location < self.length){
            return [self hookAttribute:attrName atIndex:location effectiveRange:range];
        }else{
            return nil;
        }
    }
}
- (void)hookAddAttribute:(id)name value:(id)value range:(NSRange)range {
    @synchronized (self) {
        if (!range.length) {
            [self hookAddAttribute:name value:value range:range];
        }else if (value){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookAddAttribute:name value:value range:range];
            }else if (range.location < self.length){
                [self hookAddAttribute:name value:value range:NSMakeRange(range.location, self.length-range.location)];
            }
        }else {
            SFAssert(NO, @"hookAddAttribute:value:range: value is nil");
        }
    }
}
- (void)hookAddAttributes:(NSDictionary<NSString *,id> *)attrs range:(NSRange)range {
    @synchronized (self) {
        if (!range.length) {
            [self hookAddAttributes:attrs range:range];
        }else if (attrs){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookAddAttributes:attrs range:range];
            }else if (range.location < self.length){
                [self hookAddAttributes:attrs range:NSMakeRange(range.location, self.length-range.location)];
            }
        }else{
            SFAssert(NO, @"hookAddAttributes:range: attrs is nil");
        }
    }
}
- (void)hookSetAttributes:(NSDictionary<NSString *,id> *)attrs range:(NSRange)range {
    @synchronized (self) {
        if (!range.length) {
            [self hookSetAttributes:attrs range:range];
        }else if (attrs){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookSetAttributes:attrs range:range];
            }else if (range.location < self.length){
                [self hookSetAttributes:attrs range:NSMakeRange(range.location, self.length-range.location)];
            }
        }else{
            SFAssert(NO, @"hookSetAttributes:range:  attrs is nil");
        }
    }
}
- (void)hookRemoveAttribute:(id)name range:(NSRange)range {
    @synchronized (self) {
        if (!range.length) {
            [self hookRemoveAttribute:name range:range];
        }else if (name){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookRemoveAttribute:name range:range];
            }else if (range.location < self.length) {
                [self hookRemoveAttribute:name range:NSMakeRange(range.location, self.length-range.location)];
            }
        }else{
            SFAssert(NO, @"hookRemoveAttribute:range:  name is nil");
        }
    }
}
- (void)hookDeleteCharactersInRange:(NSRange)range {
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookDeleteCharactersInRange:range];
        }else if (range.location < self.length) {
            [self hookDeleteCharactersInRange:NSMakeRange(range.location, self.length-range.location)];
        }
    }
}
- (void)hookReplaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    @synchronized (self) {
        if (str){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookReplaceCharactersInRange:range withString:str];
            }else if (range.location < self.length) {
                [self hookReplaceCharactersInRange:NSMakeRange(range.location, self.length-range.location) withString:str];
            }
        }else{
            SFAssert(NO, @"hookReplaceCharactersInRange:withString:  str is nil");
        }
    }
}
- (void)hookReplaceCharactersInRange:(NSRange)range withAttributedString:(NSString *)str {
    @synchronized (self) {
        if (str){
            if (NSSafeMaxRange(range) <= self.length) {
                [self hookReplaceCharactersInRange:range withAttributedString:str];
            }else if (range.location < self.length) {
                [self hookReplaceCharactersInRange:NSMakeRange(range.location, self.length-range.location) withAttributedString:str];
            }
        }else{
            SFAssert(NO, @"hookReplaceCharactersInRange:withString:  str is nil");
        }
    }
}
- (void)hookEnumerateAttribute:(NSString*)attrName inRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(id _Nullable, NSRange, BOOL * _Nonnull))block
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookEnumerateAttribute:attrName inRange:range options:opts usingBlock:block];
        }else if (range.location < self.length){
            [self hookEnumerateAttribute:attrName inRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
        }
    }
}
- (void)hookEnumerateAttributesInRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(NSDictionary<NSString*,id> * _Nonnull, NSRange, BOOL * _Nonnull))block
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookEnumerateAttributesInRange:range options:opts usingBlock:block];
        }else if (range.location < self.length){
            [self hookEnumerateAttributesInRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
        }
    }
}
@end

#pragma mark - NSArray
@implementation NSArray (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法不用在NSMutableArray里再swizz一次 */
        [NSArray swizzleClassMethod:@selector(arrayWithObject:) withMethod:@selector(hookArrayWithObject:)];
        [NSArray swizzleClassMethod:@selector(arrayWithObjects:count:) withMethod:@selector(hookArrayWithObjects:count:)];
        
        /* 没内容类型是__NSArray0 */
        swizzleInstanceMethod(NSClassFromString(@"__NSArray0"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArray0"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArray0"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        /* 有内容obj类型才是__NSArrayI */
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        /* 有内容obj类型才是__NSArrayI_Transfer */
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI_Transfer"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI_Transfer"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayI_Transfer"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        /* iOS10 以上，单个内容类型是__NSSingleObjectArrayI */
        swizzleInstanceMethod(NSClassFromString(@"__NSSingleObjectArrayI"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSSingleObjectArrayI"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSSingleObjectArrayI"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        /* __NSFrozenArrayM */
        swizzleInstanceMethod(NSClassFromString(@"__NSFrozenArrayM"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSFrozenArrayM"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSFrozenArrayM"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        /* __NSArrayReversed */
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayReversed"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayReversed"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayReversed"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
    });
}
+ (instancetype) hookArrayWithObject:(id)anObject
{
    if (anObject) {
        return [self hookArrayWithObject:anObject];
    }
    SFAssert(NO, @"NSArray invalid args hookArrayWithObject:[%@]", anObject);
    return nil;
}

- (id) hookObjectAtIndex:(NSUInteger)index {
    @synchronized (self) {
        if (index < self.count) {
            return [self hookObjectAtIndex:index];
        }
        SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
        return nil;
    }
}
- (id) hookObjectAtIndexedSubscript:(NSInteger)index {
    @synchronized (self) {
        if (index < self.count) {
            return [self hookObjectAtIndexedSubscript:index];
        }
        SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
        return nil;
    }
}
- (NSArray *)hookSubarrayWithRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.count){
            return [self hookSubarrayWithRange:range];
        }else if (range.location < self.count){
            return [self hookSubarrayWithRange:NSMakeRange(range.location, self.count-range.location)];
        }
        return nil;
    }
}
+ (instancetype)hookArrayWithObjects:(const id [])objects count:(NSUInteger)cnt
{
    @synchronized (self) {
        NSInteger index = 0;
        id objs[cnt];
        for (NSInteger i = 0; i < cnt ; ++i) {
            if (objects[i]) {
                objs[index++] = objects[i];
            } else {
                SFAssert(NO, @"NSArray invalid args hookArrayWithObjects:[%@] atIndex:[%@]", objects[i], @(i));
            }
        }
        return [self hookArrayWithObjects:objs count:index];
    }
}
@end

@implementation NSMutableArray(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* __NSArrayM */
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(addObject:), @selector(hookAddObject:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(insertObject:atIndex:), @selector(hookInsertObject:atIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(removeObjectAtIndex:), @selector(hookRemoveObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(replaceObjectAtIndex:withObject:), @selector(hookReplaceObjectAtIndex:withObject:));
        swizzleInstanceMethod(NSClassFromString(@"__NSArrayM"), @selector(removeObjectsInRange:), @selector(hookRemoveObjectsInRange:));
        
        /* __NSCFArray */
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(subarrayWithRange:), @selector(hookSubarrayWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(objectAtIndexedSubscript:), @selector(hookObjectAtIndexedSubscript:));
        
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(addObject:), @selector(hookAddObject:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(insertObject:atIndex:), @selector(hookInsertObject:atIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(removeObjectAtIndex:), @selector(hookRemoveObjectAtIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(replaceObjectAtIndex:withObject:), @selector(hookReplaceObjectAtIndex:withObject:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFArray"), @selector(removeObjectsInRange:), @selector(hookRemoveObjectsInRange:));
    });
}
- (void) hookAddObject:(id)anObject {
    @synchronized (self) {
        if (anObject) {
            [self hookAddObject:anObject];
        } else {
            SFAssert(NO, @"NSMutableArray invalid args hookAddObject:[%@]", anObject);
        }
    }
}
- (id) hookObjectAtIndex:(NSUInteger)index {
    @synchronized (self) {
        if (index < self.count) {
            return [self hookObjectAtIndex:index];
        }
        SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
        return nil;
    }
}
- (id) hookObjectAtIndexedSubscript:(NSInteger)index {
    @synchronized (self) {
        if (index < self.count) {
            return [self hookObjectAtIndexedSubscript:index];
        }
        SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
        return nil;
    }
}
- (void) hookInsertObject:(id)anObject atIndex:(NSUInteger)index {
    @synchronized (self) {
        if (anObject && index <= self.count) {
            [self hookInsertObject:anObject atIndex:index];
        } else {
            if (!anObject) {
                SFAssert(NO, @"NSMutableArray invalid args hookInsertObject:[%@] atIndex:[%@]", anObject, @(index));
            }
            if (index > self.count) {
                SFAssert(NO, @"NSMutableArray hookInsertObject[%@] atIndex:[%@] out of bound:[%@]", anObject, @(index), @(self.count));
            }
        }
    }
}

- (void) hookRemoveObjectAtIndex:(NSUInteger)index {
    @synchronized (self) {
        if (index < self.count) {
            [self hookRemoveObjectAtIndex:index];
        } else {
            SFAssert(NO, @"NSMutableArray hookRemoveObjectAtIndex:[%@] out of bound:[%@]", @(index), @(self.count));
        }
    }
}


- (void) hookReplaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    @synchronized (self) {
        if (index < self.count && anObject) {
            [self hookReplaceObjectAtIndex:index withObject:anObject];
        } else {
            if (!anObject) {
                SFAssert(NO, @"NSMutableArray invalid args hookReplaceObjectAtIndex:[%@] withObject:[%@]", @(index), anObject);
            }
            if (index >= self.count) {
                SFAssert(NO, @"NSMutableArray hookReplaceObjectAtIndex:[%@] withObject:[%@] out of bound:[%@]", @(index), anObject, @(self.count));
            }
        }
    }
}

- (void) hookRemoveObjectsInRange:(NSRange)range {
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.count) {
            [self hookRemoveObjectsInRange:range];
        }else {
            SFAssert(NO, @"NSMutableArray invalid args hookRemoveObjectsInRange:[%@]", NSStringFromRange(range));
        }
    }
}

- (NSArray *)hookSubarrayWithRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.count){
            return [self hookSubarrayWithRange:range];
        }else if (range.location < self.count){
            return [self hookSubarrayWithRange:NSMakeRange(range.location, self.count-range.location)];
        }
        return nil;
    }
}

@end

#pragma mark - NSDictionary
@implementation NSData (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteData"), @selector(subdataWithRange:), @selector(hookSubdataWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteData"), @selector(rangeOfData:options:range:), @selector(hookRangeOfData:options:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableData"), @selector(subdataWithRange:), @selector(hookSubdataWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableData"), @selector(rangeOfData:options:range:), @selector(hookRangeOfData:options:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"_NSZeroData"), @selector(subdataWithRange:), @selector(hookSubdataWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"_NSZeroData"), @selector(rangeOfData:options:range:), @selector(hookRangeOfData:options:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"_NSInlineData"), @selector(subdataWithRange:), @selector(hookSubdataWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"_NSInlineData"), @selector(rangeOfData:options:range:), @selector(hookRangeOfData:options:range:));
        
        swizzleInstanceMethod(NSClassFromString(@"__NSCFData"), @selector(subdataWithRange:), @selector(hookSubdataWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFData"), @selector(rangeOfData:options:range:), @selector(hookRangeOfData:options:range:));
        
    });
}
- (NSData*)hookSubdataWithRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length){
            return [self hookSubdataWithRange:range];
        }else if (range.location < self.length){
            return [self hookSubdataWithRange:NSMakeRange(range.location, self.length-range.location)];
        }
        return nil;
    }
}

- (NSRange)hookRangeOfData:(NSData *)dataToFind options:(NSDataSearchOptions)mask range:(NSRange)range
{
    @synchronized (self) {
        if (dataToFind){
            if (NSSafeMaxRange(range) <= self.length) {
                return [self hookRangeOfData:dataToFind options:mask range:range];
            }else if (range.location < self.length){
                return [self hookRangeOfData:dataToFind options:mask range:NSMakeRange(range.location, self.length - range.location) ];
            }
            return NSMakeRange(NSNotFound, 0);
        }else{
            SFAssert(NO, @"hookRangeOfData:options:range: dataToFind is nil");
            return NSMakeRange(NSNotFound, 0);
        }
    }
}
@end

@implementation NSMutableData (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableData"), @selector(resetBytesInRange:), @selector(hookResetBytesInRange:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableData"), @selector(replaceBytesInRange:withBytes:), @selector(hookReplaceBytesInRange:withBytes:));
        swizzleInstanceMethod(NSClassFromString(@"NSConcreteMutableData"), @selector(replaceBytesInRange:withBytes:length:), @selector(hookReplaceBytesInRange:withBytes:length:));
        
        swizzleInstanceMethod(NSClassFromString(@"__NSCFData"), @selector(resetBytesInRange:), @selector(hookResetBytesInRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFData"), @selector(replaceBytesInRange:withBytes:), @selector(hookReplaceBytesInRange:withBytes:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFData"), @selector(replaceBytesInRange:withBytes:length:), @selector(hookReplaceBytesInRange:withBytes:length:));
    });
}

- (void)hookResetBytesInRange:(NSRange)range
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length){
            [self hookResetBytesInRange:range];
        }else if (range.location < self.length){
            [self hookResetBytesInRange:NSMakeRange(range.location, self.length-range.location)];
        }
    }
}

- (void)hookReplaceBytesInRange:(NSRange)range withBytes:(const void *)bytes
{
    @synchronized (self) {
        if (bytes){
            if (range.location <= self.length) {
                [self hookReplaceBytesInRange:range withBytes:bytes];
            }else {
                SFAssert(NO, @"hookReplaceBytesInRange:withBytes: range.location error");
            }
        }else{
            SFAssert(NO, @"hookReplaceBytesInRange:withBytes: bytes is nil");
        }
    }
}

- (void)hookReplaceBytesInRange:(NSRange)range withBytes:(const void *)bytes length:(NSUInteger)replacementLength
{
    @synchronized (self) {
        if (NSSafeMaxRange(range) <= self.length) {
            [self hookReplaceBytesInRange:range withBytes:bytes length:replacementLength];
        }else if (range.location < self.length){
            [self hookReplaceBytesInRange:NSMakeRange(range.location, self.length - range.location) withBytes:bytes length:replacementLength];
        }
    }
}

@end

#pragma mark - NSDictionary
@implementation NSDictionary (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法 */
        [NSDictionary swizzleClassMethod:@selector(dictionaryWithObject:forKey:) withMethod:@selector(hookDictionaryWithObject:forKey:)];
        [NSDictionary swizzleClassMethod:@selector(dictionaryWithObjects:forKeys:count:) withMethod:@selector(hookDictionaryWithObjects:forKeys:count:)];
    });
}
+ (instancetype) hookDictionaryWithObject:(id)object forKey:(id)key
{
    if (object && key) {
        return [self hookDictionaryWithObject:object forKey:key];
    }
    SFAssert(NO, @"NSDictionary invalid args hookDictionaryWithObject:[%@] forKey:[%@]", object, key);
    return nil;
}
+ (instancetype) hookDictionaryWithObjects:(const id [])objects forKeys:(const id [])keys count:(NSUInteger)cnt
{
    NSInteger index = 0;
    id ks[cnt];
    id objs[cnt];
    for (NSInteger i = 0; i < cnt ; ++i) {
        if (keys[i] && objects[i]) {
            ks[index] = keys[i];
            objs[index] = objects[i];
            ++index;
        }
    }
    return [self hookDictionaryWithObjects:objs forKeys:ks count:index];
}
@end

@implementation NSMutableDictionary (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod(NSClassFromString(@"__NSDictionaryM"), @selector(setObject:forKey:), @selector(hookSetObject:forKey:));
        swizzleInstanceMethod(NSClassFromString(@"__NSDictionaryM"), @selector(removeObjectForKey:), @selector(hookRemoveObjectForKey:));
        swizzleInstanceMethod(NSClassFromString(@"__NSDictionaryM"), @selector(setObject:forKeyedSubscript:), @selector(hookSetObject:forKeyedSubscript:));
    });
}

- (void) hookSetObject:(id)anObject forKey:(id)aKey {
    @synchronized (self) {
        if (anObject && aKey) {
            [self hookSetObject:anObject forKey:aKey];
        } else {
            SFAssert(NO, @"NSMutableDictionary invalid args hookSetObject:[%@] forKey:[%@]", anObject, aKey);
        }
    }
}

- (void) hookRemoveObjectForKey:(id)aKey {
    @synchronized (self) {
        if (aKey) {
            [self hookRemoveObjectForKey:aKey];
        } else {
            SFAssert(NO, @"NSMutableDictionary invalid args hookRemoveObjectForKey:[%@]", aKey);
        }
    }
}

- (void)hookSetObject:(id)obj forKeyedSubscript:(id<NSCopying>)key
{
    @synchronized (self) {
        if (key){
            [self hookSetObject:obj forKeyedSubscript:key];
        } else {
            SFAssert(NO, @"NSMutableDictionary invalid args hookSetObject:forKeyedSubscript:");
        }
    }
}

@end

#pragma mark - NSSet
@implementation NSSet (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法 */
        [NSSet swizzleClassMethod:@selector(setWithObject:) withMethod:@selector(hookSetWithObject:)];
    });
}
+ (instancetype)hookSetWithObject:(id)object
{
    if (object){
        return [self hookSetWithObject:object];
    }
    SFAssert(NO, @"NSSet invalid args hookSetWithObject:[%@]", object);
    return nil;
}
@end

@implementation NSMutableSet (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 普通方法 */
        NSMutableSet* obj = [NSMutableSet setWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(hookAddObject:)];
        [obj swizzleInstanceMethod:@selector(removeObject:) withMethod:@selector(hookRemoveObject:)];
    });
}
- (void) hookAddObject:(id)object {
    @synchronized (self) {
        if (object) {
            [self hookAddObject:object];
        } else {
            SFAssert(NO, @"NSMutableSet invalid args hookAddObject[%@]", object);
        }
    }
}

- (void) hookRemoveObject:(id)object {
    @synchronized (self) {
        if (object) {
            [self hookRemoveObject:object];
        } else {
            SFAssert(NO, @"NSMutableSet invalid args hookRemoveObject[%@]", object);
        }
    }
}
@end

#pragma mark - NSOrderedSet
@implementation NSOrderedSet (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法 */
        [NSOrderedSet swizzleClassMethod:@selector(orderedSetWithObject:) withMethod:@selector(hookOrderedSetWithObject:)];
        
        /* init方法 */
        swizzleInstanceMethod(NSClassFromString(@"__NSPlaceholderOrderedSet"), @selector(initWithObject:), @selector(hookInitWithObject:));
        
        /* 普通方法 */
        swizzleInstanceMethod(NSClassFromString(@"__NSOrderedSetI"), @selector(objectAtIndex:), @selector(hookObjectAtIndex:));
    });
}
+ (instancetype)hookOrderedSetWithObject:(id)object
{
    if (object) {
        return [self hookOrderedSetWithObject:object];
    }
    SFAssert(NO, @"NSOrderedSet invalid args hookOrderedSetWithObject:[%@]", object);
    return nil;
}
- (instancetype)hookInitWithObject:(id)object
{
    if (object){
        return [self hookInitWithObject:object];
    }
    SFAssert(NO, @"NSOrderedSet invalid args hookInitWithObject:[%@]", object);
    return nil;
}
- (id)hookObjectAtIndex:(NSUInteger)idx
{
    @synchronized (self) {
        if (idx < self.count){
            return [self hookObjectAtIndex:idx];
        }
        return nil;
    }
}
@end

@implementation NSMutableOrderedSet (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 普通方法 */
        NSMutableOrderedSet* obj = [NSMutableOrderedSet orderedSetWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(hookObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(hookAddObject:)];
        [obj swizzleInstanceMethod:@selector(removeObjectAtIndex:) withMethod:@selector(hookRemoveObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(insertObject:atIndex:) withMethod:@selector(hookInsertObject:atIndex:)];
        [obj swizzleInstanceMethod:@selector(replaceObjectAtIndex:withObject:) withMethod:@selector(hookReplaceObjectAtIndex:withObject:)];
    });
}
- (id)hookObjectAtIndex:(NSUInteger)idx
{
    @synchronized (self) {
        if (idx < self.count){
            return [self hookObjectAtIndex:idx];
        }
        return nil;
    }
}
- (void)hookAddObject:(id)object {
    @synchronized (self) {
        if (object) {
            [self hookAddObject:object];
        } else {
            SFAssert(NO, @"NSMutableOrderedSet invalid args hookAddObject:[%@]", object);
        }
    }
}
- (void)hookInsertObject:(id)object atIndex:(NSUInteger)idx
{
    @synchronized (self) {
        if (object && idx <= self.count) {
            [self hookInsertObject:object atIndex:idx];
        }else{
            SFAssert(NO, @"NSMutableOrderedSet invalid args hookInsertObject:[%@] atIndex:[%@]", object, @(idx));
        }
    }
}
- (void)hookRemoveObjectAtIndex:(NSUInteger)idx
{
    @synchronized (self) {
        if (idx < self.count){
            [self hookRemoveObjectAtIndex:idx];
        }else{
            SFAssert(NO, @"NSMutableOrderedSet invalid args hookRemoveObjectAtIndex:[%@]", @(idx));
        }
    }
}
- (void)hookReplaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    @synchronized (self) {
        if (object && idx < self.count) {
            [self hookReplaceObjectAtIndex:idx withObject:object];
        }else{
            SFAssert(NO, @"NSMutableOrderedSet invalid args hookReplaceObjectAtIndex:[%@] withObject:[%@]", @(idx), object);
        }
    }
}
@end

#pragma mark - NSUserDefaults
@implementation NSUserDefaults(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod(NSClassFromString(@"NSUserDefaults"), @selector(objectForKey:), @selector(hookObjectForKey:));
        swizzleInstanceMethod(NSClassFromString(@"NSUserDefaults"), @selector(setObject:forKey:), @selector(hookSetObject:forKey:));
        swizzleInstanceMethod(NSClassFromString(@"NSUserDefaults"), @selector(removeObjectForKey:), @selector(hookRemoveObjectForKey:));
    });
}
- (id) hookObjectForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self hookObjectForKey:defaultName];
    }
    return nil;
}

- (void) hookSetObject:(id)value forKey:(NSString*)aKey
{
    if (aKey) {
        [self hookSetObject:value forKey:aKey];
    } else {
        SFAssert(NO, @"NSUserDefaults invalid args hookSetObject:[%@] forKey:[%@]", value, aKey);
    }
}
- (void) hookRemoveObjectForKey:(NSString*)aKey
{
    if (aKey) {
        [self hookRemoveObjectForKey:aKey];
    } else {
        SFAssert(NO, @"NSUserDefaults invalid args hookRemoveObjectForKey:[%@]", aKey);
    }
}

@end

#pragma mark - NSCache

@implementation NSCache(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzleInstanceMethod([NSCache class], @selector(setObject:forKey:), @selector(hookSetObject:forKey:));
        swizzleInstanceMethod([NSCache class], @selector(setObject:forKey:cost:), @selector(hookSetObject:forKey:cost:));
    });
}
- (void)hookSetObject:(id)obj forKey:(id)key // 0 cost
{
    if (obj && key) {
        [self hookSetObject:obj forKey:key];
    }else {
        SFAssert(NO, @"NSCache invalid args hookSetObject:[%@] forKey:[%@]", obj, key);
    }
}
- (void)hookSetObject:(id)obj forKey:(id)key cost:(NSUInteger)g
{
    if (obj && key) {
        [self hookSetObject:obj forKey:key cost:g];
    }else {
        SFAssert(NO, @"NSCache invalid args hookSetObject:[%@] forKey:[%@] cost:[%@]", obj, key, @(g));
    }
}
@end
