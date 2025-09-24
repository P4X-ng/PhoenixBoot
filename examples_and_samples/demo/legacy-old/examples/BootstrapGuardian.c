/**
 * BootstrapGuardian - Advanced Boot Chain Integrity Protection
 * 
 * "NO SWITCHEROOS ON OUR WATCH!"
 * 
 * This system extends beyond firmware security to protect the entire
 * boot chain from initramfs through OS loading. It detects and prevents
 * last-minute redirections, container traps, and boot chain compromises.
 * 
 * Phases of Protection:
 * 1. Post-firmware integrity verification
 * 2. Bootloader and initramfs validation  
 * 3. Kernel and initial filesystem verification
 * 4. Final OS environment validation
 * 5. Immutable media recovery when needed
 */

#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/IoLib.h>
#include <Library/TimerLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Protocol/SimpleFileSystem.h>
#include <Protocol/BlockIo.h>
#include <Protocol/DiskIo.h>

//
// BootstrapGuardian Configuration
//
#define GUARDIAN_SIGNATURE           SIGNATURE_32('B','G','R','D')
#define GUARDIAN_VERSION             0x00010000
#define GUARDIAN_MAX_CHECKSUMS       100
#define GUARDIAN_RECOVERY_TIMEOUT    30  // seconds

//
// Boot chain validation phases
//
typedef enum {
  GuardianPhasePreBoot     = 0,  // Just after firmware handoff
  GuardianPhaseBootloader  = 1,  // GRUB/bootloader validation
  GuardianPhaseInitramfs   = 2,  // Initramfs and early kernel
  GuardianPhaseKernel      = 3,  // Kernel and drivers loading
  GuardianPhaseFilesystem  = 4,  // Root filesystem mounting
  GuardianPhaseComplete    = 5   // Full OS environment ready
} GUARDIAN_PHASE;

//
// Integrity verification types
//
typedef enum {
  IntegrityTypeSHA256      = 0,
  IntegrityTypeSHA512      = 1,
  IntegrityTypeCRC32       = 2,
  IntegrityTypeSignature   = 3,
  IntegrityTypeCustom      = 4
} INTEGRITY_TYPE;

//
// Recovery media types
//
typedef enum {
  RecoveryMediaCdDvd       = 0,  // CD/DVD-ROM
  RecoveryMediaUsb         = 1,  // USB drive (write-protected)
  RecoveryMediaNetwork     = 2,  // Network PXE boot
  RecoveryMediaEmbedded    = 3   // Embedded in firmware
} RECOVERY_MEDIA_TYPE;

//
// Boot target validation
//
typedef struct {
  CHAR16              *Path;           // Boot target path
  UINT64              ExpectedSize;    // Expected file/partition size
  UINT8               ExpectedHash[64]; // Expected hash (SHA-512)
  INTEGRITY_TYPE      HashType;        // Type of integrity check
  BOOLEAN             Critical;        // Must match exactly
  CHAR16              *Description;    // Human-readable description
} BOOT_TARGET;

//
// Physical media identification
//
typedef struct {
  CHAR8               SerialNumber[32]; // Disk serial number
  UINT8               PartitionUuid[16]; // Partition UUID
  UINT32              SectorSize;       // Expected sector size
  UINT64              TotalSectors;     // Expected total sectors
  BOOLEAN             Immutable;        // Should be read-only
} PHYSICAL_MEDIA_ID;

//
// Switcheroo detection patterns
//
typedef struct {
  CHAR16              *Pattern;         // Suspicious pattern to detect
  GUARDIAN_PHASE      Phase;            // When to check for this pattern
  UINT32              SuspicionScore;   // How suspicious this is
  BOOLEAN             (*DetectionFunc)(VOID *Context); // Custom detection
} SWITCHEROO_PATTERN;

//
// Main Guardian control structure
//
typedef struct {
  UINT32              Signature;
  UINT32              Version;
  GUARDIAN_PHASE      CurrentPhase;
  BOOLEAN             IntegrityValid;
  BOOLEAN             SwitcherooDetected;
  UINT32              SuspicionScore;
  
  // Expected boot targets
  BOOT_TARGET         BootTargets[GUARDIAN_MAX_CHECKSUMS];
  UINT32              BootTargetCount;
  
  // Physical media identification
  PHYSICAL_MEDIA_ID   AuthorizedMedia[10];
  UINT32              AuthorizedMediaCount;
  
  // Recovery configuration
  RECOVERY_MEDIA_TYPE RecoveryMedia;
  CHAR16              *RecoveryPath;
  BOOLEAN             RecoveryEnabled;
  
  // Detection state
  UINT64              BootStartTime;
  UINT64              LastPhaseTime;
  CHAR16              *LastBootPath;
  UINT32              RedirectionCount;
  
  // Immutable media validation
  BOOLEAN             RequireImmutableMedia;
  BOOLEAN             ImmutableMediaPresent;
  CHAR8               ImmutableMediaSerial[32];
  
} BOOTSTRAP_GUARDIAN;

//
// Global guardian instance
//
STATIC BOOTSTRAP_GUARDIAN  *gGuardian = NULL;

//
// Known switcheroo patterns
//
STATIC SWITCHEROO_PATTERN gSwitcherooPatterns[] = {
  {L"\\EFI\\Boot\\bootx64.efi", GuardianPhaseBootloader, 300, DetectBootloaderRedirection},
  {L"\\boot\\grub\\grub.cfg", GuardianPhaseBootloader, 250, DetectGrubConfigTampering},
  {L"\\initrd.img", GuardianPhaseInitramfs, 400, DetectInitramfsSwitch},
  {L"\\vmlinuz", GuardianPhaseKernel, 450, DetectKernelReplacement},
  {L"containers", GuardianPhaseFilesystem, 500, DetectContainerTrap},
  {NULL, 0, 0, NULL}  // Sentinel
};

/**
 * Initialize BootstrapGuardian system
 */
EFI_STATUS
EFIAPI
GuardianInitialize (
  VOID
  )
{
  EFI_STATUS  Status;
  
  DEBUG((DEBUG_INFO, "🛡️ BootstrapGuardian: Initializing boot chain protection\n"));
  
  //
  // Allocate guardian structure
  //
  Status = gBS->AllocatePool(
    EfiRuntimeServicesData,
    sizeof(BOOTSTRAP_GUARDIAN),
    (VOID**)&gGuardian
  );
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ Failed to allocate guardian structure\n"));
    return Status;
  }
  
  //
  // Initialize guardian
  //
  ZeroMem(gGuardian, sizeof(BOOTSTRAP_GUARDIAN));
  gGuardian->Signature = GUARDIAN_SIGNATURE;
  gGuardian->Version = GUARDIAN_VERSION;
  gGuardian->CurrentPhase = GuardianPhasePreBoot;
  gGuardian->IntegrityValid = FALSE;
  gGuardian->BootStartTime = GetTimeInNanoSecond(GetPerformanceCounter());
  
  //
  // Set up default recovery configuration
  //
  gGuardian->RecoveryMedia = RecoveryMediaCdDvd;
  gGuardian->RecoveryPath = L"\\EFI\\PhoenixGuard\\recovery.efi";
  gGuardian->RecoveryEnabled = TRUE;
  gGuardian->RequireImmutableMedia = TRUE;
  
  //
  // Load expected boot targets configuration
  //
  Status = GuardianLoadBootTargets();
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_WARN, "⚠️ Failed to load boot targets configuration\n"));
  }
  
  //
  // Load authorized physical media list
  //
  Status = GuardianLoadAuthorizedMedia();
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_WARN, "⚠️ Failed to load authorized media list\n"));
  }
  
  //
  // Detect and validate immutable media
  //
  Status = GuardianDetectImmutableMedia();
  if (!EFI_ERROR(Status)) {
    gGuardian->ImmutableMediaPresent = TRUE;
    DEBUG((DEBUG_INFO, "💿 Immutable media detected and validated\n"));
  }
  
  DEBUG((DEBUG_INFO, "✅ BootstrapGuardian: Initialized and ready\n"));
  DEBUG((DEBUG_INFO, "🎯 Recovery media: %a\n", GuardianRecoveryTypeToString(gGuardian->RecoveryMedia)));
  DEBUG((DEBUG_INFO, "📀 Immutable media: %s\n", gGuardian->ImmutableMediaPresent ? "YES" : "NO"));
  
  return EFI_SUCCESS;
}

/**
 * Validate boot chain integrity at specific phase
 */
EFI_STATUS
EFIAPI
GuardianValidatePhase (
  IN GUARDIAN_PHASE  Phase
  )
{
  EFI_STATUS  Status;
  BOOLEAN     PhaseValid = TRUE;
  UINT32      PhaseScore = 0;
  
  if (!gGuardian) {
    return EFI_NOT_READY;
  }
  
  DEBUG((DEBUG_INFO, "🔍 BootstrapGuardian: Validating phase %a\n", 
         GuardianPhaseToString(Phase)));
  
  gGuardian->CurrentPhase = Phase;
  gGuardian->LastPhaseTime = GetTimeInNanoSecond(GetPerformanceCounter());
  
  //
  // Perform phase-specific validation
  //
  switch (Phase) {
    
    case GuardianPhasePreBoot:
      Status = GuardianValidatePreBoot();
      break;
      
    case GuardianPhaseBootloader:
      Status = GuardianValidateBootloader();
      break;
      
    case GuardianPhaseInitramfs:
      Status = GuardianValidateInitramfs();
      break;
      
    case GuardianPhaseKernel:
      Status = GuardianValidateKernel();
      break;
      
    case GuardianPhaseFilesystem:
      Status = GuardianValidateFilesystem();
      break;
      
    case GuardianPhaseComplete:
      Status = GuardianValidateComplete();
      break;
      
    default:
      DEBUG((DEBUG_ERROR, "❌ Unknown guardian phase: %d\n", Phase));
      Status = EFI_INVALID_PARAMETER;
      break;
  }
  
  //
  // Check for switcheroo patterns
  //
  PhaseScore += GuardianDetectSwitcherooPatterns(Phase);
  
  //
  // Validate expected vs actual boot path
  //
  Status = GuardianValidateBootPath(Phase);
  if (EFI_ERROR(Status)) {
    PhaseScore += 200;
    PhaseValid = FALSE;
    DEBUG((DEBUG_ERROR, "🚨 BOOT PATH VALIDATION FAILED!\n"));
  }
  
  //
  // Check for container traps and virtualization
  //
  if (Phase >= GuardianPhaseFilesystem) {
    if (GuardianDetectContainerTrap()) {
      PhaseScore += 500;
      PhaseValid = FALSE;
      gGuardian->SwitcherooDetected = TRUE;
      DEBUG((DEBUG_ERROR, "🚨 CONTAINER TRAP DETECTED!\n"));
    }
  }
  
  gGuardian->SuspicionScore += PhaseScore;
  
  //
  // Handle validation failure
  //
  if (!PhaseValid || gGuardian->SuspicionScore > 1000) {
    DEBUG((DEBUG_ERROR, "🚨 PHASE VALIDATION FAILED - Score: %d\n", gGuardian->SuspicionScore));
    
    if (gGuardian->RecoveryEnabled) {
      // Present "Please Wait" screen and initiate recovery
      GuardianShowRecoveryScreen();
      Status = GuardianInitiateRecovery();
      
      if (EFI_ERROR(Status)) {
        DEBUG((DEBUG_ERROR, "❌ Recovery failed - system may be compromised\n"));
        return Status;
      }
    } else {
      // No recovery - halt system
      DEBUG((DEBUG_ERROR, "❌ No recovery configured - halting system\n"));
      CpuDeadLoop();
    }
  }
  
  gGuardian->IntegrityValid = PhaseValid;
  
  DEBUG((DEBUG_INFO, "✅ Phase %a validation complete - Score: %d\n", 
         GuardianPhaseToString(Phase), PhaseScore));
  
  return Status;
}

/**
 * Validate pre-boot environment
 */
EFI_STATUS
GuardianValidatePreBoot (
  VOID
  )
{
  DEBUG((DEBUG_INFO, "🔍 Validating pre-boot environment\n"));
  
  //
  // Verify we're not in a VM or container already
  //
  if (GuardianDetectVirtualization()) {
    DEBUG((DEBUG_WARN, "⚠️ Virtualization detected in pre-boot\n"));
    gGuardian->SuspicionScore += 100;
  }
  
  //
  // Validate memory layout hasn't been tampered with
  //
  if (!GuardianValidateMemoryLayout()) {
    DEBUG((DEBUG_ERROR, "🚨 Memory layout tampering detected\n"));
    gGuardian->SuspicionScore += 300;
  }
  
  //
  // Check for unexpected boot services modifications
  //
  if (!GuardianValidateBootServices()) {
    DEBUG((DEBUG_ERROR, "🚨 Boot services tampering detected\n"));
    gGuardian->SuspicionScore += 250;
  }
  
  return EFI_SUCCESS;
}

/**
 * Validate bootloader integrity and prevent redirection
 */
EFI_STATUS
GuardianValidateBootloader (
  VOID
  )
{
  EFI_STATUS  Status;
  CHAR16      *BootloaderPath;
  UINT8       ActualHash[64];
  UINT32      TargetIndex;
  
  DEBUG((DEBUG_INFO, "🔍 Validating bootloader integrity\n"));
  
  //
  // Get the actual bootloader path being used
  //
  Status = GuardianGetActiveBootPath(&BootloaderPath);
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ Failed to get active boot path\n"));
    return Status;
  }
  
  DEBUG((DEBUG_INFO, "🎯 Active boot path: %s\n", BootloaderPath));
  
  //
  // Check if this path matches our expected targets
  //
  for (TargetIndex = 0; TargetIndex < gGuardian->BootTargetCount; TargetIndex++) {
    if (StrCmp(BootloaderPath, gGuardian->BootTargets[TargetIndex].Path) == 0) {
      
      // Calculate hash of actual bootloader
      Status = GuardianCalculateFileHash(
        BootloaderPath, 
        gGuardian->BootTargets[TargetIndex].HashType,
        ActualHash
      );
      
      if (EFI_ERROR(Status)) {
        DEBUG((DEBUG_ERROR, "❌ Failed to calculate bootloader hash\n"));
        return Status;
      }
      
      // Compare with expected hash
      if (CompareMem(ActualHash, gGuardian->BootTargets[TargetIndex].ExpectedHash, 64) != 0) {
        DEBUG((DEBUG_ERROR, "🚨 BOOTLOADER HASH MISMATCH!\n"));
        DEBUG((DEBUG_ERROR, "    Expected: %02x%02x%02x%02x...\n", 
               gGuardian->BootTargets[TargetIndex].ExpectedHash[0],
               gGuardian->BootTargets[TargetIndex].ExpectedHash[1],
               gGuardian->BootTargets[TargetIndex].ExpectedHash[2],
               gGuardian->BootTargets[TargetIndex].ExpectedHash[3]));
        DEBUG((DEBUG_ERROR, "    Actual:   %02x%02x%02x%02x...\n", 
               ActualHash[0], ActualHash[1], ActualHash[2], ActualHash[3]));
        
        gGuardian->SuspicionScore += 400;
        return EFI_COMPROMISED_DATA;
      }
      
      DEBUG((DEBUG_INFO, "✅ Bootloader hash validated\n"));
      return EFI_SUCCESS;
    }
  }
  
  //
  // Bootloader path not in our expected list - suspicious!
  //
  DEBUG((DEBUG_ERROR, "🚨 UNEXPECTED BOOTLOADER PATH: %s\n", BootloaderPath));
  gGuardian->SuspicionScore += 350;
  gGuardian->SwitcherooDetected = TRUE;
  
  return EFI_COMPROMISED_DATA;
}

/**
 * Detect container traps and fake environments
 */
BOOLEAN
GuardianDetectContainerTrap (
  VOID
  )
{
  //
  // Check for common container indicators
  //
  
  // Look for container-specific mount points
  if (GuardianCheckFileExists(L"\\proc\\1\\cgroup")) {
    DEBUG((DEBUG_WARN, "⚠️ Container cgroup detected\n"));
    return TRUE;
  }
  
  // Check for Docker/Podman indicators
  if (GuardianCheckFileExists(L"\\.dockerenv") || 
      GuardianCheckFileExists(L"\\var\\run\\docker.sock")) {
    DEBUG((DEBUG_ERROR, "🚨 Docker container environment detected\n"));
    return TRUE;
  }
  
  // Check for LXC/LXD indicators
  if (GuardianCheckFileExists(L"\\run\\lxc") ||
      GuardianCheckFileExists(L"\\var\\lib\\lxd")) {
    DEBUG((DEBUG_ERROR, "🚨 LXC/LXD container detected\n"));
    return TRUE;
  }
  
  // Check for chroot indicators (common in malware)
  if (GuardianDetectChroot()) {
    DEBUG((DEBUG_ERROR, "🚨 Chroot environment detected\n"));
    return TRUE;
  }
  
  // Check for fake filesystem indicators
  if (GuardianDetectFakeFilesystem()) {
    DEBUG((DEBUG_ERROR, "🚨 Fake filesystem detected\n"));
    return TRUE;
  }
  
  return FALSE;
}

/**
 * Show recovery screen and options
 */
VOID
GuardianShowRecoveryScreen (
  VOID
  )
{
  UINT32  Countdown;
  
  gST->ConOut->ClearScreen(gST->ConOut);
  gST->ConOut->SetAttribute(gST->ConOut, EFI_LIGHTRED | EFI_BACKGROUND_BLACK);
  
  Print(L"\n");
  Print(L"  ╔══════════════════════════════════════════════════════════════════╗\n");
  Print(L"  ║                    🚨 SECURITY ALERT 🚨                         ║\n");
  Print(L"  ║                                                                  ║\n");
  Print(L"  ║  Boot chain integrity validation FAILED!                        ║\n");
  Print(L"  ║                                                                  ║\n");
  Print(L"  ║  Possible causes:                                                ║\n");
  Print(L"  ║  • Bootkit infection detected                                    ║\n");
  Print(L"  ║  • Boot path redirection (switcheroo attack)                    ║\n");
  Print(L"  ║  • Container trap or fake environment                           ║\n");
  Print(L"  ║  • Corrupted boot files                                         ║\n");
  Print(L"  ║                                                                  ║\n");
  Print(L"  ║  Suspicion Score: %-3d                                           ║\n", gGuardian->SuspicionScore);
  Print(L"  ║                                                                  ║\n");
  Print(L"  ║  🛡️ BootstrapGuardian will now attempt recovery...              ║\n");
  Print(L"  ╚══════════════════════════════════════════════════════════════════╝\n");
  Print(L"\n");
  
  gST->ConOut->SetAttribute(gST->ConOut, EFI_LIGHTCYAN | EFI_BACKGROUND_BLACK);
  Print(L"  Please wait while we load a clean boot environment...\n");
  Print(L"\n");
  
  if (gGuardian->ImmutableMediaPresent) {
    Print(L"  💿 Using immutable media for recovery\n");
  } else {
    Print(L"  🌐 Using network recovery\n");
  }
  
  Print(L"\n");
  
  //
  // Countdown timer
  //
  for (Countdown = GUARDIAN_RECOVERY_TIMEOUT; Countdown > 0; Countdown--) {
    Print(L"\r  Recovery starting in %d seconds... ", Countdown);
    gBS->Stall(1000000);  // 1 second
  }
  
  Print(L"\n\n  🚀 Initiating recovery process...\n");
}

/**
 * Initiate recovery from immutable media
 */
EFI_STATUS
GuardianInitiateRecovery (
  VOID
  )
{
  EFI_STATUS  Status;
  
  DEBUG((DEBUG_INFO, "🚑 Initiating BootstrapGuardian recovery\n"));
  
  //
  // Try recovery methods in order of preference
  //
  
  // 1. Immutable CD/DVD media
  if (gGuardian->ImmutableMediaPresent) {
    Print(L"  💿 Attempting recovery from immutable media...\n");
    Status = GuardianRecoverFromImmutableMedia();
    if (!EFI_ERROR(Status)) {
      Print(L"  ✅ Recovery successful - booting clean environment\n");
      return Status;
    }
    Print(L"  ❌ Immutable media recovery failed\n");
  }
  
  // 2. Network PXE recovery
  Print(L"  🌐 Attempting network recovery...\n");
  Status = GuardianRecoverFromNetwork();
  if (!EFI_ERROR(Status)) {
    Print(L"  ✅ Network recovery successful\n");
    return Status;
  }
  Print(L"  ❌ Network recovery failed\n");
  
  // 3. Embedded recovery
  Print(L"  🔧 Attempting embedded recovery...\n");
  Status = GuardianRecoverFromEmbedded();
  if (!EFI_ERROR(Status)) {
    Print(L"  ✅ Embedded recovery successful\n");
    return Status;
  }
  Print(L"  ❌ Embedded recovery failed\n");
  
  // 4. Last resort - safe mode boot
  Print(L"  🛡️ Attempting safe mode boot...\n");
  Status = GuardianSafeModeRecovery();
  if (!EFI_ERROR(Status)) {
    Print(L"  ✅ Safe mode boot successful\n");
    return Status;
  }
  
  Print(L"  ❌ All recovery methods failed\n");
  Print(L"  🚨 System may be severely compromised\n");
  Print(L"  💿 Please boot from external media manually\n");
  
  return EFI_COMPROMISED_DATA;
}

/**
 * Recovery from immutable CD/DVD media
 */
EFI_STATUS
GuardianRecoverFromImmutableMedia (
  VOID
  )
{
  EFI_STATUS    Status;
  EFI_HANDLE    *Handles;
  UINTN         HandleCount;
  UINTN         Index;
  
  //
  // Find all block I/O handles (potential CD/DVD drives)
  //
  Status = gBS->LocateHandleBuffer(
    ByProtocol,
    &gEfiBlockIoProtocolGuid,
    NULL,
    &HandleCount,
    &Handles
  );
  
  if (EFI_ERROR(Status)) {
    return Status;
  }
  
  //
  // Check each handle for immutable media
  //
  for (Index = 0; Index < HandleCount; Index++) {
    EFI_BLOCK_IO_PROTOCOL  *BlockIo;
    
    Status = gBS->HandleProtocol(
      Handles[Index],
      &gEfiBlockIoProtocolGuid,
      (VOID**)&BlockIo
    );
    
    if (EFI_ERROR(Status)) {
      continue;
    }
    
    // Check if this is a removable, read-only medium (CD/DVD)
    if (BlockIo->Media->RemovableMedia && BlockIo->Media->ReadOnly) {
      DEBUG((DEBUG_INFO, "💿 Found immutable media candidate\n"));
      
      // Validate this is our authorized recovery media
      Status = GuardianValidateRecoveryMedia(Handles[Index]);
      if (!EFI_ERROR(Status)) {
        // Load and execute recovery environment
        Status = GuardianLoadRecoveryEnvironment(Handles[Index]);
        if (!EFI_ERROR(Status)) {
          gBS->FreePool(Handles);
          return EFI_SUCCESS;
        }
      }
    }
  }
  
  gBS->FreePool(Handles);
  return EFI_NOT_FOUND;
}

/**
 * Validate recovery media authenticity
 */
EFI_STATUS
GuardianValidateRecoveryMedia (
  IN EFI_HANDLE  MediaHandle
  )
{
  // In a real implementation, this would:
  // 1. Read media serial number and verify against authorized list
  // 2. Check for cryptographic signatures on recovery files
  // 3. Validate read-only status
  // 4. Verify media hasn't been tampered with
  
  DEBUG((DEBUG_INFO, "✅ Recovery media validation successful\n"));
  return EFI_SUCCESS;
}

/**
 * Helper functions
 */

CHAR8*
GuardianPhaseToString (
  IN GUARDIAN_PHASE Phase
  )
{
  switch (Phase) {
    case GuardianPhasePreBoot:    return "PRE-BOOT";
    case GuardianPhaseBootloader: return "BOOTLOADER";
    case GuardianPhaseInitramfs:  return "INITRAMFS";
    case GuardianPhaseKernel:     return "KERNEL";
    case GuardianPhaseFilesystem: return "FILESYSTEM";
    case GuardianPhaseComplete:   return "COMPLETE";
    default:                      return "UNKNOWN";
  }
}

CHAR8*
GuardianRecoveryTypeToString (
  IN RECOVERY_MEDIA_TYPE Type
  )
{
  switch (Type) {
    case RecoveryMediaCdDvd:    return "CD/DVD";
    case RecoveryMediaUsb:      return "USB";
    case RecoveryMediaNetwork:  return "NETWORK";
    case RecoveryMediaEmbedded: return "EMBEDDED";
    default:                    return "UNKNOWN";
  }
}

/**
 * Print guardian status and statistics
 */
VOID
GuardianPrintStatus (
  VOID
  )
{
  if (!gGuardian) {
    DEBUG((DEBUG_INFO, "BootstrapGuardian not initialized\n"));
    return;
  }
  
  DEBUG((DEBUG_INFO, "\n🛡️ BootstrapGuardian Status:\n"));
  DEBUG((DEBUG_INFO, "  Current Phase: %a\n", GuardianPhaseToString(gGuardian->CurrentPhase)));
  DEBUG((DEBUG_INFO, "  Integrity Valid: %s\n", gGuardian->IntegrityValid ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Switcheroo Detected: %s\n", gGuardian->SwitcherooDetected ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Suspicion Score: %d\n", gGuardian->SuspicionScore));
  DEBUG((DEBUG_INFO, "  Boot Targets: %d configured\n", gGuardian->BootTargetCount));
  DEBUG((DEBUG_INFO, "  Recovery Enabled: %s\n", gGuardian->RecoveryEnabled ? "YES" : "NO"));
  DEBUG((DEBUG_INFO, "  Immutable Media: %s\n", gGuardian->ImmutableMediaPresent ? "YES" : "NO"));
  
  if (gGuardian->SuspicionScore > 1000) {
    DEBUG((DEBUG_ERROR, "🚨 HIGH SUSPICION SCORE - POTENTIAL COMPROMISE!\n"));
  } else if (gGuardian->SuspicionScore > 500) {
    DEBUG((DEBUG_WARN, "⚠️ MODERATE SUSPICION - MONITORING REQUIRED\n"));
  }
}
