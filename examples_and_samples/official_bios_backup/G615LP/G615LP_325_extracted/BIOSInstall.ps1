#############################################################################################################
Write-Host "`n`n<----------------------------->"
$model_name = (Get-WmiObject Win32_ComputerSystem).Model
$SN_name = (Get-WmiObject Win32_BIOS).SerialNumber
$curr_BIOSver = (Get-CimInstance -ClassName Win32_BIOS).SMBIOSBIOSVersion -replace '.*(?=.{3}$)'

Write-Host " Model Name: `n $model_name"
Write-Host " SN: $SN_name"   
Write-Host " BIOS ver: $curr_BIOSver"

$firmwareDrivers = Get-CimInstance Win32_PnPSignedDriver
foreach ($driver in $firmwareDrivers) {
    if ($driver.CompatID -and $driver.CompatID -eq "UEFI\CC_00010001") {
        $SystemFirmware = $driver.InfName
        $instanceId = $driver.DeviceID
        Write-Host " Current InstanceId: `n $instanceId" 
        Write-Host " Found a match. InfName: $SystemFirmware"
        break
    }
}

$Devices_FirstScan = Get-PnpDevice -PresentOnly | 
                    Where-Object { ($_.Class -ne 'SoftwareComponent') -and ($_.FriendlyName -notmatch 'Virtual Adapter') -and ($_.InstanceId -match 'UEFI\\RES_')} | 
                    Select-Object Status, Class, FriendlyName, InstanceId, Problem
$UEFIRESDevices = $Devices_FirstScan | Where-Object {$_.InstanceId -eq $instanceId}
Write-Host " Device Status: $($UEFIRESDevices.Status)"
Write-Host " Device Problem Code: $($UEFIRESDevices.Problem)"
Write-Host "<----------------------------->"

#############################################################################################################

# #Start Cab update
$infFilePath = Join-Path (Get-Location) "Cabfile\*.inf"
$infFile = Get-ChildItem -Path $infFilePath | Select-Object -First 1
$pnputilUnCommand = "pnputil.exe /delete-driver $SystemFirmware /uninstall /force"
Write-Host "Problem Code is ''$($UEFIRESDevices.Problem)'', INF Name: $SystemFirmware, INF Path $infFile"

#Start to Uninstall and Install.
if ($UEFIRESDevices.Problem -eq "CM_PROB_NEED_RESTART" -or $UEFIRESDevices.Problem -eq "CM_PROB_FAILED_START") {
    $scriptblock = {
        $shell = New-Object -ComObject WScript.Shell
        $exec = $shell.Exec("cmd.exe /c $using:pnputilUnCommand")
        $exec.StdOut.ReadAll()
    }
    if ($SystemFirmware -ne "c_firmware.inf") {
        Start-Job -ScriptBlock $scriptblock | Wait-Job | Receive-Job
        Write-Host "Uninstall success !"
    } else {
        Write-Host "Uninstall already !!"
    }
    if ($null -ne $infFile) {
        Write-Host "$infFile is exist!"
        $pnputilInCommand = "pnputil.exe /add-driver `"$infFile`" /install"
        $scriptblock = {
            $shell = New-Object -ComObject WScript.Shell
            $exec = $shell.Exec("cmd.exe /c $using:pnputilInCommand")
            $exec.StdOut.ReadAll()
        }
        Start-Job -ScriptBlock $scriptblock | Wait-Job | Receive-Job
        Write-Host "Install Pass!"
    } else {
        Write-Host "INF not exist, Install Fail!"
    }
} else {
    $scriptblock = {
        $shell = New-Object -ComObject WScript.Shell
        $exec = $shell.Exec("cmd.exe /c $using:pnputilUnCommand")
        $exec.StdOut.ReadAll()
    }
    if ($SystemFirmware -ne "c_firmware.inf") {
        Start-Job -ScriptBlock $scriptblock | Wait-Job | Receive-Job
        Write-Host "Uninstall success !"
    } else {
        Write-Host "Uninstall already !!"
    }
    if ($null -ne $infFile) {
        Write-Host "$infFile is exist!"
        $pnputilInCommand = "pnputil.exe /add-driver `"$infFile`" /install"
        $scriptblock = {
            $shell = New-Object -ComObject WScript.Shell
            $exec = $shell.Exec("cmd.exe /c $using:pnputilInCommand")
            $exec.StdOut.ReadAll()
        }
        Start-Job -ScriptBlock $scriptblock | Wait-Job | Receive-Job
        Write-Host "Install Pass!"
    } else {
        Write-Host "INF not exist, Install Fail!"
    }
}
# Finish !
#############################################################################################################

# SIG # Begin signature block
# MIIp2AYJKoZIhvcNAQcCoIIpyTCCKcUCAQExDzANBglghkgBZQMEAgIFADCBiQYK
# KwYBBAGCNwIBBKB7MHkwNAYKKwYBBAGCNwIBHjAmAgMBAAAEEB/MO2BZSwhOtyTS
# xil+81ECAQACAQACAQACAQACAQAwQTANBglghkgBZQMEAgIFAAQwTMvJZnSsA4QI
# Wh0wUSOKEl9i1VcdvPPsRIRN1ywF9vu75RbGZDaw2xezDlizHxAyoIIOiDCCBrAw
# ggSYoAMCAQICEAitQLJg0pxMn17Nqb2TrtkwDQYJKoZIhvcNAQEMBQAwYjELMAkG
# A1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRp
# Z2ljZXJ0LmNvbTEhMB8GA1UEAxMYRGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4X
# DTIxMDQyOTAwMDAwMFoXDTM2MDQyODIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVk
# IEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMTCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANW0L0LQKK14t13VOVkbsYhC9TOM6z2B
# l3DFu8SFJjCfpI5o2Fz16zQkB+FLT9N4Q/QX1x7a+dLVZxpSTw6hV/yImcGRzIED
# Pk1wJGSzjeIIfTR9TIBXEmtDmpnyxTsf8u/LR1oTpkyzASAl8xDTi7L7CPCK4J0J
# wGWn+piASTWHPVEZ6JAheEUuoZ8s4RjCGszF7pNJcEIyj/vG6hzzZWiRok1MghFI
# UmjeEL0UV13oGBNlxX+yT4UsSKRWhDXW+S6cqgAV0Tf+GgaUwnzI6hsy5srC9Kej
# Aw50pa85tqtgEuPo1rn3MeHcreQYoNjBI0dHs6EPbqOrbZgGgxu3amct0r1EGpIQ
# gY+wOwnXx5syWsL/amBUi0nBk+3htFzgb+sm+YzVsvk4EObqzpH1vtP7b5NhNFy8
# k0UogzYqZihfsHPOiyYlBrKD1Fz2FRlM7WLgXjPy6OjsCqewAyuRsjZ5vvetCB51
# pmXMu+NIUPN3kRr+21CiRshhWJj1fAIWPIMorTmG7NS3DVPQ+EfmdTCN7DCTdhSm
# W0tddGFNPxKRdt6/WMtyEClB8NXFbSZ2aBFBE1ia3CYrAfSJTVnbeM+BSj5AR1/J
# gVBzhRAjIVlgimRUwcwhGug4GXxmHM14OEUwmU//Y09Mu6oNCFNBfFg9R7P6tuyM
# MgkCzGw8DFYRAgMBAAGjggFZMIIBVTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1Ud
# DgQWBBRoN+Drtjv4XxGG+/5hewiIZfROQjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzf
# Lmc/57qYrhwPTzAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMw
# dwYIKwYBBQUHAQEEazBpMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2Vy
# dC5jb20wQQYIKwYBBQUHMAKGNWh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMBwG
# A1UdIAQVMBMwBwYFZ4EMAQMwCAYGZ4EMAQQBMA0GCSqGSIb3DQEBDAUAA4ICAQA6
# I0Q9jQh27o+8OpnTVuACGqX4SDTzLLbmdGb3lHKxAMqvbDAnExKekESfS/2eo3wm
# 1Te8Ol1IbZXVP0n0J7sWgUVQ/Zy9toXgdn43ccsi91qqkM/1k2rj6yDR1VB5iJqK
# isG2vaFIGH7c2IAaERkYzWGZgVb2yeN258TkG19D+D6U/3Y5PZ7Umc9K3SjrXyah
# lVhI1Rr+1yc//ZDRdobdHLBgXPMNqO7giaG9OeE4Ttpuuzad++UhU1rDyulq8aI+
# 20O4M8hPOBSSmfXdzlRt2V0CFB9AM3wD4pWywiF1c1LLRtjENByipUuNzW92NyyF
# PxrOJukYvpAHsEN/lYgggnDwzMrv/Sk1XB+JOFX3N4qLCaHLC+kxGv8uGVw5ceG+
# nKcKBtYmZ7eS5k5f3nqsSc8upHSSrds8pJyGH+PBVhsrI/+PteqIe3Br5qC6/To/
# RabE6BaRUotBwEiES5ZNq0RA443wFSjO7fEYVgcqLxDEDAhkPDOPriiMPMuPiAsN
# vzv0zh57ju+168u38HcT5ucoP6wSrqUvImxB+YJcFWbMbA7KxYbD9iYzDAdLoNMH
# AmpqQDBISzSoUSC7rRuFCOJZDW3KBVAr6kocnqX9oKcfBnTn8tZSkP2vhUgh+Vc7
# tJwD7YZF9LRhbr9o4iZghurIr6n+lB3nYxs6hlZ4TjCCB9AwggW4oAMCAQICEA3W
# nsNBA2swtlbcSS+BvowwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAV
# BgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVk
# IEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMTAeFw0yNDAz
# MjgwMDAwMDBaFw0yNjExMTAyMzU5NTlaMIHYMRMwEQYLKwYBBAGCNzwCAQMTAlRX
# MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjERMA8GA1UEBRMIMjM2Mzg3
# NzcxCzAJBgNVBAYTAlRXMRQwEgYDVQQIEwtUYWlwZWkgQ2l0eTEYMBYGA1UEBxMP
# QmVpdG91IERpc3RyaWN0MR4wHAYDVQQKExVBU1VTVGVLIENPTVBVVEVSIElOQy4x
# EjAQBgNVBAsTCVNXIENlbnRlcjEeMBwGA1UEAxMVQVNVU1RlSyBDT01QVVRFUiBJ
# TkMuMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA4cy8eNLamr+VSRLy
# /lRzYzjuWx1pT2Tcosc6CjFlyJ+UU7RDuIepMaGeZcV0JFBPTxfHDpRMey41MZfS
# 1OslTjNAr+LpwjvWFYWbUkjO16HU3QYag5qN8AKlXC7Soj73baEQsIK7hKmc1W9s
# 9Z/L4sp3l0/mDAXWYC4ubjnxT86R7hY4wj8Z0R+1rYpU+eM/fZSP6y+vrUT1HdKw
# xYtjnpOMt5HEc19LFHXxDODY9KNLcEwhlUCiYHWFlUC51Jura5rYSNgTnFBiLBqv
# XsAjI4i4j0eu0hNI84YEOAcCw8WDHnzNiE5/Hg/FZu4XZsHa0tPyyhnI95f++1aX
# 2y8nc+b4SyrZU6ZMBTHWixpj8K6TUuDrwcBoFoNQ0MVjUe4yvcC9OrvLkfD8LR9m
# IkOSIcyzhtsyh1saRhAASBUlBnr4oJiFgzhkwJELSp8h3WewXoC6OmhTT8D0NeJL
# RXEfzuenLq/OS7Fw5pfO4pIsoV7A738IosPxoeSqrg09SXeThpkPKyMDSSlIkYhp
# +RLejhZaK4Tt1SlCjWM/IXG63Vrui3DGIkHqtHaA9jMNz+bhMwKFP2hqM10MGpPy
# d1z/E6Rj2xaXRnkYrykR3wFCrT7SGAbmnLwaW/ZbbbICPsmrk9Aruu19W5MQk/nd
# C4/x+C5/g/qfBiSFLUz3cKksF6MCAwEAAaOCAgIwggH+MB8GA1UdIwQYMBaAFGg3
# 4Ou2O/hfEYb7/mF7CIhl9E5CMB0GA1UdDgQWBBSWK4Ql50Ch/Nn00iJ8G8D+Uc5p
# GTA9BgNVHSAENjA0MDIGBWeBDAEDMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cu
# ZGlnaWNlcnQuY29tL0NQUzAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYB
# BQUHAwMwgbUGA1UdHwSBrTCBqjBToFGgT4ZNaHR0cDovL2NybDMuZGlnaWNlcnQu
# Y29tL0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAy
# MUNBMS5jcmwwU6BRoE+GTWh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4NDIwMjFDQTEuY3JsMIGU
# BggrBgEFBQcBAQSBhzCBhDAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMFwGCCsGAQUFBzAChlBodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZTSEEzODQyMDIxQ0Ex
# LmNydDAJBgNVHRMEAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQAT0baYaCNR0uRY3lmf
# MANofGe961ucVCnfyP13M8BwhtjMXTuEScqNpJPdSgYi64BLGlPGfXfyWqxdE2BD
# n2gqpt7act5HSGPjnqplf7HLIHCO5QYKowr9RvtjtBMEF853rD5ULuaFqXL16b74
# Qbqy2BVZVOOq6ffGw2AvpHTjC6DC80HtkWHNw9SdaiX8RemMEYV4e0GlR94zKbz5
# 7zfXv8xeitYDIlh2C+CMU7VjHBW7poL2c7JPp65kcfqsoIRQCMZhz3T75eFjg4os
# qTcJ/P0oU7d+b7xlPwnr24QnTCbq2WIOCc0hXxBqJxSv4GeclkndyHizHidD8CB5
# rNbBs+MxkB5gjE4wmbrGN81R4+fDrL+qhI6lXMnfwwIn7Ib+NAHrC0JVArhWQX4o
# XdCh4xdXbfe3eFKGIuUgBwRYxn47U/J0Mol0symlxiaeecwV4Oo/F2qUwElNbQPF
# 6yk2a2Ta/CmXMOyVaECVvGzgubQuOyW7jBIP6NcXw4v6sAuxV33r8RvPSB2Sx+DC
# yg6tGsXkp48Vi7kDO1UXCfMS9AATg2q7pAN7h8VPaWaI2voYhxmMw1TqQPQEi1B+
# IaPS27jpM/thnhTMlbLlUyksi6+c3P/SAepehGJIN3DobKCmwla35be5Lccfk2V3
# 5VgkEesnpF2voTCX9FtE2W9kBTGCGpUwghqRAgEBMH0waTELMAkGA1UEBhMCVVMx
# FzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVz
# dGVkIEc0IENvZGUgU2lnbmluZyBSU0E0MDk2IFNIQTM4NCAyMDIxIENBMQIQDdae
# w0EDazC2VtxJL4G+jDANBglghkgBZQMEAgIFAKCBjDAQBgorBgEEAYI3AgEMMQIw
# ADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYK
# KwYBBAGCNwIBFTA/BgkqhkiG9w0BCQQxMgQweK7yX8u3csjXL2rjCWFqO+XHjX+r
# kbbhqxgogS11eC8Bor+XWKdnefd2oIkiYjOMMA0GCSqGSIb3DQEBAQUABIICAF59
# FON8cWJCaXuWRn6mglfK1xJZWD5JFZW4wklhLXNOmZ1u907d1fLtVAcDyS+1PjSA
# 1lwDM9xINOPrNAXxnsM7p98IzSuYchJMW2daD+RGYopL+ULSMLW9LaeI41VFpEin
# jgrWWGmtRDTkFJBYcM5yK/rgD/+MhF2Q0XDACbLhbqZ+Omja25H2nFuJKJLXIOU+
# W5SmndM8NMqKwH9HI/Q8HqMxgrXwrexW3l4h++4SkoQQDNyEnMyaB2S5qGI7SAZl
# GodlxldeqBSbNTtnAQUOsr3x5Amn/+TEkaA9wJZPIVImL/Hub7zs6h3VUaQPBnTr
# hvQHDLCK/0Kw9Zcx8uquxJKEvxwomNBQ3AVpqRSfcj2R7jlZYJ/stpAkc222rjrR
# c6bCnl6+XkpOyAFcpNO3InUwXqzGMTzb619oRTt1yLHpMi1SjeptZ4kivQzXRq5l
# gY7Z0oBFRoBGXMBFZ01tDYhLUh2UEZrTGk5UTABbQ/K8x1MhlOJc1Odh2PU77qku
# EVzD6k5hLy0ArgxmZABfe5leVPIufU8jaZ9ngLXj02rQmvR35J+I/PcaqHwcWnDq
# m0WbW8fmmUVIqawkgugBSnO6dYUqOfhMeMKzQfaB2B1Ehj2SngLSLLXnvfceTlqD
# gFywT/L5oFAI9SyVO/6Stz20H7/aV1Akh5gj4RfhoYIXWjCCF1YGCisGAQQBgjcD
# AwExghdGMIIXQgYJKoZIhvcNAQcCoIIXMzCCFy8CAQMxDzANBglghkgBZQMEAgIF
# ADCBhwYLKoZIhvcNAQkQAQSgeAR2MHQCAQEGCWCGSAGG/WwHATBBMA0GCWCGSAFl
# AwQCAgUABDCeHyAbbz7FkBffLJHXpqaTUATlhFGFiZuZMUvE5Fl/GGjZSfjSQvhd
# BdPMgmwNN6gCED7+RWWl5YSzrO/MbLmIZrcYDzIwMjQxMTI1MDEzODQ5WqCCEwMw
# gga8MIIEpKADAgECAhALrma8Wrp/lYfG+ekE4zMEMA0GCSqGSIb3DQEBCwUAMGMx
# CzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMy
# RGlnaUNlcnQgVHJ1c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcg
# Q0EwHhcNMjQwOTI2MDAwMDAwWhcNMzUxMTI1MjM1OTU5WjBCMQswCQYDVQQGEwJV
# UzERMA8GA1UEChMIRGlnaUNlcnQxIDAeBgNVBAMTF0RpZ2lDZXJ0IFRpbWVzdGFt
# cCAyMDI0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvmpzn/aVIauW
# MLpbbeZZo7Xo/ZEfGMSIO2qZ46XB/QowIEMSvgjEdEZ3v4vrrTHleW1JWGErrjOL
# 0J4L0HqVR1czSzvUQ5xF7z4IQmn7dHY7yijvoQ7ujm0u6yXF2v1CrzZopykD07/9
# fpAT4BxpT9vJoJqAsP8YuhRvflJ9YeHjes4fduksTHulntq9WelRWY++TFPxzZrb
# ILRYynyEy7rS1lHQKFpXvo2GePfsMRhNf1F41nyEg5h7iOXv+vjX0K8RhUisfqw3
# TTLHj1uhS66YX2LZPxS4oaf33rp9HlfqSBePejlYeEdU740GKQM7SaVSH3TbBL8R
# 6HwX9QVpGnXPlKdE4fBIn5BBFnV+KwPxRNUNK6lYk2y1WSKour4hJN0SMkoaNV8h
# yyADiX1xuTxKaXN12HgR+8WulU2d6zhzXomJ2PleI9V2yfmfXSPGYanGgxzqI+Sh
# oOGLomMd3mJt92nm7Mheng/TBeSA2z4I78JpwGpTRHiT7yHqBiV2ngUIyCtd0pZ8
# zg3S7bk4QC4RrcnKJ3FbjyPAGogmoiZ33c1HG93Vp6lJ415ERcC7bFQMRbxqrMVA
# Niav1k425zYyFMyLNyE1QulQSgDpW9rtvVcIH7WvG9sqYup9j8z9J1XqbBZPJ5XL
# ln8mS8wWmdDLnBHXgYly/p1DhoQo5fkCAwEAAaOCAYswggGHMA4GA1UdDwEB/wQE
# AwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMCAGA1Ud
# IAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATAfBgNVHSMEGDAWgBS6FtltTYUv
# cyl2mi91jGogj57IbzAdBgNVHQ4EFgQUn1csA3cOKBWQZqVjXu5Pkh92oFswWgYD
# VR0fBFMwUTBPoE2gS4ZJaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNybDCBkAYIKwYB
# BQUHAQEEgYMwgYAwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNv
# bTBYBggrBgEFBQcwAoZMaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNydDANBgkq
# hkiG9w0BAQsFAAOCAgEAPa0eH3aZW+M4hBJH2UOR9hHbm04IHdEoT8/T3HuBSyZe
# q3jSi5GXeWP7xCKhVireKCnCs+8GZl2uVYFvQe+pPTScVJeCZSsMo1JCoZN2mMew
# /L4tpqVNbSpWO9QGFwfMEy60HofN6V51sMLMXNTLfhVqs+e8haupWiArSozyAmGH
# /6oMQAh078qRh6wvJNU6gnh5OruCP1QUAvVSu4kqVOcJVozZR5RRb/zPd++PGE3q
# F1P3xWvYViUJLsxtvge/mzA75oBfFZSbdakHJe2BVDGIGVNVjOp8sNt70+kEoMF+
# T6tptMUNlehSR7vM+C13v9+9ZOUKzfRUAYSyyEmYtsnpltD/GWX8eM70ls1V6QG/
# ZOB6b6Yum1HvIiulqJ1Elesj5TMHq8CWT/xrW7twipXTJ5/i5pkU5E16RSBAdOp1
# 2aw8IQhhA/vEbFkEiF2abhuFixUDobZaA0VhqAsMHOmaT3XThZDNi5U2zHKhUs5u
# HHdG6BoQau75KiNbh0c+hatSF+02kULkftARjsyEpHKsF7u5zKRbt5oK5YGwFvgc
# 4pEVUNytmB3BpIiowOIIuDgP5M9WArHYSAR16gc0dP2XdkMEP5eBsX7bf/MGN4K3
# HP50v/01ZHo/Z5lGLvNwQ7XHBx1yomzLP8lx4Q1zZKDyHcp4VQJLu2kWTsKsOqQw
# ggauMIIElqADAgECAhAHNje3JFR82Ees/ShmKl5bMA0GCSqGSIb3DQEBCwUAMGIx
# CzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3
# dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBH
# NDAeFw0yMjAzMjMwMDAwMDBaFw0zNzAzMjIyMzU5NTlaMGMxCzAJBgNVBAYTAlVT
# MRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgVHJ1
# c3RlZCBHNCBSU0E0MDk2IFNIQTI1NiBUaW1lU3RhbXBpbmcgQ0EwggIiMA0GCSqG
# SIb3DQEBAQUAA4ICDwAwggIKAoICAQDGhjUGSbPBPXJJUVXHJQPE8pE3qZdRodbS
# g9GeTKJtoLDMg/la9hGhRBVCX6SI82j6ffOciQt/nR+eDzMfUBMLJnOWbfhXqAJ9
# /UO0hNoR8XOxs+4rgISKIhjf69o9xBd/qxkrPkLcZ47qUT3w1lbU5ygt69OxtXXn
# HwZljZQp09nsad/ZkIdGAHvbREGJ3HxqV3rwN3mfXazL6IRktFLydkf3YYMZ3V+0
# VAshaG43IbtArF+y3kp9zvU5EmfvDqVjbOSmxR3NNg1c1eYbqMFkdECnwHLFuk4f
# sbVYTXn+149zk6wsOeKlSNbwsDETqVcplicu9Yemj052FVUmcJgmf6AaRyBD40Nj
# gHt1biclkJg6OBGz9vae5jtb7IHeIhTZgirHkr+g3uM+onP65x9abJTyUpURK1h0
# QCirc0PO30qhHGs4xSnzyqqWc0Jon7ZGs506o9UD4L/wojzKQtwYSH8UNM/STKvv
# mz3+DrhkKvp1KCRB7UK/BZxmSVJQ9FHzNklNiyDSLFc1eSuo80VgvCONWPfcYd6T
# /jnA+bIwpUzX6ZhKWD7TA4j+s4/TXkt2ElGTyYwMO1uKIqjBJgj5FBASA31fI7tk
# 42PgpuE+9sJ0sj8eCXbsq11GdeJgo1gJASgADoRU7s7pXcheMBK9Rp6103a50g5r
# mQzSM7TNsQIDAQABo4IBXTCCAVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4E
# FgQUuhbZbU2FL3MpdpovdYxqII+eyG8wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5n
# P+e6mK4cD08wDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcG
# CCsGAQUFBwEBBGswaTAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQu
# Y29tMEEGCCsGAQUFBzAChjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGln
# aUNlcnRUcnVzdGVkUm9vdEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8v
# Y3JsMy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNV
# HSAEGTAXMAgGBmeBDAEEAjALBglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIB
# AH1ZjsCTtm+YqUQiAX5m1tghQuGwGC4QTRPPMFPOvxj7x1Bd4ksp+3CKDaopafxp
# wc8dB+k+YMjYC+VcW9dth/qEICU0MWfNthKWb8RQTGIdDAiCqBa9qVbPFXONASIl
# zpVpP0d3+3J0FNf/q0+KLHqrhc1DX+1gtqpPkWaeLJ7giqzl/Yy8ZCaHbJK9nXzQ
# cAp876i8dU+6WvepELJd6f8oVInw1YpxdmXazPByoyP6wCeCRK6ZJxurJB4mwbfe
# Kuv2nrF5mYGjVoarCkXJ38SNoOeY+/umnXKvxMfBwWpx2cYTgAnEtp/Nh4cku0+j
# Sbl3ZpHxcpzpSwJSpzd+k1OsOx0ISQ+UzTl63f8lY5knLD0/a6fxZsNBzU+2QJsh
# IUDQtxMkzdwdeDrknq3lNHGS1yZr5Dhzq6YBT70/O3itTK37xJV77QpfMzmHQXh6
# OOmc4d0j/R0o08f56PGYX/sr2H7yRp11LB4nLCbbbxV7HhmLNriT1ObyF5lZynDw
# N7+YAN8gFk8n+2BnFqFmut1VwDophrCYoCvtlUG3OtUVmDG0YgkPCr2B2RP+v6TR
# 81fZvAT6gt4y3wSJ8ADNXcL50CN/AAvkdgIm2fBldkKmKYcJRyvmfxqkhQ/8mJb2
# VVQrH4D6wPIOK+XW+6kvRBVK5xMOHds3OBqhK/bt1nz8MIIFjTCCBHWgAwIBAgIQ
# DpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAx
# MDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQD
# ExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aa
# za57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllV
# cq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT
# +CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd
# 463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+
# EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92k
# J7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5j
# rubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7
# f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJU
# KSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+wh
# X8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQAB
# o4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5n
# P+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0P
# AQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDww
# OqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJ
# RFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IB
# AQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229
# GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FD
# RJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVG
# amlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCw
# rFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvR
# XKwYw02fc7cBqZ9Xql4o4rmUMYIDhjCCA4ICAQEwdzBjMQswCQYDVQQGEwJVUzEX
# MBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRpZ2lDZXJ0IFRydXN0
# ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENBAhALrma8Wrp/lYfG
# +ekE4zMEMA0GCWCGSAFlAwQCAgUAoIHhMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0B
# CRABBDAcBgkqhkiG9w0BCQUxDxcNMjQxMTI1MDEzODQ5WjArBgsqhkiG9w0BCRAC
# DDEcMBowGDAWBBTb04XuYtvSPnvk9nFIUIck1YZbRTA3BgsqhkiG9w0BCRACLzEo
# MCYwJDAiBCB2dp+o8mMvH0MLOiMwrtZWdf7Xc9sF1mW5BZOYQ4+a2zA/BgkqhkiG
# 9w0BCQQxMgQwbAO4kaFeZzcw8+MGZ5w9yOlc74ixLwkMjse7t3RTxoqM2yOErKsP
# pT8Kw+dmBoMEMA0GCSqGSIb3DQEBAQUABIICAGZMYoDlM3UW+BfsWQutzb+UFuy9
# Ol/2kBei17kQnechnIqT0NLU0QJERWUfU0GzcbMhRCFnnVAZSdv7fMIlIpuXuXmm
# 4IEp972JN1BAi9/BTaymQ+WbfaWf/UHHnC7QbEExq1zKzGvA7a0ucTDqReYUYsVu
# cVPl5tXItZxKewghhkuKfpa5ZTf8Slo5zeSRuJKzqjCqNb+O+P3Sb3/l1Z5gnaxi
# Gb0/BeYkvGVJlLoxUN3abJVGsPARodgk1BayzrBwisyu+p+gKY4qRu+jXolwJzwL
# 6y6Y6jWkC1lBwinxHsjMpVNWHgb4XmvrpSjJovNSTAF3wVZkBbdW59i6wm7dytn5
# c+Y62H7jKsyRrWNVYi2newsWMqd5pSVXPCrYdWYRGO9MNpuhNRcosCc0ld74Tfri
# raraWpzSn6YwR9TeAxpcVQLNjbbEjeuAlIJ+SRRxhuP28xshHpTysBiP8UyGYUXi
# PbQJjUa70FmOrfl2W6Or9n0++Ercq2wpPHqm9CK9kAlc2AqALLS6M6qo7Y6/2xGg
# MIufBpcE53eJ6wodykGJkjTNKm+0jjrg0OC/Z2Y4rC6cZdnbCHemSMJfe0/b0efQ
# OfRN4WeSdjalFg6Xd9x3EmnmlddIdqT0XxG5swtiHKSjFU2Ij23y1gLn3nIIqdbV
# dfPSDoOBSAyG1Lwc
# SIG # End signature block
