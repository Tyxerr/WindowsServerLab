# Enterprise Root CA and a trusted certificate for RDS.

# --- CA (run as Enterprise Admin; an Enterprise CA writes to AD's configuration partition) ---
Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CACommonName 'LAB-CA' -Force

# certtmpl.msc: duplicate "Web Server" -> LabWebServer
#   Request Handling: Allow private key to be exported (the broker hands the cert to the other RDS roles)
#   Security: RDS01's computer account (or a group it's in) gets Read + Enroll
Add-CATemplate -Name LabWebServer -Force
Restart-Service certsvc

# --- On RDS01 ---
$r = Get-Certificate -Template LabWebServer -DnsName rds01.lab.local -CertStoreLocation Cert:\LocalMachine\My
$t = $r.Certificate.Thumbprint

# Bind to the RDS roles
'RDWebAccess','RDPublishing','RDRedirector' | ForEach-Object {
    Set-RDCertificate -Role $_ -Thumbprint $t -ConnectionBroker rds01.lab.local -Force
}

# Or from a PFX (what you'd do for a multi-server deployment)
# $pw = Read-Host 'PFX password' -AsSecureString
# Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$t" -FilePath C:\rdweb.pfx -Password $pw
# Set-RDCertificate -Role RDWebAccess -ImportPath C:\rdweb.pfx -Password $pw -ConnectionBroker rds01.lab.local -Force

# The RDP listener itself uses its own cert setting
$ts = Get-CimInstance -Namespace root/cimv2/TerminalServices -ClassName Win32_TSGeneralSetting -Filter "TerminalName='RDP-Tcp'"
Set-CimInstance -InputObject $ts -Property @{ SSLCertificateSHA1Hash = $t }

# Verify
Get-RDCertificate -ConnectionBroker rds01.lab.local          # Level: Trusted
Get-ChildItem Cert:\LocalMachine\My | Select-Object Subject, NotAfter, Thumbprint

# Clients: gpupdate pulls the CA root from AD, then https://rds01.lab.local/RDWeb loads clean.
# Published RemoteApps (Notepad, Paint) launch from RD Web.

# Session hosts: GPO on OU=VDA
#   Computer Config > Admin Templates > System > Group Policy >
#   Configure user Group Policy loopback processing mode = Enabled, Mode: Replace
#   (users get the session-host user settings, not the ones from their own OU)
