//
//  NSObject+KVC.h
//  Test
//
//  Created by xiefei5 on 2017/10/31.
//  Copyright © 2017年 xiefei5. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (KVC)

@property (class, readonly) BOOL xf_accessInstanceVariablesDirectly;

- (id)xf_valueForKey:(NSString *)key;
- (void)xf_setValue:(id)value forKey:(NSString *)key;

//- (BOOL)xf_validateValue:(id)ioValue forKey:(NSString *)inKey error:(NSError **)outError;
//- (BOOL)xf_validateValue:(id)ioValue forKeyPath:(NSString *)inKeyPath error:(NSError **)outError;
//
//- (id)xf_valueForKeyPath:(NSString *)keyPath;
//- (void)xf_setValue:(id)value forKeyPath:(NSString *)keyPath;
//
- (id)xf_valueForUndefinedKey:(NSString *)key;
- (void)xf_setValue:(id)value forUndefinedKey:(NSString *)key;

- (void)xf_setNilValueForKey:(NSString *)key;

@end
