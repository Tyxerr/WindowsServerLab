# DNS and DHCP on the domain controllers. Run on DC01 after both DCs are promoted.

# --- DNS ---
# Reverse lookup zone, AD-integrated and replicated to every DC in the forest
Add-DnsServerPrimaryZone -NetworkId 10.10.10.0/24 -ReplicationScope Forest

# Both DCs should show up as LDAP SRV records. If one is missing, clients can't find it.
nslookup -type=SRV _ldap._tcp.dc._msdcs.lab.local

# Which DC did this machine actually pick?
nltest /dsgetdc:lab.local

# --- DHCP (install on DC01 and DC02) ---
Install-WindowsFeature DHCP -IncludeManagementTools
Add-DhcpServerInDC -DnsName dc01.lab.local -IPAddress 10.10.10.10
Add-DhcpServerInDC -DnsName dc02.lab.local -IPAddress 10.10.10.11

# Create the scope on DC01 ONLY. Failover copies it to the partner.
# If the scope already exists on DC02, Add-DhcpServerv4Failover fails ("scope already exists on the server dc02").
Add-DhcpServerv4Scope -Name Lab -StartRange 10.10.10.100 -EndRange 10.10.10.200 -SubnetMask 255.255.255.0
Set-DhcpServerv4OptionValue -ScopeId 10.10.10.0 -Router 10.10.10.1 -DnsServer 10.10.10.10,10.10.10.11 -DnsDomain lab.local

$secret = Read-Host 'Failover shared secret'

# Load balance: both servers hand out leases, 50/50
Add-DhcpServerv4Failover -Name LabFO -PartnerServer dc02.lab.local -ScopeId 10.10.10.0 `
    -LoadBalancePercent 50 -SharedSecret $secret

# Hot standby instead: one active, the other takes over after the failure timer
# Add-DhcpServerv4Failover -Name LabFO -PartnerServer dc02.lab.local -ScopeId 10.10.10.0 `
#     -ServerRole Active -ReservePercent 5 -SharedSecret $secret

Get-DhcpServerv4Failover
