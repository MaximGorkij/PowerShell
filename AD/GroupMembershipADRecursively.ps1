$Recurse = $true
$GroupName = 'Domain Admins'
Add-Type -AssemblyName System.DirectoryServices.AccountManagement

# use the 'Machine' ContextType if you want to retrieve local group members
# for possible values of the numeration, visit
# http://msdn.microsoft.com/en-us/library/system.directoryservices.accountmanagement.contexttype.aspx

$ct = [System.DirectoryServices.AccountManagement.ContextType]::Domain
$group = [System.DirectoryServices.AccountManagement.GroupPrincipal]::FindByIdentity($ct,$GroupName)
$group.GetMembers($Recurse)