# Authors: Peng Jiang(peng@seal.io) & Yinlin Li(yinlin@seal.io)
# Last Change: 2023-09-12

# Debug switch to enable log output
param (
    [switch]$os,
    [switch]$debug,
    [switch]$help
)

# Usage message
function usage {
    Write-Host "####################################"
    Write-Host "USAGE: $PSCommandPath"
    Write-Host "  [ -os ] Output os info only"
    Write-Host "  [ -debug ] Output more debug info"
    Write-Host "  [ -h | -help ] Usage message"
    Write-Host "####################################"
}

# Process checklist
$global:process_checklist = @(
    "nginx",
    "tomcat",
    "java",
    "sqlservr"
)

function Log-Debug {
    param (
        [string]$message
    )

    if ($debug) {
        Write-Output "[DEBUG] $message"
    }
}

function Get-Hostname {
    $env:COMPUTERNAME
}

function Get-IPv4 {
    $defaultInterface = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }).InterfaceAlias
    $ipv4Address = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq $defaultInterface -and $_.AddressFamily -eq "IPv4" }).IPAddress
    return $ipv4Address
}

function Get-IPv6 {
    $defaultInterface = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }).InterfaceAlias
    $ipv6Address = (Get-NetIPAddress | Where-Object { $_.InterfaceAlias -eq $defaultInterface -and $_.AddressFamily -eq "IPv6" }).IPAddress
    return $ipv6Address
}

function Get-MAC {
    $defaultInterface = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }).InterfaceAlias
    $macAddress = (Get-NetAdapter | Where-Object { $_.InterfaceAlias -eq $defaultInterface -and $_.Status -eq "Up" }).MacAddress
    return $macAddress
}

function Get-OSInfo {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem

    $osInfoArray = @{
        "os_version" = $osInfo.Caption
        "kernel" = $osInfo.Version
    }

    return $osInfoArray
}

# Check and ouptput server info
function Get-ServerInfo {
    $server_hostname = Get-Hostname
    $ipv4_address = Get-IPv4
    $ipv6_address = Get-IPv6    
    $mac_address = Get-MAC
    $os_Info = Get-OSInfo

    $ip_array = @()
    if (-not [string]::IsNullOrEmpty($ipv6_address)) {
        $ip_array += $ipv4_address, $ipv6_address
    } else {
        $ip_array += $ipv4_address
    }

    $ip_array = $ip_array -ne ""

    if ($os_Info) {
        $server_info = [ordered]@{
            "hostname" = "$server_hostname"
            "ip_array" = $ip_array
            "mac_address" = "$mac_address"
            "os" = "Microsoft Windows"
            "os_version" = "$($os_Info.os_version)"
            "kernel" = "$($os_Info.kernel)"
        }
        return $server_info
    }
    else {
        return $null
    }
}

function Get-Port {
    param (
        [int]$ProcessId
    )

    $port = (Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $ProcessId -and $_.State -eq "Listen" } | Select-Object -First 1).LocalPort

    if ($port) {
        return $port
    } else {
        Log-Debug "WARNING: Failed to get the port for process."
        return $null
    }
}


function Get-TomcatPath {
    param (
        [string]$ProcessPath,
        [string]$CommandLine
    )

    # Process started by Windows service will have the path in the Path
    if (-not [string]::IsNullOrWhiteSpace($ProcessPath)) {
        $tomcatPath = $ProcessPath -replace "\\bin\\.*", ""
        return $tomcatPath.Trim()
    }

    # Process started by Java will have the path in the CommandLine
    $cleanCommandLine = $CommandLine.Trim('"')
    $tomcatPath = $cleanCommandLine -replace "(?s).*(-Dcatalina\.home=[^ ]+).*", '$1'
    $tomcatPath = $tomcatPath -replace "-Dcatalina\.home=""|""", ""
    return $tomcatPath.Trim()
}

function Get-TomcatVersion {
    param (
        [string]$Path
    )

    # Search for version information inside the catalina.bat file
    $catalinaBatPath = Join-Path $Path "\bin\catalina.bat"
    if (Test-Path $catalinaBatPath) {
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = $catalinaBatPath
        $processStartInfo.Arguments = "version"
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.WorkingDirectory = $Path 
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processStartInfo

        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        # Match the line containing "Server version" and extract the version
        if ($output -match "Server version: Apache Tomcat/(\d+\.\d+\.\d+)") {
            $version = $Matches[1]
            return $version.Trim()
        }
        else {
            Log-Debug "Failed to get tomcat version from catalina.sh"
        }
    }

    # If catalina.bat does not contain version info, try version.bat
    $versionBatPath = Join-Path $Path "\bin\version.bat"
    if (Test-Path $versionBatPath) {
        $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processStartInfo.FileName = $versionBatPath
        $processStartInfo.RedirectStandardOutput = $true
        $processStartInfo.UseShellExecute = $false
        $processStartInfo.WorkingDirectory = $Path 
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processStartInfo

        $process.Start() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()

        # Match the line containing "Server version" and extract the version
        if ($output -match "Server version: Apache Tomcat/(\d+\.\d+\.\d+)") {
            $version = $Matches[1]
            return $version.Trim()
        }
        else {
            Log-Debug "Failed to get tomcat version from version.sh"
        }
    }

    # If no version information found in the files, return unknown
    return "Unknown"
}


# Nginx Related

function Get-NginxPath {
    param (
        [int]$ProcessId
    )

    $process = Get-Process -Id $ProcessId
    $processPath = $process.Path
    $nginxPath = $processPath -replace "nginx.exe", ""

    return $nginxPath.Trim()
}

function Get-NginxVersion {
    param (
        [string]$NginxPath
    )

    $nginxVersionOutput = & "$NginxPath\nginx.exe" -v 2>&1
    $versionPattern = "nginx\/(\d+\.\d+\.\d+)"
    $nginxVersion = $nginxVersionOutput | Select-String -Pattern $versionPattern | ForEach-Object { $_.Matches[0].Groups[1].Value }

    if ($null -ne $nginxVersion) {
        return $nginxVersion
    } else {
        # If no version information found, return unknown
        Write-Output "WARNING: Failed to get the version for Nginx."        
        return "Unknown"
    }
}

# SQLServer related
function Get-SqlServerPath {
    param (
        [string]$CommandLine
    )

    if ($processInfo.CommandLine -match "(?<=\\MSSQL).*?(?=\\MSSQL|\\$)") {
        $instancePath = "MSSQL" + $matches[0]
        return $instancePath
    }
    else {
        Log-Debug "Failed to extract instance path from commandline."
        return $null
    }
}

function Get-SqlServerVersion {
    param (
        [string]$instancePath
    )

    $versionKey = "SOFTWARE\Microsoft\Microsoft SQL Server\$instancePath\Setup"
    $regVersion = Get-ItemProperty -Path "HKLM:\$versionKey" -Name Version -ErrorAction SilentlyContinue
    if ($null -ne $regVersion) {
        return $regVersion.Version
    } else {
        # If no version information found, return unknown
        return "Unkown"
    }
}

# Check and ouptput processes info
function Process-Check {
    $server_hostname = Get-Hostname
    $ipv4_address = Get-IPv4
    $ipv6_address = Get-IPv6    
    $mac_address = Get-MAC
    $os_Info = Get-OSInfo

    $ip_array = @()
    if (-not [string]::IsNullOrEmpty($ipv6_address)) {
        $ip_array += $ipv4_address, $ipv6_address
    } else {
        $ip_array += $ipv4_address
    }

    # Filter out empty strings from the array
    $ip_array = $ip_array -ne ""

    $found_process = $false
    $sqlserver_instances_info = @()

    foreach ($process in $process_checklist) {

        Log-Debug "Checking process $process"

        $processInfos = Get-CimInstance Win32_Process | Where-Object { $_.Name -like "*$process*" -and $_.Name -notlike "*tomcat*w.exe*" }

        if ($processInfos) {

            $found_process = $true

            foreach ($processInfo in $processInfos) {
                
                # Process started by Windows service has an emtpy path. We will only check if the path is not empty. Otherwise, we will goto service and registy check.
                if ($processInfo.Path) {
                    switch ($process) {
                        "nginx" {
                            
                            Log-Debug "Found Nginx process"

                            # Check nginx port first to confirm if it's worker process
                            $nginx_port = Get-Port -ProcessId $processInfo.ProcessId

                            if ($null -eq $nginx_port) {

                                Log-Debug "Nginx port is null. Skip processing worker process"

                            } 
                            else {

                                $nginx_path = Get-NginxPath -ProcessId $processInfo.ProcessId
                                
                                # Check if the path has been processed. A single nginx installation can start multiple processes with different configuraiton files.                              
                                if ($processedPaths -like "*$nginx_path*") {
                                    continue
                                }

                                # Add nginx path to processed list for check
                                $processedPaths += $nginx_path 
                                $nginx_version = Get-NginxVersion -NginxPath $nginx_path

                                $nginx_output = [ordered]@{
                                    "hostname" = "$server_hostname"
                                    "ip_array" = $ip_array
                                    "mac_address" = "$mac_address"
                                    "os" = "Microsoft Windows"
                                    "os_version" = "$($os_Info.os_version)"
                                    "kernel" = "$($os_Info.kernel)"
                                    "type" = "middleware"
                                    "middleware_type" = "Nginx"
                                    "state" = "running"
                                    "version" = "$nginx_version"
                                    "port" = @($nginx_port)
                                    "in_com" = @{
                                        "components" = @(
                                            @{
                                                "name" = "nginx"
                                                "state" = "running"
                                                "port" = @($nginx_port)
                                                "version" = "$nginx_version"
                                            }
                                        )
                                    }
    
                                }
                                Write-Output ($nginx_output | ConvertTo-Json -Depth 10)
                            }
                        }
                        
                        "tomcat" {

                            Log-Debug "Found Tomcat process"
                            $tomcat_port = Get-Port -ProcessId $processInfo.ProcessId
                            $catalina_home = Get-TomcatPath -ProcessPath $processInfo.Path
                            $tomcat_version = Get-TomcatVersion -Path $catalina_home

                            $tomcat_output = [ordered]@{
                                "hostname" = "$server_hostname"
                                "ip_array" = $ip_array
                                "mac_address" = "$mac_address"
                                "os" = "Microsoft Windows"
                                "os_version" = "$($os_Info.os_version)"
                                "kernel" = "$($os_Info.kernel)"
                                "type" = "middleware"
                                "middleware_type" = "Tomcat"
                                "state" = "running"
                                "version" = "$tomcat_version"
                                "port" = @($tomcat_port)
                                "in_com" = @{
                                    "components" = @(
                                        @{
                                            "name" = "tomcat"
                                            "state" = "running"
                                            "port" = @($tomcat_port)
                                            "version" = "$tomcat_version"
                                        }
                                    )
                                }

                            }
                            Write-Output ($tomcat_output | ConvertTo-Json -Depth 10)
                        }

                        "java" {

                            Log-Debug "Found Java process"

                            if ($processInfo.CommandLine -like "*tomcat*" ) {

                                $tomcat_port = Get-Port -ProcessId $processInfo.ProcessId
                                Log-Debug "Java process path is $($processInfo.CommandLine)"
                                $catalina_home = Get-TomcatPath -CommandLine $processInfo.CommandLine
                                Log-Debug "Catalina home is $catalina_home"
                                $tomcat_version = Get-TomcatVersion -Path $catalina_home
                               
                                $java_output = [ordered]@{
                                    "hostname" = "$server_hostname"
                                    "ip_array" = $ip_array
                                    "mac_address" = "$mac_address"
                                    "os" = "Microsoft Windows"
                                    "os_version" = "$($os_Info.os_version)"
                                    "kernel" = "$($os_Info.kernel)"
                                    "type" = "middleware"
                                    "middleware_type" = "Tomcat"
                                    "state" = "running"
                                    "version" = "$tomcat_version"
                                    "port" = @($tomcat_port)
                                    "in_com" = @{
                                        "components" = @(
                                            @{
                                                "name" = "tomcat"
                                                "state" = "running"
                                                "port" = @($tomcat_port)
                                                "version" = "$tomcat_version"
                                            }
                                        )
                                    }

                                }
                                Write-Output ($java_output | ConvertTo-Json -Depth 10)
                            }
                            else {
                                Log-debug "Found Java process unrelated to tomcat. Skipping"
                            }
                        }

                        "sqlservr" {

                            Log-Debug "Found Sqlservr process"
                            function Get-Port {
                                param (
                                    [int]$ProcessId
                                )
                            
                                $port = (Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $ProcessId -and $_.LocalAddress -eq "0.0.0.0" -and $_.State -eq "Listen" } | Select-Object -ExpandProperty LocalPort)
                                $port = $port -join ','
                            
                                if ($port) {
                                    return $port
                                } else {
                                    Log-Debug "WARNING: Failed to get the port for process."
                                    return $null
                                }
                            }
                            # SQL Server Check
                            $sqlserver_port = Get-Port -ProcessId $processInfo.ProcessId
                            Log-Debug "Process commandline is $($processInfo.CommandLine)"
                            $instancePath = Get-SqlServerPath -CommandLine $processInfo.CommandLine
                            $sqlserver_version = Get-SqlServerVersion -instancePath $instancePath
                            $sqlserver_instance_info = @{
                                "name" = $instancePath
                                "state" = "running"
                                "port" = @($sqlserver_port)
                                "version" = $sqlserver_version
                            }
                            $sqlserver_instance_info.port = $sqlserver_instance_info.port | ForEach-Object { [int]$_ }
                            $sqlserver_instances_info += $sqlserver_instance_info
                        }
                    }
                }
            }
        }
    }

    if (-not $found_process) {
        return 255
    }
    if ($sqlserver_instances_info.Count -gt 0) {
        $sqlserver_output = [ordered]@{
            "hostname" = "$server_hostname"
            "ip_array" = $ip_array
            "mac_address" = "$mac_address"
            "os" = "Microsoft Windows"
            "os_version" = "$($os_Info.os_version)"
            "kernel" = "$($os_Info.kernel)"
            "type" = "database"
            "database_type" = "SQL_Server"
            "state" = "running"
            "version" = $sqlserver_version
            "port" = @($sqlserver_instances_info | ForEach-Object { $_.port })
            "in_com" = @{
                "components" = @($sqlserver_instances_info)
            }
        }
        Write-Output ($sqlserver_output | ConvertTo-Json -Depth 10)
    }
}

# Call the function to check for installation
function main {
    if ($help) {
        usage
        exit 0
    }
    if ($os) {
        $server_info = Get-ServerInfo
        if ($server_info) {
            $jsonOutput = $server_info | ConvertTo-Json -Depth 10
            Write-Output $jsonOutput
        }
        else {
            Log-Debug "Failed to retrieve server info."
        }
    } else {
        Process-Check
    }
}

main