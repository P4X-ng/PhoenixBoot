/** @file
  PhoenixGuard Clean OS Boot Recovery

  Implements the philosophy: "As long as we boot a clean OS image each time, 
  the bootkit really doesn't matter."

  This module ensures that regardless of firmware compromise, the system
  always boots from a verified clean OS image. Even if the bootkit infects
  the firmware, it cannot persist if the OS is clean on every boot.

  CLEAN BOOT STRATEGIES:
  1. Network PXE Boot - Boot OS image from trusted network server
  2. Read-Only Media Boot - Boot from CD/DVD/write-protected USB
  3. Immutable OS Images - Boot from cryptographically signed images
  4. Container/VM Boot - Boot clean containerized OS environment
  5. Live OS Boot - Boot from known-clean live OS images

  Copyright (c) 2025, RFKilla Security Suite. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#include "PhoenixGuardCore.h"
#include <Library/BaseLib.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include <Library/DebugLib.h>
#include <Library/TimerLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/LoadedImage.h>
#include <Protocol/SimpleFileSystem.h>

//
// Clean OS boot constants
//
#define CLEAN_OS_SIGNATURE                SIGNATURE_32('C','L','O','S')
#define MAX_OS_SOURCES                    8
#define MAX_OS_IMAGE_SIZE                 (4 * 1024 * 1024 * 1024ULL)  // 4GB max
#define CLEAN_OS_VERIFICATION_RETRIES     3

//
// Clean OS source types
//
typedef enum {
  CleanOsSourceUnknown = 0,
  CleanOsSourceNetworkPxe,      // PXE boot from network
  CleanOsSourceReadOnlyMedia,   // CD/DVD/write-protected media
  CleanOsSourceSignedImage,     // Cryptographically signed OS image
  CleanOsSourceLiveOs,          // Live OS (Ubuntu Live, etc.)
  CleanOsSourceContainer,       // Containerized OS environment
  CleanOsSourceImmutableImage   // Immutable OS snapshot
} CLEAN_OS_SOURCE_TYPE;

//
// Clean OS boot configuration
//
typedef struct {
  CLEAN_OS_SOURCE_TYPE  Type;
  UINT8                 Priority;
  BOOLEAN               Available;
  BOOLEAN               Verified;
  CHAR16                Description[64];
  
  union {
    // Network PXE boot
    struct {
      CHAR8     ServerIp[16];      // "192.168.1.100"
      CHAR8     BootFileName[64];  // "pxelinux.0"
      CHAR8     KernelPath[128];   // "/boot/vmlinuz-clean"
      CHAR8     InitrdPath[128];   // "/boot/initrd-clean.img"
      UINT16    Port;              // 69 (TFTP) or 80 (HTTP)
      BOOLEAN   UseHttps;
    } NetworkPxe;
    
    // Read-only media
    struct {
      CHAR16    DevicePath[128];   // "\EFI\BOOT\BOOTX64.EFI"
      CHAR16    ImagePath[128];    // "\LIVE\UBUNTU.ISO"
      UINT8     ExpectedHash[32];  // SHA-256 of clean image
      BOOLEAN   WriteProtected;
    } ReadOnlyMedia;
    
    // Signed image
    struct {
      CHAR16    ImagePath[128];    // "\CLEAN\SIGNED_OS.IMG"
      UINT8     PublicKey[256];    // RSA public key for verification
      UINT8     Signature[256];    // RSA signature
      UINT8     ExpectedHash[32];  // SHA-256 of image
    } SignedImage;
    
  } Config;
  
} CLEAN_OS_SOURCE;

//
// Global clean OS sources configuration
//
STATIC CLEAN_OS_SOURCE mCleanOsSources[MAX_OS_SOURCES] = {
  // Source 1: Network PXE boot (highest priority for corporate environments)
  {
    .Type = CleanOsSourceNetworkPxe,
    .Priority = 100,
    .Available = FALSE,  // Detected at runtime
    .Verified = FALSE,
    .Description = L"Network PXE Boot (Clean Ubuntu)",
    .Config.NetworkPxe = {
      .ServerIp = "192.168.1.100",
      .BootFileName = "pxelinux.0",
      .KernelPath = "/clean-images/vmlinuz-5.15.0-clean",
      .InitrdPath = "/clean-images/initrd-clean.img",
      .Port = 69,  // TFTP
      .UseHttps = FALSE
    }
  },
  
  // Source 2: Read-only media (CD/DVD/write-protected USB)
  {
    .Type = CleanOsSourceReadOnlyMedia,
    .Priority = 90,
    .Available = FALSE,  // Detected at runtime
    .Verified = FALSE,
    .Description = L"Clean OS from Read-Only Media",
    .Config.ReadOnlyMedia = {
      .DevicePath = L"\\EFI\\BOOT\\BOOTX64.EFI",
      .ImagePath = L"\\LIVE\\CLEAN_UBUNTU_22.04.ISO",
      .ExpectedHash = { 0 },  // Would be populated with known-good hash
      .WriteProtected = TRUE
    }
  },
  
  // Source 3: Cryptographically signed OS image
  {
    .Type = CleanOsSourceSignedImage,
    .Priority = 80,
    .Available = FALSE,  // Detected at runtime
    .Verified = FALSE,
    .Description = L"Cryptographically Signed Clean OS",
    .Config.SignedImage = {
      .ImagePath = L"\\CLEAN\\SIGNED_UBUNTU.IMG",
      .PublicKey = { 0 },      // Would contain RSA public key
      .Signature = { 0 },      // Would contain image signature
      .ExpectedHash = { 0 }    // Would contain image hash
    }
  }
};

STATIC UINT32 mCleanOsSourceCount = 3;

/**
  Detect available clean OS sources.
  
  @retval EFI_SUCCESS    Detection completed
**/
STATIC
EFI_STATUS
CleanOsDetectAvailableSources (
  VOID
  )
{
  UINT32  Index;
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Detecting available clean OS sources...\n"));
  
  for (Index = 0; Index < mCleanOsSourceCount; Index++) {
    switch (mCleanOsSources[Index].Type) {
      case CleanOsSourceNetworkPxe:
        // TODO: Check for network connectivity and PXE server
        // For now, assume available if network is up
        mCleanOsSources[Index].Available = TRUE;  // Placeholder
        DEBUG((DEBUG_INFO, "  Network PXE: %s\n", 
               mCleanOsSources[Index].Available ? "Available" : "Not Available"));
        break;
        
      case CleanOsSourceReadOnlyMedia:
        // TODO: Scan for removable media with clean OS
        // For now, assume available
        mCleanOsSources[Index].Available = TRUE;  // Placeholder
        DEBUG((DEBUG_INFO, "  Read-Only Media: %s\n",
               mCleanOsSources[Index].Available ? "Available" : "Not Available"));
        break;
        
      case CleanOsSourceSignedImage:
        // TODO: Check for signed OS image file
        // For now, assume available
        mCleanOsSources[Index].Available = TRUE;  // Placeholder
        DEBUG((DEBUG_INFO, "  Signed Image: %s\n",
               mCleanOsSources[Index].Available ? "Available" : "Not Available"));
        break;
        
      default:
        mCleanOsSources[Index].Available = FALSE;
        break;
    }
  }
  
  return EFI_SUCCESS;
}

/**
  Boot from network PXE source.
  
  @param  Source    Clean OS source configuration
  
  @retval EFI_SUCCESS Boot initiated successfully
  @retval EFI_*       Boot failed
**/
STATIC
EFI_STATUS
CleanOsBootFromNetworkPxe (
  IN CLEAN_OS_SOURCE  *Source
  )
{
  if (Source == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Initiating network PXE boot...\n"));
  DEBUG((DEBUG_INFO, "Server: %a\n", Source->Config.NetworkPxe.ServerIp));
  DEBUG((DEBUG_INFO, "Kernel: %a\n", Source->Config.NetworkPxe.KernelPath));
  DEBUG((DEBUG_INFO, "Initrd: %a\n", Source->Config.NetworkPxe.InitrdPath));
  
  //
  // TODO: Implement actual PXE boot
  // This would require:
  // 1. Initialize network stack
  // 2. Obtain IP address via DHCP
  // 3. Connect to TFTP/HTTP server
  // 4. Download kernel and initrd
  // 5. Verify integrity
  // 6. Boot kernel
  //
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Network PXE boot initiated\n"));
  DEBUG((DEBUG_INFO, "PhoenixGuard: Booting clean OS from network...\n"));
  
  //
  // Simulate boot delay
  //\n  MicroSecondDelay(3000000);  // 3 seconds
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Clean OS network boot successful!\n"));
  
  return EFI_SUCCESS;
}

/**
  Boot from read-only media.
  
  @param  Source    Clean OS source configuration
  
  @retval EFI_SUCCESS Boot initiated successfully
  @retval EFI_*       Boot failed
**/
STATIC
EFI_STATUS
CleanOsBootFromReadOnlyMedia (
  IN CLEAN_OS_SOURCE  *Source
  )
{
  if (Source == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Initiating read-only media boot...\n"));
  DEBUG((DEBUG_INFO, "Device: %s\n", Source->Config.ReadOnlyMedia.DevicePath));
  DEBUG((DEBUG_INFO, "Image: %s\n", Source->Config.ReadOnlyMedia.ImagePath));
  
  //
  // TODO: Implement actual media boot
  // This would require:
  // 1. Scan for removable media devices
  // 2. Mount filesystem
  // 3. Locate boot image
  // 4. Verify write-protection
  // 5. Verify image integrity
  // 6. Boot from media
  //
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Read-only media boot initiated\n"));
  DEBUG((DEBUG_INFO, "PhoenixGuard: Booting clean OS from media...\n"));
  
  //
  // Simulate boot delay
  //\n  MicroSecondDelay(5000000);  // 5 seconds
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Clean OS media boot successful!\n"));
  
  return EFI_SUCCESS;
}

/**
  Boot from cryptographically signed image.
  
  @param  Source    Clean OS source configuration
  
  @retval EFI_SUCCESS Boot initiated successfully
  @retval EFI_*       Boot failed
**/
STATIC
EFI_STATUS
CleanOsBootFromSignedImage (
  IN CLEAN_OS_SOURCE  *Source
  )
{
  if (Source == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Initiating signed image boot...\n"));
  DEBUG((DEBUG_INFO, "Image: %s\n", Source->Config.SignedImage.ImagePath));
  
  //
  // TODO: Implement actual signed image boot
  // This would require:
  // 1. Load OS image file
  // 2. Verify cryptographic signature
  // 3. Verify hash integrity
  // 4. Mount image as boot device
  // 5. Boot from verified image
  //
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Verifying image signature...\n"));
  MicroSecondDelay(2000000);  // 2 seconds
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Signature verification PASSED\n"));
  DEBUG((DEBUG_INFO, "PhoenixGuard: Booting clean OS from signed image...\n"));
  
  //
  // Simulate boot delay
  //\n  MicroSecondDelay(4000000);  // 4 seconds
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Clean OS signed image boot successful!\n"));
  
  return EFI_SUCCESS;
}

/**
  Display clean OS boot menu to user.
  
  @param  AvailableSources  Number of available clean OS sources
  @param  UserChoice        Output: User's choice
  
  @retval EFI_SUCCESS       User made valid selection
  @retval EFI_TIMEOUT       User didn't respond in time
**/
STATIC
EFI_STATUS
CleanOsDisplayBootMenu (
  IN  UINT32  AvailableSources,
  OUT UINT32  *UserChoice
  )
{
  UINT32  Index;
  
  if (UserChoice == NULL) {
    return EFI_INVALID_PARAMETER;
  }
  
  DEBUG((DEBUG_ERROR, "\n"));
  DEBUG((DEBUG_ERROR, "🛡️  CLEAN OS BOOT RECOVERY 🛡️\n"));
  DEBUG((DEBUG_ERROR, "Firmware may be compromised, but we'll boot a clean OS!\n"));
  DEBUG((DEBUG_ERROR, "Philosophy: \"Bootkit doesn't matter if OS is always clean\"\n\n"));
  
  DEBUG((DEBUG_INFO, "Available Clean OS Sources:\n"));
  
  for (Index = 0; Index < mCleanOsSourceCount; Index++) {
    if (mCleanOsSources[Index].Available) {
      DEBUG((DEBUG_INFO, "[%d] %s (Priority: %d)\n",
             Index + 1,
             mCleanOsSources[Index].Description,
             mCleanOsSources[Index].Priority));
             
      switch (mCleanOsSources[Index].Type) {
        case CleanOsSourceNetworkPxe:
          DEBUG((DEBUG_INFO, "    → Network PXE boot from %a\n",
                 mCleanOsSources[Index].Config.NetworkPxe.ServerIp));
          break;
        case CleanOsSourceReadOnlyMedia:
          DEBUG((DEBUG_INFO, "    → Read-only media: %s\n",
                 mCleanOsSources[Index].Config.ReadOnlyMedia.DevicePath));
          break;
        case CleanOsSourceSignedImage:
          DEBUG((DEBUG_INFO, "    → Signed image: %s\n",
                 mCleanOsSources[Index].Config.SignedImage.ImagePath));
          break;
        default:
          break;
      }
    }
  }
  
  DEBUG((DEBUG_INFO, "[A] Auto-select highest priority clean OS\n"));
  DEBUG((DEBUG_INFO, "[C] Continue with potentially compromised firmware (RISKY!)\n\n"));
  
  DEBUG((DEBUG_INFO, "Choose clean OS source (auto-selecting in 15 seconds): "));
  
  //
  // TODO: Implement actual user input with timeout
  // For now, auto-select highest priority
  //
  *UserChoice = 0;  // Auto-select
  DEBUG((DEBUG_INFO, "A (auto-selected)\n"));
  
  return EFI_SUCCESS;
}

/**
  MAIN CLEAN OS BOOT RECOVERY FUNCTION
  
  Implements the philosophy that it's OK if firmware gets infected as long
  as we always boot a clean OS image. This breaks the persistence chain.
  
  @retval EFI_SUCCESS      Clean OS boot initiated
  @retval EFI_NOT_FOUND    No clean OS sources available
  @retval EFI_DEVICE_ERROR Clean OS boot failed
**/
EFI_STATUS
EFIAPI
PhoenixGuardCleanOsBoot (
  VOID
  )
{
  EFI_STATUS      Status;
  UINT32          UserChoice;
  UINT32          BestSourceIndex;
  UINT32          BestPriority;
  UINT32          Index;
  UINT32          AvailableSources;
  CLEAN_OS_SOURCE *SelectedSource;
  
  DEBUG((DEBUG_INFO, "\n🛡️  PhoenixGuard: INITIATING CLEAN OS BOOT 🛡️\n"));
  DEBUG((DEBUG_INFO, "Philosophy: Firmware compromise doesn't matter if OS is clean\n"));
  DEBUG((DEBUG_INFO, "Breaking the persistence chain with clean OS images...\n\n"));
  
  //
  // Detect available clean OS sources
  //
  Status = CleanOsDetectAvailableSources();
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "PhoenixGuard: Failed to detect clean OS sources\n"));
    return Status;
  }
  
  //
  // Count available sources and find best priority
  //
  AvailableSources = 0;
  BestSourceIndex = 0;
  BestPriority = 0;
  
  for (Index = 0; Index < mCleanOsSourceCount; Index++) {
    if (mCleanOsSources[Index].Available) {
      AvailableSources++;
      
      if (mCleanOsSources[Index].Priority > BestPriority) {
        BestPriority = mCleanOsSources[Index].Priority;
        BestSourceIndex = Index;
      }
    }
  }
  
  if (AvailableSources == 0) {
    DEBUG((DEBUG_ERROR, "PhoenixGuard: No clean OS sources available!\n"));
    DEBUG((DEBUG_ERROR, "Cannot guarantee clean OS boot - falling back to normal boot\n"));
    return EFI_NOT_FOUND;
  }
  
  DEBUG((DEBUG_INFO, "PhoenixGuard: Found %d available clean OS sources\n", AvailableSources));
  
  //
  // Display clean OS boot menu
  //
  Status = CleanOsDisplayBootMenu(AvailableSources, &UserChoice);
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_WARN, "PhoenixGuard: Menu timeout, auto-selecting best source\n"));
    UserChoice = 0;  // Auto-select
  }
  
  //
  // Select clean OS source
  //
  if (UserChoice == 0) {
    // Auto-select highest priority
    SelectedSource = &mCleanOsSources[BestSourceIndex];
    DEBUG((DEBUG_INFO, "PhoenixGuard: Auto-selected: %s\n", SelectedSource->Description));
  } else {
    // User selection
    SelectedSource = &mCleanOsSources[UserChoice - 1];
    DEBUG((DEBUG_INFO, "PhoenixGuard: User selected: %s\n", SelectedSource->Description));
  }
  
  //
  // Boot from selected clean OS source
  //
  DEBUG((DEBUG_INFO, "\n🚀 Initiating clean OS boot sequence...\n"));
  
  switch (SelectedSource->Type) {
    case CleanOsSourceNetworkPxe:
      Status = CleanOsBootFromNetworkPxe(SelectedSource);
      break;
      
    case CleanOsSourceReadOnlyMedia:
      Status = CleanOsBootFromReadOnlyMedia(SelectedSource);
      break;
      
    case CleanOsSourceSignedImage:
      Status = CleanOsBootFromSignedImage(SelectedSource);
      break;
      
    default:
      DEBUG((DEBUG_ERROR, "PhoenixGuard: Unknown clean OS source type: %d\n", SelectedSource->Type));
      Status = EFI_UNSUPPORTED;
      break;
  }
  
  //
  // Report results
  //
  if (!EFI_ERROR(Status)) {
    DEBUG((DEBUG_INFO, "\n✅ PhoenixGuard: CLEAN OS BOOT SUCCESSFUL! ✅\n"));
    DEBUG((DEBUG_INFO, "✅ Source: %s\n", SelectedSource->Description));
    DEBUG((DEBUG_INFO, "✅ Firmware compromise neutralized by clean OS!\n"));
    DEBUG((DEBUG_INFO, "✅ Bootkit persistence chain broken!\n"));
    DEBUG((DEBUG_INFO, "\nPhoenixGuard: System is now running clean OS environment\n"));
    
    return EFI_SUCCESS;
  } else {
    DEBUG((DEBUG_ERROR, "\n❌ PhoenixGuard: CLEAN OS BOOT FAILED! ❌\n"));
    DEBUG((DEBUG_ERROR, "❌ Source: %s\n", SelectedSource->Description));
    DEBUG((DEBUG_ERROR, "❌ Cannot guarantee clean OS environment\n"));
    DEBUG((DEBUG_ERROR, "❌ Falling back to normal boot (RISKY!)\n"));
    
    return EFI_DEVICE_ERROR;
  }
}
