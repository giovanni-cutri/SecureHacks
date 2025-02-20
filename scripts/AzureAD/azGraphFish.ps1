<#
.Synopsis
   Helper function that gets stuff from Microsoft Graph and requests all pages recursively
.DESCRIPTION
   Helper function that gets stuff from Microsoft Graph and requests all pages recursively
.EXAMPLE
   Get-GraphRecursive -Url 'https://graph.microsoft.com/v1.0/groups?$filter=isAssignableToRole eq true' -AccessToken $AccessToken
.EXAMPLE
   Get-GraphRecursive -Url "https://graph.microsoft.com/v1.0/groups/<guid>/members?`$select=id,displayName,userPrincipalName,onPremisesDistinguishedName,onPremisesImmutableId" -AccessToken $AccessToken
#>
function Get-GraphRecursive {
    [CmdletBinding()]
    [Alias()]
    Param
    (
        [Parameter(Mandatory = $true,
            Position = 0)]
        [securestring]$Token,

        # Graph access token
        [Parameter(Mandatory = $false,
            Position = 1)]
        [string]$Method,

        # Graph access token
        [Parameter(Mandatory = $false,
            Position = 2)]
        [string]$Api,

        [Parameter(Mandatory = $true,
            Position = 3)]
        [string]$Authentication,

        [Parameter(Mandatory = $false,
            Position = 4)]
        [string]$filter,

        [Parameter(Mandatory = $false,
            Position = 5)]
        [string]$select,

        # Graph url
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 6)]
        [String] $Url
    )

    if ($api) {
        $url = '{0}?api-version={1}' -f $Url, $Api
        if ($filter) {
            $url = '{0}&`filter={1}' -f $Url, $filter
        }
    }
    if ($select) {
        $url = '{0}&`$select={1}' -f $url, "$select"
    }

    $result = Invoke-RestMethod -Uri $Url -method $method -Authentication $Authentication -token $token -Verbose:$false
    if ($result.value) {
        $Result.value
    }

    # Calls itself when there is a nextlink, in order to get next page
    try {
        if ($result.'@odata.nextLink') {
            Get-GraphRecursive -Url $result.'@odata.nextLink' -method $method -Authentication $Authentication -token $token
            $resultCount = ($Result.value).count
            if ($resultCount -gt 1000) {
                Write-Host "Processing $($resultCount) items"
            }
        }
    }
    catch {
        # Nothing to process
    }
}

function Get-Members {
    [CmdletBinding()]
    [Alias()]
    Param
    (
        [Parameter(Mandatory = $false,
            Position = 0)]
        [array]$ArrayObject,

        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true,
            Position = 4)]
        [String] $type,

        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            Position = 5)]
        [String] $roleTemplateId
    )

    switch ($type) {
        "azgroupmembers" {
            $graph = 'groups'
            $objectType = 'members'
            $userType = 'member'
        }
        "azgroupowners" {
            $graph = 'groups'
            $objectType = 'owners'
            $userType = 'owner'
        }
        "azrolemembers" {
            $graph = 'directoryRoles'
            $objectType = 'members'
            $userType = 'member'
        }
        "azapplicationowners" {
            $graph = 'applications'
            $objectType = 'owners'
            $userType = 'owner'
        }
        "azglobaladminrights" {
            $graph = 'directoryRoles'
            $objectType = 'members'
            $userType = 'member'
            $roleTemplateId = '62e90394-69f5-4237-9190-012177145e10'
        }
        "azprivroleadminrights" {
            # Can add role assignments to any other user including themselves
            $graph = 'directoryRoles'
            $objectType = 'members'
            $userType = 'member'
            $roleTemplateId = "e8611ab8-c189-46e8-94e1-60213ab1f814"
        }
        "azapplicationadmins" {
            # Can create new secrets for application service principals
            $graph = 'directoryRoles'
            $objectType = 'members'
            $userType = 'AppAdmin'
        }
        "azcloudappadmins" {
            # Can create new secrets for application service principals
            $graph = 'directoryRoles'
            $objectType = 'owners'
            $userType = 'owner'
            $roleTemplateId = '158c047a-c907-4556-b7ef-446551a6b5f7'
        }
        "azintuneadmins" {
            # Can add principals to cloud-resident security groups
            $graph = 'directoryRoles'
            $objectType = 'members'
            $userType = 'member'
            $roleTemplateId = '3a2c62db-5318-420d-8d74-23affee5d9d5'
        }
        "azapplicationtosp" {
            # Can add principals to cloud-resident security groups
            $graph = 'serviceprincipals'
            $userType = 'serviceprincipal'
        }
        Default {}
    }

    $metadata = New-Object System.Collections.ArrayList
    $dataHash = New-Object System.Collections.ArrayList
    $i = 1
    if ($roleTemplateId) {
        $uri = "$baseUrl/$graph/roleTemplateId=$($roleTemplateId)/$($objectType)"
        $accounts = (Get-GraphRecursive -Url $uri @aadRequestHeader)
        foreach ($account in $accounts) {
            $currentItem = [PSCustomObject]@{
                "UserName"          = $account.displayName
                "ObjectType"        = (($account.'@odata.id' -split "\.")[-1])
                "UserID"            = $account.id
                "UserOnPremId"      = $account.OnPremisesSecurityIdentifier
                "TenantDisplayName" = ($organizations | Where-Object id -eq (($account.'@odata.id' -split "/")[4])).displayName
                "TenantId"          = ($account.'@odata.id' -split "/")[4]
            }
            #Write-Output $currentItem
            $null = $dataHash.Add($currentItem)
        }
    }
    else {
        foreach ($item in $ArrayObject) {
            Write-Host -nonewline "Processing item $($i) of $($ArrayObject.count)`r"
            $i++
            Write-Verbose "[$($graph): $($item.displayName)]`n"
            if ($type -eq "azapplicationtosp") {
                $uri = "$baseUrl/$graph/?`$filter=appid eq '$($item.appId)'"
            }
            else {
                $uri = "$baseUrl/$graph/$($item.id)/$($objectType)"
            }
            $accounts = (Get-GraphRecursive -Url $uri @aadRequestHeader)
            foreach ($account in $accounts) {
                switch ($type) {
                    "azapplicationowners" {
                        $currentItem = [PSCustomObject]@{
                            AppId                  = $item.appId
                            AppObjectId            = $item.id
                            AppName                = $item.displayName
                            "$($userType)Name"     = $account.displayName
                            "$($userType)ID"       = $account.id
                            "$($userType)Type"     = (($account.'@odata.id' -split "\.")[-1])
                            "$($userType)OnPremID" = $account.OnPremisesSecurityIdentifier
                        }
                        Write-Verbose $currentItem
                        $null = $dataHash.Add($currentItem)
                    }
                    "azapplicationtosp" {
                        $currentItem = [PSCustomObject]@{
                            AppId              = $item.appId
                            AppName            = $item.displayName
                            "$($userType)ID"   = $account.Id
                            "$($userType)Type" = (($account.'@odata.id' -split "\.")[-1])
                        }
                        Write-Verbose $currentItem
                        $null = $dataHash.Add($currentItem)
                    }
                    default {
                        $currentItem = [PSCustomObject]@{
                            GroupName              = $item.displayname
                            GroupID                = $item.id
                            GroupOnPremID          = $item.OnPremisesSecurityIdentifier
                            "$($userType)Name"     = $account.displayName
                            "$($userType)ID"       = $account.id
                            "$($userType)Type"     = (($account.'@odata.id' -split "\.")[-1])
                            "$($userType)OnPremID" = $account.OnPremisesSecurityIdentifier
                        }
                        #Write-Verbose $currentItem
                        $null = $dataHash.Add($currentItem)
                    }
                }
            }
        }
    }
    Get-Chunk -Coll $dataHash -Directory $outputDirectory -Type $type
    return $dataHash
}
function Export-Data {
    [CmdletBinding()]
    [Alias()]
    Param
    (
        [Parameter(Mandatory = $true,
            ValueFromPipeline,
            Position = 0)]
        [array]$dataObject,

        [Parameter(Mandatory = $true,
            Position = 1)]
        $type
    )

    $metadata = New-Object System.Collections.ArrayList
    $dataHash = New-Object System.Collections.ArrayList

    $metadata.Add([ordered]@{
            count   = $dataObject.count
            type    = $type
            version = 4
        }) | Out-Null

    foreach ($item in $dataObject) {
        if ($item.appId) {
            $currentItem = [PSCustomObject]@{
                AppName = $item.displayname
                AppId   = $item.appId
            }
        }
        else {
            $currentItem = [PSCustomObject]@{
                DisplayName                  = $item.displayname
                OnPremisesSecurityIdentifier = $item.OnPremisesSecurityIdentifier
                ObjectId                     = $item.id
                TenantId                     = ($item.'@odata.id' -split "/")[4]
            }
        }

        if ($item.userPrincipalName) {
            $currentItem | Add-Member -MemberType NoteProperty -Name UserPrincipalName -Value "$($item.userPrincipalName)" -Force
            $currentItem | Add-Member -MemberType NoteProperty -Name TenantId -Value "$($context.tenantId)" -Force
        }

        if ($item.appId) {
            $currentItem | Add-Member -MemberType NoteProperty -Name ServicePrincipalId -Value "$($item.id)" -Force
            $currentItem | Add-Member -MemberType NoteProperty -Name ServicePrincipalType -Value "ServicePrincipal" -Force
        }

        Write-Verbose $currentItem
        $null = $dataHash.Add($currentItem)
    }
    $json = [ordered]@{}
    $json.add("meta", [ordered]@{
            count   = $dataHash.count
            type    = $type
            version = 4
        })
    $json.add("data", $dataHash)
    $json | ConvertTo-Json | Out-File "$outputDirectory\$date-$($type).json"
}
function Get-PasswordResetRights {
    Write-Output "Get Password Reset Permissions"
    $metadata = New-Object System.Collections.ArrayList
    $dataHash = New-Object System.Collections.ArrayList

    $permissionList = (Invoke-WebRequest 'https://raw.githubusercontent.com/SecureHats/SecureHacks/main/documentation/passwordResetRoles.json').content | ConvertFrom-Json

    foreach ($item in ($permissionList)) {
        Write-Host $item.Role -ForegroundColor Yellow
        $passwordAdmins = ($RoleMembers | Where-Object GroupName -eq $item.Role)
        if ($passwordAdmins) {
            $adminRoleGroups = ($item.PasswordResetPermissions).Role
            Write-Output "Admin Roles: $($adminRoleGroups)"

            foreach ($adminRoleGroup in $adminRoleGroups) {
                #Write-Output "Admin Role Group" $adminRoleGroup
                #Write-Output ($RoleMembers | Where-Object GroupName -eq $adminRoleGroup)
                foreach ($account in ($RoleMembers | Where-Object GroupName -eq $adminRoleGroup)) {
                    foreach ($pwdAdmin in $passwordAdmins) {
                        if ($pwdAdmin.MemberName -ne $account.MemberName) {
                            $currentItem = [PSCustomObject]@{
                                UserName           = $pwdAdmin.MemberName
                                ObjectType         = $pwdAdmin.MemberType
                                UserId             = $pwdAdmin.MemberId
                                UserOnPremId       = $pwdAdmin.MemberOnPremId
                                TargetUserName     = $account.MemberName
                                TargetUserId       = $account.MemberId
                                TargetUserOnPremId = $account.MemberOnPremId
                            }
                            $null = $dataHash.Add($currentItem)
                        }
                    }
                }
            }
        }
        $passwordAdmins = ''
    }

    $json = [ordered]@{}
    $null = $json.add("data", ($dataHash | Sort-Object -unique -property Username, TargetUserName ))

    Get-Chunk -Coll $json -Directory $outputDirectory -Type "pwdresetrights"
    $json | ConvertTo-Json | Out-File "$outputDirectory\$date-azpwdresetrights.json"
}
function Get-GraphToken {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateSet('AzureAd', 'Azure')]
        [string]$resource
    )

    Begin {
        try {
            az version | out-Null
        }
        catch {
            Write-Output "Azure CLI is required to run az-GraphFish. Press any key to continue (except the power button)"
            Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; Remove-Item .\AzureCLI.msi
        }
    }
    Process {
        try {
            # https://docs.microsoft.com/en-us/cli/azure/account?view=azure-cli-latest#az_account_get_access_token
            if ($resource -eq "AzureAD") {
                Write-Output "Grabbing Azure AD Token"
                $_graphToken = (az account get-access-token --resource-type ms-graph | ConvertFrom-Json)
            }
            else {
                Write-Output "Grabbing Azure Resource Token"
                $_graphToken = (az account get-access-token | ConvertFrom-Json)
            }

            return $_graphToken
        }
        catch {
            Write-Error $Error #"Unable to process graph token request"
        }
    }
}
function Get-Chunk($Coll, $Type, $Directory) {

    $Count = $Coll.Count

    if ($null -eq $Coll) {
        $Coll = New-Object System.Collections.ArrayList
    }

    # ConvertTo-Json consumes too much memory on larger objects, which can have millions
    # of entries in a large tenant. Write out the JSON structure a bit at a time to work
    # around this. This is a bit inefficient, but makes this work when the tenant becomes
    # too large.
    $FileName = $Directory.path + [IO.Path]::DirectorySeparatorChar + $date + "-" + $($Type) + ".json"
    try {
        $Stream = [System.IO.StreamWriter]::new($FileName)

        # Write file header JSON
        $Stream.WriteLine('{')
        $Stream.WriteLine("`t""meta"": {")
        $Stream.WriteLine("`t`t""count"": $Count,")
        $Stream.WriteLine("`t`t""type"": ""az$($Type)"",")
        $Stream.WriteLine("`t`t""version"": 4")
        $Stream.WriteLine("`t},")

        # Write data JSON
        $Stream.WriteLine("`t""data"": [")
        $Stream.Flush()

        $chunksize = 250
        $chunkarray = @()
        $parts = [math]::Ceiling($coll.Count / $chunksize)
        Write-Output "Collections" $($Coll)
        Write-Output "Chopping and Chunking data in $chunksize items"

        if ($Coll.count -eq 1) {
            $chunkarray = $Coll
        }
        else {
            for ($n = 0; $n -lt $parts; $n++) {
                $start = $n * $chunksize
                $end = (($n + 1) * $chunksize) - 1
                $chunkarray += , @($coll[$start..$end])
                #Write-Host $($chunkarray)
            }
            $Count = $chunkarray.Count
        }

        $chunkcounter = 1
        $jsonout = ""
        ForEach ($chunk in $chunkarray) {
            if ($Count -gt 0) {
                Write-Host -nonewline "Writing data block $chunkcounter of $Count`r"
            }
            $jsonout = ConvertTo-Json($chunk) -Depth 100
            $jsonout = $jsonout.trimstart("[`r`n").trimend("`r`n]")
            $Stream.Write($jsonout)
            If ($chunkcounter -lt $Count) {
                $Stream.WriteLine(",")
            }
            Else {
                $Stream.WriteLine("")
            }
            $Stream.Flush()
            $chunkcounter += 1
        }
        $Stream.WriteLine("`t]")
        $Stream.WriteLine("}")
    }
    finally {
        $Stream.close()
    }
}
function Start-GraphFish {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()]
        [bool]
        $Hound,

        [Parameter()]
        [string]$resourceType,

        [Parameter()]
        [string]$servicePrincipalId,

        [Parameter()]
        [string]$servicePrincipalKey,

        [Parameter()]
        [string]$tenantId
    )

    Begin {
        #Set-StrictMode -Version Latest
        #$ErrorActionPreference = 'SilentlyContinue'

        $logo = "
                  ╭━━━╮       ╭╮ ╭━━━╮   ╭╮
                  ┃╭━╮┃       ┃┃ ┃╭━━╯   ┃┃
        ╭━━┳━━━╮  ┃┃ ╰╋━┳━━┳━━┫╰━┫╰━━┳┳━━┫╰━╮
        ┃╭╮┣━━┃┣━━┫┃╭━┫╭┫╭╮┃╭╮┃╭╮┃╭━━╋┫━━┫╭╮┃
        ┃╭╮┃┃━━╋━━┫╰┻━┃┃┃╭╮┃╰╯┃┃┃┃┃  ┃┣━━┃┃┃┃
        ╰╯╰┻━━━╯  ╰━━━┻╯╰╯╰┫╭━┻╯╰┻╯  ╰┻━━┻╯╰╯
                           ┃┃
                           ╰╯"

        $date = get-date -f yyyyMMddhhmmss
        $baseUrl = 'https://graph.microsoft.com/beta'
        $mngtUrl = 'https://management.azure.com'
        $outputDirectory = $(Get-Location)

        try {
            if ($null -ne $graphToken) {
                [datetime]$expiresOn = $graphToken.expiresOn
                $refresh = ($expiresOn - (get-date)).minutes
            }
            else {
                $refresh = 0
            }
        }
        catch {
            $refresh = 0
        }
        if ($refresh -le 1) {
            if ($servicePrincipalId) {
                az login --service-principal -u $servicePrincipalId -p $servicePrincipalKey --tenant $tenantId

            }
            else {
                az login --use-device-code | Out-Null
            }
            $graphToken = Get-GraphToken -resource $resourceType #| ConvertTo-Json
        }
    }
    Process {
        Clear-Host
        Write-Host $logo -ForegroundColor White
        Write-Output "      -- L E T S   S T A R T   F I S H I N G --"

        #current context
        $context = az account show | ConvertFrom-Json
        Write-Output "`nCurrent Context:" $context
        Write-Output "Token valid until:" $($graphToken.expiresOn)

        #region Active Directory
        $aadRequestHeader = @{
            "Token"          = ($graphToken.accessToken | ConvertTo-SecureString -AsPlainText -Force)
            "Authentication" = 'OAuth'
            "Method"         = 'GET'
        }

        if ($resourceType -eq 'AzureAd') {
            Write-Output "Collecting RAW tenant data"
            $organizations = (Get-GraphRecursive @aadRequestHeader -Url "$baseUrl/organization")
            $users = (Get-GraphRecursive @aadRequestHeader -Url "$baseUrl/users")
            $groups = (Get-GraphRecursive @aadRequestHeader -Url "$baseUrl/groups")
            $directoryRoles = (Get-GraphRecursive @aadRequestHeader -Url "$baseUrl/directoryRoles")
            $applications = (Get-GraphRecursive @aadRequestHeader -Url "$baseUrl/applications")
            $roleMembers = (Get-Members -ArrayObject $directoryRoles -type azrolemembers)

            $organizations  | ConvertTo-Json -Depth 10 | Out-File "$outputDirectory\$date-tenants.json"
            $users          | Get-Chunk -Coll $users -Directory $outputDirectory -type "users"
            $groups         | ConvertTo-Json -Depth 10 | Out-File "$outputDirectory\$date-groups.json"
            $directoryRoles | ConvertTo-Json -Depth 10 | Out-File "$outputDirectory\$date-directoryroles.json"
            $applications   | ConvertTo-Json -Depth 10 | Out-File "$outputDirectory\$date-applications.json"

            if ($hound) {
                Write-Output "Building AzureHound Export"
                export-data $organizations -type aztenants
                export-data $users -type azusers
                export-data $groups -type azgroups
                export-data $directoryRoles -type azdirectoryroles
                export-data $applications -type azapplicationowners
            }

            Write-Output "Processing 'Role Assignments' "
            Get-Chunk -Type "azglobaladminrights" -Directory $outputDirectory -coll ($roleMembers | Where-Object GroupName -eq "Global Administrator")
            Get-Chunk -Type "azprivroleadminrights" -Directory $outputDirectory -coll ($roleMembers | Where-Object GroupName -eq "Privileged Role Administrator")
            Get-Chunk -Type "azapplicationadmins" -Directory $outputDirectory -coll ($roleMembers | Where-Object GroupName -eq "Application Administrator")

            $groupsArray = @(
                "azgroupmembers"
                "azgroupowners"
            )

            Write-Output "Processing 'Groups Objects' "
            foreach ($grp in $groupsArray) {
                Get-Members -ArrayObject $groups -Type $grp
            }

            $appsArray = @(
                "azapplicationowners"
                "azapplicationtosp"
            )

            Write-Output "Processing 'AAD Applications' "
            foreach ($app in $appsArray) {
                Get-Members -ArrayObject $applications -Type $app
            }
            Get-PasswordResetRights
        }
        if ($resourceType -eq 'Azure') {
            #region Azure
            #$graphToken = Get-GraphToken -resource Azure
            #$requestBody = @{
            #    "Token"          = ($graphToken.accessToken | ConvertTo-SecureString -AsPlainText -Force)
            #    "Authentication" = 'OAuth'
            #    "Method"         = 'GET'
            #}

            $subscriptions = (Get-GraphRecursive @aadRequestHeader -api '2020-01-01' -Url "$mngtUrl/subscriptions")
            foreach ($subid in $subscriptions.subscriptionId) {
                $subroles = (Get-GraphRecursive @aadRequestHeader -api '2018-07-01' -Url "$mngtUrl/subscriptions/$subId/providers/Microsoft.Authorization/roleDefinitions")
                $subRoleAssignments = (Get-GraphRecursive @aadRequestHeader -api '2020-04-01-preview' -Url "$mngtUrl/subscriptions/$subId/providers/Microsoft.Authorization/roleAssignments")
                $customRoles = $subroles.Properties | Where-Object type -ne 'BuiltInRole'

                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*8e3af657-a8ff-443c-a75c-2fe8c4bcb635*' }).properties | ConvertTo-CSV | out-file "$($subId)-owners.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*b24988ac-6180-42a0-ab88-20f7382dd24c*' }).properties | ConvertTo-CSV | out-file "$($subId)-contributors.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*18d7d88d-d35e-4fb5-a5c3-7773c20a72d9*' }).properties | ConvertTo-CSV | out-file "$($subId)-useraccessadmins.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*9980e02c-c2be-4d73-94e8-173b1dc7cf3c*' }).properties | ConvertTo-CSV | out-file "$($subId)-vmcontributors.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*00482a5a-887f-4fb3-b363-3b7fe8e74483*' }).properties | ConvertTo-CSV | out-file "$($subId)-kvAdmins.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*17d1049b-9a84-46fb-8f53-869881c3d3ab*' }).properties | ConvertTo-CSV | out-file "$($subId)-stgContributors.csv"
                ($subRoleAssignments | Where-Object { $_.properties.roledefinitionId -like '*81a9662b-bebf-436f-a333-f67b29880f12*' }).properties | ConvertTo-CSV | out-file "$($subId)-stgKeyOperators.csv"
            }
            #endregion Azure
        }
    }
    End {}
}


#Current User Permissions
$permissions = (Get-GraphRecursive -Url "$mngtUrl/subscriptions/$subId/resourcegroups/{resourceGroupName}/providers/Microsoft.Authorization/permissions" @requestBody -api '2018-07-01')

foreach ($directoryRole in $directoryRoles) {
    Write-Output "[Role: $($directoryRole.displayName)]"

    $uri = "$baseUrl/directoryRoles/$($directoryRole.id)/members"

    $directoryRoleMembers = (Get-GraphRecursive -Url $uri @requestBody)
    Write-Output $directoryRoleMembers | ConvertTo-Json -Depth 100 | Out-File .\outputs\$($directoryRole.id).json
}

$    = az account get-access-token | ConvertFrom-Json
Write-Host "retrieved token" -ForegroundColor Green
Write-Output $token
# Get Azure Resource Groups
$endpoint = "https://management.azure.com/subscriptions/$($token.subscription)/resourcegroups?api-version=2019-08-01"
$headers = @{}
$headers.Add("Authorization", "$("bearer") " + " " + "$($token.accesstoken)")
$resourceGroups = Invoke-RestMethod -Method Get `
    -Uri $endpoint `
    -Headers $Headers
Write-host "retrieved Resource groups" -ForegroundColor Green
Write-Output $resourceGroups.value.name

$baseUrl = 'https://management.azure.com'
$subs = (Invoke-RestMethod -Uri "$baseUrl/subscriptions?api-version=2020-01-01" -Headers $headers).value

foreach ($sub in $subs) {
    $uri = "https://management.azure.com/subscriptions/$($sub.subscriptionId)/resourcegroups?api-version=2019-08-01"
    (Invoke-RestMethod -Method Get `
        -Uri $endpoint `
        -Headers $Headers).value
}

Get-Assignments -ArrayObject $users @requestBody -objectType azusers


(Invoke-RestMethod @requestBody -uri "$baseUrl/serviceprincipals?`$filter=appid eq '$applicationId'").value
"https://graph.microsoft.com/beta/users/?`$filter=id eq '$($UserAccount)'&`$select=onPremisesDistinguishedName, displayName" `
    -accessToken $accessToken)
