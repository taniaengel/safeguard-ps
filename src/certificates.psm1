# Certificate helper function
function Get-CertificateFileContents
{
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$CertificateFile
    )

    try 
    {
        $CertificateFullPath = (Resolve-Path $CertificateFile).ToString()
        if ((Get-Item $CertificateFullPath).Length -gt 100kb)
        {
            throw "'$CertificateFile' appears to be too large to be a certificate"
        }
    }
    catch
    {
        throw "'$CertificateFile' does not exist"
    }
    $CertificateContents = [string](Get-Content $CertificateFullPath)
    if (-not ($CertificateContents.StartsWith("-----BEGIN CERTIFICATE-----")))
    {
        Write-Host "Converting to Base64..."
        $CertificateContents = [System.IO.File]::ReadAllBytes($CertificateFullPath)
        $CertificateContents = [System.Convert]::ToBase64String($CertificateContents)
    }

    $CertificateContents
}
# Helper function for finding tools to generate certificates
function Get-Tool {
    Param(
        [Parameter(Mandatory=$true, Position=0)]
        [string[]]$Paths,
        [Parameter(Mandatory=$true, Position=1)]
        [string]$Tool
    )
    foreach ($path in $Paths) {
        Write-Host "Searching $path for $Tool"
        $makecerts = (Get-ChildItem -Recurse -EA SilentlyContinue $path | ?{ $_.Name -eq $Tool })
        if ($makecerts.Length -gt 0) {
            $makecerts[-1].Fullname
            return
        }
    }
    throw "Unable to find $Tool"
}

<#
.SYNOPSIS
Upload trusted certificate to Safeguard via the Web API.

.DESCRIPTION
Upload a certificate to serve as a new trusted root certificate for
Safeguard. You use this same method to upload an intermediate 
certificate that is part of the chain of trust.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER CertificateFile
A string containing the path to a certificate in DER or Base64 format.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Install-SafeguardTrustedCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Install-SafeguardTrustedCertificate "\\someserver.corp\share\Cert Root CA.cer"
#>
function Install-SafeguardTrustedCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$true,Position=0)]
        [string]$CertificateFile
    )

    $ErrorActionPreference = "Stop"

    $CertificateContents = (Get-CertificateFileContents $CertificateFile)
    if (-not $CertificateContents)
    {
        throw "No valid certificate to upload"
    }

    Write-Host "Uploading Certificate..."
    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core `
        POST TrustedCertificates -Body @{
            Base64CertificateData = "$CertificateContents" 
        }
}

<#
.SYNOPSIS
Remove trusted certificate from Safeguard via the Web API.

.DESCRIPTION
Remove a trusted certificate that was previously added to Safeguard via
the Web API.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER Thumbprint
A string containing the thumbprint of the certificate.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Uninstall-SafeguardTrustedCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Uninstall-SafeguardTrustedCertificate -Thumbprint 3E1A99AE7ACFB163DEE3CCAC00A437D675937FCA 
#>
function Uninstall-SafeguardTrustedCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false,Position=0)]
        [string]$Thumbprint
    )

    $ErrorActionPreference = "Stop"

    if (-not $Thumbprint)
    {
        $CurrentThumbprints = (Get-SafeguardTrustedCertificate -AccessToken $AccessToken -Appliance $Appliance).Thumbprint -join ", "
        Write-Host "Currently Installed Trusted Certificates: [ $CurrentThumbprints ]"
        $Thumbprint = (Read-Host "Thumbprint")
    }

    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core DELETE "TrustedCertificates/$Thumbprint"
}

<#
.SYNOPSIS
Get all trusted certificate from Safeguard via the Web API.

.DESCRIPTION
Retrieve all trusted certificates that were previously added to Safeguard via
the Web API.  These will be only the user-added trusted certificates.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Get-SafeguardTrustedCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Get-SafeguardTrustedCertificate
#>
function Get-SafeguardTrustedCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken
    )

    $ErrorActionPreference = "Stop"

    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core GET TrustedCertificates
}

<#
.SYNOPSIS
Upload SSL certificate to Safeguard appliance via the Web API.

.DESCRIPTION
Upload a certificate for use with SSL server authentication. A separate
action is required to assign an SSL certificate to a particular appliance if
you do not use the -Assign parameter. A certificate can be assigned using
the Set-SafeguardSslCertificateForAppliance cmdlet.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER CertificateFile
A string containing the path to a certificate PFX file.

.PARAMETER Password
A secure string to be used as a passphrase for the certificate PFX file.

.PARAMETER Assign
Install the certificate to this server immediately.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Install-SafeguardSslCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Install-SafeguardSslCertificate -CertificateFile C:\cert.pfx
#>
function Install-SafeguardSslCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$true,Position=0)]
        [string]$CertificateFile,
        [Parameter(Mandatory=$false,Position=1)]
        [SecureString]$Password
    )

    $ErrorActionPreference = "Stop"

    $CertificateContents = (Get-CertificateFileContents $CertificateFile)
    if (-not $CertificateContents)
    {
        throw "No valid certificate to upload"
    }

    if (-not $Password)
    {
        Write-Host "For no password just press enter..."
        $Password = (Read-host "Password" -AsSecureString)
        $PasswordPlainText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))
    }

    Write-Host "Uploading Certificate..."
    if ($PasswordPlainText)
    {
        $NewCertificate = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core `
            POST SslCertificates -Body @{
                Base64CertificateData = "$CertificateContents";
                Passphrase = "$PasswordPlainText"
            })
    }
    else
    {
        $NewCertificate = (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core `
            POST SslCertificates -Body @{
                Base64CertificateData = "$CertificateContents" 
            })
    }

    $NewCertificate

    if ($Assign -and $NewCertificate.Thumbprint)
    {
        Set-SafeguardSslCertificate -AccessToken $AccessToken -Appliance $Appliance $NewCertificate.Thumbprint
    }
}

<#
.SYNOPSIS
Remove SSL certificate from Safeguard via the Web API.

.DESCRIPTION
Remove an SSL certificate that was previously added to Safeguard via
the Web API.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER Thumbprint
A string containing the thumbprint of the certificate.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Uninstall-SafeguardSslCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Uninstall-SafeguardSslCertificate -Thumbprint 3E1A99AE7ACFB163DEE3CCAC00A437D675937FCA 
#>
function Uninstall-SafeguardSslCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false,Position=0)]
        [string]$Thumbprint
    )

    $ErrorActionPreference = "Stop"

    if (-not $Thumbprint)
    {
        $CurrentThumbprints = (Get-SafeguardSslCertificate -AccessToken $AccessToken -Appliance $Appliance).Thumbprint -join ", "
        Write-Host "Currently Installed SSL Certificates: [ $CurrentThumbprints ]"
        $Thumbprint = (Read-Host "Thumbprint")
    }

    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core DELETE "SslCertificates/$Thumbprint"
}

<#
.SYNOPSIS
Get all trusted certificate from Safeguard via the Web API.

.DESCRIPTION
Retrieve all trusted certificates that were previously added to Safeguard via
the Web API.  These will be only the user-added trusted certificates.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Get-SafeguardSslCertificate -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Get-SafeguardSslCertificate
#>
function Get-SafeguardSslCertificate
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken
    )

    $ErrorActionPreference = "Stop"

    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core GET SslCertificates
}

<#
.SYNOPSIS
Assign an SSL certificate to a specific Safeguard appliance via the Web API.

.DESCRIPTION
Assign a previously added SSL certificate to a specific Safeguard appliance via
the Web API.  If an appliance ID is not specified this cmdlet will use the appliance
that you are communicating with.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER Thumbprint
A string containing the thumbprint of the SSL certificate.

.PARAMETER ApplianceId
A string containing the ID of the appliance to assign the SSL certificate to.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Set-SafeguardTrustedCertificateForAppliance -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Set-SafeguardTrustedCertificateForAppliance -Thumbprint 3E1A99AE7ACFB163DEE3CCAC00A437D675937FCA -ApplianceId 00155D26E342
#>
function Set-SafeguardSslCertificateForAppliance
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false,Position=0)]
        [string]$Thumbprint,
        [Parameter(Mandatory=$false,Position=1)]
        [string]$ApplianceId
    )

    $ErrorActionPreference = "Stop"

    if (-not $Thumbprint)
    {
        $CurrentThumbprints = (Get-SafeguardSslCertificate -AccessToken $AccessToken -Appliance $Appliance).Thumbprint -join ", "
        Write-Host "Currently Installed SSL Certificates: [ $CurrentThumbprints ]"
        $Thumbprint = (Read-Host "Thumbprint")
    }

    if ($ApplianceId)
    {
        $ApplianceId = (Invoke-SafeguardMethod -Anonymous -Appliance $Appliance Notification GET Status).ApplianceId
    }

    Write-Host "Setting $Thumbprint as current SSL Certificate for $ApplianceId..."
    $CurrentIds = @(Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core GET "SslCertificates/$Thumbprint/Appliances")
    $CurrentIds += @{ Id = $ApplianceId }
    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core PUT "SslCertificates/$Thumbprint/Appliances" -Body $CurrentIds
}

<#
.SYNOPSIS
Unassign SSL certificate from a Safeguard appliance via the Web API.

.DESCRIPTION
Unassign SSL certificate from a Safeguard appliance that was previously
configured via the Web API.  If an appliance ID is not specified to this
cmdlet will use the appliance that you are communicating with.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER Thumbprint
A string containing the thumbprint of the SSL certificate.

.PARAMETER ApplianceId
A string containing the ID of the appliance to unassign the SSL certificate from.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Clear-SafeguardTrustedCertificateForAppliance -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Clear-SafeguardTrustedCertificateForAppliance -Thumbprint 3E1A99AE7ACFB163DEE3CCAC00A437D675937FCA -ApplianceId 00155D26E342
#>
function Clear-SafeguardSslCertificateForAppliance
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false,Position=0)]
        [string]$Thumbprint,
        [Parameter(Mandatory=$false,Position=1)]
        [string]$ApplianceId
    )

    $ErrorActionPreference = "Stop"

    if (-not $Thumbprint)
    {
        $CurrentThumbprints = (Get-SafeguardSslCertificate -AccessToken $AccessToken -Appliance $Appliance).Thumbprint -join ", "
        Write-Host "Currently Installed SSL Certificates: [ $CurrentThumbprints ]"
        $Thumbprint = (Read-Host "Thumbprint")
    }

    if (-not $ApplianceId)
    {
        $ApplianceId = (Invoke-SafeguardMethod -Anonymous -Appliance $Appliance Notification GET Status).ApplianceId
    }

    Write-Host "Clearing $Thumbprint as current SSL Certificate for $ApplianceId..."
    $CurrentIds = @(Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core GET "SslCertificates/$Thumbprint/Appliances")
    $NewIds = $CurrentIds | Where-Object { $_.Id -ne $ApplianceId }
    Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core PUT "SslCertificates/$Thumbprint/Appliances" -Body $NewIds
}

<#
.SYNOPSIS
Get SSL certificate assigned to a specific Safeguard via the Web API.

.DESCRIPTION
Get the SSL certificate that has been previously assigned to a specific
Safeguard appliance.  If an appliance ID is not specified to this cmdlet
will use the appliance that you are communicating with.

.PARAMETER Appliance
IP address or hostname of a Safeguard appliance.

.PARAMETER AccessToken
A string containing the bearer token to be used with Safeguard Web API.

.PARAMETER ApplianceId
A string containing the ID of the appliance to assign the SSL certificate to.

.INPUTS
None.

.OUTPUTS
JSON response from Safeguard Web API.

.EXAMPLE
Get-SafeguardTrustedCertificateForAppliance -AccessToken $token -Appliance 10.5.32.54

.EXAMPLE
Get-SafeguardTrustedCertificateForAppliance -ApplianceId 00155D26E342
#>
function Get-SafeguardSslCertificateForAppliance
{
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Appliance,
        [Parameter(Mandatory=$false)]
        [object]$AccessToken,
        [Parameter(Mandatory=$false,Position=1)]
        [string]$ApplianceId
    )

    $ErrorActionPreference = "Stop"

    if (-not $ApplianceId)
    {
        $ApplianceId = (Invoke-SafeguardMethod -Anonymous -Appliance $Appliance Notification GET Status).ApplianceId
    }

    $Certificates = (Get-SafeguardSslCertificate -AccessToken $AccessToken -Appliance $Appliance)
    $Certificates | ForEach-Object {
        if (Invoke-SafeguardMethod -AccessToken $AccessToken -Appliance $Appliance Core GET "SslCertificates/$($_.Thumbprint)/Appliances" | Where-Object {
            $_.Id -eq $ApplianceId
        })
        {
            $_
        }
    }
}

<#
.SYNOPSIS
Create test certificates for use with Safeguard.

.DESCRIPTION
Creates test certificates for use with Safeguard.  This cmdlet will create
a new root CA, an intermediate CA, a user certificate, and a server SSL
certificate.  The user certificate can be used for login.  The SSL certificate
can be used to secure Safeguard.

.PARAMETER SubjectBaseDn
A string containing the subject base Dn (e.g. "").

.PARAMETER KeySize
An integer with the RSA key size.

.PARAMETER Insecure
Ignore verification of Safeguard appliance SSL certificate--will be ignored for entire session.

.INPUTS
None.

.OUTPUTS
None.  Just host messages describing what has been created.

.EXAMPLE
New-SafeguardTestCertificates

.EXAMPLE
New-SafeguardTestCertificates 
#>
function New-SafeguardTestCertificates
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$SubjectBaseDn,
        [Parameter(Mandatory=$false)]
        [int]$KeySize = 2048,
        [Parameter(Mandatory=$false)]
        $OutputDirectory = "$(Get-Location)\" + ("CERTS-{0}" -f (Get-Date -format s) -replace ':','-')
    )

    Write-Host -ForegroundColor Yellow "Locating tools"
    $MakeCert = (Get-Tool @("C:\Program Files (x86)\Windows Kits", "C:\Program Files (x86)\Microsoft SDKs\Windows") "makecert.exe")
    $Pvk2Pfx = (Get-Tool @("C:\Program Files (x86)\Windows Kits", "C:\Program Files (x86)\Microsoft SDKs\Windows") "pvk2pfx.exe")
    $CertUtil = (Join-Path $env:windir "system32\certutil.exe")

    Write-Host "Creating Directory: $OutputDirectory"
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    Write-Host -ForegroundColor Yellow "Generating Certificates"
    Write-Host "This script can be annoying because you have to type your password a lot... this is a limitation of the underlying tools"
    Write-Host -ForegroundColor Yellow "Just type the same password at all of the prompts!!! It can be as simple as one letter."
    $Password = Read-Host "Password"

    $Name = "RootCA"
    $Subject = "CN=$Name,$SubjectBaseDn"
    Write-Host "Creating Root CA Certificate as $Subject"
    Invoke-Expression ("& '$MakeCert' -n '$Subject' -r -a sha256 -len $KeySize -m 240 -cy authority -sky signature -sv '$OutputDirectory\$Name.pvk' '$OutputDirectory\$Name.cer'")
    Invoke-Expression ("& '$certutil' -encode '$OutputDirectory\$Name.cer' '$OutputDirectory\$Name.pem'")
    Invoke-Expression ("& '$pvk2pfx' -pvk '$OutputDirectory\$Name.pvk' -spc '$OutputDirectory\$Name.cer' -pfx '$OutputDirectory\$Name.pfx' -pi $Password")

    $Issuer = "RootCA"
    $Name = "IntermediateCA"
    $Subject = "CN=$Name,$SubjectBaseDn"
    Write-Host "Creating Intermediate CA Certificate as $Subject"
    Invoke-Expression ("& '$MakeCert' -n '$Subject' -a sha256 -len $KeySize -m 240 -cy authority -sky signature -iv '$OutputDirectory\$Issuer.pvk' -ic '$OutputDirectory\$Issuer.cer' -sv '$OutputDirectory\$Name.pvk' '$OutputDirectory\$Name.cer'")
    Invoke-Expression ("& '$certutil' -encode '$OutputDirectory\$Name.cer' '$OutputDirectory\$Name.pem'")
    Invoke-Expression ("& '$pvk2pfx' -pvk '$OutputDirectory\$Name.pvk' -spc '$OutputDirectory\$Name.cer' -pfx '$OutputDirectory\$Name.pfx' -pi $Password")

    $Issuer = "IntermediateCA"
    $Name = "UserCert"
    $Subject = "CN=$Name,$SubjectBaseDn"
    Write-Host "Creating User Certificate as $Subject"
    Invoke-Expression ("& '$MakeCert' -n '$Subject' -a sha256 -len $KeySize -m 120 -cy end -sky exchange -eku '1.3.6.1.4.1.311.10.3.4,1.3.6.1.5.5.7.3.4,1.3.6.1.5.5.7.3.2' -iv '$OutputDirectory\$Issuer.pvk' -ic '$OutputDirectory\$Issuer.cer' -sv '$OutputDirectory\$Name.pvk' '$OutputDirectory\$Name.cer'")
    Invoke-Expression ("& '$certutil' -encode '$OutputDirectory\$Name.cer' '$OutputDirectory\$Name.pem'")
    Invoke-Expression ("& '$pvk2pfx' -pvk '$OutputDirectory\$Name.pvk' -spc '$OutputDirectory\$Name.cer' -pfx '$OutputDirectory\$Name.pfx' -pi $Password")

    $Issuer = "IntermediateCA"
    Write-Host "The IP address of your host is necessary to define the SSL Certificate subject name"
    $Name = Read-Host "IPAddress"
    $Subject = "CN=$Name,$SubjectBaseDn"
    Write-Host "Creating User Certificate as $Subject"
    Invoke-Expression ("& '$MakeCert' -n '$Subject' -a sha256 -len $KeySize -m 120 -cy end -sky exchange -eku '1.3.6.1.5.5.7.3.1' -iv '$OutputDirectory\$Issuer.pvk' -ic '$OutputDirectory\$Issuer.cer' -sv '$OutputDirectory\$Name.pvk' '$OutputDirectory\$Name.cer'")
    Invoke-Expression ("& '$certutil' -encode '$OutputDirectory\$Name.cer' '$OutputDirectory\$Name.pem'")
    Invoke-Expression ("& '$pvk2pfx' -pvk '$OutputDirectory\$Name.pvk' -spc '$OutputDirectory\$Name.cer' -pfx '$OutputDirectory\$Name.pfx' -pi $Password")

    Write-Host -ForegroundColor Yellow "You now have four certificates in $OutputDirectory."
    Write-Host "To do SSL:"
    Write-Host "- Upload both RootCA and IntermediateCA to Safeguard using Upload-SafeguardTrustedCertificate.ps1"
    Write-Host "- Upload the certificate with the IP address to Safeguard using Upload-SafeguardSSlCertificate.ps1"
    Write-Host "- Import RootCA into your trusted root store"
    Write-Host "- Import IntermediateCA into your intermediate store"
    Write-Host "- Then, open a browser... if the IP address matches the subject you gave it should work"
    Write-Host "To do certificate log in:"
    Write-Host "- Upload both RootCA and IntermediateCA if you haven't already using Upload-SafeguardTrustedCertificate.ps1"
    Write-Host "- Import UserCert into your personal user store"
    Write-Host "- Create a user with the PrimaryAuthenticationIdentity set to the thumbprint of UserCert"
    Write-Host "   - You can see your installed certificate thumbprints with: gci Cert:\CurrentUser\My\"
    Write-Host "   - The POST to create the user will need a body like this: -Body @{`n" `
    "                `"PrimaryAuthenticationProviderId`" = -2;`n" `
    "                `"UserName`" = `"CertBoy`";`n" `
    "                `"PrimaryAuthenticationIdentity`" = `"<thumbprint>`" }"
    Write-Host "- Test it by getting a token: Connect-Safeguard -Thumbprint `"<thumbprint>`""
}