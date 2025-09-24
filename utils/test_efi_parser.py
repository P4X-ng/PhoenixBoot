#!/usr/bin/env python3
"""
Test script for EFI Parser
Demonstrates parsing your specific efi-readvar output
"""

from efi_parser import EFIParser
import json

# Your EFI variable output (truncated for demo)
efi_output = """Variable PK, length 1016
PK: List 0, type X509
    Signature 0, size 988, owner 26dc4851-195f-4ae1-9a19-fbf883bbb35e
        Subject:
            C=US, ST=PhoenixGuard, L=Firmware Liberation, O=PhoenixGuard User, CN=phoenixguard_user SecureBoot Key
        Issuer:
            C=US, ST=PhoenixGuard, L=Firmware Liberation, O=PhoenixGuard User, CN=phoenixguard_user SecureBoot Key
Variable KEK, length 1016
KEK: List 0, type X509
    Signature 0, size 988, owner 62341e11-d504-41f5-aba8-550b9aa20c14
        Subject:
            C=US, ST=PhoenixGuard, L=Firmware Liberation, O=PhoenixGuard User, CN=phoenixguard_user SecureBoot Key
        Issuer:
            C=US, ST=PhoenixGuard, L=Firmware Liberation, O=PhoenixGuard User, CN=phoenixguard_user SecureBoot Key
Variable db, length 1320
db: List 0, type SHA256
    Signature 0, size 48, owner 26dc4851-195f-4ae1-9a19-fbf883bbb35e
        Hash:724de6844dd0fe618ba5776c7bca0728be38a6544e24e44ef259b987b7abce80
db: List 1, type SHA256
    Signature 0, size 48, owner 26dc4851-195f-4ae1-9a19-fbf883bbb35e
        Hash:4caffb530989433f184353c48d8150fcdce6037933ab129249f50f0068cf1815
Variable MokList has no entries"""

def main():
    print("EFI Parser Test")
    print("=" * 50)
    
    # Create parser instance
    parser = EFIParser()
    
    # Parse the EFI output
    result = parser.parse_string(efi_output)
    
    # Display results
    print("Parsed EFI Variables:")
    print(json.dumps(result, indent=2))
    
    print("\n" + "=" * 50)
    print("Summary:")
    summary = result["summary"]
    print(f"Total Variables: {summary['total_variables']}")
    print(f"Variables with entries: {summary['variables_with_entries']}")
    print(f"Total Lists: {summary['total_lists']}")
    print(f"Total Signatures: {summary['total_signatures']}")
    
    print("\n" + "=" * 50)
    print("Variable Details:")
    for var_name, var_data in result["efi_variables"].items():
        print(f"\n{var_name}:")
        print(f"  Length: {var_data['length']} bytes")
        print(f"  Has entries: {var_data['has_entries']}")
        print(f"  Lists: {len(var_data['lists'])}")
        
        for i, list_data in enumerate(var_data["lists"]):
            print(f"    List {list_data['list_id']} ({list_data['type']}):")
            print(f"      Signatures: {len(list_data['signatures'])}")
            
            for sig in list_data["signatures"][:2]:  # Show first 2 signatures
                print(f"        Sig {sig['signature_id']}: {sig['size']} bytes, Owner: {sig['owner'][:8]}...")
                for detail_key, detail_value in sig["details"].items():
                    if len(str(detail_value)) > 60:
                        detail_value = str(detail_value)[:60] + "..."
                    print(f"          {detail_key.capitalize()}: {detail_value}")

if __name__ == "__main__":
    main()
