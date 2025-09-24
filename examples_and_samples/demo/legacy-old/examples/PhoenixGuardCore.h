/** @file
  PhoenixGuard - Self-Healing Firmware Recovery System Header

  Defines constants, structures, and function prototypes for the PhoenixGuard
  recovery system that automatically restores clean firmware instead of halting.

  Copyright (c) 2025, RFKilla Security Suite. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#ifndef __PHOENIX_GUARD_CORE_H__
#define __PHOENIX_GUARD_CORE_H__

#include <Uefi.h>
#include <Pi/PiPeiCis.h>
#include <Library/BaseLib.h>
#include <Library/DebugLib.h>

//
// PhoenixGuard version and signatures
//
#define PHOENIX_GUARD_MAJOR_VERSION       1
#define PHOENIX_GUARD_MINOR_VERSION       0
#define PHOENIX_GUARD_SIGNATURE           SIGNATURE_32('P','H','O','X')

//
// Compromise types (can be combined with bitwise OR)
//
#define PHOENIX_COMPROMISE_MICROCODE      BIT0
#define PHOENIX_COMPROMISE_THERMAL        BIT1
#define PHOENIX_COMPROMISE_SPI_FLASH      BIT2
#define PHOENIX_COMPROMISE_EFI_VARS       BIT3
#define PHOENIX_COMPROMISE_BOOTKIT        BIT4
#define PHOENIX_COMPROMISE_FIRMWARE       BIT5

//
// Recovery configuration constants
//
#define PHOENIX_MAX_RECOVERY_SOURCES      8
#define PHOENIX_MAX_URL_LENGTH            256
#define PHOENIX_MAX_PATH_LENGTH           128
#define PHOENIX_MAX_FILENAME_LENGTH       64
#define PHOENIX_MAX_DESCRIPTION_LENGTH    64
#define PHOENIX_MAX_ERROR_LENGTH          128
#define PHOENIX_SHA256_HASH_SIZE          32

//
// Recovery priorities (higher number = higher priority)
//
#define PHOENIX_PRIORITY_EMBEDDED         100
#define PHOENIX_PRIORITY_PHYSICAL_MEDIA   80
#define PHOENIX_PRIORITY_NETWORK_HTTPS    60
#define PHOENIX_PRIORITY_NETWORK_HTTP     40
#define PHOENIX_PRIORITY_USER_PROVIDED    20

//
// Recovery types
//
typedef enum {
  PhoenixRecoveryTypeUnknown = 0,
  PhoenixRecoveryTypeEmbedded,       // Embedded backup in protected flash
  PhoenixRecoveryTypePhysicalMedia,  // CD/USB/other removable media
  PhoenixRecoveryTypeNetwork,        // Download from trusted server
  PhoenixRecoveryTypeUserProvided,   // User-supplied recovery source
  PhoenixRecoveryTypeMax
} PHOENIX_RECOVERY_TYPE;

//
// Recovery results
//
typedef enum {
  PhoenixRecoveryResultSuccess = 0,
  PhoenixRecoveryResultFailed,
  PhoenixRecoveryResultPartial,
  PhoenixRecoveryResultAborted,
  PhoenixRecoveryResultNotAvailable,
  PhoenixRecoveryResultTimeout,
  PhoenixRecoveryResultMax
} PHOENIX_RECOVERY_RESULT;

//
// Forward declarations
//
typedef struct _PHOENIX_RECOVERY_SOURCE PHOENIX_RECOVERY_SOURCE;
typedef struct _PHOENIX_RECOVERY_OPERATION PHOENIX_RECOVERY_OPERATION;

//
// Recovery operation structure
//
struct _PHOENIX_RECOVERY_OPERATION {
  PHOENIX_RECOVERY_RESULT   Result;
  PHOENIX_RECOVERY_TYPE     SourceUsed;
  UINT32                    BytesRecovered;
  UINT32                    TimeElapsed;
  CHAR8                     ErrorDetails[PHOENIX_MAX_ERROR_LENGTH];
  UINT32                    Checksum;
  BOOLEAN                   VerificationPassed;
  UINT32                    RetryCount;
};

//
// Function prototypes
//

/**
  Execute PhoenixGuard recovery process.
  
  @param  CompromiseType   Bitmask of compromise types detected
  @param  SecurityLevel    Current security level (0-3)
  
  @retval EFI_SUCCESS      Recovery completed successfully
  @retval EFI_ABORTED      User chose to abort recovery
  @retval EFI_NOT_FOUND    No recovery sources available
  @retval EFI_DEVICE_ERROR Recovery failed
**/
EFI_STATUS
EFIAPI
PhoenixGuardExecuteRecovery (
  IN UINT32  CompromiseType,
  IN UINT8   SecurityLevel
  );

/**
  Initialize PhoenixGuard recovery system.
  
  @retval EFI_SUCCESS      Initialization successful
  @retval EFI_DEVICE_ERROR Initialization failed
**/
EFI_STATUS
EFIAPI
PhoenixGuardInitialize (
  VOID
  );

/**
  Shutdown PhoenixGuard recovery system.
  
  @retval EFI_SUCCESS      Shutdown successful
**/
EFI_STATUS
EFIAPI
PhoenixGuardShutdown (
  VOID
  );

/**
  Get PhoenixGuard version information.
  
  @param  MajorVersion   Output: Major version number
  @param  MinorVersion   Output: Minor version number
  
  @retval EFI_SUCCESS    Version retrieved successfully
**/
EFI_STATUS
EFIAPI
PhoenixGuardGetVersion (
  OUT UINT32  *MajorVersion,
  OUT UINT32  *MinorVersion
  );

#endif // __PHOENIX_GUARD_CORE_H__
