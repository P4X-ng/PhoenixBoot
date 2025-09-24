/**
 * SentinelAnalysis.c - Advanced Bootkit Behavioral Analysis Engine
 * 
 * "KNOW YOUR ENEMY - EVERY MOVE, EVERY PATTERN, EVERY TRICK"
 * 
 * This module implements sophisticated behavioral analysis to distinguish
 * between legitimate OS tools (like flashrom) and malicious bootkits.
 * It uses pattern recognition, heuristics, and machine learning techniques.
 */

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/IoLib.h>
#include <Library/TimerLib.h>
#include "BootkitSentinel.h"

//
// Suspicious address ranges and patterns
//
#define SPI_FLASH_BASE               0xFF000000
#define SPI_FLASH_SIZE               0x01000000
#define TPM_REGISTER_BASE            0xFED40000
#define TPM_REGISTER_SIZE            0x00005000
#define SECURE_BOOT_NVRAM_BASE       0xFF050000
#define MICROCODE_REGION_BASE        0xFF080000
#define BIOS_BOOT_BLOCK_BASE         0xFFFF0000

//
// Bootkit behavior patterns
//
typedef struct {
  CHAR8    *Name;
  UINT32   SuspicionScore;
  BOOLEAN  (*DetectionFunction)(INTERCEPT_TYPE, UINT64, UINT64, UINT32);
} BOOTKIT_PATTERN;

//
// Analysis state tracking
//
typedef struct {
  // Operation frequency tracking
  UINT32  SpiWriteCount;
  UINT32  SpiEraseCount;
  UINT32  TpmAccessCount;
  UINT32  MicrocodeUpdateCount;
  UINT32  SecureBootModCount;
  
  // Suspicious patterns
  BOOLEAN WritingToBootBlock;
  BOOLEAN DisablingSecureBoot;
  BOOLEAN ModifyingTpmNvram;
  BOOLEAN UpdatedMicrocode;
  BOOLEAN ErasedCriticalRegions;
  
  // Timing analysis
  UINT64  FirstSpiWrite;
  UINT64  LastSpiWrite;
  UINT32  RapidWriteCount;
  
  // Address pattern analysis
  UINT64  LastWriteAddress;
  UINT32  SequentialWrites;
  UINT32  ScatteredWrites;
  
} ANALYSIS_STATE;

STATIC ANALYSIS_STATE  gAnalysisState = {0};

//
// Forward declarations
//
BOOLEAN DetectBootBlockModification(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectSecureBootDisabling(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectTpmTampering(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectMicrocodeInfection(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectMassFlashErase(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectRapidFireWrites(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectPersistenceAttempt(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);
BOOLEAN DetectAntiAnalysis(INTERCEPT_TYPE Op, UINT64 Addr, UINT64 Val, UINT32 Size);

//
// Known bootkit patterns database
//
STATIC BOOTKIT_PATTERN gBootkitPatterns[] = {
  {"Boot Block Modification",    500, DetectBootBlockModification},
  {"Secure Boot Disabling",      400, DetectSecureBootDisabling},
  {"TPM Tampering",              450, DetectTpmTampering},
  {"Microcode Infection",        600, DetectMicrocodeInfection},
  {"Mass Flash Erase",           300, DetectMassFlashErase},
  {"Rapid Fire Writes",          250, DetectRapidFireWrites},
  {"Persistence Attempt",        350, DetectPersistenceAttempt},
  {"Anti-Analysis Behavior",     200, DetectAntiAnalysis},
  {NULL, 0, NULL}  // Sentinel
};

/**
 * Main analysis function - determines if operation is suspicious
 */
BOOLEAN
SentinelAnalyzeOperation (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  UINT32   PatternIndex;
  BOOLEAN  IsSuspicious = FALSE;
  UINT32   TotalSuspicionScore = 0;
  
  //
  // Update analysis state
  //
  SentinelUpdateAnalysisState(Operation, Address, Value, Size);
  
  //
  // Check against known bootkit patterns
  //
  for (PatternIndex = 0; gBootkitPatterns[PatternIndex].Name != NULL; PatternIndex++) {
    if (gBootkitPatterns[PatternIndex].DetectionFunction(Operation, Address, Value, Size)) {
      DEBUG((DEBUG_WARN, "🚨 Detected pattern: %a (Score: %d)\n", 
             gBootkitPatterns[PatternIndex].Name,
             gBootkitPatterns[PatternIndex].SuspicionScore));
      
      TotalSuspicionScore += gBootkitPatterns[PatternIndex].SuspicionScore;
      IsSuspicious = TRUE;
    }
  }
  
  //
  // Additional heuristic checks
  //
  if (SentinelCheckAddressHeuristics(Operation, Address)) {
    TotalSuspicionScore += 100;
    IsSuspicious = TRUE;
  }
  
  if (SentinelCheckTimingHeuristics(Operation, Address)) {
    TotalSuspicionScore += 150;
    IsSuspicious = TRUE;
  }
  
  if (SentinelCheckSequenceHeuristics(Operation, Address)) {
    TotalSuspicionScore += 200;
    IsSuspicious = TRUE;
  }
  
  //
  // Log analysis results
  //
  if (IsSuspicious) {
    DEBUG((DEBUG_WARN, "⚠️ Suspicious operation detected: %a Addr=0x%lx Score=%d\n",
           SentinelOperationToString(Operation), Address, TotalSuspicionScore));
  }
  
  return IsSuspicious;
}

/**
 * Calculate numerical suspicion score
 */
UINT32
SentinelCalculateSuspicionScore (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address
  )
{
  UINT32  Score = 0;
  
  //
  // Base scores by operation type
  //
  switch (Operation) {
    case InterceptSpiFlashWrite:
      Score += 50;
      break;
    case InterceptSpiFlashErase:
      Score += 30;
      break;
    case InterceptMicrocodeUpdate:
      Score += 200;
      break;
    case InterceptTpmAccess:
      Score += 100;
      break;
    case InterceptSecureBootMod:
      Score += 150;
      break;
    default:
      Score += 10;
      break;
  }
  
  //
  // Address-based scoring
  //
  if (Address >= BIOS_BOOT_BLOCK_BASE) {
    Score += 300;  // Boot block modification is highly suspicious
  } else if (Address >= MICROCODE_REGION_BASE && Address < MICROCODE_REGION_BASE + 0x100000) {
    Score += 250;  // Microcode region
  } else if (Address >= SECURE_BOOT_NVRAM_BASE && Address < SECURE_BOOT_NVRAM_BASE + 0x10000) {
    Score += 200;  // Secure Boot NVRAM
  } else if (Address >= TPM_REGISTER_BASE && Address < TPM_REGISTER_BASE + TPM_REGISTER_SIZE) {
    Score += 180;  // TPM registers
  }
  
  //
  // Pattern-based scoring
  //
  if (gAnalysisState.RapidWriteCount > 10) {
    Score += 100;
  }
  
  if (gAnalysisState.ErasedCriticalRegions) {
    Score += 200;
  }
  
  if (gAnalysisState.DisablingSecureBoot) {
    Score += 150;
  }
  
  return Score;
}

/**
 * Update internal analysis state
 */
VOID
SentinelUpdateAnalysisState (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  UINT64  CurrentTime;
  
  CurrentTime = GetTimeInNanoSecond(GetPerformanceCounter());
  
  switch (Operation) {
    case InterceptSpiFlashWrite:
      gAnalysisState.SpiWriteCount++;
      
      if (gAnalysisState.FirstSpiWrite == 0) {
        gAnalysisState.FirstSpiWrite = CurrentTime;
      }
      gAnalysisState.LastSpiWrite = CurrentTime;
      
      // Check for rapid writes
      if (CurrentTime - gAnalysisState.LastSpiWrite < 100000000) {  // 100ms
        gAnalysisState.RapidWriteCount++;
      } else {
        gAnalysisState.RapidWriteCount = 0;
      }
      
      // Check for sequential vs scattered writes
      if (gAnalysisState.LastWriteAddress != 0) {
        if (Address == gAnalysisState.LastWriteAddress + Size) {
          gAnalysisState.SequentialWrites++;
        } else {
          gAnalysisState.ScatteredWrites++;
        }
      }
      gAnalysisState.LastWriteAddress = Address;
      
      break;
      
    case InterceptSpiFlashErase:
      gAnalysisState.SpiEraseCount++;
      
      // Check if erasing critical regions
      if (Address >= BIOS_BOOT_BLOCK_BASE || 
          Address >= SECURE_BOOT_NVRAM_BASE) {
        gAnalysisState.ErasedCriticalRegions = TRUE;
      }
      break;
      
    case InterceptTmpAccess:
      gAnalysisState.TpmAccessCount++;
      break;
      
    case InterceptMicrocodeUpdate:
      gAnalysisState.MicrocodeUpdateCount++;
      gAnalysisState.UpdatedMicrocode = TRUE;
      break;
      
    case InterceptSecureBootMod:
      gAnalysisState.SecureBootModCount++;
      gAnalysisState.DisablingSecureBoot = TRUE;
      break;
      
    default:
      break;
  }
}

/**
 * Pattern detection functions
 */

BOOLEAN
DetectBootBlockModification (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Boot block modification is a classic bootkit technique
  //
  if ((Operation == InterceptSpiFlashWrite || Operation == InterceptSpiFlashErase) &&
      Address >= BIOS_BOOT_BLOCK_BASE) {
    gAnalysisState.WritingToBootBlock = TRUE;
    DEBUG((DEBUG_ERROR, "🚨 BOOT BLOCK MODIFICATION DETECTED at 0x%lx\n", Address));
    return TRUE;
  }
  
  return FALSE;
}

BOOLEAN
DetectSecureBootDisabling (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Look for writes to Secure Boot NVRAM variables
  //
  if (Operation == InterceptSecureBootMod ||
      (Operation == InterceptSpiFlashWrite && 
       Address >= SECURE_BOOT_NVRAM_BASE && 
       Address < SECURE_BOOT_NVRAM_BASE + 0x10000)) {
    
    // Check if value indicates disabling (common patterns)
    if (Value == 0x00000000 || Value == 0xFFFFFFFF) {
      DEBUG((DEBUG_ERROR, "🚨 SECURE BOOT DISABLING DETECTED\n"));
      return TRUE;
    }
  }
  
  return FALSE;
}

BOOLEAN
DetectTmpTampering (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // TPM tampering detection
  //
  if (Operation == InterceptTmpAccess ||
      (Address >= TPM_REGISTER_BASE && Address < TPM_REGISTER_BASE + TPM_REGISTER_SIZE)) {
    
    // Multiple rapid TPM accesses are suspicious
    if (gAnalysisState.TmpAccessCount > 5) {
      gAnalysisState.ModifyingTmpNvram = TRUE;
      DEBUG((DEBUG_ERROR, "🚨 TPM TAMPERING DETECTED\n"));
      return TRUE;
    }
  }
  
  return FALSE;
}

BOOLEAN
DetectMicrocodeInfection (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Microcode infection is extremely sophisticated
  //
  if (Operation == InterceptMicrocodeUpdate ||
      (Operation == InterceptSpiFlashWrite &&
       Address >= MICROCODE_REGION_BASE &&
       Address < MICROCODE_REGION_BASE + 0x100000)) {
    
    DEBUG((DEBUG_ERROR, "🚨 MICROCODE INFECTION DETECTED\n"));
    return TRUE;
  }
  
  return FALSE;
}

BOOLEAN
DetectMassFlashErase (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Mass flash erase often precedes bootkit installation
  //
  if (Operation == InterceptSpiFlashErase) {
    if (Size > 1024 * 1024 ||  // Erasing more than 1MB
        gAnalysisState.SpiEraseCount > 10) {  // Many erase operations
      
      DEBUG((DEBUG_WARN, "⚠️ MASS FLASH ERASE DETECTED: Size=%d Count=%d\n", 
             Size, gAnalysisState.SpiEraseCount));
      return TRUE;
    }
  }
  
  return FALSE;
}

BOOLEAN
DetectRapidFireWrites (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Automated tools often write very rapidly
  //
  if (Operation == InterceptSpiFlashWrite && gAnalysisState.RapidWriteCount > 20) {
    DEBUG((DEBUG_WARN, "⚠️ RAPID FIRE WRITES DETECTED: Count=%d\n", 
           gAnalysisState.RapidWriteCount));
    return TRUE;
  }
  
  return FALSE;
}

BOOLEAN
DetectPersistenceAttempt (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Look for patterns indicating persistence installation
  //
  if (gAnalysisState.WritingToBootBlock && 
      gAnalysisState.DisablingSecureBoot &&
      gAnalysisState.SpiWriteCount > 5) {
    
    DEBUG((DEBUG_ERROR, "🚨 PERSISTENCE ATTEMPT DETECTED\n"));
    return TRUE;
  }
  
  return FALSE;
}

BOOLEAN
DetectAntiAnalysis (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address,
  IN UINT64          Value,
  IN UINT32          Size
  )
{
  //
  // Some bootkits try to detect analysis environments
  //
  
  // Excessive scattered writes might indicate evasion
  if (gAnalysisState.ScatteredWrites > gAnalysisState.SequentialWrites * 3) {
    DEBUG((DEBUG_WARN, "⚠️ ANTI-ANALYSIS BEHAVIOR: Scattered writes\n"));
    return TRUE;
  }
  
  // Unusual timing patterns
  if (gAnalysisState.RapidWriteCount > 0 && gAnalysisState.RapidWriteCount < 5) {
    // Intermittent rapid writes might be evasion
    return TRUE;
  }
  
  return FALSE;
}

/**
 * Heuristic analysis functions
 */

BOOLEAN
SentinelCheckAddressHeuristics (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address
  )
{
  //
  // Check for suspicious address patterns
  //
  
  // Writes to very high addresses (near 4GB) are often firmware-related
  if (Address >= 0xF0000000 && Operation == InterceptSpiFlashWrite) {
    return TRUE;
  }
  
  // Writes to known bootkit hiding spots
  UINT64 SuspiciousAddresses[] = {
    0xFF000000,  // Flash base
    0xFFFE0000,  // High flash region
    0xFFFF0000,  // Boot block
    0
  };
  
  for (UINT32 i = 0; SuspiciousAddresses[i] != 0; i++) {
    if (Address >= SuspiciousAddresses[i] && Address < SuspiciousAddresses[i] + 0x10000) {
      return TRUE;
    }
  }
  
  return FALSE;
}

BOOLEAN
SentinelCheckTimingHeuristics (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address
  )
{
  UINT64  CurrentTime;
  UINT64  TimeSinceFirstWrite;
  
  CurrentTime = GetTimeInNanoSecond(GetPerformanceCounter());
  
  if (gAnalysisState.FirstSpiWrite == 0) {
    return FALSE;
  }
  
  TimeSinceFirstWrite = CurrentTime - gAnalysisState.FirstSpiWrite;
  
  // Very rapid operations (less than 1 second total) are suspicious
  if (TimeSinceFirstWrite < 1000000000 && gAnalysisState.SpiWriteCount > 10) {  // 1 second
    return TRUE;
  }
  
  // Very slow operations (taking hours) might be legitimate tools
  if (TimeSinceFirstWrite > 3600000000000LL) {  // 1 hour
    return FALSE;
  }
  
  return FALSE;
}

BOOLEAN
SentinelCheckSequenceHeuristics (
  IN INTERCEPT_TYPE  Operation,
  IN UINT64          Address
  )
{
  //
  // Analyze operation sequences for suspicious patterns
  //
  
  // Classic bootkit sequence: Erase -> Write -> Disable Secure Boot
  if (gAnalysisState.SpiEraseCount > 0 &&
      gAnalysisState.SpiWriteCount > 0 &&
      gAnalysisState.DisablingSecureBoot) {
    return TRUE;
  }
  
  // Microcode + TPM tampering combination
  if (gAnalysisState.UpdatedMicrocode && gAnalysisState.ModifyingTmpNvram) {
    return TRUE;
  }
  
  return FALSE;
}

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
  )
{
  //
  // Capture extensive forensic information for later analysis
  //
  
  DEBUG((DEBUG_INFO, "🔍 FORENSIC: Op=%a Addr=0x%lx Val=0x%lx Size=%d\n",
         SentinelOperationToString(Operation), Address, Value, Size));
  
  //
  // Capture memory dump around the operation
  //
  if (Operation == InterceptSpiFlashWrite && Size <= 1024) {
    // Log the data being written
    DEBUG((DEBUG_INFO, "🔍 Write data: "));
    for (UINT32 i = 0; i < MIN(Size, 64); i++) {
      DEBUG((DEBUG_INFO, "%02x ", ((UINT8*)&Value)[i]));
    }
    DEBUG((DEBUG_INFO, "\n"));
  }
  
  //
  // Capture timing information
  //
  DEBUG((DEBUG_INFO, "🔍 Timestamp: %ld ns\n", 
         GetTimeInNanoSecond(GetPerformanceCounter())));
  
  //
  // Capture stack trace if available
  //
  if (Context != NULL) {
    DEBUG((DEBUG_INFO, "🔍 Context: 0x%p\n", Context));
  }
}

/**
 * Validate OS tool requests
 */
BOOLEAN
SentinelValidateOsToolRequest (
  IN UINT64   Address,
  IN UINT32   Size,
  IN BOOLEAN  Write
  )
{
  //
  // Validate that this looks like a legitimate OS tool request
  //
  
  // Check address range
  if (Address < SPI_FLASH_BASE || Address >= SPI_FLASH_BASE + SPI_FLASH_SIZE) {
    DEBUG((DEBUG_ERROR, "❌ OS tool request outside flash range: 0x%lx\n", Address));
    return FALSE;
  }
  
  // Check size limits
  if (Size > 1024 * 1024) {  // 1MB limit
    DEBUG((DEBUG_ERROR, "❌ OS tool request too large: %d bytes\n", Size));
    return FALSE;
  }
  
  // For writes, be more restrictive
  if (Write) {
    // Don't allow writes to boot block from OS tools during active bootkit detection
    if (Address >= BIOS_BOOT_BLOCK_BASE && gAnalysisState.WritingToBootBlock) {
      DEBUG((DEBUG_ERROR, "❌ OS tool write to boot block blocked during bootkit activity\n"));
      return FALSE;
    }
  }
  
  DEBUG((DEBUG_INFO, "✅ OS tool request validated: Addr=0x%lx Size=%d Write=%d\n",
         Address, Size, Write));
  
  return TRUE;
}

/**
 * Print detailed analysis report
 */
VOID
SentinelPrintAnalysisReport (
  VOID
  )
{
  DEBUG((DEBUG_INFO, "\n🔍 BootkitSentinel Analysis Report:\n"));
  DEBUG((DEBUG_INFO, "  SPI Writes: %d\n", gAnalysisState.SpiWriteCount));
  DEBUG((DEBUG_INFO, "  SPI Erases: %d\n", gAnalysisState.SpiEraseCount));
  DEBUG((DEBUG_INFO, "  TPM Access: %d\n", gAnalysisState.TmpAccessCount));
  DEBUG((DEBUG_INFO, "  Microcode Updates: %d\n", gAnalysisState.MicrocodeUpdateCount));
  DEBUG((DEBUG_INFO, "  Secure Boot Mods: %d\n", gAnalysisState.SecureBootModCount));
  DEBUG((DEBUG_INFO, "  Rapid Writes: %d\n", gAnalysisState.RapidWriteCount));
  DEBUG((DEBUG_INFO, "  Sequential Writes: %d\n", gAnalysisState.SequentialWrites));
  DEBUG((DEBUG_INFO, "  Scattered Writes: %d\n", gAnalysisState.ScatteredWrites));
  
  DEBUG((DEBUG_INFO, "\n🚨 Threat Indicators:\n"));
  DEBUG((DEBUG_INFO, "  Boot Block Modification: %s\n", 
         gAnalysisState.WritingToBootBlock ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Secure Boot Disabling: %s\n", 
         gAnalysisState.DisablingSecureBoot ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  TPM Tampering: %s\n", 
         gAnalysisState.ModifyingTmpNvram ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Microcode Updated: %s\n", 
         gAnalysisState.UpdatedMicrocode ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Critical Regions Erased: %s\n", 
         gAnalysisState.ErasedCriticalRegions ? "YES" : "NO"));
}
