#
# Copyright 2018, Alexis La Goutte <alexis dot lagoutte at gmail dot com>
#
# SPDX-License-Identifier: Apache-2.0
#

function Connect-ArubaCX {

    <#
      .SYNOPSIS
      Connect to a ArubaCX Switches

      .DESCRIPTION
      Connect to a ArubaCX Switches
      .EXAMPLE
      Connect-ArubaCX -Server 192.0.2.1

      Connect to a ArubaCX Switch with IP 192.0.2.1 using (Get-)credential

      .EXAMPLE
      Connect-ArubaCX -Server 192.0.2.1 -SkipCertificateCheck

      Connect to an ArubaCX Switch using HTTPS (without check certificate validation) with IP 192.0.2.1 using (Get-)credential

      .EXAMPLE
      $cred = get-credential
      PS C:\>Connect-ArubaCX -Server 192.0.2.1 -credential $cred

      Connect to a ArubaCX Switch with IP 192.0.2.1 and passing (Get-)credential

      .EXAMPLE
      $mysecpassword = ConvertTo-SecureString aruba -AsPlainText -Force
      PS C:\>Connect-ArubaCX -Server 192.0.2.1 -Username admin -Password $mysecpassword

      Connect to a ArubaCX Switch with IP 192.0.2.1 using Username and Password
  #>

    Param(
        [Parameter(Mandatory = $true, position = 1)]
        [String]$Server,
        [Parameter(Mandatory = $false)]
        [String]$Username,
        [Parameter(Mandatory = $false)]
        [SecureString]$Password,
        [Parameter(Mandatory = $false)]
        [PSCredential]$Credentials,
        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck = $false,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 65535)]
        [int]$port = 443,
        [Parameter(Mandatory = $false)]
        [boolean]$DefaultConnection = $true
    )

    Begin {
    }

    Process {


        $connection = @{server = ""; session = ""; invokeParams = ""; port = $port; version = "" }
        $invokeParams = @{DisableKeepAlive = $false; UseBasicParsing = $true; SkipCertificateCheck = $SkipCertificateCheck }

        #If there is a password (and a user), create a credentials
        if ($Password) {
            $Credentials = New-Object System.Management.Automation.PSCredential($Username, $Password)
        }
        #Not Credentials (and no password)
        if ($null -eq $Credentials) {
            $Credentials = Get-Credential -Message 'Please enter administrative credentials for your ArubaCX Switch'
        }

        if ("Desktop" -eq $PSVersionTable.PsEdition) {
            #Remove -SkipCertificateCheck from Invoke Parameter (not supported <= PS 5)
            $invokeParams.remove("SkipCertificateCheck")
        }
        else {
            #Core Edition
            #Remove -UseBasicParsing (Enable by default with PowerShell 6/Core)
            $invokeParams.remove("UseBasicParsing")
        }

        #for PowerShell (<=) 5 (Desktop), Enable TLS 1.1, 1.2 and Disable SSL chain trust (needed/recommanded by ArubaCX)
        if ("Desktop" -eq $PSVersionTable.PsEdition) {
            #Enable TLS 1.1 and 1.2
            Set-ArubaCXCipherSSL
            if ($SkipCertificateCheck) {
                #Disable SSL chain trust...
                Set-ArubaCXuntrustedSSL
            }
        }

        $postParams = @{username = $Credentials.username; password = $Credentials.GetNetworkCredential().Password }
        $url = "https://${Server}:${Port}/rest/v1/login"
        try {
            Invoke-RestMethod $url -Method POST -Body $postParams -SessionVariable arubacx @invokeParams | Out-Null
        }
        catch {
            Show-ArubaCXException $_
            throw "Unable to connect"
        }

        $url = "https://${Server}:${Port}/rest"
        try {
            $rest = Invoke-RestMethod $url -Method "get" -WebSession $arubacx @invokeParams
        }
        catch {
            throw "Unsupported release Need to use ArubaCX >= 10.04"
        }

        $connection.server = $server
        $connection.session = $arubacx
        $connection.invokeParams = $invokeParams
        $connection.version = $rest.latest.version

        if ( $DefaultConnection ) {
            set-variable -name DefaultArubaCXConnection -value $connection -scope Global
        }

        $connection
    }

    End {
    }
}

function Disconnect-ArubaCX {

    <#
        .SYNOPSIS
        Disconnect to a ArubaCX Switches

        .DESCRIPTION
        Disconnect the connection on ArubaCX Switchs

        .EXAMPLE
        Disconnect-ArubaCX

        Disconnect the connection

        .EXAMPLE
        Disconnect-ArubaCX -noconfirm

        Disconnect the connection with no confirmation

    #>

    Param(
        [Parameter(Mandatory = $false)]
        [switch]$noconfirm,
        [Parameter (Mandatory = $False)]
        [ValidateNotNullOrEmpty()]
        [PSObject]$connection = $DefaultArubaSWConnection
    )

    Begin {
    }

    Process {

        $url = "logout"

        if ( -not ( $Noconfirm )) {
            $message = "Remove ArubaCX Switch connection."
            $question = "Proceed with removal of ArubaCX Switch connection ?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 }
        if ($decision -eq 0) {
            Write-Progress -activity "Remove ArubaCX SW connection"
            Invoke-ArubaCXRestMethod -method "POST" -uri $url -connection $connection | Out-Null
            Write-Progress -activity "Remove ArubaCX SW connection" -completed
            if (Test-Path variable:global:DefaultArubaCXConnection) {
                Remove-Variable -name DefaultArubaCXConnection -scope global
            }
        }

    }

    End {
    }
}
