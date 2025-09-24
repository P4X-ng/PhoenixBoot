/**
 * PhoenixGuardDemo.h - Demo-compatible definitions
 * 
 * Linux-compatible header for PhoenixGuard demonstration
 */

#ifndef _PHOENIXGUARD_DEMO_H_
#define _PHOENIXGUARD_DEMO_H_

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

// UEFI-compatible type definitions for demo
typedef uint64_t UINT64;
typedef uint32_t UINT32;
typedef uint16_t UINT16;
typedef uint8_t UINT8;
typedef bool BOOLEAN;
typedef char CHAR8;
typedef uint16_t CHAR16;
typedef void VOID;
typedef UINT64 UINTN;
typedef UINT64 EFI_STATUS;
typedef void* EFI_HANDLE;

#define TRUE true
#define FALSE false
#define NULL ((void*)0)

// EFI Status codes
#define EFI_SUCCESS             0
#define EFI_ERROR(Status)       (((int64_t)(Status)) < 0)
#define EFI_INVALID_PARAMETER   0x8000000000000002ULL
#define EFI_NOT_READY           0x8000000000000006ULL
#define EFI_NOT_FOUND           0x800000000000000EULL
#define EFI_COMPROMISED_DATA    0x8000000000000021ULL
#define EFI_ACCESS_DENIED       0x800000000000000FULL
#define EFI_OUT_OF_RESOURCES    0x8000000000000009ULL
#define EFI_ABORTED             0x8000000000000015ULL
#define EFI_SECURITY_VIOLATION  0x800000000000001AULL
#define EFI_DEVICE_ERROR        0x8000000000000007ULL
#define EFI_UNSUPPORTED         0x8000000000000003ULL

// Function attributes
#define EFIAPI
#define STATIC static
#define IN
#define OUT

// Memory functions
#define ZeroMem(dest, size) memset(dest, 0, size)
#define CopyMem(dest, src, size) memcpy(dest, src, size)
#define CompareMem(buf1, buf2, size) memcmp(buf1, buf2, size)

// String functions for demo
#define StrCmp(str1, str2) wcscmp((wchar_t*)str1, (wchar_t*)str2)
#define StrCpyS(dest, size, src) wcscpy((wchar_t*)dest, (wchar_t*)src)
#define StrCatS(dest, size, src) wcscat((wchar_t*)dest, (wchar_t*)src)
#define AsciiStrCmp(str1, str2) strcmp(str1, str2)
#define AsciiStrCpyS(dest, size, src) strcpy(dest, src)
#define AsciiSPrint(dest, size, fmt, ...) sprintf(dest, fmt, ##__VA_ARGS__)
#define AsciiStrCatS(dest, size, src) strcat(dest, src)

// Print function
#define Print(fmt, ...) printf(fmt, ##__VA_ARGS__)

// Debug macros
#define DEBUG_INFO    1
#define DEBUG_ERROR   2
#define DEBUG_WARN    3
#define DEBUG_VERBOSE 4

#define DEBUG(x) printf x

// Signature macro
#define SIGNATURE_32(a, b, c, d) \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24))

// Min/Max macros
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

// Dummy structures and functions for demo
typedef struct {
  VOID* ConOut;
  VOID* ConIn;
} EFI_SYSTEM_TABLE;

typedef struct {
  UINT16 UnicodeChar;
} EFI_INPUT_KEY;

typedef struct {
  EFI_STATUS (*AllocatePool)(UINT32 Type, UINTN Size, VOID** Buffer);
  EFI_STATUS (*FreePool)(VOID* Buffer);
} EFI_BOOT_SERVICES;

extern EFI_BOOT_SERVICES* gBS;
extern EFI_HANDLE gImageHandle;

// Dummy implementations
static inline EFI_STATUS DummyAllocatePool(UINT32 Type, UINTN Size, VOID** Buffer) {
  *Buffer = malloc(Size);
  return *Buffer ? EFI_SUCCESS : EFI_OUT_OF_RESOURCES;
}

static inline EFI_STATUS DummyFreePool(VOID* Buffer) {
  free(Buffer);
  return EFI_SUCCESS;
}

static inline UINT64 GetTimeInNanoSecond(UINT64 Counter) {
  return 12345678; // Dummy timestamp
}

static inline UINT64 GetPerformanceCounter(void) {
  return 98765; // Dummy counter
}

static inline VOID MicroSecondDelay(UINTN Microseconds) {
  usleep(Microseconds);
}

// Boot services data types
#define EfiBootServicesData     1
#define EfiRuntimeServicesData  2

#endif // _PHOENIXGUARD_DEMO_H_
