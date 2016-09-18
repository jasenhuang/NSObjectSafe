//
//  NSObjectSafeTests.m
//  NSObjectSafeTests
//
//  Created by jasenhuang on 15/12/29.
//  Copyright © 2015年 tencent. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSObjectSafe.h"

@interface NSObjectSafeTests : XCTestCase

@end

@implementation NSObjectSafeTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
    
    NSArray* array = [NSArray arrayWithObjects:nil];//__NSArray0
    [array objectAtIndex:4];
    [array subarrayWithRange:NSMakeRange(2, 2)];
    
    array = [NSArray arrayWithObjects:@1, nil];//__NSSingleObjectArrayI
    [array objectAtIndex:4];
    
    array = [NSArray arrayWithObjects:@1, @2, nil];//__NSArrayI
    [array objectAtIndex:4];
    
    NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:nil];//__NSDictionary0
    [dict objectForKey:nil];
    
    dict = [NSDictionary dictionaryWithObjectsAndKeys:@"a",@"1", nil];//__NSSingleEntryDictionaryI
    [dict objectForKey:nil];
    
    dict = [NSDictionary dictionaryWithObjectsAndKeys:@"a",@"1",@"b",@"2", nil];//__NSDictionaryI
    [dict objectForKey:nil];
    
//    NSString* string = @"12345";
//    [string substringFromIndex:6];
//    [string substringToIndex:6];
//    [string substringWithRange:NSMakeRange(0, 6)];
//
//    NSMutableString* mstring = [NSMutableString string];
//    [mstring appendString:@"12345"];
//    NSLog(@"%@", [mstring substringToIndex:10]);
//    NSLog(@"%@", [mstring substringWithRange:NSMakeRange(3, 10)]);
    
//    NSCache * cache = [[NSCache alloc] init];
//    
//    [cache setObject:nil forKey:@""];
//    [cache setObject:nil forKey:@"" cost:0];

//    id a[] = {@"a",@"b", nil ,@"c"};
//    NSLog(@"%@", [NSMutableArray arrayWithObjects:a count:4]);
    
//    /* NSArray: Syntactic sugar */
//    NSArray* item = nil;
//    NSArray * items = @[@"a",@"b", item ,@"c"];
//    NSLog(@"%@", items);
//    
//    /* NSDictory: Syntactic sugar */
//    NSString* key = nil;
//    NSString* value = nil;
//    NSLog(@"%@", @{@"b":@"c",key:value, @"e":value});
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end
