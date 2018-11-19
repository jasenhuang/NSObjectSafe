//
//  NSObjectSafeTests.m
//  NSObjectSafeTests
//
//  Created by jasenhuang on 15/12/29.
//  Copyright © 2015年 tencent. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSObjectSafe.h"
#import <objc/runtime.h>

@interface NSObject(test)
@end

@implementation NSObject(test)
- (void)wrongSwizzleInstanceMethod:(SEL)origSelector withMethod:(SEL)newSelector
{
    Class cls = [self class];
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
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}
+ (void)wrongSwizzleClassMethod:(SEL)origSelector withMethod:(SEL)newSelector
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
@end

@interface Base : NSObject
- (void)print:(NSString*)msg;
@end
@implementation Base
- (void)print:(NSString*)msg
{
    NSLog(@"Base obj %@ print say:%@", NSStringFromClass(self.class), msg);
}
- (void)hookPrint:(NSString*)msg {
    NSLog(@"hook obj %@ print say:%@", NSStringFromClass(self.class), msg);
}
+ (void)printClass:(NSString*)msg
{
    NSLog(@"Base class %@ print say:%@", NSStringFromClass(self.class), msg);
}
+ (void)hookPrintClass:(NSString*)msg {
    NSLog(@"hook class %@ print say:%@", NSStringFromClass(self.class), msg);
}
@end

@interface A : Base
@end
@implementation A
- (void)print:(NSString*)msg {
    NSLog(@"A obj print say:%@", msg);
}
+ (void)printClass:(NSString*)msg {
    NSLog(@"A class print say:%@", msg);
}

@end

@interface B : Base
@end
@implementation B
@end


@interface NSObjectSafeTests : XCTestCase

@end

@implementation NSObjectSafeTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
    [A wrongSwizzleInstanceMethod:@selector(print:) withMethod:@selector(hookPrint:)];
    [B wrongSwizzleInstanceMethod:@selector(print:) withMethod:@selector(hookPrint:)];
    
    
    [A wrongSwizzleClassMethod:@selector(printClass:) withMethod:@selector(hookPrintClass:)];
    [B wrongSwizzleClassMethod:@selector(printClass:) withMethod:@selector(hookPrintClass:)];
    
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.

    A* a = [A new];[a print:@"hello"];
    B* b = [B new];[b print:@"hello"];

    [A printClass:@"hello"];
    [B printClass:@"hello"];
    
    a = [A new];
    [a print:@"hello"];
    
    NSArray* array = @"hello";
    NSLog(@"%@", [array objectAtIndex:1]);
    
    array = [NSArray arrayWithObjects:@1, @2, nil];//__NSArrayI
    [array subarrayWithRange:NSMakeRange(0, 1)];
    
    array = [NSArray arrayWithObjects:nil];//__NSArray0
    [array subarrayWithRange:NSMakeRange(2, 2)];

    array = [NSArray arrayWithObjects:@1, nil];//__NSSingleObjectArrayI
    NSLog(@"%@", array[2]);
    [array objectAtIndex:4];

    array = [NSArray arrayWithObjects:@1, @2, nil];//__NSArrayI
    NSLog(@"%@", array[3]);
    [array objectAtIndex:4];

    NSMutableArray* marray = [NSMutableArray arrayWithObjects:@1, @2, nil];//__NSArrayM
    marray = [marray copy];
    [marray insertObject:@3 atIndex:3];
    NSLog(@"%@", marray[3]);
    [marray removeObjectAtIndex:3];
    
    NSArray* item = nil;
    NSArray * items = @[@"a",@"b", item ,@"c"];

    NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:nil];//__NSDictionary0
    [dict objectForKey:nil];

    dict = [NSDictionary dictionaryWithObjectsAndKeys:@"a",@"1", nil];//__NSSingleEntryDictionaryI
    [dict objectForKey:nil];

    dict = [NSDictionary dictionaryWithObjectsAndKeys:@"a",@"1",@"b",@"2", nil];//__NSDictionaryI
    [dict objectForKey:nil];

    
    NSMutableDictionary* mdict = [[NSMutableDictionary alloc] initWithCapacity:3];
    [mdict setObject:@1 forKey:@1];
    [mdict setObject:nil forKey:@1];
    [mdict setObject:@1 forKey:@1];
    [mdict removeObjectForKey:nil];
    mdict[@1] = nil;
    [NSMutableArray arrayWithArray:[mdict allValues]];
    
    NSString* string = @"12345";
    [string substringFromIndex:6];
    [string substringToIndex:6];
    [string substringWithRange:NSMakeRange(0, 6)];

    string = [NSString stringWithUTF8String:"1"];
    [string substringFromIndex:600];
    [string substringToIndex:600];
    [string substringWithRange:NSMakeRange(100, 6)];

    //__NSCFString
    string = [NSMutableString stringWithUTF8String:"1"];
    [string substringFromIndex:600];
    [string substringToIndex:600];
    [string substringWithRange:NSMakeRange(100, 6)];
    
    NSMutableString* mstring = [NSMutableString string];
    [mstring appendString:@"12345"];
    NSLog(@"%@", [mstring substringToIndex:10]);
    NSLog(@"%@", [mstring substringWithRange:NSMakeRange(3, 10)]);
    
    NSCache * cache = [[NSCache alloc] init];
    
    [cache setObject:nil forKey:@""];
    [cache setObject:nil forKey:@"" cost:0];

    id nilArray[] = {@"a",@"b", nil ,@"c"};
    NSLog(@"%@", [NSMutableArray arrayWithObjects:nilArray count:4]);
    
    /* NSArray: Syntactic sugar */
    NSArray* nilItem = nil;
    NSArray * testItems = @[@"a",@"b", nilItem ,@"c"];
    NSLog(@"%@", testItems);

    /* NSDictory: Syntactic sugar */
    NSString* key = nil;
    NSString* value = nil;
    NSLog(@"%@", @{@"b":@"c",key:value, @"e":value});
    
    NSMutableString* aStr = @"hello";
    [aStr rangeOfString:nil];
    
    NSMutableAttributedString* attr = [[NSMutableAttributedString alloc] initWithString:nil attributes:nil];
    attr = [[NSMutableAttributedString alloc] initWithString:@"hello"];
    [attr addAttribute:@"a" value:@"b" range:NSMakeRange(1, 2)];
    NSRange range;
    NSLog(@"%@", [attr attribute:@"a" atIndex:5 effectiveRange:&range]);
    [attr removeAttribute:@"a" range:NSMakeRange(1, 20)];
    attr = [[NSMutableAttributedString alloc] initWithString:nil attributes:nil];
    attr = [[NSMutableAttributedString alloc] initWithString:@""];
    [attr attributedSubstringFromRange:NSMakeRange(1, 3)];
    
    attr = [[NSMutableAttributedString alloc] initWithString:@"hello" attributes:nil];
    [attr enumerateAttribute:nil inRange:NSMakeRange(0, 20) options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {

    }];
    [attr enumerateAttributesInRange:NSMakeRange(0, 20) options:0 usingBlock:^(NSDictionary<NSString*,id> * _Nonnull attrs, NSRange range, BOOL * _Nonnull stop) {

    }];
    
    [attr attributedSubstringFromRange:NSMakeRange(1000, 1)];
    
    [attr addAttribute:@"a" value:nil range:NSMakeRange(100, 0)];
    [attr addAttributes:@{@"c":@"d"} range:NSMakeRange(1000, 0)];
    [attr removeAttribute:@"a" range:NSMakeRange(1000, 10)];
    [attr setAttributes:nil range:NSMakeRange(100, 0)];
    
    [attr replaceCharactersInRange:NSMakeRange(10, 1) withString:@"a"];
    [attr replaceCharactersInRange:NSMakeRange(10, 1) withAttributedString:@"a"];
    
    [attr deleteCharactersInRange:NSMakeRange(10000, 1)];
    NSLog(@"%@", attr);
    
    NSData* data = [[NSData alloc] initWithData:nil];
    data = [NSData dataWithBytes:NULL length:0];
    [data subdataWithRange:NSMakeRange(1, 10)];
    [data rangeOfData:[@"2" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(1, 10)];
    
    data = [@"123" dataUsingEncoding:NSUTF8StringEncoding];
    [data subdataWithRange:NSMakeRange(1, 10)];
    [data rangeOfData:[@"2" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(1, 10)];

    NSMutableData* mdata = [NSMutableData data];
    [mdata appendData:[@"123" dataUsingEncoding:NSUTF8StringEncoding]];
    [mdata resetBytesInRange:NSMakeRange(10, 10)];
    [mdata replaceBytesInRange:NSMakeRange(0, 10) withBytes:[@"12345" dataUsingEncoding:NSUTF8StringEncoding].bytes length:5];
    [mdata replaceBytesInRange:NSMakeRange(10, 10) withBytes:[@"12345" dataUsingEncoding:NSUTF8StringEncoding].bytes];
    [mdata replaceBytesInRange:NSMakeRange(1, 10) withBytes:NULL];
    SEL s = @selector(objectAtIndex:);
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}
@end
