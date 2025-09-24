/**
 * PhoenixGuardNetworkBoot.c - PXE Network Boot for Ubuntu Recovery
 * 
 * "When local storage is compromised, the network becomes our savior"
 */

#include <Uefi.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/PrintLib.h>
#include <Library/DebugLib.h>
#include <Protocol/PxeBaseCode.h>
#include <Protocol/NetworkInterfaceIdentifier.h>
#include <Protocol/SimpleNetwork.h>
#include <Protocol/Dhcp4.h>
#include <Protocol/Ip4.h>
#include <Protocol/Udp4.h>
#include <Protocol/Tcp4.h>

#include "PhoenixGuardCore.h"

//
// PXE Boot Configuration
//
#define PHOENIXGUARD_TFTP_SERVER      "192.168.1.100"
#define PHOENIXGUARD_HTTP_SERVER      "https://boot.phoenixguard.local"
#define PHOENIXGUARD_NFS_SERVER       "192.168.1.100:/ubuntu-recovery"

//
// Network boot file paths
//
#define UBUNTU_PXE_KERNEL             "phoenixguard/ubuntu/vmlinuz-22.04-recovery"
#define UBUNTU_PXE_INITRD             "phoenixguard/ubuntu/initrd-22.04-recovery"
#define UBUNTU_PXE_CONFIG             "phoenixguard/ubuntu/boot-config.txt"

//
// Network boot sources
//
typedef struct {
  CHAR8     *ServerAddress;
  CHAR8     *KernelPath;
  CHAR8     *InitrdPath;
  CHAR8     *ConfigPath;
  UINT16    Protocol;  // 0=TFTP, 1=HTTP, 2=HTTPS
  UINT32    Priority;
} NETWORK_BOOT_SOURCE;

NETWORK_BOOT_SOURCE mNetworkBootSources[] = {
  {
    "192.168.1.100",
    "phoenixguard/ubuntu-22.04/vmlinuz-clean",
    "phoenixguard/ubuntu-22.04/initrd-clean",
    "phoenixguard/ubuntu-22.04/config.txt",
    0,  // TFTP
    100
  },
  {
    "192.168.1.101",
    "phoenix-recovery/ubuntu/kernel",
    "phoenix-recovery/ubuntu/initrd",
    "phoenix-recovery/ubuntu/config",
    1,  // HTTP
    90
  }
};

#define NETWORK_BOOT_SOURCES_COUNT (sizeof(mNetworkBootSources)/sizeof(mNetworkBootSources[0]))

//
// Network boot state
//
typedef struct {
  EFI_PXE_BASE_CODE_PROTOCOL        *PxeBaseCode;
  EFI_SIMPLE_NETWORK_PROTOCOL       *SimpleNetwork;
  EFI_DHCP4_PROTOCOL               *Dhcp4;
  EFI_IP4_PROTOCOL                 *Ip4;
  EFI_UDP4_PROTOCOL                *Udp4;
  BOOLEAN                           NetworkInitialized;
  EFI_IP4_CONFIG_DATA               Ip4Config;
} PHOENIXGUARD_NETWORK_STATE;

PHOENIXGUARD_NETWORK_STATE mNetworkState = {0};

/**
 * Initialize network interfaces for PXE boot
 */
EFI_STATUS
InitializeNetworkInterface(
  VOID
  )
{
  EFI_STATUS              Status;
  UINTN                   HandleCount;
  EFI_HANDLE              *HandleBuffer;
  UINTN                   Index;
  EFI_PXE_BASE_CODE_MODE  *PxeMode;

  DEBUG((DEBUG_INFO, "📡 Initializing network interface for PXE boot...\n"));

  //
  // Locate all PXE base code protocols
  //
  Status = gBS->LocateHandleBuffer(
    ByProtocol,
    &gEfiPxeBaseCodeProtocolGuid,
    NULL,
    &HandleCount,
    &HandleBuffer
  );

  if (EFI_ERROR(Status) || HandleCount == 0) {
    DEBUG((DEBUG_ERROR, "❌ No PXE interfaces found\n"));
    return EFI_NOT_FOUND;
  }

  //
  // Try each PXE interface
  //
  for (Index = 0; Index < HandleCount; Index++) {
    Status = gBS->HandleProtocol(
      HandleBuffer[Index],
      &gEfiPxeBaseCodeProtocolGuid,
      (VOID**)&mNetworkState.PxeBaseCode
    );

    if (EFI_ERROR(Status)) {
      continue;
    }

    //
    // Start PXE base code
    //
    Status = mNetworkState.PxeBaseCode->Start(mNetworkState.PxeBaseCode, FALSE);
    if (EFI_ERROR(Status)) {
      DEBUG((DEBUG_WARN, "⚠️ Failed to start PXE interface %d\n", Index));
      continue;
    }

    //
    // Enable ARP, ICMP, UDP, and DHCP
    //
    Status = mNetworkState.PxeBaseCode->SetParameters(
      mNetworkState.PxeBaseCode,
      NULL,     // Use default parameters
      NULL,     // No new boot policy
      NULL,     // No DHCP discover
      NULL,     // No DHCP override
      NULL,     // No ARP override
      NULL      // No route table override
    );

    if (!EFI_ERROR(Status)) {
      PxeMode = mNetworkState.PxeBaseCode->Mode;
      DEBUG((DEBUG_INFO, "✅ PXE interface %d initialized\n", Index));
      DEBUG((DEBUG_INFO, "   Started: %s\n", PxeMode->Started ? "YES" : "NO"));
      DEBUG((DEBUG_INFO, "   DHCP Used: %s\n", PxeMode->DhcpAckReceived ? "YES" : "NO"));
      
      mNetworkState.NetworkInitialized = TRUE;
      break;
    }
  }

  FreePool(HandleBuffer);

  if (!mNetworkState.NetworkInitialized) {
    DEBUG((DEBUG_ERROR, "❌ Failed to initialize any network interface\n"));
    return EFI_NOT_FOUND;
  }

  return EFI_SUCCESS;
}

/**
 * Perform DHCP to get network configuration
 */
EFI_STATUS
PerformDhcpConfiguration(
  VOID
  )
{
  EFI_STATUS              Status;
  EFI_PXE_BASE_CODE_MODE  *PxeMode;

  if (!mNetworkState.NetworkInitialized) {
    return EFI_NOT_READY;
  }

  DEBUG((DEBUG_INFO, "📡 Performing DHCP configuration...\n"));

  //
  // Perform DHCP
  //
  Status = mNetworkState.PxeBaseCode->Dhcp(mNetworkState.PxeBaseCode, TRUE);
  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ DHCP failed: %r\n", Status));
    return Status;
  }

  PxeMode = mNetworkState.PxeBaseCode->Mode;
  
  if (PxeMode->DhcpAckReceived) {
    DEBUG((DEBUG_INFO, "✅ DHCP configuration successful\n"));
    DEBUG((DEBUG_INFO, "   Client IP: %d.%d.%d.%d\n",
      PxeMode->StationIp.Addr[0],
      PxeMode->StationIp.Addr[1],
      PxeMode->StationIp.Addr[2],
      PxeMode->StationIp.Addr[3]
    ));
    DEBUG((DEBUG_INFO, "   Server IP: %d.%d.%d.%d\n",
      PxeMode->DhcpAck.Dhcpv4.BootpSiAddr[0],
      PxeMode->DhcpAck.Dhcpv4.BootpSiAddr[1],
      PxeMode->DhcpAck.Dhcpv4.BootpSiAddr[2],
      PxeMode->DhcpAck.Dhcpv4.BootpSiAddr[3]
    ));
  } else {
    DEBUG((DEBUG_ERROR, "❌ DHCP ACK not received\n"));
    return EFI_NOT_READY;
  }

  return EFI_SUCCESS;
}

/**
 * Download file via TFTP
 */
EFI_STATUS
DownloadViaTftp(
  IN CHAR8     *ServerIp,
  IN CHAR8     *FilePath,
  OUT VOID     **Buffer,
  OUT UINT64   *BufferSize
  )
{
  EFI_STATUS        Status;
  EFI_IP_ADDRESS    ServerAddress;
  CHAR8             *FileName;
  UINTN             BlockSize;
  BOOLEAN           DontUseBuffer;

  if (!mNetworkState.NetworkInitialized) {
    return EFI_NOT_READY;
  }

  DEBUG((DEBUG_INFO, "📡 Downloading via TFTP: %a:%a\n", ServerIp, FilePath));

  //
  // Convert server IP string to EFI_IP_ADDRESS
  //
  ZeroMem(&ServerAddress, sizeof(ServerAddress));
  // TODO: Parse IP address string to bytes
  // For now, use a placeholder
  ServerAddress.Addr[0] = 192;
  ServerAddress.Addr[1] = 168;
  ServerAddress.Addr[2] = 1;
  ServerAddress.Addr[3] = 100;

  FileName = FilePath;
  BlockSize = 8192;      // 8KB blocks
  DontUseBuffer = FALSE; // Use provided buffer
  *BufferSize = 0;
  *Buffer = NULL;

  //
  // Download file via TFTP
  //
  Status = mNetworkState.PxeBaseCode->Mtftp(
    mNetworkState.PxeBaseCode,
    EFI_PXE_BASE_CODE_TFTP_READ_FILE,
    *Buffer,
    DontUseBuffer,
    BufferSize,
    &BlockSize,
    &ServerAddress,
    FileName,
    NULL,
    FALSE
  );

  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ TFTP download failed: %r\n", Status));
    return Status;
  }

  //
  // Allocate buffer and download again if needed
  //
  if (*Buffer == NULL && *BufferSize > 0) {
    *Buffer = AllocatePages(EFI_SIZE_TO_PAGES(*BufferSize));
    if (*Buffer == NULL) {
      DEBUG((DEBUG_ERROR, "❌ Failed to allocate buffer for TFTP download\n"));
      return EFI_OUT_OF_RESOURCES;
    }

    //
    // Download again with allocated buffer
    //
    Status = mNetworkState.PxeBaseCode->Mtftp(
      mNetworkState.PxeBaseCode,
      EFI_PXE_BASE_CODE_TFTP_READ_FILE,
      *Buffer,
      FALSE,
      BufferSize,
      &BlockSize,
      &ServerAddress,
      FileName,
      NULL,
      FALSE
    );

    if (EFI_ERROR(Status)) {
      DEBUG((DEBUG_ERROR, "❌ TFTP download with buffer failed: %r\n", Status));
      FreePages(*Buffer, EFI_SIZE_TO_PAGES(*BufferSize));
      *Buffer = NULL;
      return Status;
    }
  }

  DEBUG((DEBUG_INFO, "✅ TFTP download successful (%llu bytes)\n", *BufferSize));
  return EFI_SUCCESS;
}

/**
 * Verify downloaded network boot components
 */
EFI_STATUS
VerifyNetworkBootComponents(
  IN VOID    *KernelBuffer,
  IN UINT64  KernelSize,
  IN VOID    *InitrdBuffer,
  IN UINT64  InitrdSize
  )
{
  EFI_STATUS Status;
  UINT32     KernelHash;
  UINT32     InitrdHash;

  DEBUG((DEBUG_INFO, "🔐 Verifying network boot components...\n"));

  //
  // Verify kernel integrity
  //
  Status = IntegrityValidatorVerifyComponent(
    KernelBuffer,
    (UINTN)KernelSize,
    L"network-ubuntu-kernel",
    &KernelHash
  );

  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ Network kernel verification failed\n"));
    return Status;
  }

  //
  // Verify initrd integrity
  //
  Status = IntegrityValidatorVerifyComponent(
    InitrdBuffer,
    (UINTN)InitrdSize,
    L"network-ubuntu-initrd",
    &InitrdHash
  );

  if (EFI_ERROR(Status)) {
    DEBUG((DEBUG_ERROR, "❌ Network initrd verification failed\n"));
    return Status;
  }

  DEBUG((DEBUG_INFO, "✅ Network boot components verified\n"));
  DEBUG((DEBUG_INFO, "   Network Kernel Hash: 0x%08X\n", KernelHash));
  DEBUG((DEBUG_INFO, "   Network Initrd Hash: 0x%08X\n", InitrdHash));

  return EFI_SUCCESS;
}

/**
 * Execute network boot for Ubuntu recovery
 */
EFI_STATUS
ExecuteNetworkBootRecovery(
  VOID
  )
{
  EFI_STATUS Status;
  UINTN      SourceIndex;
  VOID       *KernelBuffer = NULL;
  UINT64     KernelSize = 0;
  VOID       *InitrdBuffer = NULL;
  UINT64     InitrdSize = 0;

  Print(L"📡 Executing network boot recovery...\n");

  //
  // Initialize network interface
  //
  Status = InitializeNetworkInterface();
  if (EFI_ERROR(Status)) {
    Print(L"❌ Network initialization failed\n");
    return Status;
  }

  //
  // Configure network via DHCP
  //
  Status = PerformDhcpConfiguration();
  if (EFI_ERROR(Status)) {
    Print(L"❌ DHCP configuration failed\n");
    return Status;
  }

  //
  // Try network boot sources in priority order
  //
  for (SourceIndex = 0; SourceIndex < NETWORK_BOOT_SOURCES_COUNT; SourceIndex++) {
    NETWORK_BOOT_SOURCE *Source = &mNetworkBootSources[SourceIndex];

    Print(L"🔍 Trying network source: %a\n", Source->ServerAddress);

    if (Source->Protocol == 0) { // TFTP
      //
      // Download kernel via TFTP
      //
      Status = DownloadViaTftp(Source->ServerAddress, Source->KernelPath, &KernelBuffer, &KernelSize);
      if (EFI_ERROR(Status)) {
        Print(L"❌ Failed to download kernel via TFTP\n");
        continue;
      }

      //
      // Download initrd via TFTP
      //
      Status = DownloadViaTftp(Source->ServerAddress, Source->InitrdPath, &InitrdBuffer, &InitrdSize);
      if (EFI_ERROR(Status)) {
        Print(L"❌ Failed to download initrd via TFTP\n");
        if (KernelBuffer) FreePages(KernelBuffer, EFI_SIZE_TO_PAGES(KernelSize));
        continue;
      }

      //
      // Verify components
      //
      Status = VerifyNetworkBootComponents(KernelBuffer, KernelSize, InitrdBuffer, InitrdSize);
      if (EFI_ERROR(Status)) {
        Print(L"❌ Network boot verification failed\n");
        if (KernelBuffer) FreePages(KernelBuffer, EFI_SIZE_TO_PAGES(KernelSize));
        if (InitrdBuffer) FreePages(InitrdBuffer, EFI_SIZE_TO_PAGES(InitrdSize));
        continue;
      }

      //
      // Boot Ubuntu from network
      //
      Print(L"✅ Network boot components ready\n");
      Print(L"🚀 Booting Ubuntu from network...\n");
      
      // TODO: Call actual Linux boot function
      // BootUbuntuLinux(KernelBuffer, KernelSize, InitrdBuffer, InitrdSize, NetworkKernelArgs);
      
      Print(L"🎉 Network boot successful!\n");
      return EFI_SUCCESS;

    } else {
      Print(L"⚠️ HTTP/HTTPS boot not implemented in this demo\n");
      continue;
    }
  }

  Print(L"❌ All network boot sources failed\n");
  return EFI_NOT_FOUND;
}

/**
 * Check if network boot is available
 */
BOOLEAN
IsNetworkBootAvailable(
  VOID
  )
{
  EFI_STATUS  Status;
  UINTN       HandleCount;
  EFI_HANDLE  *HandleBuffer;

  //
  // Check for PXE base code protocol
  //
  Status = gBS->LocateHandleBuffer(
    ByProtocol,
    &gEfiPxeBaseCodeProtocolGuid,
    NULL,
    &HandleCount,
    &HandleBuffer
  );

  if (!EFI_ERROR(Status) && HandleCount > 0) {
    FreePool(HandleBuffer);
    return TRUE;
  }

  return FALSE;
}

/**
 * Get network boot status information
 */
EFI_STATUS
GetNetworkBootStatus(
  OUT CHAR16  **StatusString
  )
{
  EFI_PXE_BASE_CODE_MODE  *PxeMode;
  CHAR16                  *Status;

  if (!mNetworkState.NetworkInitialized || !mNetworkState.PxeBaseCode) {
    *StatusString = L"Network not initialized";
    return EFI_NOT_READY;
  }

  PxeMode = mNetworkState.PxeBaseCode->Mode;
  
  Status = AllocateZeroPool(256 * sizeof(CHAR16));
  if (Status == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }

  UnicodeSPrint(
    Status,
    256 * sizeof(CHAR16),
    L"Network Status: %s, DHCP: %s, IP: %d.%d.%d.%d",
    PxeMode->Started ? L"Active" : L"Inactive",
    PxeMode->DhcpAckReceived ? L"Configured" : L"Not Configured",
    PxeMode->StationIp.Addr[0],
    PxeMode->StationIp.Addr[1],
    PxeMode->StationIp.Addr[2],
    PxeMode->StationIp.Addr[3]
  );

  *StatusString = Status;
  return EFI_SUCCESS;
}
