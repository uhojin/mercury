#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>

// Private IOHIDEventSystem types (not in public headers)
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

// Private IOHIDEventSystem functions
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeout);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

// HID event constants
#define kIOHIDEventTypeTemperature 15
#define kIOHIDEventFieldTemperatureLevel (15 << 16)

NS_ASSUME_NONNULL_BEGIN

@interface HIDSensorReader : NSObject

+ (BOOL)isAvailable;
+ (NSDictionary<NSString *, NSNumber *> *)readTemperatures;

@end

NS_ASSUME_NONNULL_END
