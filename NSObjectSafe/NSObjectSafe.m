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
    NSLog(@"%s|%s|%d|%@", file, func, line, [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

@implementation NSObject(Swizzle)
+ (void)swizzleClassMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    Class class = [self class];
    
    Method originalMethod = class_getClassMethod(class, origSelector);
    Method swizzledMethod = class_getClassMethod(class, newSelector);
    
    Class metacls = objc_getMetaClass(NSStringFromClass(class).UTF8String);
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
    Class class = [self class];
    
    Method originalMethod = class_getInstanceMethod(class, origSelector);
    Method swizzledMethod = class_getInstanceMethod(class, newSelector);
    
    if (class_addMethod(class,
                        origSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod)) ) {
        /*swizzing super class instance method, added if not exist */
        class_replaceMethod(class,
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
        [obj swizzleInstanceMethod:@selector(addObserver:forKeyPath:options:context:) withMethod:@selector(safeAddObserver:forKeyPath:options:context:)];
        [obj swizzleInstanceMethod:@selector(removeObserver:forKeyPath:) withMethod:@selector(safeRemoveObserver:forKeyPath:)];
    });
}
- (void) safeAddObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context
{
    if (!observer || !keyPath.length) {
        SFAssert(NO, @"safeAddObserver invalid args: %@", self);
        return;
    }
    @try {
        [self safeAddObserver:observer forKeyPath:keyPath options:options context:context];
    }
    @catch (NSException *exception) {
        NSLog(@"safeAddObserver ex: %@", [exception callStackSymbols]);
    }
}
- (void) safeRemoveObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
{
    if (!observer || !keyPath.length) {
        SFAssert(NO, @"safeRemoveObserver invalid args: %@", self);
        return;
    }
    @try {
        [self safeRemoveObserver:observer forKeyPath:keyPath];
    }
    @catch (NSException *exception) {
        NSLog(@"safeRemoveObserver ex: %@", [exception callStackSymbols]);
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
        [NSString swizzleClassMethod:@selector(stringWithUTF8String:) withMethod:@selector(safeStringWithUTF8String:)];
        [NSString swizzleClassMethod:@selector(stringWithCString:encoding:) withMethod:@selector(safeStringWithCString:encoding:)];
        
        /* init方法 */
        NSString* obj = [NSString alloc];//NSPlaceholderString
        [obj swizzleInstanceMethod:@selector(initWithCString:encoding:) withMethod:@selector(safeInitWithCString:encoding:)];
        
        /* 普通方法 */
        obj = [[NSString alloc] init];
        [obj swizzleInstanceMethod:@selector(stringByAppendingString:) withMethod:@selector(safeStringByAppendingString:)];
    });
}
+ (NSString*) safeStringWithUTF8String:(const char *)nullTerminatedCString
{
    if (NULL != nullTerminatedCString) {
        return [NSString safeStringWithUTF8String:nullTerminatedCString];
    }
    SFAssert(NO, @"NSString invalid args safeStringWithUTF8String nil cstring");
    return nil;
}
+ (nullable instancetype) safeStringWithCString:(const char *)cString encoding:(NSStringEncoding)enc
{
    if (NULL != cString){
        return [self safeStringWithCString:cString encoding:enc];
    }
    SFAssert(NO, @"NSString invalid args safeStringWithCString nil cstring");
    return nil;
}
- (nullable instancetype) safeInitWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding
{
    if (NULL != nullTerminatedCString){
        return [self safeInitWithCString:nullTerminatedCString encoding:encoding];
    }
    SFAssert(NO, @"NSString invalid args safeInitWithCString nil cstring");
    return nil;
}
- (NSString *)safeStringByAppendingString:(NSString *)aString
{
    if (aString){
        return [self safeStringByAppendingString:aString];
    }
    return self;
}

@end

@implementation NSMutableString (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        /* init方法 */
        NSMutableString* obj = [NSMutableString alloc];//NSPlaceholderMutableString
        [obj swizzleInstanceMethod:@selector(initWithCString:encoding:) withMethod:@selector(safeInitWithCString:encoding:)];
        
        /* 普通方法 */
        obj = [[NSMutableString alloc] init];
        [obj swizzleInstanceMethod:@selector(appendString:) withMethod:@selector(safeAppendString:)];
        [obj swizzleInstanceMethod:@selector(insertString:atIndex:) withMethod:@selector(safeInsertString:atIndex:)];
        [obj swizzleInstanceMethod:@selector(deleteCharactersInRange:) withMethod:@selector(safeDeleteCharactersInRange:)];
        [obj swizzleInstanceMethod:@selector(stringByAppendingString:) withMethod:@selector(safeStringByAppendingString:)];
    });
}
- (nullable instancetype) safeInitWithCString:(const char *)nullTerminatedCString encoding:(NSStringEncoding)encoding
{
    if (NULL != nullTerminatedCString){
        return [self safeInitWithCString:nullTerminatedCString encoding:encoding];
    }
    SFAssert(NO, @"NSMutableString invalid args safeInitWithCString nil cstring");
    return nil;
}
- (void) safeAppendString:(NSString *)aString
{
    if (aString){
        [self safeAppendString:aString];
    }else{
        SFAssert(NO, @"NSMutableString invalid args safeAppendString:[%@]", aString);
    }
}
- (void) safeInsertString:(NSString *)aString atIndex:(NSUInteger)loc
{
    if (aString && loc <= self.length) {
        [self safeInsertString:aString atIndex:loc];
    }else{
        SFAssert(NO, @"NSMutableString invalid args safeInsertString:[%@] atIndex:[%@]", aString, @(loc));
    }
}
- (void) safeDeleteCharactersInRange:(NSRange)range
{
    if (range.location < self.length && range.location + range.length < self.length){
        [self safeDeleteCharactersInRange:range];
    }else{
        SFAssert(NO, @"NSMutableString invalid args safeDeleteCharactersInRange:[%@]", NSStringFromRange(range));
    }
}
- (NSString *)safeStringByAppendingString:(NSString *)aString
{
    if (aString){
        return [self safeStringByAppendingString:aString];
    }
    return self;
}
@end

#pragma mark - NSArray
@implementation NSArray (Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        /* 类方法不用在NSMutableArray里再swizz一次 */
        [NSArray swizzleClassMethod:@selector(arrayWithObject:) withMethod:@selector(safeArrayWithObject:)];
        
        /* 数组有内容obj类型才是__NSArrayI */
        NSArray* obj = [[NSArray alloc] initWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(safeObjectAtIndex:)];
        
        /* 没内容类型是__NSArray0 */
        obj = [[NSArray alloc] init];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(safeObjectAtIndex0:)];
    });
}
+ (instancetype) safeArrayWithObject:(id)anObject
{
    if (anObject) {
        return [self safeArrayWithObject:anObject];
    }
    SFAssert(NO, @"NSArray invalid args safeArrayWithObject:[%@]", anObject);
    return nil;
}
/* __NSArray0 没有元素，也不可以变 */
- (id) safeObjectAtIndex0:(NSUInteger)index {
    return nil;
}
- (id) safeObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        return [self safeObjectAtIndex:index];
    }
    return nil;
}
@end

@implementation NSMutableArray(Safe)
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray* obj = [[NSMutableArray alloc] init];
        //对象方法 __NSArrayM 和 __NSArrayI 都有实现，都要swizz
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(safeObjectAtIndex:)];
        
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(safeAddObject:)];
        [obj swizzleInstanceMethod:@selector(insertObject:atIndex:) withMethod:@selector(safeInsertObject:atIndex:)];
        [obj swizzleInstanceMethod:@selector(removeObjectAtIndex:) withMethod:@selector(safeRemoveObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(replaceObjectAtIndex:withObject:) withMethod:@selector(safeReplaceObjectAtIndex:withObject:)];
        [obj swizzleInstanceMethod:@selector(removeObjectsInRange:) withMethod:@selector(safeRemoveObjectsInRange:)];
    });
}
- (void) safeAddObject:(id)anObject {
    if (anObject) {
        [self safeAddObject:anObject];
    } else {
        SFAssert(NO, @"NSMutableArray invalid args safeAddObject:[%@]", anObject);
    }
}
- (id) safeObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        return [self safeObjectAtIndex:index];
    }
    return nil;
}
- (void) safeInsertObject:(id)anObject atIndex:(NSUInteger)index {
    if (anObject && index <= self.count) {
        [self safeInsertObject:anObject atIndex:index];
    } else {
        if (!anObject) {
            SFAssert(NO, @"NSMutableArray invalid args safeInsertObject:[%@] atIndex:[%@]", anObject, @(index));
        }
        if (index > self.count) {
            SFAssert(NO, @"NSMutableArray safeInsertObject[%@] atIndex:[%@] out of bound:[%@]", anObject, @(index), @(self.count));
        }
    }
}

- (void) safeRemoveObjectAtIndex:(NSUInteger)index {
    if (index < self.count) {
        [self safeRemoveObjectAtIndex:index];
    } else {
        SFAssert(NO, @"NSMutableArray safeRemoveObjectAtIndex:[%@] out of bound:[%@]", @(index), @(self.count));
    }
}


- (void) safeReplaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    if (index < self.count && anObject) {
        [self safeReplaceObjectAtIndex:index withObject:anObject];
    } else {
        if (!anObject) {
            SFAssert(NO, @"NSMutableArray invalid args safeReplaceObjectAtIndex:[%@] withObject:[%@]", @(index), anObject);
        }
        if (index >= self.count) {
            SFAssert(NO, @"NSMutableArray safeReplaceObjectAtIndex:[%@] withObject:[%@] out of bound:[%@]", @(index), anObject, @(self.count));
        }
    }
}

- (void) safeRemoveObjectsInRange:(NSRange)range {
    if (range.location < self.count && range.location + range.length < self.count) {
        [self safeRemoveObjectsInRange:range];
    }else {
        SFAssert(NO, @"NSMutableArray invalid args safeRemoveObjectsInRange:[%@]", NSStringFromRange(range));
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
        [NSDictionary swizzleClassMethod:@selector(dictionaryWithObject:forKey:) withMethod:@selector(safeDictionaryWithObject:forKey:)];
        
        /* 数组有内容obj类型才是__NSDictionaryI，没内容类型是__NSDictionary0 */
        NSDictionary* obj = [NSDictionary dictionaryWithObjectsAndKeys:@0,@0,nil];
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(safeObjectForKey:)];
    });
}
+ (instancetype) safeDictionaryWithObject:(id)object forKey:(id)key
{
    if (object && key) {
        return [self safeDictionaryWithObject:object forKey:key];
    }
    SFAssert(NO, @"NSDictionary invalid args safeDictionaryWithObject:[%@] forKey:[%@]", object, key);
    return nil;
}
- (id) safeObjectForKey:(id)aKey
{
    if (aKey){
        return [self safeObjectForKey:aKey];
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
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(safeObjectForKey:)];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:) withMethod:@selector(safeSetObject:forKey:)];
        [obj swizzleInstanceMethod:@selector(removeObjectForKey:) withMethod:@selector(safeRemoveObjectForKey:)];
    });
}
- (id) safeObjectForKey:(id)aKey
{
    if (aKey){
        return [self safeObjectForKey:aKey];
    }
    return nil;
}
- (void) safeSetObject:(id)anObject forKey:(id)aKey {
    if (anObject && aKey) {
        [self safeSetObject:anObject forKey:aKey];
    } else {
        SFAssert(NO, @"NSMutableDictionary invalid args safeSetObject:[%@] forKey:[%@]", anObject, aKey);
    }
}

- (void) safeRemoveObjectForKey:(id)aKey {
    if (aKey) {
        [self safeRemoveObjectForKey:aKey];
    } else {
        SFAssert(NO, @"NSMutableDictionary invalid args safeRemoveObjectForKey:[%@]", aKey);
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
        [NSSet swizzleClassMethod:@selector(setWithObject:) withMethod:@selector(safeSetWithObject:)];
    });
}
+ (instancetype)safeSetWithObject:(id)object
{
    if (object){
        return [self safeSetWithObject:object];
    }
    SFAssert(NO, @"NSSet invalid args safeSetWithObject:[%@]", object);
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
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(safeAddObject:)];
        [obj swizzleInstanceMethod:@selector(removeObject:) withMethod:@selector(safeRemoveObject:)];
    });
}
- (void) safeAddObject:(id)object {
    if (object) {
        [self safeAddObject:object];
    } else {
        SFAssert(NO, @"NSMutableSet invalid args safeAddObject[%@]", object);
    }
}

- (void) safeRemoveObject:(id)object {
    if (object) {
        [self safeRemoveObject:object];
    } else {
        SFAssert(NO, @"NSMutableSet invalid args safeRemoveObject[%@]", object);
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
        [NSOrderedSet swizzleClassMethod:@selector(orderedSetWithObject:) withMethod:@selector(safeOrderedSetWithObject:)];
        
        /* init方法:[NSOrderedSet alloc] 和 [NSMutableOrderedSet alloc] 返回的类是一样   */
        NSOrderedSet* obj = [NSOrderedSet alloc];
        [obj swizzleInstanceMethod:@selector(initWithObject:) withMethod:@selector(safeInitWithObject:)];
        
        /* 普通方法 */
        obj = [NSOrderedSet orderedSetWithObjects:@0, nil];
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(safeObjectAtIndex:)];
    });
}
+ (instancetype)safeOrderedSetWithObject:(id)object
{
    if (object) {
        return [self safeOrderedSetWithObject:object];
    }
    SFAssert(NO, @"NSOrderedSet invalid args safeOrderedSetWithObject:[%@]", object);
    return nil;
}
- (instancetype)safeInitWithObject:(id)object
{
    if (object){
        return [self safeInitWithObject:object];
    }
    SFAssert(NO, @"NSOrderedSet invalid args safeInitWithObject:[%@]", object);
    return nil;
}
- (id)safeObjectAtIndex:(NSUInteger)idx
{
    if (idx < self.count){
        return [self safeObjectAtIndex:idx];
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
        [obj swizzleInstanceMethod:@selector(objectAtIndex:) withMethod:@selector(safeObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(addObject:) withMethod:@selector(safeAddObject:)];
        [obj swizzleInstanceMethod:@selector(removeObjectAtIndex:) withMethod:@selector(safeRemoveObjectAtIndex:)];
        [obj swizzleInstanceMethod:@selector(insertObject:atIndex:) withMethod:@selector(safeInsertObject:atIndex:)];
        [obj swizzleInstanceMethod:@selector(replaceObjectAtIndex:withObject:) withMethod:@selector(safeReplaceObjectAtIndex:withObject:)];
    });
}
- (id)safeObjectAtIndex:(NSUInteger)idx
{
    if (idx < self.count){
        return [self safeObjectAtIndex:idx];
    }
    return nil;
}
- (void)safeAddObject:(id)object {
    if (object) {
        [self safeAddObject:object];
    } else {
        SFAssert(NO, @"NSMutableOrderedSet invalid args safeAddObject:[%@]", object);
    }
}
- (void)safeInsertObject:(id)object atIndex:(NSUInteger)idx
{
    if (object && idx <= self.count) {
        [self safeInsertObject:object atIndex:idx];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args safeInsertObject:[%@] atIndex:[%@]", object, @(idx));
    }
}
- (void)safeRemoveObjectAtIndex:(NSUInteger)idx
{
    if (idx < self.count){
        [self safeRemoveObjectAtIndex:idx];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args safeRemoveObjectAtIndex:[%@]", @(idx));
    }
}
- (void)safeReplaceObjectAtIndex:(NSUInteger)idx withObject:(id)object
{
    if (object && idx < self.count) {
        [self safeReplaceObjectAtIndex:idx withObject:object];
    }else{
        SFAssert(NO, @"NSMutableOrderedSet invalid args safeReplaceObjectAtIndex:[%@] withObject:[%@]", @(idx), object);
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
        [obj swizzleInstanceMethod:@selector(objectForKey:) withMethod:@selector(safeObjectForKey:)];
        [obj swizzleInstanceMethod:@selector(setObject:forKey:) withMethod:@selector(safeSetObject:forKey:)];
        [obj swizzleInstanceMethod:@selector(removeObjectForKey:) withMethod:@selector(safeRemoveObjectForKey:)];
        
        [obj swizzleInstanceMethod:@selector(integerForKey:) withMethod:@selector(safeIntegerForKey:)];
        [obj swizzleInstanceMethod:@selector(boolForKey:) withMethod:@selector(safeBoolForKey:)];
        
    });
}
- (id) safeObjectForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self safeObjectForKey:defaultName];
    }
    return nil;
}

- (NSInteger) safeIntegerForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self safeIntegerForKey:defaultName];
    }
    return 0;
}

- (BOOL) safeBoolForKey:(NSString *)defaultName
{
    if (defaultName) {
        return [self safeBoolForKey:defaultName];
    }
    return NO;
}

- (void) safeSetObject:(id)value forKey:(NSString*)aKey
{
    if (aKey) {
        [self safeSetObject:value forKey:aKey];
    } else {
        SFAssert(NO, @"NSUserDefaults invalid args safeSetObject:[%@] forKey:[%@]", value, aKey);
    }
}
- (void) safeRemoveObjectForKey:(NSString*)aKey
{
    if (aKey) {
        [self safeRemoveObjectForKey:aKey];
    } else {
        SFAssert(NO, @"NSUserDefaults invalid args safeRemoveObjectForKey:[%@]", aKey);
    }
}

@end
