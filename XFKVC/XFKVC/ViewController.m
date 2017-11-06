//
//  ViewController.m
//  XFKVC
//
//  Created by xiefei5 on 2017/11/3.
//  Copyright © 2017年 xiefei. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+KVC.h"

@interface ViewController ()
//@property (nonatomic, assign) NSInteger age;
//@property (nonatomic,   copy) NSString *name;
@end

@implementation ViewController {
//    NSInteger age;
//    NSInteger _age;
    NSInteger _isAge;
    NSInteger isAge;
    NSString *name;
    
}


- (void)viewDidLoad {
    [super viewDidLoad];
//    age = 10;
//    _age = 11;
    _isAge = 12;
    isAge = 13;
    name = @"hello world!";
    NSLog(@"name:%@-------age:%@",[self xf_valueForKey:@"name"],[self xf_valueForKey:@"age"]);
}



//- (NSInteger)getAge {
//    return 10;
//}

//- (NSInteger)age {
//    return 101;
//}

//- (NSInteger)isAge {
//    return 102;
//}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



@end
