#include <Uefi.h>
#include <Library/UefiLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/PrintLib.h>
#include <Protocol/SimpleFileSystem.h>
#include <Protocol/LoadedImage.h>
#include <Guid/GlobalVariable.h>
#include <Guid/FileInfo.h>

#define KEYS_DIR L"\\EFI\\PhoenixGuard\\keys\\"

STATIC EFI_STATUS ReadFile(EFI_FILE_PROTOCOL *Root, CHAR16 *Path, VOID **Buffer, UINTN *BufferSize) {
  EFI_STATUS Status;
  EFI_FILE_PROTOCOL *File = NULL;
  EFI_FILE_INFO *FileInfo = NULL;
  UINTN InfoSize = 0;

  Status = Root->Open(Root, &File, Path, EFI_FILE_MODE_READ, 0);
  if (EFI_ERROR(Status)) return Status;

  // Get file size
  Status = File->GetInfo(File, &gEfiFileInfoGuid, &InfoSize, NULL);
  if (Status == EFI_BUFFER_TOO_SMALL) {
    FileInfo = AllocateZeroPool(InfoSize);
    if (!FileInfo) { File->Close(File); return EFI_OUT_OF_RESOURCES; }
    Status = File->GetInfo(File, &gEfiFileInfoGuid, &InfoSize, FileInfo);
  }
  if (EFI_ERROR(Status)) { if (FileInfo) FreePool(FileInfo); File->Close(File); return Status; }

  *BufferSize = (UINTN)FileInfo->FileSize;
  *Buffer = AllocateZeroPool(*BufferSize);
  if (!*Buffer) { FreePool(FileInfo); File->Close(File); return EFI_OUT_OF_RESOURCES; }

  Status = File->Read(File, BufferSize, *Buffer);
  File->Close(File);
  FreePool(FileInfo);
  return Status;
}

STATIC EFI_STATUS EnrollFromAuth(EFI_FILE_PROTOCOL *Root, CHAR16 *Name, EFI_GUID *VendorGuid) {
  EFI_STATUS Status;
  CHAR16 Path[256];
  VOID *Data = NULL;
  UINTN Size = 0;
  UINT32 Attr = EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS | EFI_VARIABLE_RUNTIME_ACCESS | EFI_VARIABLE_TIME_BASED_AUTHENTICATED_WRITE_ACCESS;

  UnicodeSPrint(Path, sizeof(Path), L"%s%s", KEYS_DIR, Name);
  Status = ReadFile(Root, Path, &Data, &Size);
  if (EFI_ERROR(Status)) {
    Print(L"[Enroll] Missing %s (status=%r)\n", Path, Status);
    return Status;
  }

  Status = gRT->SetVariable(Name, VendorGuid, Attr, Size, Data);
  if (EFI_ERROR(Status)) {
    Print(L"[Enroll] SetVariable %s failed: %r\n", Name, Status);
  } else {
    Print(L"[Enroll] SetVariable %s ok (%u bytes)\n", Name, (UINT32)Size);
  }
  FreePool(Data);
  return Status;
}

EFI_STATUS EFIAPI UefiMain(IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE *SystemTable) {
  EFI_STATUS Status;
  EFI_LOADED_IMAGE_PROTOCOL *LoadedImage = NULL;
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL *Root = NULL;

  Print(L"\nPhoenixGuard Key Enroller\n==========================\n");

  Status = gBS->HandleProtocol(ImageHandle, &gEfiLoadedImageProtocolGuid, (VOID **)&LoadedImage);
  if (EFI_ERROR(Status)) { Print(L"No LoadedImage: %r\n", Status); return Status; }

  Status = gBS->HandleProtocol(LoadedImage->DeviceHandle, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs);
  if (EFI_ERROR(Status)) { Print(L"No SimpleFileSystem: %r\n", Status); return Status; }

  Status = Fs->OpenVolume(Fs, &Root);
  if (EFI_ERROR(Status)) { Print(L"OpenVolume failed: %r\n", Status); return Status; }

  // Expect pk.auth, kek.auth, db.auth under KEYS_DIR
  EFI_GUID Global = EFI_GLOBAL_VARIABLE;
  UINTN ok = 0, fail = 0;

  if (!EFI_ERROR(EnrollFromAuth(Root, L"pk.auth", &Global))) ok++; else fail++;
  if (!EFI_ERROR(EnrollFromAuth(Root, L"kek.auth", &Global))) ok++; else fail++;
  if (!EFI_ERROR(EnrollFromAuth(Root, L"db.auth", &Global))) ok++; else fail++;

  Print(L"\nEnrollment complete: %u ok, %u failed.\n", ok, fail);
  if (Root) Root->Close(Root);

  Print(L"Reboot firmware and enable Secure Boot to use the custom keys.\n");
  return EFI_SUCCESS;
}

