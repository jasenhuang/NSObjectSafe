//
//  NSMutableArray+Hook.m
//  test
//
//  Created by jasenhuang on 15/12/21.
//  Copyright © 2015年 tencent. All rights reserved.
//

#import "NSObjectSafe.h"
#import <objc/runtime.h>

#define SFAssert(condition, ...) \
if (!(condition)){ SFLog(__FILE__, __FUNCTION__, __LINE__, __VA_ARGS__);} \
NSAssert(condition, @"%@", __VA_ARGS__);

void SFLog(const char* file, const char* func, int line, NSString* fmt, ...)
{
    va_list args; va_start(args, fmt);
    NSLog(@"%s|%s|%d|%@", file, func, line, [[[NSString alloc] initWithFormat:fmt arguments:args] autorelease]);
    va_end(args);
}

@implementation NSObject(Swizzle)
+ (void)swizzleClassMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    Class cls = [self class];
    
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
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}
- (void)swizzleInstanceMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    Class cls = [self class];
    
    Method originalMethod = class_getInstanceMethod(cls, origSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, newSelector);
    
    if (class_addMethod(cls,
                        origSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)) ) {
        /*swizzing super class instance method, added if not exist */
        class_replaceMethod(cls,
                            newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
        
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
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
        
        /* 普通方法 */
        obj = [[NSString alloc] init];
        [obj swizzleInstanceMethod:@selector(stringByAppendingString:) withMethod:@selector(hookStringByAppendingString:)];
        [obj swizzleInstanceMethod:@selector(substringFromIndex:) withMethod:@selector(hookSubstringFromIndex:)];
        [obj swizzleInstanceMethod:@selector(substringToIndex:) withMethod:@selector(hookSubstringToIndex:)];
        [obj swizzleInstanceMethod:@selector(substringWithRange:) withMethod:@selector(hookSubstringWithRange:)];
        [obj release];
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
        
        /* 普通方法 */
        obj = [[NSMutableString alloc] init];
        [obj swizzleInstanceMethod:@selector(appendString:) withMethod:@selector(hookAppendString:)];
        [obj swizzleInstanceMethod:@selector(insertString:atIndex:) withMethod:@selector(hookInsertString:atIndex:)];
        [obj swizzleInstanceMethod:@selector(deleteCharactersInRange:) withMethod:@selector(hookDeleteCharactersInRange:)];
        [obj swizzleInstanceMethod:@selector(stringByAppendingString:) withMethod:@selector(hookStringByAppendingString:)];
        [obj swizzleInstanceMethod:@selector(substringFromIndex:) withMethod:@selector(hookSubstringFromIndex:)];
        [obj swizzleInstanceMethod:@selector(substringToIndex:) withMethod:@selector(hookSubstringToIndex:)];
        [obj swizzleInstanceMethod:@selector(substringWithRange:) withMethod:@selector(hookSubstringWithRange:)];
        [obj release];
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

#pragma mark - NSArray
@implementation NSArray (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法不用在NSMutableArray里再swizz一次 */
        [NSArray swizzleClassMethod:@selector(arrayWithObject:) withMethod:@selector(hookArrayWithObject:)];
        [NSArray swizzleClassMethod:@selector(arrayWithObjects:count:) withMethod:@selector(hookArrayWithObjects:count:)];
        
        /* 数组有内容obj类型才是__NSArrayI */
        NSArray* obj = [[NSArray alloc] initWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(hookObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(subarrayWithRange:) withMethod:@selector(hookSubarrayWithRange:)];
        [obj release];
        
        /* iOS9 以上，没内容类型是__NSArray0 */
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0){
            obj = [[NSArray alloc] init];
            [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(hookObjectAtIndex0:)];
            [obj swizzleInstanceMethod:@selector(subarrayWithRange:) withMethod:@selector(hookSubarrayWithRange:)];
            [obj release];
        }
        
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
    return nil;
}
- (id) hookObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        return [self hookObjectAtIndex:index];
    }
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
        NSMutableArray* obj = [[NSMutableArray alloc] init];
        //对象方法 __NSArrayM 和 __NSArrayI 都有实现，都要swizz
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(hookObjectAtIndex:)];
        
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(hookAddObject:)];
        [obj swizzleInstanceMethod:@selector(insertObject:atIndex:) withMethod:@selector(hookInsertObject:atIndex:)];
        [obj swizzleInstanceMethod:@selector(removeObjectAtIndex:) withMethod:@selector(hookRemoveObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(replaceObjectAtIndex:withObject:) withMethod:@selector(hookReplaceObjectAtIndex:withObject:)];
        [obj swizzleInstanceMethod:@selector(removeObjectsInRange:) withMethod:@selector(hookRemoveObjectsInRange:)];
        [obj swizzleInstanceMethod:@selector(subarrayWithRange:) withMethod:@selector(hookSubarrayWithRange:)];
        
        [obj release];
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
@implementation NSDictionary (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法 */
        [NSDictionary swizzleClassMethod:@selector(dictionaryWithObject:forKey:) withMethod:@selector(hookDictionaryWithObject:forKey:)];
        [NSDictionary swizzleClassMethod:@selector(dictionaryWithObjects:forKeys:count:) withMethod:@selector(hookDictionaryWithObjects:forKeys:count:)];
        
        /* 数组有内容obj类型才是__NSDictionaryI，没内容类型是__NSDictionary0 */
        NSDictionary* obj = [NSDictionary dictionaryWithObjectsAndKeys:@0,@0,nil];
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(hookObjectForKey:)];
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
        } else {
            SFAssert(NO, @"NSDictionary invalid args hookDictionaryWithObject:[%@] forKey:[%@]", objects[i], keys[i]);
        }
    }
    return [self hookDictionaryWithObjects:objs forKeys:ks count:index];
}
- (id) hookObjectForKey:(id)aKey
{
    if (aKey){
        return [self hookObjectForKey:aKey];
    }
    return nil;
}

@end

@implementation NSMutableDictionary (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary* obj = [[NSMutableDictionary alloc] init];
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(hookObjectForKey:)];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:) withMethod:@selector(hookSetObject:forKey:)];
        [obj swizzleInstanceMethod:@selector(removeObjectForKey:) withMethod:@selector(hookRemoveObjectForKey:)];
        [obj release];
    });
}
- (id) hookObjectForKey:(id)aKey
{
    if (aKey){
        return [self hookObjectForKey:aKey];
    }
    return nil;
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
        SFAssert(NO, @"NSCache invalid args hookSetObject:[%@] forKey:[%@] cost:[%@]", obj, key, g);
    }
}
@end
