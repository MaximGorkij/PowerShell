$tenantId     = "ebf9edb5-a5f7-4d70-9a59-501865f222ee"
$clientId     = "5fedee17-9a32-4856-992e-d5db97596721"
$clientSecret = "fxG8Q~Aj3uB9c14dJcpobSzyGv6Xaslh5DvpicI."

$body = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $accessToken" }

# Testovací email
$email = "findrik@tauris.sk"
$uri = "https://graph.microsoft.com/beta/auditLogs/signIns?\$filter=userPrincipalName eq '$email'"
$response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

$response.value | Format-Table userPrincipalName, appDisplayName, signInEventTypes, createdDateTime