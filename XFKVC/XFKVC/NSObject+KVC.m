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
    if (key == nil || key.length <= 0) {
        [self xf_valueForUndefinedKey:key];
        return nil;
    }
    // 查找是否有这些方法  -get<Key>, -<key>, -is<Key>
    Class selfClass = [self class];
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(selfClass, &methodCount);
    if (methodCount > 0) {
        NSArray *searchFunctions = [self convertGetterInstanceMethod:key];
        for (int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *methodName = NSStringFromSelector(sel);
            for (int j = 0; j < searchFunctions.count; j++) {
                if ([methodName isEqualToString:searchFunctions[j]]) {
                    char *returnType = method_copyReturnType(methods[i]);
                    NSString *type = [NSString stringWithUTF8String:returnType];
                    if (![type  isEqual:@"@"]) {  // 非指针类型
                        NSNumber *result = [self getReturnValueForMethod:methods[i]];
                        return result;
                    } else {
                        id resultValue = ((id (*)(id,SEL))objc_msgSend)(self,sel);
                        return resultValue;
                    }
                }
            }
        }
    }

    // 判断accessInstanceVariablesDirectly值,然后做是否搜寻实例变量操作
    if (![self.class xf_accessInstanceVariablesDirectly]) {
        [self xf_valueForUndefinedKey:key];
    }
    unsigned int ivarCount = 0;
    //返回类中所有实例变量
    Ivar *ivars = class_copyIvarList(self.class, &ivarCount);
    // 寻找变量 _<key>, _is<Key>, <key>, is<Key>
    NSArray<NSString *> *keyNameArray = [self convertKeyToInstanceVariable:key];
    
    for (unsigned int i = 0; i < ivarCount; i++) {
        const char *ivarCName = ivar_getName(ivars[i]);
        NSString *ivarName = [NSString stringWithCString:ivarCName encoding:NSUTF8StringEncoding];
        for (NSUInteger j = 0; j < keyNameArray.count; j++) {
            if ([ivarName isEqualToString:keyNameArray[j]]) {
                // 找到符合要求的ivar，根据对象类型进行相应操作
                const char *ivarType = ivar_getTypeEncoding(ivars[i]);
                if (*ivarType != '@') { // 非指针对象
                    return [self getValueForIvar:ivars[i]];
                }
                //指针对象
                id ivarValue = object_getIvar(self, ivars[i]);
                free(ivars); ivars = NULL;
                return ivarValue;
            }
        }
    }
    free(ivars); ivars = NULL;
    [self xf_valueForUndefinedKey:key];
    
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

- (id)getValueForIvar:(Ivar)ivar {
    const char *type = ivar_getTypeEncoding(ivar);
    if (strcmp(type, @encode(double)) == 0) {
        double (* function)(id, Ivar) = (double(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithDouble:function(self,ivar)];
    } else if (strcmp(type, @encode(float)) == 0) {
        float (* function)(id, Ivar) = (float(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithFloat:function(self,ivar)];
    } else if (strcmp(type, @encode(int)) == 0) {
        int (* function)(id, Ivar) = (int(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithInt:function(self,ivar)];
    } else if (strcmp(type, @encode(long)) == 0) {
        long (* function)(id, Ivar) = (long (*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithLong:function(self,ivar)];
    } else if (strcmp(type, @encode(long long)) == 0) {
        long long (* function)(id, Ivar) = (long long(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithLongLong:function(self,ivar)];
    } else if (strcmp(type, @encode(short)) == 0) {
        short (* function)(id, Ivar) = (short(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithShort:function(self,ivar)];
    } else if (strcmp(type, @encode(char)) == 0) {
        char (* function)(id, Ivar) = (char(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithChar:function(self,ivar)];
    } else if (strcmp(type, @encode(bool)) == 0) {
        bool (* function)(id, Ivar) = (bool(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithBool:function(self,ivar)];
    } else if (strcmp(type, @encode(unsigned char)) == 0) {
        unsigned char (* function)(id, Ivar) = (unsigned char(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithUnsignedChar:function(self,ivar)];
    } else if (strcmp(type, @encode(unsigned int)) == 0) {
        unsigned int (* function)(id, Ivar) = (unsigned int(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithUnsignedInt:function(self,ivar)];
    } else if (strcmp(type, @encode(unsigned long)) == 0) {
        unsigned long (* function)(id, Ivar) = (unsigned long(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithUnsignedLong:function(self,ivar)];
    } else if (strcmp(type, @encode(unsigned long long)) == 0) {
        unsigned long long (* function)(id, Ivar) = (unsigned long long(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithUnsignedLongLong:function(self,ivar)];
    } else if (strcmp(type, @encode(unsigned short)) == 0) {
        unsigned short (* function)(id, Ivar) = (unsigned short(*)(id, Ivar))object_getIvar;
        return [NSNumber numberWithUnsignedShort:function(self,ivar)];
    }
    return nil;
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

- (NSNumber *)getReturnValueForMethod:(Method)method {
    char *returnType = method_copyReturnType(method);
    SEL sel = method_getName(method);
    if (strcmp(returnType, @encode(double)) == 0) {
        double result = ((double (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithDouble:result];
    } else if (strcmp(returnType, @encode(float)) == 0) {
        float result = ((float (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithFloat:result];
    } else if (strcmp(returnType, @encode(int)) == 0) {
        int result = ((int (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithInt:result];
    } else if (strcmp(returnType, @encode(long)) == 0) {
        long result = ((long (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithLong:result];
    } else if (strcmp(returnType, @encode(long long)) == 0) {
        long long result = ((long long (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithLongLong:result];
    } else if (strcmp(returnType, @encode(short)) == 0) {
        short result = ((short (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithShort:result];
    } else if (strcmp(returnType, @encode(char)) == 0) {
        char result = ((char (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithChar:result];
    } else if (strcmp(returnType, @encode(bool)) == 0) {
        bool result = ((bool (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithBool:result];
    } else if (strcmp(returnType, @encode(unsigned char)) == 0) {
        unsigned char result = ((unsigned char (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithUnsignedChar:result];
    } else if (strcmp(returnType, @encode(unsigned int)) == 0) {
        unsigned int result = ((unsigned int (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithUnsignedInt:result];
    } else if (strcmp(returnType, @encode(unsigned long)) == 0) {
        unsigned long result = ((unsigned long (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithUnsignedLong:result];
    } else if (strcmp(returnType, @encode(unsigned long long)) == 0) {
        unsigned long long result = ((unsigned long long (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithUnsignedLongLong:result];
    } else if (strcmp(returnType, @encode(unsigned short)) == 0) {
        unsigned short result = ((unsigned short (*)(id,SEL))objc_msgSend)(self,sel);
        return [NSNumber numberWithUnsignedShort:result];
    }
    return nil;
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

- (NSArray<NSString *> *)convertGetterInstanceMethod:(NSString *)key {
    if (key == nil || key.length <= 0) {
        return nil;
    }
    NSString *getKey = [NSString stringWithFormat:@"get%@",[self capitalizationWord:key]];
    NSString *isKey = [NSString stringWithFormat:@"is%@",[self capitalizationWord:key]];
    NSArray *array = @[getKey,key,isKey];
    return array;
}

@end
