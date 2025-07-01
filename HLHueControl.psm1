# WORK IN PROGRESS

# TO DO: something about saving initial fetching of bridge ID + IP into a class or variable?
# TO DO: modify/recompile FindDevice.exe to fetch TXT records for full bridge ID

# https://developers.meethue.com/develop/hue-api-v2/core-concepts/
# We have some limitations to bear in mind:

# We can’t send commands to the lights too fast. If you stick to around 10 commands per second to the /light resource as maximum you should be fine. For /grouped_light commands you should keep to a maximum of 1 per second. The REST API should not be used to send a continuous stream of fast light updates for an extended period of time, for that use case you should use the dedicated Hue Entertainment Streaming API.


function Get-HueBridge {
<#
    .SYNOPSIS
    Gets information about the Hue bridges available on the local network.
    
    .DESCRIPTION
    Get-HueBridge utilises mDNS discovery to retrieve information about the Hue bridges on the local network. This cmdlet utilises Microsoft's FindDevice.exe command line tool.

    .PARAMETER Timeout
    Optional parameter for specifying the discovery timeout in milliseconds. As noted in the FindDevice.exe documentation, a default of 2000ms or greater is recommended for intitiating device discovery over Wi-Fi.

    .EXAMPLE
    Get-HueBridge -Timeout 3000

    .NOTES
    Get-HueBridge performs an initial check for the required Windows Defender Firewall rule and will create an inbound rule allowing FindDevice.exe to receive connections from the local subnet on port UDP/5353 if required. As such, an administator PowerShell session is required if running Get-HueBridge for the first time.
    
    There is an unfortunate limitation with FindDevice.exe in that it only requests A / AAAA records and consequently does not return the full bridge id (contained within the TXT record) required for authenticating HTTPS requests. Looking at the code, this omission stems from the underlying Makaretu.Dns.Multicast package. It is relatively trivial to add this functionality (see link 5), but I have no real experience with C# or software development in general and do not have the requisite skills, at this point, to compile the amended code into a modified application version. 
    
    As such, attempting to pipe Get-HueBridge to other cmdlets in HLHueControl will sadly fail. 
    
    .LINK
    https://github.com/microsoft/FindDevice

    .LINK
    https://developers.meethue.com/develop/application-design-guidance/hue-bridge-discovery/
    
    .LINK
    https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml?&search=hue

    .LINK
    https://github.com/richardschneider/net-mdns/tree/master

    .LINK
    https://github.com/richardschneider/net-mdns/issues/112 

    .LINK
    https://learn.microsoft.com/en-us/dotnet/api/system.io.filenotfoundexception?view=net-9.0
#>
    [CmdletBinding()]
    param(
        [Parameter()] 
        [int] $Timeout = 2500
    )
    begin {
    }
    process {
        Write-Verbose "[PROCESS] Establishing path to FindDevice.exe"
        $FindDeviceExe = Join-Path -Path $PSScriptRoot -ChildPath 'FindDevice-win-x64\FindDevice.exe'
        switch (Test-Path $FindDeviceExe) {
            $false { throw [System.IO.FileNotFoundException] "$FindDeviceExe not found" }
            Default { Write-Verbose "[PROCESS] $FindDeviceExe" }
        }
        try {
            Write-Verbose "[PROCESS] Checking firewall rules"
            if (Get-NetFirewallRule -DisplayName "finddevice.exe" -ErrorAction SilentlyContinue) {
                Write-Verbose "[PROCESS] Removing permissive firewall rules"
                Remove-NetFirewallRule -DisplayName "finddevice.exe" -ErrorAction Stop
                Write-Verbose "[PROCESS] Firewall rules removed"
            }
            if (Get-NetFirewallRule -DisplayName "Get-HueBridge mDNS" -ErrorAction SilentlyContinue) {
                Write-Verbose "[PROCESS] Get-HueBridge firewall rule present"
            }
            else {
                Write-Verbose "[PROCESS] Creating firewall rule"
                New-NetFirewallRule -DisplayName "Get-HueBridge mDNS" -Direction Inbound -Program $FindDeviceExe -RemoteAddress LocalSubnet -Action Allow -Protocol UDP -LocalPort 5353 -Profile Public, Private -ErrorAction Stop | Out-Null
                Write-Verbose "[PROCESS] Firewall rule created"
            }
            $arguments = @('--service' , '_hue._tcp.local' 
            '--timeout' , $Timeout
            ) 
            Write-Verbose "[PROCESS] Searching for connected bridges on local network"
            Write-Verbose "Invoking $FindDeviceExe with arguments: $($arguments -join ' ')"
            $Bridges = & $FindDeviceExe @arguments
            ($Bridges -match 'Discovered').TrimStart('Discovered:') | ForEach-Object { 
                $Items = -split $_
                [PSCustomObject]@{
                    "BridgeHostName"=($Items[0])
                    "BridgeId"=($Items[0]).TrimEnd(".local") # as explained in the notes, this is not the full bridge id 
                    "BridgeIP"=$Items[1]
                }
            }   
        }
        catch [System.Management.Automation.ActionPreferenceStopException] {
            Write-Error -Message $PSItem.Exception.Message -RecommendedAction "If running for the first time, run cmdlet in an admin PowerShell window to modify firewall rules." -Category InvalidOperation 
        }
        catch {
            Write-Error -Message $PSItem.Exception
        }
    }   
} 
    
    
function Get-HueBridgeFromDiscoveryEndpoint {
<#
    .SYNOPSIS
    Fetches the ID, LAN IP and port of Hue bridges connected to the local network.

    .DESCRIPTION
    Get-HueBridgeFromDiscoveryEndpoint sends a GET request over HTTPS to the Hue Discovery Endpoint to fetch the ID, LAN IP, and port of all Hue bridges on the local network. As noted in the Hue developer documentation, this presupposes that the bridge has connected to the Hue Cloud at least once. 
    
    .NOTES
    The Hue developer documentation also states that if a bridge does not poll the Hue Cloud for a "longer period", the Cloud will consider the bridge disconnected. I have not tested if this causes the bridge to fall off the discovery endpoint.

    There is a highly restrictive rate limit for sending requests to the endpoint (one request per 15 minutes) which makes this a suboptimal method of discovery.
    
    .LINK
    https://developers.meethue.com/develop/application-design-guidance/hue-bridge-discovery/
#>
    [CmdletBinding()]
    param (
    )
    begin {      
    }
    process {
        Write-Warning -Message "There is a rate limit of 1 request /15 minutes for the Hue discovery endpoint; as such, repeated running of this cmdlet will likely result in HTTP 429 errors. Do you acknowledge this limitation?" -WarningAction Inquire 
        try {
            $Response = Invoke-RestMethod -Uri "https://discovery.meethue.com/" -Method Get
            foreach ($bridge in $Response) {
                [PSCustomObject]@{
                    BridgeId = $bridge.id
                    BridgeIP = $bridge.internalipaddress
                    Port = $bridge.port
                }
            }
        }
        catch {
            Write-Error -Message $PSItem.Exception.Message -RecommendedAction "You have likely exceeded the rate limit. Wait 15 minutes and try again." -Category ConnectionError
        }
    }
}


function Get-HueDevices {
<#
    .SYNOPSIS
    Fetches the devices currently connected to a Hue bridge.    

    .DESCRIPTION
    Get-HueDevices fetches the devices currently connected to the specified Hue bridge and returns information about each one, including, where applicable, the lightId which is required for controlling connected lights via the Hue API. Requests are made over HTTPS using TLSv1.2, presupposing the presence of the Hue root CA.
    
    Note: this function does not retrieve information about grouped lights. Use Get-HueGroupedLights for this purpose. 

    .PARAMETER ApplicationKey
    The application key for authenticating REST requests to the Hue API. 

    .PARAMETER BridgeId
    The Id of the bridge. This is a requirement for HTTPS authentication.
    
    .EXAMPLE
    Get-HueDevices -ApplicationKey $ApplicationKey -BridgeId $BridgeId
    
    .EXAMPLE
    Get-HueDevices -ApplicationKey (Get-AzKeyVaultSecret -VaultName TestVault -Name HueApplicationKey -AsPlainText) -BridgeId $BridgeId

    .EXAMPLE
    Get-HueBridge | Get-HueDevices -ApplicationKey $ApplicationKey
    
    .INPUTS
    System.String

    .NOTES
    Get-HueDevices checks for the Hue root CA in the Trusted Root CA store and will throw a FileNotFoundException if this check fails. See first related link for guidance (requires Hue developer account).
    
    .LINK
    https://developers.meethue.com/develop/application-design-guidance/using-https/
    
    .LINK
    https://developers.meethue.com/develop/hue-api-v2/api-reference/

    .LINK
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod?view=powershell-7.5
#>
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory=$true,
            ValueFromPipeline=$true)]
        [string] $ApplicationKey,
        [Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [string] $BridgeId
    )
    begin {
        $Uri = "https://192.168.1.63/clip/v2/resource/device"
        $BridgeId = "ecb5fafffe94f0ec" # this is included until I find a way to reliably fetch the Hue bridge Id using mDNS. See notes section of Get-HueBridge for detail of this limitation. 
        Write-Verbose "[ BEGIN ] Checking Trusted Root CA store for Hue certificate"
        switch (Test-Path -Path Cert:\LocalMachine\Root\47745E6B0BC173E13133ACFA785BD9D5E008067C) {
            $false { throw [System.IO.FileNotFoundException] "Hue root CA not found" }
            Default { Write-Verbose "[ BEGIN ] Certificate present" }
        }
    }
    process {
        try {
            $Headers = @{Host=$BridgeId;"hue-application-key"=$ApplicationKey} 
            Write-Verbose "[PROCESS] Sending GET request over HTTPS"
            $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -HttpVersion 2.0 -SslProtocol Tls12
            $ResponseData = $Response.data
            foreach ($datum in $ResponseData) {
                $lightService = $datum.services | Where-Object { $_.rtype -eq "light" }
                [PSCustomObject]@{
                    displayName = $datum.metadata.name
                    lightId = if ($lightservice) {$lightservice.rid} else {$null}
                    productName = $datum.product_data.product_name
                    modelid = $datum.product_data.model_id
                    softwareVersion = $datum.product_data.software_version
                    applicationKey = $ApplicationKey
                }
            } 
        }
        catch [System.Net.Http.HttpRequestException] {
            Write-Error $PSItem.Exception.Message -Category ConnectionError
        }
        catch {
            Write-Error $PSItem.Exception.Message
        }
    }
    clean {}
}
    

function Enable-HueLight {
<#
    .SYNOPSIS
    Turns on the specified Hue connected light.   

    .DESCRIPTION
    Enable-HueLight sends a put request to the Hue REST API, turning on the light specified by the LightId parameter. Enable-HueLight can turn on individual lights or grouped lights. Requests are made over HTTPS using TLSv1.2, presupposing the presence of the Hue root CA.

    .PARAMETER LightId

    .PARAMETER ApplicationKey

    .PARAMETER ColourXValue

    .PARAMETER ColourYValue

    .PARAMETER Brightness

    .EXAMPLE
    Enable-HueLight -LightId $LightId -ColourXValue 0.20 -ColourYValue 0.20 -Brightness 80 -ApplicationKey $ApplicationKey

    .EXAMPLE
    Enable-HueLight -LightId 12356778910 -Group -Brightness 60

    .INPUTS
    System.String

    .LINK
    https://developers.meethue.com/develop/application-design-guidance/using-https/

    .LINK
    https://community.jumpcloud.com/t5/community-scripts/building-a-nested-json-body-in-powershell-making-a-put-call-to/m-p/1866 
#>
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [string] $LightId,
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [string] $ApplicationKey,
        [Parameter()]
        [ValidateRange(0.15,0.68)]
        [float] $ColourXValue = 0.15,
        [Parameter()]
        [ValidateRange(0.05,0.69)]
        [float] $ColourYValue = 0.05,
        [Parameter()]
        [ValidateRange(0.1,100.0)]
        [float] $Brightness = 75.0,
        [Parameter()]
        [string] $BridgeId,
        [Parameter()]
        [switch] $Group
    )
    begin {
        $Body = [PSCustomObject]@{
            on = @{on = $($true)}
            dimming = @{brightness = $Brightness}
            color = @{xy = @{x = $ColourXValue
                y = $ColourYValue}}
        }
        $BridgeId = "ecb5fafffe94f0ec" # this is included until I find a way to reliably fetch the Hue bridge Id using mDNS. See notes section of Get-HueBridge for detail of this limitation. 
    }
    process {
        try {
            $Headers = @{Host=$BridgeId;"hue-application-key"=$ApplicationKey} 
            switch ($true) {
                $Group {  
                    $groupuri = "https://192.168.1.63/clip/v2/resource/grouped_light/$($LightId)"   
                    $response = Invoke-RestMethod -Method Get -Uri $groupuri -Headers $Headers -HttpVersion 2.0 -SslProtocol Tls12                    
                    switch ($false) {
                        ($response.data.on.on) { 
                            $BodyJSON = $Body | ConvertTo-Json -Compress
                            Invoke-RestMethod -Method 'Put' -Uri $groupuri -ContentType "application/json" -Body $BodyJSON -Headers $headers -HttpVersion 2.0 -SslProtocol Tls12
                        }
                        Default { Write-Warning "$($MyInvocation.MyCommand): Lightgroup $LightId already enabled" } 
                    } 
                }
                Default {
                    $uri = "https://192.168.1.63/clip/v2/resource/light/$($LightId)"   
                    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -HttpVersion 2.0 -SslProtocol Tls12      
                    switch ($false) {
                        ($response.data.on.on) { 
                            $BodyJSON = $Body | ConvertTo-Json -Compress
                            Invoke-RestMethod -Method 'Put' -Uri $uri -ContentType "application/json" -Body $BodyJSON -Headers $headers -HttpVersion 2.0 -SslProtocol Tls12 
                        }
                        Default { Write-Warning "$($MyInvocation.MyCommand): Light $LightId already enabled" }       
                    } 
                }
            }
        }
        catch [System.Net.Http.HttpRequestException] {
            Write-Error $PSItem.Exception.Message -RecommendedAction "Ensure the Hue Bridge root CA is present in the Trusted Root CA Store. Verify LightId is correct using Get-HueDevices. Ensure -Group parameter is only specified when working with Ids for grouped lights." -Category ConnectionError
        }
        catch {
            $errormessage = $PSItem.Exception.Message
            Write-Error -Message $errormessage 
        }
    }   
    clean {}
} 


function Disable-HueLight {
<#
    .SYNOPSIS

    .DESCRIPTION
    Disable-HueLight sends a put request to the Hue REST API, turning off the light specified by the LightId parameter. Disable-HueLight can turn off individual lights or grouped lights. Requests are made over HTTPS using TLSv1.2, presupposing the presence of the Hue root CA.
    
    .PARAMETER LightId

    .PARAMETER ApplicationKey

    .PARAMETER Group

    .EXAMPLE
    Disable-HueLight -LightId $LightId -ApplicationKey $ApplicationKey

    Get-HueDevices | Select -First 1 | Disable-HueLight

    .INPUTS
    System.String

    .LINK
    https://community.jumpcloud.com/t5/community-scripts/building-a-nested-json-body-in-powershell-making-a-put-call-to/m-p/1866 
#>
    [CmdletBinding(PositionalBinding=$false)]
    param (
        [Parameter(
            Position=0,
            Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [string] $LightId,
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [string] $ApplicationKey,
        [Parameter()]
        [string] $BridgeId,
        [Parameter()]
        [switch] $Group
    )
    begin {
        $Body = [PSCustomObject]@{
            on = @{on = $($false)}
        }
        $BridgeId = "ecb5fafffe94f0ec" # this is included until I find a way to reliably fetch the Hue bridge Id using mDNS. See notes section of Get-HueBridge for detail of this limitation. 
    }
    process {
        try {
            $Headers = @{Host=$BridgeId;"hue-application-key"=$ApplicationKey} 
            switch ($true) {
                $Group {  
                    $groupuri = "https://192.168.1.63/clip/v2/resource/grouped_light/$($LightId)"   
                    $response = Invoke-RestMethod -Method Get -Uri $groupuri -Headers $Headers -HttpVersion 2.0 -SslProtocol Tls12
                    switch ($true) {
                        ($response.data.on.on) { 
                            $BodyJSON = $Body | ConvertTo-Json -Compress
                            Invoke-RestMethod -Method 'Put' -Uri $groupuri -ContentType "application/json" -Body $BodyJSON -Headers $headers -HttpVersion 2.0 -SslProtocol Tls12
                        }
                        Default { Write-Warning "$($MyInvocation.MyCommand): Lightgroup $LightId already disabled." -WarningAction Continue} 
                    } 
                }
                Default {
                    $uri = "https://192.168.1.63/clip/v2/resource/light/$($LightId)"   
                    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -HttpVersion 2.0 -SslProtocol Tls12
                    switch ($true) {
                        ($response.data.on.on) { 
                            $BodyJSON = $Body | ConvertTo-Json -Compress
                            Invoke-RestMethod -Method 'Put' -Uri $uri -ContentType "application/json" -Body $BodyJSON -Headers $headers -HttpVersion 2.0 -SslProtocol Tls12
                        }
                        Default { Write-Warning "$($MyInvocation.MyCommand): Light $LightId already disabled." -WarningAction Continue }       
                    } 
                }
            }
        }
        catch [System.Net.Http.HttpRequestException] {
            Write-Error $PSItem.Exception.Message -RecommendedAction "Ensure the Hue Bridge root CA is present in the Trusted Root CA Store. Verify LightId is correct using Get-HueDevices. Ensure -Group parameter is only specified when working with Ids for grouped lights." -Category ConnectionError
        }
        catch {
            $errormessage = $PSItem.Exception.Message
            Write-Error -Message $errormessage 
        }
    }   
    clean {}
}
