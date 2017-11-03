//
//  NSObject+KVC.m
//  Test
//
//  Created by xiefei5 on 2017/10/31.
//  Copyright © 2017年 xiefei5. All rights reserved.
//

#import "NSObject+KVC.h"
#import <objc/runtime.h>
#import <objc/message.h>

#define SetIvarWithType(type) \
type result; \
[(NSValue *)value getValue:&result]; \
void(* function)(id, Ivar, type) = (void(*)(id, Ivar, type))object_setIvar; \
function(self, ivar, result);

@implementation NSObject (KVC)

+ (BOOL)xf_accessInstanceVariablesDirectly {
    return YES;
}

- (void)xf_setNilValueForKey:(NSString *)key {
    [NSException raise: NSInvalidArgumentException
                format: @"%@ -- %@ 0x%"PRIxPTR": Given nil value to set for key \"%@\"",
     NSStringFromSelector(_cmd), NSStringFromClass([self class]),
     (NSUInteger)self, key];
}

- (id)xf_valueForKey:(NSString *)key {
    return nil;
}

- (void)xf_setValue:(id)value forKey:(NSString *)key {
    if (key == nil || key.length <= 0) {
        [self xf_setValue:nil forUndefinedKey:key];
    }
    Class selfClass = [self class];
    SEL sel = NSSelectorFromString([self assemblySetterMethod:key]);
    Method setterMethod = class_getInstanceMethod(selfClass, sel);
    // 先在对象类查找是否有setter方法
    if (setterMethod) {
        char *argumentType = method_copyArgumentType(setterMethod, 2); // 第一个参数 self ，第二个参数 _cmd
        NSString *type = [NSString stringWithCString:argumentType encoding:NSUTF8StringEncoding];
        if (![type isEqualToString:@"@"]) {  // @An object (whether statically typed or typed id) 表示一个对象
            if (value == nil) {
                [self xf_setNilValueForKey:key];
                return;
            } // 非指针类型方法调用
            [self setterMsgsendWithArgumentType:argumentType sel:sel argument:value];
            return;
        }
        ((void (*)(id,SEL,id))objc_msgSend)(self,sel,value);
    } else {
        // 无setter方法则查找成员变量, _<key>, _is<Key>, <key>, is<Key>
        // 首先判断是否需要寻找成员变量
        if (![self.class xf_accessInstanceVariablesDirectly]) {
            [self xf_setValue:value forUndefinedKey:key];
            return;
        }
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(selfClass, &count);
        // _<key>, _is<Key>, <key>, is<Key>数组
        NSArray<NSString *> *varibleKeys = [self convertKeyToInstanceVariable:key];
        
        for (int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *name = ivar_getName(ivar);
            NSString *ivarName = [NSString stringWithCString:name encoding:NSUTF8StringEncoding];
            
            for (int j = 0; j < varibleKeys.count; j++) {
                if ([ivarName isEqualToString:varibleKeys[j]]) {
                    const char *type = ivar_getTypeEncoding(ivar);
                    if (*type != '@') { // 如果非指针类型而且值还为nil
                        if (value == nil) {
                            free(ivars); ivars = NULL;
                            [self xf_setNilValueForKey:key];
                            return;
                        }
                    }
                    [self setValue:value forIvar:ivar]; // 给变量赋值
                    free(ivars); ivars = NULL; return;
                }
            }
        }
        free(ivars); ivars = NULL;
        [self xf_setValue:value forUndefinedKey:key];
    }
}

- (id)xf_valueForUndefinedKey:(NSString *)key {
    [self xf_setValue:nil forUndefinedKey:key];
    return nil;
}

- (void)xf_setValue:(id)value forUndefinedKey:(NSString *)key {
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
            (value ? (id)value : @"(nil)"), @"NSTargetObjectUserInfoKey",
            (key ? key : @"(nil)"), @"NSUnknownUserInfoKey",
            nil];
    NSException *exception = [NSException exceptionWithName: NSUndefinedKeyException
                                  reason: @"Unable to set value for undefined key"
                                userInfo: dict];
    [exception raise];
}


#pragma mark ---------------------------- PrivateMethod

- (void)setValue:(id)value forIvar:(Ivar)ivar {
    const char *type = ivar_getTypeEncoding(ivar);
    if (strcmp(type, @encode(id)) == 0) {
        object_setIvar(self, ivar, value);
    } else if (strcmp(type, @encode(double)) == 0) {
        SetIvarWithType(double)
    } else if (strcmp(type, @encode(float)) == 0) {
        SetIvarWithType(float)
    } else if (strcmp(type, @encode(int)) == 0) {
        SetIvarWithType(int)
    } else if (strcmp(type, @encode(long)) == 0) {
        SetIvarWithType(long)
    } else if (strcmp(type, @encode(long long)) == 0) {
        SetIvarWithType(long long)
    } else if (strcmp(type, @encode(short)) == 0) {
        SetIvarWithType(short)
    } else if (strcmp(type, @encode(char)) == 0) {
        SetIvarWithType(char)
    } else if (strcmp(type, @encode(bool)) == 0) {
        SetIvarWithType(bool)
    } else if (strcmp(type, @encode(unsigned char)) == 0) {
        SetIvarWithType(unsigned char)
    } else if (strcmp(type, @encode(unsigned int)) == 0) {
        SetIvarWithType(unsigned int)
    } else if (strcmp(type, @encode(unsigned long)) == 0) {
        SetIvarWithType(unsigned long)
    } else if (strcmp(type, @encode(unsigned long long)) == 0) {
        SetIvarWithType(unsigned long long)
    } else if (strcmp(type, @encode(unsigned short)) == 0) {
        SetIvarWithType(unsigned short)
    }
}

// https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html

- (void)setterMsgsendWithArgumentType:(char *)type sel:(SEL)sel argument:(id)value {
    switch (*type) {
        case 'c': {
            ((void (*)(id,SEL,char))objc_msgSend)(self,sel,[value charValue]);
        }
            break;
        case 'i': {
            ((void (*)(id,SEL,int))objc_msgSend)(self,sel,[value intValue]);
        }
            break;
        case 's': {
            ((void (*)(id,SEL,short))objc_msgSend)(self,sel,[value shortValue]);
        }
            break;
        case 'l': {
            ((void (*)(id,SEL,long))objc_msgSend)(self,sel,[value longValue]);
        }
            break;
        case 'q': {
            ((void (*)(id,SEL,long long))objc_msgSend)(self,sel,[value longLongValue]);
        }
            break;
        case 'C': {
            ((void (*)(id,SEL,unsigned char))objc_msgSend)(self,sel,[value unsignedCharValue]);
        }
            break;
        case 'I': {
            ((void (*)(id,SEL,unsigned int))objc_msgSend)(self,sel,[value unsignedIntValue]);
        }
            break;
        case 'S': {
            ((void (*)(id,SEL,unsigned short))objc_msgSend)(self,sel,[value unsignedShortValue]);
        }
            break;
        case 'L': {
            ((void (*)(id,SEL,unsigned long))objc_msgSend)(self,sel,[value unsignedLongValue]);
        }
            break;
        case 'Q': {
            ((void (*)(id,SEL,unsigned long long))objc_msgSend)(self,sel,[value unsignedLongLongValue]);
        }
            break;
        case 'f': {
            ((void (*)(id,SEL,float))objc_msgSend)(self,sel,[value floatValue]);
        }
            break;
        case 'd': {
            ((void (*)(id,SEL,double))objc_msgSend)(self,sel,[value doubleValue]);
        }
            break;
        case 'B': {
            ((void (*)(id,SEL,BOOL))objc_msgSend)(self,sel,[value boolValue]);
        }
            break;
        default: {
            ((void (*)(id,SEL,id))objc_msgSend)(self,sel,value);
        }
    }
}


- (NSString *)capitalizationWord:(NSString *)str {
    if (str == nil || str.length <= 0) {
        return nil;
    }
    NSString *capitalization = [str substringToIndex:1].uppercaseString;
    NSString *others = [str substringFromIndex:1];
    return [NSString stringWithFormat:@"%@%@",capitalization,others];
}

- (NSString *)assemblySetterMethod:(NSString *)key {
    if (key == nil || key.length <= 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"set%@:",[self capitalizationWord:key]];
}

- (NSArray<NSString *> *)convertKeyToInstanceVariable:(NSString *)key {
    if (key == nil || key.length <= 0) {
        return nil;
    }
    NSString *_key = [NSString stringWithFormat:@"_%@",key];
    NSString *_isKey = [NSString stringWithFormat:@"_is%@",[self capitalizationWord:key]];
    NSString *isKey = [NSString stringWithFormat:@"is%@",[self capitalizationWord:key]];
    return @[_key,_isKey,key,isKey];
}

@end
