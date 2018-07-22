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
#error This file must be compiled with MRR. Use -fno-objc-arc flag.
#endif

NSString *const NSSafeSuffix = @"_NSSafe_";
NSString *const NSSafeNotification = @"_NSSafeNotification_";

void (^safeAssertCallback)(const char *, int, NSString *, ...);

#define SFAssert(condition, ...) \
if (!(condition)){ SFLog(__FILE__, __FUNCTION__, __LINE__, __VA_ARGS__); \
if (safeAssertCallback) safeAssertCallback(__FUNCTION__, __LINE__, __VA_ARGS__);} \
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

+ (void)setSafeAssertCallback:(void (^)(const char *, int, NSString *, ...))callback {
    safeAssertCallback = [callback copy];
}
@end

@implementation NSObject(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSObject* obj = [[NSObject alloc] init];
        [obj swizzleInstanceMethod:@selector(addObserver:forKeyPath:options:context:) withMethod:@selector(hookAddObserver:forKeyPath:options:context:)];
        [obj swizzleInstanceMethod:@selector(removeObserver:forKeyPath:) withMethod:@selector(hookRemoveObserver:forKeyPath:)];
        [obj swizzleInstanceMethod:@selector(methodSignatureForSelector:) withMethod:@selector(hookMethodSignatureForSelector:)];
        [obj swizzleInstanceMethod:@selector(forwardInvocation:) withMethod:@selector(hookForwardInvocation:)];
        [obj release];
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
    [[NSSafeProxy new] dealException:info];
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
        NSString* obj = [NSString alloc];//NSPlaceholderString
        [obj swizzleInstanceMethod:@selector(initWithCString:encoding:) withMethod:@selector(hookInitWithCString:encoding:)];
        [obj release];
        
        /* _NSCFConstantString */
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringFromIndex:), @selector(hookSubstringFromIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringToIndex:), @selector(hookSubstringToIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(substringWithRange:), @selector(hookSubstringWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFConstantString"), @selector(rangeOfString:options:range:locale:), @selector(hookRangeOfString:options:range:locale:));
        
        /* NSTaggedPointerString */
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
    if (aString){
        return [self hookStringByAppendingString:aString];
    }
    return self;
}
- (NSString *)hookSubstringFromIndex:(NSUInteger)from
{
    if (from <= self.length) {
        return [self hookSubstringFromIndex:from];
    }
    return nil;
}
- (NSString *)hookSubstringToIndex:(NSUInteger)to
{
    if (to <= self.length) {
        return [self hookSubstringToIndex:to];
    }
    return self;
}
- (NSString *)hookSubstringWithRange:(NSRange)range
{
    if (range.location + range.length <= self.length) {
        return [self hookSubstringWithRange:range];
    }else if (range.location < self.length){
        return [self hookSubstringWithRange:NSMakeRange(range.location, self.length-range.location)];
    }
    return nil;
}
- (NSRange)hookRangeOfString:(NSString *)searchString options:(NSStringCompareOptions)mask range:(NSRange)range locale:(nullable NSLocale *)locale
{
    if (searchString){
        if (range.location + range.length <= self.length) {
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
@end

@implementation NSMutableString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        NSMutableString* obj = [NSMutableString alloc];//NSPlaceholderMutableString
        [obj swizzleInstanceMethod:@selector(initWithCString:encoding:) withMethod:@selector(hookInitWithCString:encoding:)];
        [obj release];
        
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(appendString:), @selector(hookAppendString:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(insertString:atIndex:), @selector(hookInsertString:atIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(deleteCharactersInRange:), @selector(hookDeleteCharactersInRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringFromIndex:), @selector(hookSubstringFromIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringToIndex:), @selector(hookSubstringToIndex:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(substringWithRange:), @selector(hookSubstringWithRange:));
        swizzleInstanceMethod(NSClassFromString(@"__NSCFString"), @selector(rangeOfString:options:range:locale:), @selector(hookRangeOfString:options:range:locale:));
    });
    
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
    if (aString){
        [self hookAppendString:aString];
    }else{
        SFAssert(NO, @"NSMutableString invalid args hookAppendString:[%@]", aString);
    }
}
- (void) hookInsertString:(NSString *)aString atIndex:(NSUInteger)loc
{
    if (aString && loc <= self.length) {
        [self hookInsertString:aString atIndex:loc];
    }else{
        SFAssert(NO, @"NSMutableString invalid args hookInsertString:[%@] atIndex:[%@]", aString, @(loc));
    }
}
- (void) hookDeleteCharactersInRange:(NSRange)range
{
    if (range.location + range.length <= self.length){
        [self hookDeleteCharactersInRange:range];
    }else{
        SFAssert(NO, @"NSMutableString invalid args hookDeleteCharactersInRange:[%@]", NSStringFromRange(range));
    }
}
- (NSString *)hookStringByAppendingString:(NSString *)aString
{
    if (aString){
        return [self hookStringByAppendingString:aString];
    }
    return self;
}
- (NSString *)hookSubstringFromIndex:(NSUInteger)from
{
    if (from <= self.length) {
        return [self hookSubstringFromIndex:from];
    }
    return nil;
}
- (NSString *)hookSubstringToIndex:(NSUInteger)to
{
    if (to <= self.length) {
        return [self hookSubstringToIndex:to];
    }
    return self;
}
- (NSString *)hookSubstringWithRange:(NSRange)range
{
    if (range.location + range.length <= self.length) {
        return [self hookSubstringWithRange:range];
    }else if (range.location < self.length){
        return [self hookSubstringWithRange:NSMakeRange(range.location, self.length-range.location)];
    }
    return nil;
}
@end

#pragma mark - NSAttributedString
@implementation NSAttributedString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        NSAttributedString* obj = [NSAttributedString alloc];
        [obj swizzleInstanceMethod:@selector(initWithString:) withMethod:@selector(hookInitWithString:)];
        [obj release];
        
        /* 普通方法 */
        obj = [[NSAttributedString alloc] init];
        [obj swizzleInstanceMethod:@selector(attributedSubstringFromRange:) withMethod:@selector(hookAttributedSubstringFromRange:)];
        [obj swizzleInstanceMethod:@selector(attribute:atIndex:effectiveRange:) withMethod:@selector(hookAttribute:atIndex:effectiveRange:)];
        [obj swizzleInstanceMethod:@selector(enumerateAttribute:inRange:options:usingBlock:) withMethod:@selector(hookEnumerateAttribute:inRange:options:usingBlock:)];
        [obj swizzleInstanceMethod:@selector(enumerateAttributesInRange:options:usingBlock:) withMethod:@selector(hookEnumerateAttributesInRange:options:usingBlock:)];
        [obj release];
    });
}
- (id)hookInitWithString:(NSString*)str {
    if (str){
        return [self hookInitWithString:str];
    }
    return nil;
}
- (id)hookAttribute:(NSAttributedStringKey)attrName atIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range
{
    if (location < self.length){
        return [self hookAttribute:attrName atIndex:location effectiveRange:range];
    }else{
        return nil;
    }
}
- (NSAttributedString *)hookAttributedSubstringFromRange:(NSRange)range {
    if (range.location + range.length <= self.length) {
        return [self hookAttributedSubstringFromRange:range];
    }else if (range.location < self.length){
        return [self hookAttributedSubstringFromRange:NSMakeRange(range.location, self.length-range.location)];
    }
    return nil;
}
- (void)hookEnumerateAttribute:(NSString *)attrName inRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(id _Nullable, NSRange, BOOL * _Nonnull))block
{
    if (range.location + range.length <= self.length) {
        [self hookEnumerateAttribute:attrName inRange:range options:opts usingBlock:block];
    }else if (range.location < self.length){
        [self hookEnumerateAttribute:attrName inRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
    }
}
- (void)hookEnumerateAttributesInRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(NSDictionary<NSString*,id> * _Nonnull, NSRange, BOOL * _Nonnull))block
{
    if (range.location + range.length <= self.length) {
        [self hookEnumerateAttributesInRange:range options:opts usingBlock:block];
    }else if (range.location < self.length){
        [self hookEnumerateAttributesInRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
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
        NSMutableAttributedString* obj = [NSMutableAttributedString alloc];
        [obj swizzleInstanceMethod:@selector(initWithString:) withMethod:@selector(hookInitWithString:)];
        [obj swizzleInstanceMethod:@selector(initWithString:attributes:) withMethod:@selector(hookInitWithString:attributes:)];
        [obj release];
        
        /* 普通方法 */
        obj = [[NSMutableAttributedString alloc] init];
        [obj swizzleInstanceMethod:@selector(attributedSubstringFromRange:) withMethod:@selector(hookAttributedSubstringFromRange:)];
        [obj swizzleInstanceMethod:@selector(attribute:atIndex:effectiveRange:) withMethod:@selector(hookAttribute:atIndex:effectiveRange:)];
        [obj swizzleInstanceMethod:@selector(addAttribute:value:range:) withMethod:@selector(hookAddAttribute:value:range:)];
        [obj swizzleInstanceMethod:@selector(addAttributes:range:) withMethod:@selector(hookAddAttributes:range:)];
        [obj swizzleInstanceMethod:@selector(setAttributes:range:) withMethod:@selector(hookSetAttributes:range:)];
        [obj swizzleInstanceMethod:@selector(removeAttribute:range:) withMethod:@selector(hookRemoveAttribute:range:)];
        [obj swizzleInstanceMethod:@selector(deleteCharactersInRange:) withMethod:@selector(hookDeleteCharactersInRange:)];
        [obj swizzleInstanceMethod:@selector(replaceCharactersInRange:withString:) withMethod:@selector(hookReplaceCharactersInRange:withString:)];
        [obj swizzleInstanceMethod:@selector(replaceCharactersInRange:withAttributedString:) withMethod:@selector(hookReplaceCharactersInRange:withAttributedString:)];
        [obj swizzleInstanceMethod:@selector(enumerateAttribute:inRange:options:usingBlock:) withMethod:@selector(hookEnumerateAttribute:inRange:options:usingBlock:)];
        [obj swizzleInstanceMethod:@selector(enumerateAttributesInRange:options:usingBlock:) withMethod:@selector(hookEnumerateAttributesInRange:options:usingBlock:)];
        [obj release];
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
    if (range.location + range.length <= self.length) {
        return [self hookAttributedSubstringFromRange:range];
    }else if (range.location < self.length){
        return [self hookAttributedSubstringFromRange:NSMakeRange(range.location, self.length-range.location)];
    }
    return nil;
}
- (id)hookAttribute:(NSAttributedStringKey)attrName atIndex:(NSUInteger)location effectiveRange:(nullable NSRangePointer)range
{
    if (location < self.length){
        return [self hookAttribute:attrName atIndex:location effectiveRange:range];
    }else{
        return nil;
    }
}
- (void)hookAddAttribute:(id)name value:(id)value range:(NSRange)range {
    if (!range.length) {
        [self hookAddAttribute:name value:value range:range];
    }else if (value){
        if (range.location + range.length <= self.length) {
            [self hookAddAttribute:name value:value range:range];
        }else if (range.location < self.length){
            [self hookAddAttribute:name value:value range:NSMakeRange(range.location, self.length-range.location)];
        }
    }else {
        SFAssert(NO, @"hookAddAttribute:value:range: value is nil");
    }
}
- (void)hookAddAttributes:(NSDictionary<NSString *,id> *)attrs range:(NSRange)range {
    if (!range.length) {
        [self hookAddAttributes:attrs range:range];
    }else if (attrs){
        if (range.location + range.length <= self.length) {
            [self hookAddAttributes:attrs range:range];
        }else if (range.location < self.length){
            [self hookAddAttributes:attrs range:NSMakeRange(range.location, self.length-range.location)];
        }
    }else{
        SFAssert(NO, @"hookAddAttributes:range: attrs is nil");
    }
}
- (void)hookSetAttributes:(NSDictionary<NSString *,id> *)attrs range:(NSRange)range {
    if (!range.length) {
        [self hookSetAttributes:attrs range:range];
    }else if (attrs){
        if (range.location + range.length <= self.length) {
            [self hookSetAttributes:attrs range:range];
        }else if (range.location < self.length){
            [self hookSetAttributes:attrs range:NSMakeRange(range.location, self.length-range.location)];
        }
    }else{
        SFAssert(NO, @"hookSetAttributes:range:  attrs is nil");
    }
    
}
- (void)hookRemoveAttribute:(id)name range:(NSRange)range {
    if (!range.length) {
        [self hookRemoveAttribute:name range:range];
    }else if (name){
        if (range.location + range.length <= self.length) {
            [self hookRemoveAttribute:name range:range];
        }else if (range.location < self.length) {
            [self hookRemoveAttribute:name range:NSMakeRange(range.location, self.length-range.location)];
        }
    }else{
        SFAssert(NO, @"hookRemoveAttribute:range:  name is nil");
    }
    
}
- (void)hookDeleteCharactersInRange:(NSRange)range {
    if (range.location + range.length <= self.length) {
        [self hookDeleteCharactersInRange:range];
    }else if (range.location < self.length) {
        [self hookDeleteCharactersInRange:NSMakeRange(range.location, self.length-range.location)];
    }
}
- (void)hookReplaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    if (str){
        if (range.location + range.length <= self.length) {
            [self hookReplaceCharactersInRange:range withString:str];
        }else if (range.location < self.length) {
            [self hookReplaceCharactersInRange:NSMakeRange(range.location, self.length-range.location) withString:str];
        }
    }else{
        SFAssert(NO, @"hookReplaceCharactersInRange:withString:  str is nil");
    }
}
- (void)hookReplaceCharactersInRange:(NSRange)range withAttributedString:(NSString *)str {
    if (str){
        if (range.location + range.length <= self.length) {
            [self hookReplaceCharactersInRange:range withAttributedString:str];
        }else if (range.location < self.length) {
            [self hookReplaceCharactersInRange:NSMakeRange(range.location, self.length-range.location) withAttributedString:str];
        }
    }else{
        SFAssert(NO, @"hookReplaceCharactersInRange:withString:  str is nil");
    }
}
- (void)hookEnumerateAttribute:(NSString*)attrName inRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(id _Nullable, NSRange, BOOL * _Nonnull))block
{
    if (range.location + range.length <= self.length) {
        [self hookEnumerateAttribute:attrName inRange:range options:opts usingBlock:block];
    }else if (range.location < self.length){
        [self hookEnumerateAttribute:attrName inRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
    }
}
- (void)hookEnumerateAttributesInRange:(NSRange)range options:(NSAttributedStringEnumerationOptions)opts usingBlock:(void (^)(NSDictionary<NSString*,id> * _Nonnull, NSRange, BOOL * _Nonnull))block
{
    if (range.location + range.length <= self.length) {
        [self hookEnumerateAttributesInRange:range options:opts usingBlock:block];
    }else if (range.location < self.length){
        [self hookEnumerateAttributesInRange:NSMakeRange(range.location, self.length-range.location) options:opts usingBlock:block];
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
/* __NSArray0 没有元素，也不可以变 */
- (id) hookObjectAtIndex0:(NSUInteger)index {
    SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
    return nil;
}
- (id) hookObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        return [self hookObjectAtIndex:index];
    }
    SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
    return nil;
}
- (id) hookObjectAtIndexedSubscript:(NSInteger)index {
    if (index < self.count) {
        return [self hookObjectAtIndexedSubscript:index];
    }
    SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
    return nil;
}
- (NSArray *)hookSubarrayWithRange:(NSRange)range
{
    if (range.location + range.length <= self.count){
        return [self hookSubarrayWithRange:range];
    }else if (range.location < self.count){
        return [self hookSubarrayWithRange:NSMakeRange(range.location, self.count-range.location)];
    }
    return nil;
}
+ (instancetype)hookArrayWithObjects:(const id [])objects count:(NSUInteger)cnt
{
    NSInteger index = 0;
    id objs[cnt];
    for (NSInteger i = 0; i < cnt ; ++i) {
        if (objects[i]) {
            objs[index++] = objects[i];
        }else {
            SFAssert(NO, @"NSArray invalid args hookArrayWithObjects:[%@] atIndex:[%@]", objects[i], @(i));
        }
    }
    return [self hookArrayWithObjects:objs count:index];
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
    if (anObject) {
        [self hookAddObject:anObject];
    } else {
        SFAssert(NO, @"NSMutableArray invalid args hookAddObject:[%@]", anObject);
    }
}
- (id) hookObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        return [self hookObjectAtIndex:index];
    }
    SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
    return nil;
}
- (id) hookObjectAtIndexedSubscript:(NSInteger)index {
    if (index < self.count) {
        return [self hookObjectAtIndexedSubscript:index];
    }
    SFAssert(NO, @"NSArray invalid index:[%@]", @(index));
    return nil;
}
- (void) hookInsertObject:(id)anObject atIndex:(NSUInteger)index {
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

- (void) hookRemoveObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        [self hookRemoveObjectAtIndex:index];
    } else {
        SFAssert(NO, @"NSMutableArray hookRemoveObjectAtIndex:[%@] out of bound:[%@]", @(index), @(self.count));
    }
}


- (void) hookReplaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
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

- (void) hookRemoveObjectsInRange:(NSRange)range {
    if (range.location + range.length <= self.count) {
        [self hookRemoveObjectsInRange:range];
    }else {
        SFAssert(NO, @"NSMutableArray invalid args hookRemoveObjectsInRange:[%@]", NSStringFromRange(range));
    }
}

- (NSArray *)hookSubarrayWithRange:(NSRange)range
{
    if (range.location + range.length <= self.count){
        return [self hookSubarrayWithRange:range];
    }else if (range.location < self.count){
        return [self hookSubarrayWithRange:NSMakeRange(range.location, self.count-range.location)];
    }
    return nil;
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
    if (range.location + range.length <= self.length){
        return [self hookSubdataWithRange:range];
    }else if (range.location < self.length){
        return [self hookSubdataWithRange:NSMakeRange(range.location, self.length-range.location)];
    }
    return nil;
}

- (NSRange)hookRangeOfData:(NSData *)dataToFind options:(NSDataSearchOptions)mask range:(NSRange)searchRange
{
    if (dataToFind){
        if (searchRange.location + searchRange.length <= self.length) {
            return [self hookRangeOfData:dataToFind options:mask range:searchRange];
        }else if (searchRange.location < self.length){
            return [self hookRangeOfData:dataToFind options:mask range:NSMakeRange(searchRange.location, self.length - searchRange.location) ];
        }
        return NSMakeRange(NSNotFound, 0);
    }else{
        SFAssert(NO, @"hookRangeOfData:options:range: dataToFind is nil");
        return NSMakeRange(NSNotFound, 0);
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
    if (range.location + range.length <= self.length){
        [self hookResetBytesInRange:range];
    }else if (range.location < self.length){
        [self hookResetBytesInRange:NSMakeRange(range.location, self.length-range.location)];
    }
}

- (void)hookReplaceBytesInRange:(NSRange)range withBytes:(const void *)bytes
{
    if (bytes){
        if (range.location < self.length) {
            [self hookReplaceBytesInRange:range withBytes:bytes];
        }else {
            SFAssert(NO, @"hookReplaceBytesInRange:withBytes: range.location error");
        }
    }else{
        SFAssert(NO, @"hookReplaceBytesInRange:withBytes: bytes is nil");
    }
}

- (void)hookReplaceBytesInRange:(NSRange)range withBytes:(const void *)bytes length:(NSUInteger)replacementLength
{
    if (range.location + range.length <= self.length) {
        [self hookReplaceBytesInRange:range withBytes:bytes length:replacementLength];
    }else if (range.location < self.length){
        [self hookReplaceBytesInRange:NSMakeRange(range.location, self.length - range.location) withBytes:bytes length:replacementLength];
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
    if (anObject && aKey) {
        [self hookSetObject:anObject forKey:aKey];
    } else {
        SFAssert(NO, @"NSMutableDictionary invalid args hookSetObject:[%@] forKey:[%@]", anObject, aKey);
    }
}

- (void) hookRemoveObjectForKey:(id)aKey {
    if (aKey) {
        [self hookRemoveObjectForKey:aKey];
    } else {
        SFAssert(NO, @"NSMutableDictionary invalid args hookRemoveObjectForKey:[%@]", aKey);
    }
}

- (void)hookSetObject:(id)obj forKeyedSubscript:(id<NSCopying>)key
{
    if (key){
        [self hookSetObject:obj forKeyedSubscript:key];
    }else {
        SFAssert(NO, @"NSMutableDictionary invalid args hookSetObject:forKeyedSubscript:");
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
    if (object) {
        [self hookAddObject:object];
    } else {
        SFAssert(NO, @"NSMutableSet invalid args hookAddObject[%@]", object);
    }
}

- (void) hookRemoveObject:(id)object {
    if (object) {
        [self hookRemoveObject:object];
    } else {
        SFAssert(NO, @"NSMutableSet invalid args hookRemoveObject[%@]", object);
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
        
        /* init方法:[NSOrderedSet alloc] 和 [NSMutableOrderedSet alloc] 返回的类是一样   */
        NSOrderedSet* obj = [NSOrderedSet alloc];
        [obj swizzleInstanceMethod:@selector(initWithObject:) withMethod:@selector(hookInitWithObject:)];
        [obj release];
        
        /* 普通方法 */
        obj = [NSOrderedSet orderedSetWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(hookObjectAtIndex:)];
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
    if (idx < self.count){
        return [self hookObjectAtIndex:idx];
    }
    return nil;
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
    if (idx < self.count){
        return [self hookObjectAtIndex:idx];
    }
    return nil;
}
- (void)hookAddObject:(id)object {
    if (object) {
        [self hookAddObject:object];
    } else {
        SFAssert(NO, @"NSMutableOrderedSet invalid args hookAddObject:[%@]", object);
    }
}
- (void)hookInsertObject:(id)object atIndex:(NSUInteger)idx
{
    if (object && idx <= self.count) {
        [self hookInsertObject:object atIndex:idx];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args hookInsertObject:[%@] atIndex:[%@]", object, @(idx));
    }
}
- (void)hookRemoveObjectAtIndex:(NSUInteger)idx
{
    if (idx < self.count){
        [self hookRemoveObjectAtIndex:idx];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args hookRemoveObjectAtIndex:[%@]", @(idx));
    }
}
- (void)hookReplaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    if (object && idx < self.count) {
        [self hookReplaceObjectAtIndex:idx withObject:object];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args hookReplaceObjectAtIndex:[%@] withObject:[%@]", @(idx), object);
    }
}
@end

#pragma mark - NSUserDefaults
@implementation NSUserDefaults(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSUserDefaults* obj = [[NSUserDefaults alloc] init];
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(hookObjectForKey:)];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:) withMethod:@selector(hookSetObject:forKey:)];
        [obj swizzleInstanceMethod:@selector(removeObjectForKey:) withMethod:@selector(hookRemoveObjectForKey:)];
        
        [obj swizzleInstanceMethod:@selector(integerForKey:) withMethod:@selector(hookIntegerForKey:)];
        [obj swizzleInstanceMethod:@selector(boolForKey:) withMethod:@selector(hookBoolForKey:)];
        [obj release];
    });
}
- (id) hookObjectForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self hookObjectForKey:defaultName];
    }
    return nil;
}

- (NSInteger) hookIntegerForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self hookIntegerForKey:defaultName];
    }
    return 0;
}

- (BOOL) hookBoolForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self hookBoolForKey:defaultName];
    }
    return NO;
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
        NSCache* obj = [[NSCache alloc] init];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:) withMethod:@selector(hookSetObject:forKey:)];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:cost:) withMethod:@selector(hookSetObject:forKey:cost:)];
        [obj release];
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
