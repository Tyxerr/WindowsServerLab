# OU layout, groups, bulk users, central ADMX store. Run on a DC.

$base = 'DC=lab,DC=local'

# --- OUs ---
New-ADOrganizationalUnit -Name Lab -Path $base
'Users','Workstations','Servers','Groups','VDA' | ForEach-Object {
    New-ADOrganizationalUnit -Name $_ -Path "OU=Lab,$base"
}

# --- Groups ---
'Eng','LinuxAdmins' | ForEach-Object {
    New-ADGroup -Name $_ -GroupScope Global -Path "OU=Groups,OU=Lab,$base"
}

# --- Users from CSV (see users.csv). One starting password, changed at first logon. ---
$pw = Read-Host 'Starting password' -AsSecureString
Import-Csv .\users.csv | ForEach-Object {
    New-ADUser -Name $_.Name -SamAccountName $_.Sam -Path "OU=Users,OU=Lab,$base" `
        -AccountPassword $pw -ChangePasswordAtLogon $true -Enabled $true
}
Add-ADGroupMember Eng -Members user1

# New computers join into OU=Workstations instead of CN=Computers (which can't take a GPO link)
redircmp "OU=Workstations,OU=Lab,$base"

# Move an existing computer
Get-ADComputer CL01 | Move-ADObject -TargetPath "OU=Workstations,OU=Lab,$base"

# --- Central ADMX store: every admin edits GPOs with the same templates ---
# Re-copy when a new Windows 11 release ships new ADMX files
Copy-Item C:\Windows\PolicyDefinitions \\lab.local\SYSVOL\lab.local\Policies\ -Recurse

# --- FSMO ---
netdom query fsmo
# 0..4 = PDCEmulator, RIDMaster, InfrastructureMaster, SchemaMaster, DomainNamingMaster
# First try failed with "The directory service is unavailable"; ran it again and it moved.
Move-ADDirectoryServerOperationMasterRole -Identity DC01 -OperationMasterRole 0,1,2,3,4

# --- Health ---
dcdiag /v            # DFSREvent fails on a fresh DC: SYSVOL warnings from the first 24h. Recheck the next day.
repadmin /showrepl
repadmin /replsummary
repadmin /syncall /AdeP
