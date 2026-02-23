#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

typedef CFTypeRef IOAVServiceRef;

extern IOAVServiceRef IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress,
                                     uint32_t dataAddress, void *data, uint32_t dataLength);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress,
                                    uint32_t dataAddress, void *data, uint32_t dataLength);

void* mkf_IOAVServiceCreate(CFAllocatorRef allocator) {
    return (void*)IOAVServiceCreate(allocator);
}

void* mkf_IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service) {
    return (void*)IOAVServiceCreateWithService(allocator, service);
}

IOReturn mkf_IOAVServiceWriteI2C(void *service, uint32_t chipAddress,
                                  uint32_t dataAddress, void *data, uint32_t dataLength) {
    return IOAVServiceWriteI2C((IOAVServiceRef)service, chipAddress, dataAddress, data, dataLength);
}

IOReturn mkf_IOAVServiceReadI2C(void *service, uint32_t chipAddress,
                                 uint32_t dataAddress, void *data, uint32_t dataLength) {
    return IOAVServiceReadI2C((IOAVServiceRef)service, chipAddress, dataAddress, data, dataLength);
}
