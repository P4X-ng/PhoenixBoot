#include <efi.h>
#include <efilib.h>

// Simple test "bootkit" for PhoenixGuard detection testing
// This is a minimal UEFI application that does nothing malicious
// but can be used to test detection mechanisms

EFI_STATUS
EFIAPI
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)
{
    EFI_STATUS Status;
    
    InitializeLib(ImageHandle, SystemTable);
    
    // Print a simple message to identify this as a test bootkit
    Print(L"\r\n");
    Print(L"TEST BOOTKIT: This is a test UEFI application for PhoenixGuard testing\r\n");
    Print(L"Not actually malicious - just for detection/recovery validation\r\n");
    Print(L"\r\n");
    
    // Sleep for 2 seconds so user can see the message
    uefi_call_wrapper(BS->Stall, 1, 2000000);
    
    // Continue normal boot by exiting
    return EFI_SUCCESS;
}
