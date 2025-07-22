$hostname = $env:COMPUTERNAME
$cert = New-SelfSignedCertificate `
  -DnsName $hostname `
  -CertStoreLocation "Cert:\LocalMachine\My" `
  -KeyUsage DigitalSignature, KeyEncipherment `
  -Type SSLServerAuthentication `
  -HashAlgorithm "SHA256" `
  -KeyLength 2048 `
  -NotAfter (Get-Date).AddYears(3)

# Export certifikátu do PFX
$pwd = ConvertTo-SecureString -String "ZabbixSecret123" -Force -AsPlainText
Export-PfxCertificate -Cert $cert `
  -FilePath "C:\Zabbix\certs\agent.pfx" `
  -Password $pwd