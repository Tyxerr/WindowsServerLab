# Build the lab VMs on LABHOST from one sysprepped Server 2022 base disk.
# Run on the Hyper-V host. L:\ is the VM volume. Cleaned-up version of what I ran.

$Switch = 'LabNet'
$Base   = 'L:\Lab\Base2022.vhdx'

# --- Network: internal switch + NAT, so lab DHCP never leaks onto the Azure vNet ---
New-VMSwitch -Name $Switch -SwitchType Internal
New-NetIPAddress -IPAddress 10.10.10.1 -PrefixLength 24 -InterfaceAlias "vEthernet ($Switch)"
New-NetNat -Name LabNAT -InternalIPInterfaceAddressPrefix 10.10.10.0/24

# --- Base image: install once, sysprep, lock it ---
New-VM -Name BASE2022 -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath $Base -NewVHDSizeBytes 60GB -SwitchName $Switch
Add-VMDvdDrive -VMName BASE2022 -Path L:\ISO\server2022.iso
Set-VMFirmware -VMName BASE2022 -FirstBootDevice (Get-VMDvdDrive -VMName BASE2022)
Start-VM BASE2022; vmconnect localhost BASE2022
# Inside the VM: install, patch, then  sysprep /generalize /oobe /shutdown

# Read-only so nothing writes to the parent. Booting BASE2022 again would break every child disk.
Set-ItemProperty $Base -Name IsReadOnly -Value $true

# --- Servers: one differencing disk each ---
foreach ($i in 'DC01','DC02','FS01','FS02','STOR01') {
    New-VHD -Path "L:\Lab\$i.vhdx" -ParentPath $Base -Differencing
    New-VM  -Name $i -Generation 2 -MemoryStartupBytes 2GB -VHDPath "L:\Lab\$i.vhdx" -SwitchName $Switch
    Set-VM  -Name $i -ProcessorCount 2 -DynamicMemory -MemoryMinimumBytes 1GB -MemoryMaximumBytes 4GB
}

# --- Windows 11 client: needs a vTPM ---
New-VM -Name CL01 -Generation 2 -MemoryStartupBytes 4GB -NewVHDPath L:\Lab\CL01.vhdx -NewVHDSizeBytes 64GB -SwitchName $Switch
Set-VMProcessor  -VMName CL01 -Count 2
Set-VMKeyProtector -VMName CL01 -NewLocalKeyProtector
Enable-VMTPM     -VMName CL01
Add-VMDvdDrive   -VMName CL01 -Path L:\ISO\win11.iso      # full ISO path; -Path L: fails ("unable to find a physical DVD drive")
Set-VMFirmware   -VMName CL01 -FirstBootDevice (Get-VMDvdDrive -VMName CL01)
Start-VM CL01; vmconnect localhost CL01

# --- Linux VMs: Gen 2 Secure Boot needs the UEFI CA template, not the Windows one ---
Set-VMFirmware -VMName LNX01 -SecureBootTemplate MicrosoftUEFICertificateAuthority

# --- Time: virtual DCs must not take time from the host ---
# Ran this twice before Get-VMIntegrationService showed Time Synchronization = False on both
Disable-VMIntegrationService -VMName DC01,DC02 -Name 'Time Synchronization'
Get-VMIntegrationService -VMName DC01,DC02 | Where-Object Name -eq 'Time Synchronization'
