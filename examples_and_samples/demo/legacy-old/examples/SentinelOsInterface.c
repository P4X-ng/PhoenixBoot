/**
 * SentinelOsInterface.c - OS Interface for BootkitSentinel
 * 
 * "BRIDGE THE GAP - FIRMWARE SECURITY MEETS OS TOOLS"
 * 
 * This module provides a safe interface between the firmware-level
 * BootkitSentinel and OS-level tools like flashrom, allowing legitimate
 * tools to work while keeping bootkits contained in the honeypot.
 * 
 * Compiles as both UEFI firmware module and Linux kernel module!
 */

#ifdef __KERNEL__
// Linux kernel module headers
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/io.h>
#include <linux/version.h>

#define DEBUG(x, ...) printk(KERN_INFO "BootkitSentinel: " x, ##__VA_ARGS__)
#define EFIAPI
#define EFI_SUCCESS 0
#define EFI_STATUS int
#define BOOLEAN bool
#define TRUE true
#define FALSE false
#define UINT32 u32
#define UINT64 u64
#define UINT8 u8
#define CHAR8 char

#else
// UEFI firmware headers
#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/IoLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/LoadedImage.h>

#define DEBUG(x, ...) DEBUG((DEBUG_INFO, x, ##__VA_ARGS__))
#endif

#include "BootkitSentinel.h"

//
// OS Interface Configuration
//
#define SENTINEL_OS_MAGIC           0x534E544C  // "SNTL"
#define SENTINEL_OS_VERSION         0x00010000
#define SENTINEL_OS_MAX_REQUEST     (1024 * 1024)  // 1MB max per request

//
// OS Interface Commands
//
typedef enum {
  SentinelOsCmdGetStatus       = 0x01,
  SentinelOsCmdGetLogs         = 0x02,
  SentinelOsCmdFlashRead       = 0x03,
  SentinelOsCmdFlashWrite      = 0x04,
  SentinelOsCmdSetMode         = 0x05,
  SentinelOsCmdGetHoneypot     = 0x06,
  SentinelOsCmdExportReport    = 0x07,
  SentinelOsCmdReset           = 0x08
} SENTINEL_OS_COMMAND;

//
// OS Interface Request/Response Structure
//
typedef struct {
  UINT32                Magic;        // SENTINEL_OS_MAGIC
  UINT32                Version;      // SENTINEL_OS_VERSION
  SENTINEL_OS_COMMAND   Command;      // Command to execute
  UINT32                RequestSize;  // Size of request data
  UINT32                ResponseSize; // Size of response data
  EFI_STATUS            Status;       // Operation status
  UINT8                 Data[0];      // Variable-length data
} SENTINEL_OS_REQUEST;

//
// Flash access request
//
typedef struct {
  UINT64   Address;
  UINT32   Size;
  BOOLEAN  Write;
  UINT8    Data[0];  // For write requests
} SENTINEL_FLASH_REQUEST;

//
// Status response
//
typedef struct {
  BOOLEAN  Active;
  UINT32   Mode;
  UINT32   InterceptCount;
  UINT32   DetectionScore;
  UINT32   LogCount;
  BOOLEAN  HoneypotActive;
  UINT32   HoneypotSize;
} SENTINEL_STATUS_RESPONSE;

#ifndef __KERNEL__
//
// UEFI Runtime Services Variable Support
//
#define SENTINEL_VARIABLE_NAME      L"BootkitSentinelData"
#define SENTINEL_VARIABLE_GUID      \
  { 0x12345678, 0x1234, 0x5678, { 0x90, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78 } }

EFI_GUID gSentinelVariableGuid = SENTINEL_VARIABLE_GUID;

//
// Global shared memory for OS communication
//
STATIC VOID    *gOsSharedMemory = NULL;
STATIC UINT32   gOsSharedMemorySize = 0;
STATIC BOOLEAN  gOsInterfaceActive = FALSE;

/**
 * Initialize OS interface in UEFI firmware
 */
EFI_STATUS
EFIAPI
SentinelOsInterfaceInitialize (
  VOID
  )
{
  EFI_STATUS  Status;
  
  DEBUG("🔗 Initializing OS interface\n");
  
  //
  // Allocate shared memory that will persist into OS
  //
  gOsSharedMemorySize = 4 * 1024 * 1024;  // 4MB
  Status = gBS->AllocatePool(
    EfiRuntimeServicesData,  // Accessible during OS runtime
    gOsSharedMemorySize,
    &gOsSharedMemory
  );
  
  if (EFI_ERROR(Status)) {
    DEBUG("❌ Failed to allocate OS shared memory\n");
    return Status;
  }
  
  ZeroMem(gOsSharedMemory, gOsSharedMemorySize);
  
  //
  // Store shared memory address in UEFI variable for OS access
  //
  UINT64 SharedMemoryAddress = (UINT64)(UINTN)gOsSharedMemory;
  Status = gRT->SetVariable(
    SENTINEL_VARIABLE_NAME,
    &gSentinelVariableGuid,
    EFI_VARIABLE_BOOTSERVICE_ACCESS | EFI_VARIABLE_RUNTIME_ACCESS,
    sizeof(UINT64),
    &SharedMemoryAddress
  );
  
  if (EFI_ERROR(Status)) {
    DEBUG("⚠️ Failed to store shared memory address in UEFI variable\n");
  }
  
  gOsInterfaceActive = TRUE;
  
  DEBUG("✅ OS interface initialized: SharedMem=0x%p Size=%d\n", 
         gOsSharedMemory, gOsSharedMemorySize);
  
  return EFI_SUCCESS;
}

/**
 * Process OS request in UEFI firmware
 */
EFI_STATUS
EFIAPI
SentinelOsProcessRequest (
  IN  SENTINEL_OS_REQUEST  *Request,
  OUT SENTINEL_OS_REQUEST  *Response
  )
{
  EFI_STATUS  Status = EFI_SUCCESS;
  UINT8       *RequestData;
  UINT8       *ResponseData;
  
  if (!gOsInterfaceActive || !Request || !Response) {
    return EFI_INVALID_PARAMETER;
  }
  
  //
  // Validate request
  //
  if (Request->Magic != SENTINEL_OS_MAGIC) {
    DEBUG("❌ Invalid OS request magic: 0x%x\n", Request->Magic);
    return EFI_INVALID_PARAMETER;
  }
  
  RequestData = (UINT8*)Request + sizeof(SENTINEL_OS_REQUEST);
  ResponseData = (UINT8*)Response + sizeof(SENTINEL_OS_REQUEST);
  
  //
  // Initialize response
  //
  Response->Magic = SENTINEL_OS_MAGIC;
  Response->Version = SENTINEL_OS_VERSION;
  Response->Command = Request->Command;
  Response->ResponseSize = 0;
  Response->Status = EFI_SUCCESS;
  
  DEBUG("🔗 Processing OS command: %d\n", Request->Command);
  
  //
  // Process command
  //
  switch (Request->Command) {
    
    case SentinelOsCmdGetStatus:
      {
        SENTINEL_STATUS_RESPONSE *StatusResp = (SENTINEL_STATUS_RESPONSE*)ResponseData;
        
        Status = SentinelGetStatus(
          &StatusResp->Active,
          &StatusResp->Mode,
          &StatusResp->InterceptCount,
          &StatusResp->DetectionScore
        );
        
        // Get additional status info
        VOID   *LogBuffer, *HoneypotFlash;
        UINT32  LogCount, HoneypotSize;
        
        SentinelExportToOS(&LogBuffer, &LogCount, &HoneypotFlash, &HoneypotSize);
        
        StatusResp->LogCount = LogCount;
        StatusResp->HoneypotActive = (HoneypotFlash != NULL);
        StatusResp->HoneypotSize = HoneypotSize;
        
        Response->ResponseSize = sizeof(SENTINEL_STATUS_RESPONSE);
        
        DEBUG("✅ Status: Active=%d Mode=%d Score=%d\n", 
               StatusResp->Active, StatusResp->Mode, StatusResp->DetectionScore);
      }
      break;
      
    case SentinelOsCmdFlashRead:
    case SentinelOsCmdFlashWrite:
      {
        SENTINEL_FLASH_REQUEST *FlashReq = (SENTINEL_FLASH_REQUEST*)RequestData;
        
        if (Request->Command == SentinelOsCmdFlashWrite) {
          // Flash write request
          Status = SentinelOsFlashRequest(
            FlashReq->Address,
            FlashReq->Size,
            TRUE,   // Write
            FlashReq->Data,
            NULL
          );
          
          DEBUG("🔧 Flash write: Addr=0x%lx Size=%d Status=%r\n", 
                 FlashReq->Address, FlashReq->Size, Status);
        } else {
          // Flash read request
          Status = SentinelOsFlashRequest(
            FlashReq->Address,
            FlashReq->Size,
            FALSE,  // Read
            NULL,
            ResponseData
          );
          
          Response->ResponseSize = FlashReq->Size;
          
          DEBUG("🔧 Flash read: Addr=0x%lx Size=%d Status=%r\n", 
                 FlashReq->Address, FlashReq->Size, Status);
        }
      }
      break;
      
    case SentinelOsCmdGetLogs:
      {
        VOID   *LogBuffer;
        UINT32  LogCount;
        
        Status = SentinelExportToOS(&LogBuffer, &LogCount, NULL, NULL);
        if (!EFI_ERROR(Status) && LogBuffer && LogCount > 0) {
          UINT32 LogDataSize = LogCount * sizeof(SENTINEL_LOG_ENTRY);
          
          if (LogDataSize <= gOsSharedMemorySize - sizeof(SENTINEL_OS_REQUEST)) {
            CopyMem(ResponseData, LogBuffer, LogDataSize);
            Response->ResponseSize = LogDataSize;
            
            DEBUG("📊 Exported %d log entries (%d bytes)\n", LogCount, LogDataSize);
          } else {
            DEBUG("⚠️ Log data too large for shared memory\n");
            Status = EFI_OUT_OF_RESOURCES;
          }
        }
      }
      break;
      
    case SentinelOsCmdGetHoneypot:
      {
        VOID   *HoneypotFlash;
        UINT32  HoneypotSize;
        
        Status = SentinelExportToOS(NULL, NULL, &HoneypotFlash, &HoneypotSize);
        if (!EFI_ERROR(Status) && HoneypotFlash && HoneypotSize > 0) {
          // Return just the first 64KB of honeypot for analysis
          UINT32 ExportSize = MIN(HoneypotSize, 64 * 1024);
          
          CopyMem(ResponseData, HoneypotFlash, ExportSize);
          Response->ResponseSize = ExportSize;
          
          DEBUG("🍯 Exported honeypot data: %d bytes\n", ExportSize);
        }
      }
      break;
      
    case SentinelOsCmdSetMode:
      {
        if (Request->RequestSize >= sizeof(UINT32)) {
          UINT32 NewMode = *(UINT32*)RequestData;
          Status = SentinelSetMode((SENTINEL_MODE)NewMode);
          
          DEBUG("🎯 Mode changed to: %d\n", NewMode);
        } else {
          Status = EFI_INVALID_PARAMETER;
        }
      }
      break;
      
    case SentinelOsCmdReset:
      Status = SentinelResetStatistics();
      DEBUG("🔄 Statistics reset\n");
      break;
      
    default:
      DEBUG("❌ Unknown OS command: %d\n", Request->Command);
      Status = EFI_UNSUPPORTED;
      break;
  }
  
  Response->Status = Status;
  return Status;
}

#else // __KERNEL__

//
// Linux Kernel Module Implementation
//

//
// Shared memory mapping
//
static void __iomem *g_shared_memory = NULL;
static u64 g_shared_memory_phys = 0;
static u32 g_shared_memory_size = 4 * 1024 * 1024;

//
// Proc filesystem interface
//
static struct proc_dir_entry *sentinel_proc_dir = NULL;
static struct proc_dir_entry *sentinel_status_entry = NULL;
static struct proc_dir_entry *sentinel_logs_entry = NULL;
static struct proc_dir_entry *sentinel_flash_entry = NULL;
static struct proc_dir_entry *sentinel_honeypot_entry = NULL;

/**
 * Get shared memory address from EFI variable
 */
static int sentinel_get_shared_memory(void)
{
    // In a real implementation, this would:
    // 1. Read EFI variable containing shared memory address
    // 2. Map the physical memory into kernel virtual space
    // 3. Validate the memory contents
    
    // For now, we'll use a placeholder
    g_shared_memory_phys = 0x80000000ULL;  // Example address
    
    g_shared_memory = ioremap(g_shared_memory_phys, g_shared_memory_size);
    if (!g_shared_memory) {
        printk(KERN_ERR "BootkitSentinel: Failed to map shared memory\n");
        return -ENOMEM;
    }
    
    printk(KERN_INFO "BootkitSentinel: Mapped shared memory at 0x%llx\n", 
           g_shared_memory_phys);
    
    return 0;
}

/**
 * Send request to firmware BootkitSentinel
 */
static int sentinel_send_request(SENTINEL_OS_COMMAND cmd, 
                                void *request_data, u32 request_size,
                                void *response_data, u32 *response_size)
{
    SENTINEL_OS_REQUEST *request;
    SENTINEL_OS_REQUEST *response;
    
    if (!g_shared_memory) {
        return -ENODEV;
    }
    
    request = (SENTINEL_OS_REQUEST*)g_shared_memory;
    response = (SENTINEL_OS_REQUEST*)((u8*)g_shared_memory + g_shared_memory_size / 2);
    
    // Prepare request
    memset(request, 0, sizeof(SENTINEL_OS_REQUEST));
    request->Magic = SENTINEL_OS_MAGIC;
    request->Version = SENTINEL_OS_VERSION;
    request->Command = cmd;
    request->RequestSize = request_size;
    
    if (request_data && request_size > 0) {
        memcpy((u8*)request + sizeof(SENTINEL_OS_REQUEST), request_data, request_size);
    }
    
    // Signal firmware (implementation-specific)
    // This could be done via:
    // - SMI (System Management Interrupt)
    // - Special MSR write
    // - ACPI method call
    // - Platform-specific mechanism
    
    // For now, we'll simulate the response
    memset(response, 0, sizeof(SENTINEL_OS_REQUEST));
    response->Magic = SENTINEL_OS_MAGIC;
    response->Version = SENTINEL_OS_VERSION;
    response->Command = cmd;
    response->Status = EFI_SUCCESS;
    
    // Copy response data
    if (response_data && response_size && response->ResponseSize > 0) {
        u32 copy_size = min(*response_size, response->ResponseSize);
        memcpy(response_data, (u8*)response + sizeof(SENTINEL_OS_REQUEST), copy_size);
        *response_size = copy_size;
    }
    
    return (response->Status == EFI_SUCCESS) ? 0 : -EIO;
}

/**
 * /proc/bootkit_sentinel/status
 */
static int sentinel_status_show(struct seq_file *m, void *v)
{
    SENTINEL_STATUS_RESPONSE status;
    u32 response_size = sizeof(status);
    int ret;
    
    ret = sentinel_send_request(SentinelOsCmdGetStatus, NULL, 0, &status, &response_size);
    if (ret == 0) {
        seq_printf(m, "BootkitSentinel Status:\n");
        seq_printf(m, "  Active: %s\n", status.Active ? "YES" : "NO");
        seq_printf(m, "  Mode: %u\n", status.Mode);
        seq_printf(m, "  Intercept Count: %u\n", status.InterceptCount);
        seq_printf(m, "  Detection Score: %u\n", status.DetectionScore);
        seq_printf(m, "  Log Count: %u\n", status.LogCount);
        seq_printf(m, "  Honeypot Active: %s\n", status.HoneypotActive ? "YES" : "NO");
        seq_printf(m, "  Honeypot Size: %u bytes\n", status.HoneypotSize);
        
        if (status.DetectionScore > 500) {
            seq_printf(m, "\n🚨 HIGH BOOTKIT DETECTION SCORE! 🚨\n");
        }
    } else {
        seq_printf(m, "Error: Could not get status from BootkitSentinel\n");
    }
    
    return 0;
}

static int sentinel_status_open(struct inode *inode, struct file *file)
{
    return single_open(file, sentinel_status_show, NULL);
}

static const struct proc_ops sentinel_status_ops = {
    .proc_open = sentinel_status_open,
    .proc_read = seq_read,
    .proc_lseek = seq_lseek,
    .proc_release = single_release,
};

/**
 * /proc/bootkit_sentinel/flash - Flash access for tools like flashrom
 */
static ssize_t sentinel_flash_write(struct file *file, const char __user *buffer,
                                   size_t count, loff_t *pos)
{
    SENTINEL_FLASH_REQUEST *flash_req;
    char *kernel_buffer;
    int ret;
    
    if (count > SENTINEL_OS_MAX_REQUEST) {
        return -EINVAL;
    }
    
    kernel_buffer = kmalloc(count, GFP_KERNEL);
    if (!kernel_buffer) {
        return -ENOMEM;
    }
    
    if (copy_from_user(kernel_buffer, buffer, count)) {
        kfree(kernel_buffer);
        return -EFAULT;
    }
    
    flash_req = (SENTINEL_FLASH_REQUEST*)kernel_buffer;
    
    // Validate flash request
    if (flash_req->Address < 0xFF000000ULL || flash_req->Size > 1024*1024) {
        kfree(kernel_buffer);
        return -EINVAL;
    }
    
    ret = sentinel_send_request(SentinelOsCmdFlashWrite, kernel_buffer, count, NULL, NULL);
    
    kfree(kernel_buffer);
    
    if (ret == 0) {
        printk(KERN_INFO "BootkitSentinel: Flash write Addr=0x%llx Size=%u\n",
               flash_req->Address, flash_req->Size);
        return count;
    }
    
    return ret;
}

static ssize_t sentinel_flash_read(struct file *file, char __user *buffer,
                                  size_t count, loff_t *pos)
{
    // Implementation for flash read requests
    return -ENOSYS;  // Not implemented in this example
}

static const struct proc_ops sentinel_flash_ops = {
    .proc_read = sentinel_flash_read,
    .proc_write = sentinel_flash_write,
};

/**
 * Module initialization
 */
static int __init sentinel_os_init(void)
{
    int ret;
    
    printk(KERN_INFO "BootkitSentinel OS Interface Loading...\n");
    
    // Get shared memory from firmware
    ret = sentinel_get_shared_memory();
    if (ret) {
        return ret;
    }
    
    // Create /proc/bootkit_sentinel directory
    sentinel_proc_dir = proc_mkdir("bootkit_sentinel", NULL);
    if (!sentinel_proc_dir) {
        printk(KERN_ERR "BootkitSentinel: Failed to create /proc/bootkit_sentinel\n");
        iounmap(g_shared_memory);
        return -ENOMEM;
    }
    
    // Create status entry
    sentinel_status_entry = proc_create("status", 0444, sentinel_proc_dir, &sentinel_status_ops);
    if (!sentinel_status_entry) {
        printk(KERN_ERR "BootkitSentinel: Failed to create status entry\n");
        proc_remove(sentinel_proc_dir);
        iounmap(g_shared_memory);
        return -ENOMEM;
    }
    
    // Create flash entry for flashrom integration
    sentinel_flash_entry = proc_create("flash", 0666, sentinel_proc_dir, &sentinel_flash_ops);
    if (!sentinel_flash_entry) {
        printk(KERN_ERR "BootkitSentinel: Failed to create flash entry\n");
        proc_remove(sentinel_status_entry);
        proc_remove(sentinel_proc_dir);
        iounmap(g_shared_memory);
        return -ENOMEM;
    }
    
    printk(KERN_INFO "✅ BootkitSentinel OS Interface Loaded\n");
    printk(KERN_INFO "   Status: /proc/bootkit_sentinel/status\n");
    printk(KERN_INFO "   Flash:  /proc/bootkit_sentinel/flash\n");
    
    return 0;
}

/**
 * Module cleanup
 */
static void __exit sentinel_os_exit(void)
{
    if (sentinel_flash_entry) {
        proc_remove(sentinel_flash_entry);
    }
    
    if (sentinel_status_entry) {
        proc_remove(sentinel_status_entry);
    }
    
    if (sentinel_proc_dir) {
        proc_remove(sentinel_proc_dir);
    }
    
    if (g_shared_memory) {
        iounmap(g_shared_memory);
    }
    
    printk(KERN_INFO "BootkitSentinel OS Interface Unloaded\n");
}

module_init(sentinel_os_init);
module_exit(sentinel_os_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("BootkitSentinel OS Interface Driver");
MODULE_AUTHOR("PhoenixGuard Security Team");
MODULE_VERSION("1.0");

#endif // __KERNEL__
