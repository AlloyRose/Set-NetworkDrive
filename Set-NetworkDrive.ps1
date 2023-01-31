#requires -runasadministrator 



    <#

.SYNOPSIS
    Set-NetworkDrive maps a network drive to a local or remote computer.

.DESCRIPTION 
    Set-NetworkDrive will map a remote drive, following a UNC path naming convention, to a local or remote computer. If proper conditions are met (such as a unique drive letter, a valid path, and a responsive host), the function will 
    attempt to edit the HKU:$User's SID\Network path by creating a new key, named after the supplied drive letter, and then creating 8 relevant attributes under said key. In doing so, the command must query the remote or local host
    for the currently logged on user and their associated SID. The script returns 0 for a successful mapping and 1 for any type of failure under the property 'Ret'. 

.PARAMETER Path
    Specifies the path of the network resource to be mapped. Must follow standard UNC pathing convention (\\servername\resource) to be accepted. Resource must be accessible by user running script as it validates the path from their perspective. 
.PARAMETER DriveLetter 
    Specifies the drive letter associated to the mapped network resource. This will be the title of the newly created key when modifying the HKU\Network portion of registry. Has alias 'drive'. 
.PARAMETER ComputerName 
    The name of the computer to map the network resource onto. No IP address. Can use 'localhost' to run the script on the local computer. Has alias 'host' or 'cn'. 

.EXAMPLE 
    Set-NetworkDrive -computername computername -driveletter 'L' -path \\server\resource
    This command will remotely map '\\server\resource' to computer computername It will be listed in File Explorer under the drive letter 'L'. 
.EXAMPLE 
    Set-NetworkDrive computername 'L' '\\server\resource' -verbose
    This command will perform the same action as the previous command but it instead uses positional parameters, meaning you don't have to type out the parameter qualifiers like '-Path','-ComputerName', or '-DriveLetter' explicitly 
    if you position the arguments in the correct order. The correct order is: ComputerName, DriveLetter, then Path. Also note the verbose flag, which will output additional information as the command runs. 
.EXAMPLE 
    Set-NetworkDrive -cn localhost -drive 'A' -path '\\server\resource' | Send-DriveEmail -MailAddress 'email@address.com'
    This command will map '\\server\resource' to the localhost with driveletter 'A'. The output is piped to a sister function called Send-DriveEmail that sends an email to the address listed to let them know their drive was successfully mapped. 
    For more information on the sister function, type 'Help Send-DriveEmail -full'. 

.NOTES
    [*] This script requires you run it under administrator privileges. 
    [*] Targeted computer must have PowerShell remoting capabilites enabled. 
    [*] The path variable must start with '\\' to be accepted as a valid input.
    [*] The user is required to log off then on for the drives to be implemented.  
    [*] The '-verbose' flag can be used to see extra information outputted during the function's run and especially useful if you need to debug the script. 
    [*] This script outputs an object called Status with the important properties being Ret, Path, and Alt. Ret is the error code; 0 indicates a successful run of the script 
        while 1 means it encountered an error at some point. Path is the path that ended up being mapped; if you see '\\null' then the network resource was not properly mapped. Lastly, Alt is used to indicate whether the Status object was modified by the script 
        during its execution. Alt starts as 0 and a 1 indicates it was changed at some point within the code, which is not ideal.

    #>
function Set-NetworkDrive{
    [cmdletbinding()]
    param(
        [parameter(valuefrompipelinebypropertyname, mandatory, position = 0)][alias('host','cn')][string]$ComputerName,   
        [parameter(mandatory, position = 1)][alias('drive')][char]$DriveLetter,
        [parameter(Mandatory, position = 2)][validatepattern("^\\\\\w")][string]$Path
    )

BEGIN{
    
}

PROCESS{
    
    $Status = [pscustomobject]@{'Ret' = 1; 'Path' = '\\null'; 'Alt' = 0}            #Object to be returned starts with return code 1 and null path. Alt = 0 means these items were not changed by errors. 
    write-verbose "Status: $status"                                                                                   
    $Alive = test-connection -ComputerName $ComputerName -ErrorAction SilentlyContinue
    $ValidPath = [System.IO.Directory]::exists("$($path.trim())")            #Check the path supplied is accessible from our admin account                                                                                           
    $Session = New-CimSession -ComputerName $computername -SessionOption (New-CimSessionOption -Protocol Wsman) -ErrorAction SilentlyContinue

    try{
        write-verbose "Accessing user data via Wsman."
        $username = get-ciminstance win32_computersystem -CimSession $session| select username | out-string            #retrieve currently logged on user 
        $username = $username.split("`n")[3].split("\")[1].trim()            #formatting 

        Write-Verbose "Username: $username"
        
        $sid = get-ciminstance win32_account -ErrorAction stop | where {$_.caption -eq "domain\$username"} | select SID | out-string            #SID is used for locating correct user in HKU:%SID%\Network location 
        $sid = $sid.split("`n")[3].trim()

        Write-Verbose "SID: $sid"

        write-verbose "Initialized username & SID."
    }
    catch{
        write-warning "Could not initialize username & SID. Please make sure the host is eligble for PowerShell remoting or that the hostname is spelled correctly."
        $Status.alt = 1
        return $Status; exit 1 
    }
    
    write-verbose "Status: $status"



    $Script = {
        $ValidDrive = [System.IO.Directory]::exists("$using:DriveLetter`:\")            #Verify the drive letter chosen isn't already on File Explorer; check here and in registry since latter only contains network drives so 'C:' wouldn't show up 
        if(!$ValidDrive){

            $ValidReg = test-path -path hku:
            if(!$ValidReg){new-psdrive -PSProvider Registry -name HKU -root HKEY_users | out-null}            #By default, HKU is not imported as a reachable path - must create a dummy pointer drive to have it be a recognized path 

            try{ 
                new-item -Path "HKU:$using:sid\Network\" -name "$using:driveletter" -ErrorAction stop | out-null            #New reg key 
            }
            catch{
                write-warning "Regedit key already exists, try another drive letter."
                ($using:status).alt = 1            #alt = 1 is used to determine later on whether the invoke-command ran into an error by returning a modified alt 
                return $using:Status; 
            }

            $RegPath = "HKU:$using:sid\network\$using:driveletter\"

            try{
                New-ItemProperty -Path $RegPath -PropertyType String -name 'RemotePath'     -ErrorAction stop -value "$using:path"               | out-null
                New-ItemProperty -path $RegPath -PropertyType DWord  -name 'ConnectFlags'   -ErrorAction stop -value 0                           | out-null
                New-ItemProperty -path $regpath -PropertyType Dword  -name 'ConnectionType' -ErrorAction stop -value 1                           | out-null
                New-ItemProperty -path $regpath -PropertyType Dword  -name 'DeferFlags'     -ErrorAction stop -value 4                           | out-null
                New-ItemProperty -path $regpath -PropertyType String -name 'ProviderName'   -ErrorAction stop -value 'Microsoft Windows Network' | out-null
                New-ItemProperty -path $RegPath -PropertyType Dword  -name 'ProviderType'   -ErrorAction stop -value 131072                      | out-null
                New-ItemProperty -path $regpath -PropertyType dword  -name 'UserName'       -ErrorAction stop -value 0                           | out-null
                New-ItemProperty -path $regpath -PropertyType binary -name 'UseOptions'     -ErrorAction stop
            }
            catch{
                ($using:status).alt = 1
                return $using:Status
            }

            write-verbose "Completed modifying registry."

            net use | out-null

        }
        else{
            write-warning "The drive letter ($using:DriveLetter) you chose already exists on the system. Please choose another one and try again." 
            ($using:status).alt = 1
            return $using:Status
        }
           
    }#script
         

    if($alive -AND $ValidPath){
        Write-Verbose "Computer is reachable and path provided is valid."

        try{
            write-verbose "Attempting to connect to $($computername.toupper()) to map drive."
            write-verbose "Status: $status"
            $status = invoke-command -ComputerName $computername -scriptblock $script -ErrorAction stop -verbose | select Ret, Alt, Path 

            if(!$status.alt){           #If alt wasn't modified, it did not encounter an error - returning all zeros indicate a successful run. Used in sister function 'Send-DriveEmail' that only sends the email if Ret is 0. 
                $Status = [pscustomobject]@{'Ret' = 0; 'Path' = "$path"; 'Alt' = 0}
                write-verbose "Status: $status"
                return $status 
            }
            else{
                return $status
            }
        }
        catch{
            Write-Warning "Failed to establish remote session on $($computername.toupper())"
            ($status).alt = 1
            return $Status
        }
        
    }
    else{
        write-warning "$($computername.toupper()) is either unavailable or the path entered is invalid." 
        ($status).alt = 1
        return $Status
    }
}

END{
    write-verbose "Set-NetworkDrive Completed -- $(get-date)"
    $session | remove-cimsession
}

}