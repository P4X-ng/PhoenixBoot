
import binaryninja as bn

def analyze_uefi_binary(bv):
    """Analyze UEFI binary for bootkit characteristics"""
    
    # Look for EFI entry points
    entry_points = []
    for func in bv.functions:
        if "efi_main" in func.name or "ModuleEntryPoint" in func.name:
            entry_points.append(func.start)
            
    # Look for suspicious API calls
    suspicious_apis = [
        "SetVariable", "GetVariable", "GetNextVariableName",
        "InstallProtocolInterface", "ReinstallProtocolInterface",
        "LoadImage", "StartImage", "Exit"
    ]
    
    findings = []
    for api in suspicious_apis:
        for ref in bv.get_code_refs_for_symbol(api):
            findings.append({
                "api": api,
                "address": hex(ref.address),
                "function": ref.function.name if ref.function else "unknown"
            })
            
    print(f"Found {len(entry_points)} entry points")
    print(f"Found {len(findings)} suspicious API references")
    
    return {
        "entry_points": entry_points,
        "suspicious_apis": findings
    }

# Register analysis function
binaryninja.user.register_function("UEFI Bootkit Analysis", analyze_uefi_binary)
