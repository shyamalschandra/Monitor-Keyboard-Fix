#ifndef IOAVServiceBridge_h
#define IOAVServiceBridge_h

#include <IOKit/IOKitLib.h>

void* _Nullable mkf_IOAVServiceCreate(CFAllocatorRef _Nullable allocator);
void* _Nullable mkf_IOAVServiceCreateWithService(CFAllocatorRef _Nullable allocator,
                                                   io_service_t service);

IOReturn mkf_IOAVServiceWriteI2C(void * _Nonnull service,
                                  uint32_t chipAddress,
                                  uint32_t dataAddress,
                                  void * _Nonnull data,
                                  uint32_t dataLength);

IOReturn mkf_IOAVServiceReadI2C(void * _Nonnull service,
                                 uint32_t chipAddress,
                                 uint32_t dataAddress,
                                 void * _Nonnull data,
                                 uint32_t dataLength);

#endif
