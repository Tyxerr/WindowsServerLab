# AD Recycle Bin, fine-grained password policy, BitLocker key escrow.

# --- Recycle Bin (one-way: can't be turned off once enabled) ---
Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target lab.local -Confirm:$false

# Test: delete a user, bring it back, check group membership survived
Remove-ADUser user1 -Confirm:$false
Get-ADObject -Filter 'samAccountName -eq "user1"' -IncludeDeletedObjects | Restore-ADObject
Get-ADUser user1 -Properties MemberOf | Select-Object Name, MemberOf   # still in CN=Eng

# --- Fine-grained password policy for admins ---
New-ADFineGrainedPasswordPolicy -Name PSO-Admins -Precedence 10 `
    -MinPasswordLength 16 -PasswordHistoryCount 24 -ComplexityEnabled $true `
    -MaxPasswordAge 60.00:00:00 -MinPasswordAge 1.00:00:00 `
    -LockoutThreshold 5 -LockoutDuration 00:30:00 -LockoutObservationWindow 00:30:00 `
    -ReversibleEncryptionEnabled $false
Add-ADFineGrainedPasswordPolicySubject PSO-Admins -Subjects 'Domain Admins'
Get-ADUserResultantPasswordPolicy user1     # which PSO actually wins for a user

# --- BitLocker ---
# BitLocker Recovery tab in ADUC
Install-WindowsFeature RSAT-Feature-Tools-BitLocker-BdeAducExt

# GPO "WS - Bitlocker" on OU=Workstations:
#   Computer Config > Admin Templates > Windows Components > BitLocker Drive Encryption > Operating System Drives
#   Choose how BitLocker-protected OS drives can be recovered = Enabled
#     Save recovery info to AD DS, store recovery passwords and key packages
#     Do not enable BitLocker until recovery info is stored in AD DS

# On CL01: push the existing recovery password to AD (needed for drives encrypted before the GPO applied)
manage-bde -status C:
$kp = (Get-BitLockerVolume -MountPoint C:).KeyProtector | Where-Object KeyProtectorType -eq RecoveryPassword
Backup-BitLockerKeyProtector -MountPoint C: -KeyProtectorId $kp.KeyProtectorId
