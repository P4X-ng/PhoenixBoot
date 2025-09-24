/**
 * BootkitSentinel.h - Advanced Bootkit Honeypot & Analysis Engine
 * 
 * Header file defining the complete BootkitSentinel API for monitoring,
 * analyzing, and controlling bootkit behavior while allowing legitimate
 * OS tools to operate safely.
 */

#ifndef _BOOTKIT_SENTINEL_H_
#define _BOOTKIT_SENTINEL_H_

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>

//
// Forward declarations from BootkitSentinel.c
//
typedef enum _SENTINEL_MODE SENTINEL_MODE;
typedef enum _INTERCEPT_TYPE INTERCEPT_TYPE;
typedef struct _SENTINEL_LOG_ENTRY SENTINEL_LOG_ENTRY;
typedef struct _BOOTKIT_SENTINEL BOOTKIT_SENTINEL;

//
// Sentinel API Functions
//

/**
 * Initialize the BootkitSentinel system
 */
EFI_STATUS
EFIAPI
SentinelInitialize (
  IN SENTINEL_MODE Mode
  );

/**
 * Main intercept handler - processes all monitored operations
 */
EFI_STATUS
EFIAPI
SentinelInterceptOperation (
  IN  INTERCEPT_TYPE  Operation,
  IN  UINT64          Address,
  IN  UINT64          Value,
  IN  UINT32          Size,
  IN  VOID           *Context,
  OUT BOOLEAN        *Allow,
  OUT UINT64         *SpoofValue
  );

/**
 * Redirect operations to honeypot flash
 */
BOOLEAN
SentinelRedirectToHoneypot (
  IN  INTERCEPT_TYPE  Operation,
  IN  UINT64          Address,
  IN  UINT64          Value,
  IN  UINT32          Size,
  OUT UINT64         *SpoofValue
  );

/**
 * Determine if caller is an OS tool like flashrom
 */
BOOLEAN
SentinelIsOperatingSystemTool (
  IN VOID  *Context
  );

/**
 * Initialize honeypot flash with realistic fake BIOS data
 */
VOID
SentinelInitializeHoneypotFlash (
  VOID
  );

/**
 * Initialize OS interface for tools like flashrom
 */
EFI_STATUS
SentinelInitializeOsInterface (
  VOID
  );

/**
 * Expose sentinel status and logs to OS
 */
EFI_STATUS
SentinelExportToOS (
  OUT VOID   **LogBuffer,
  OUT UINT32  *LogCount,
  OUT VOID   **HoneypotFlash,
  OUT UINT32  *HoneypotSize
  );

/**
 * Allow OS tools to request controlled flash access
 */
EFI_STATUS
SentinelOsFlashRequest (
  IN  UINT64   Address,
  IN  UINT32   Size,
  IN  BOOLEAN  Write,
  IN  UINT8   *Data,
  OUT UINT8   *ReadData
  );

/**
 * Helper functions
 */
CHAR8*
SentinelModeToString (
  IN SENTINEL_MODE Mode
  );

CHAR8*
SentinelOperationToString (
  IN INTERCEPT_TYPE Operation
  );

VOID
SentinelAddLogEntry (
  IN SENTINEL_LOG_ENTRY  *Entry
  );

VOID
SentinelPrintStatistics (
  VOID
  );

//
// Analysis functions (implemented separately)
//

/**
 * Analyze operation for suspicious behavior
 */
BOOLEAN
SentinelAnalyzeOperation (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  );

/**
 * Calculate suspicion score for an operation
 */
UINT32
SentinelCalculateSuspicionScore (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address
  );

/**
 * Capture detailed forensic data
 */
VOID
SentinelCaptureForensicData (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size,
  IN VOID           *Context
  );

/**
 * Validate OS tool request
 */
BOOLEAN
SentinelValidateOsToolRequest (
  IN UINT64   Address,
  IN UINT32   Size,
  IN BOOLEAN  Write
  );

/**
 * Back up real flash for comparison
 */
EFI_STATUS
SentinelBackupRealFlash (
  VOID
  );

/**
 * Install intercept hooks
 */
EFI_STATUS
SentinelInstallIntercepts (
  VOID
  );

/**
 * Perform real flash write
 */
EFI_STATUS
SentinelRealFlashWrite (
  IN UINT64  Address,
  IN UINT32  Size,
  IN UINT8  *Data
  );

/**
 * Perform real flash read
 */
EFI_STATUS
SentinelRealFlashRead (
  IN UINT64  Address,
  IN UINT32  Size,
  OUT UINT8 *Data
  );

//
// OS Interface Functions
//

/**
 * Get current sentinel status
 */
EFI_STATUS
SentinelGetStatus (
  OUT BOOLEAN  *Active,
  OUT UINT32   *Mode,
  OUT UINT32   *InterceptCount,
  OUT UINT32   *DetectionScore
  );

/**
 * Configure sentinel mode at runtime
 */
EFI_STATUS
SentinelSetMode (
  IN SENTINEL_MODE NewMode
  );

/**
 * Export logs in various formats
 */
EFI_STATUS
SentinelExportLogs (
  IN  UINT32  Format,      // 0=Binary, 1=JSON, 2=CSV
  OUT VOID   **Buffer,
  OUT UINT32  *BufferSize
  );

/**
 * Reset sentinel statistics
 */
EFI_STATUS
SentinelResetStatistics (
  VOID
  );

#endif // _BOOTKIT_SENTINEL_H_
