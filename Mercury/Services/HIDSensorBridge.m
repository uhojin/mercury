#import "HIDSensorBridge.h"

@implementation HIDSensorReader

+ (IOHIDEventSystemClientRef)createClient {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return NULL;

    // Match temperature sensors (PrimaryUsagePage=0xFF00, PrimaryUsage=5)
    NSDictionary *match = @{
        @"PrimaryUsagePage": @(0xFF00),
        @"PrimaryUsage": @(5)
    };
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)match);

    return client;
}

+ (BOOL)isAvailable {
    IOHIDEventSystemClientRef client = [self createClient];
    if (!client) return NO;

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    BOOL available = (services != NULL && CFArrayGetCount(services) > 0);

    if (services) CFRelease(services);
    CFRelease(client);

    return available;
}

+ (NSDictionary<NSString *, NSNumber *> *)readTemperatures {
    IOHIDEventSystemClientRef client = [self createClient];
    if (!client) return @{};

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) {
        CFRelease(client);
        return @{};
    }

    double cpuSum = 0;
    int cpuCount = 0;
    double gpuSum = 0;
    int gpuCount = 0;

    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);

        CFTypeRef productCF = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (!productCF) continue;
        if (CFGetTypeID(productCF) != CFStringGetTypeID()) {
            CFRelease(productCF);
            continue;
        }

        NSString *name = (__bridge_transfer NSString *)(CFStringRef)productCF;

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0);
        if (!event) continue;

        double temp = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel);
        CFRelease(event);

        // Filter invalid readings
        if (temp <= 0 || temp > 150) continue;

        // CPU die sensors: "PMU tdie*" (per-core die temps)
        // Also match pACC/eACC naming used on some chips
        if ([name containsString:@"tdie"] ||
            [name containsString:@"pACC"] || [name containsString:@"eACC"]) {
            cpuSum += temp;
            cpuCount++;
        }
        // GPU sensors: "PMU TP*g" (names ending in 'g') or "GPU MTR"
        else if (([name hasPrefix:@"PMU TP"] && [name hasSuffix:@"g"]) ||
                 [name containsString:@"GPU"]) {
            gpuSum += temp;
            gpuCount++;
        }
    }

    CFRelease(services);
    CFRelease(client);

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (cpuCount > 0) {
        result[@"cpu"] = @(cpuSum / cpuCount);
    }
    if (gpuCount > 0) {
        result[@"gpu"] = @(gpuSum / gpuCount);
    }

    return result;
}

@end
