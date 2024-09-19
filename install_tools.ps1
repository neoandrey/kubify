


function  run-SshCommandStream{
<#======================================================================================->
#
#  Executes commands on remote nodes via ssh connections
#
<-=======================================================================================#>
    param(
	    [Parameter(Mandatory=$true) ][System.Object] $server
	    ,[Parameter(Mandatory=$true) ][System.Object] $user
	    ,[Parameter(Mandatory=$true) ][System.Object] $password
	    ,[Parameter(Mandatory=$true) ][System.Object] $commandList
    )
    write-host "=========================================================="
    write-host "Connecting to $server"
    write-host "----------------------------------------------------------"

    $password            = ConvertTo-SecureString $password -AsPlainText -Force
    $cred         	 	 = New-Object System.Management.Automation.PSCredential ($user, $password)
    $session 			 = New-SSHSession -ComputerName $server -Credential $cred –AcceptKey -Force
    $stream 			 = New-SSHShellStream -SSHSession $session -TerminalName tty
    $resultMap           = @()

    $stream.WriteLine('/bin/bash')
    sleep 3
    $stream.Read()| out-null
    $commandNumber = 0;

    foreach($command  in $commandList){
	    # send a BASH one liner to list the crets and there info
        $results = @{}
        $response = ""
        $results['command']=$command
        if( $command -notmatch 'sudo -S su'){
            write-host -ForegroundColor Magenta "Running Command: $command "
        }else{
           write-host -ForegroundColor Magenta "Running command: sudo -S su -"
        }
	    $stream.WriteLine($command)
	    sleep 3
	    $tempResults     = $stream.Read()
        $checkCount      = 1;
        $response        = $tempResults
        $statusFlag      = $null

        while( $statusFlag -eq $null){
             $tempResults  = $stream.Read();
          if(-not [string]::IsNullOrWhiteSpace($tempResults)){

             $response     +=$tempResults
             $tempResults  = $null

          }else{

                try{
                    $stream.WriteLine('echo $?')
                    sleep 1
                    $statusFlag = $stream.Read()
                    $statusFlag = $statusFlag.Trim().Split("`n")[1].trim()
                    $statusFlag = [int]$statusFlag

                }catch{
                     $statusFlag = $null
                }
            }
            $checkCount+=1
             sleep $checkCount
        }
	    $results['response'] =$response
        $results['logtime']=get-date -format "yyyy-mm-dd hh:mm:ss"
        $results['flag'] =  $statusFlag
        $resultMap+=$results
        ++$commandNumber;

        if($statusFlag -ne 0){

           write-host -f DarkYellow "An error occurred when running command: $command"
           write-host -ForegroundColor red "Command Execution: FAILED`n"
           break;

        }else{

            if( $command -notmatch 'sudo -S su'){
                 write-host -ForegroundColor Magenta "Last Run Command: $command"
                 write-host -ForegroundColor green "Command Execution: OK`n"
            }else{
                 write-host -ForegroundColor Magenta "Last Run Command: sudo -S su -"
                 write-host -ForegroundColor green "Command Execution: OK`n"
        
             }
             
        }
     }
    # close the SSH session and stream
    $stream.Close()
    Remove-SSHSession -SSHSession $session | Out-Null
    return $resultMap
}

function Get-Cred{
<#======================================================================================->
#
#  Retrieves SSH credentials used for connecting to remote nodes
#
<-=======================================================================================#>
        param(
            [Parameter(mandatory=$True)] [string] $agentIPAddress
        )
        $cred = @{}
        $allKeys = if($true -eq (test-path -path "$PSScriptRoot\keystore")) { (get-childitem -Path "$PSScriptRoot\keystore").Name } else{@()}

        if($agentIPAddress -in $allKeys){

        $cred["username"]= (get-content -path "$PSScriptRoot\keystore\$agentIPAddress\kubeaccess.aue")| ConvertTo-SecureString
        $cred["password"]= (get-content -path "$PSScriptRoot\keystore\$agentIPAddress\kubeaccess.ape")| ConvertTo-SecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR( $cred["username"])
        $cred["username"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred["password"])
        $cred["password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)



        }else{

            write-host "`nPlease provide credentials for: $agentIPAddress"
            $agentCredentials = get-credential

            $cred["username"] = $agentCredentials.UserName
            $cred["password"]= $agentCredentials.Password

            if($cred["username"] -ne $null -and $cred["password"] -ne $null){
       
            $usernameSerial = $cred["username"]| ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
            $passwordSerial = $cred["password"] | ConvertFrom-SecureString

                if(-not (Test-Path -path  "$PSScriptRoot\keystore")){

                    New-Item -Path "$PSScriptRoot\keystore" -ItemType Directory -Force

                }

            $keystorePath ="$PSScriptRoot\keystore\$agentIPAddress"
            if(-not (Test-Path -path $keystorePath)){
    	            New-Item -Path $keystorePath -ItemType Directory -Force
                }
                Set-Content -Path "$PSScriptRoot\keystore\$agentIPAddress\kubeaccess.aue" -Value $usernameSerial
                Set-Content -Path "$PSScriptRoot\keystore\$agentIPAddress\kubeaccess.ape" -Value $passwordSerial
   
   
                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred["password"])
                $cred["password"] = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

            }
   
        } 
    
        if($cred["username"] -eq $null -or $cred["password"] -eq $null){
     
        return $null
       
        }

        return $cred
}

function test-sshConnection{

<#======================================================================================->
#
#  Checks for the reachability of remote nodes via SSH 
#
<-=======================================================================================#>

  param(
	    [Parameter(Mandatory=$true) ][string] $server
	    ,[Parameter(Mandatory=$true) ][string] $user
	    ,[Parameter(Mandatory=$true) ][string] $password
  )
    $isReachable = $false;
    $securePassword            = ConvertTo-SecureString $password -AsPlainText -Force
    $cred         	 	      = New-Object System.Management.Automation.PSCredential($user, $securePassword)

    $sshSession 			  = New-SSHSession -ComputerName $server -Credential $cred –AcceptKey -ErrorAction SilentlyContinue -Force

    if($sshSession){
        $isReachable = $sshSession.Connected -eq "true"
     }
    
    return $isReachable 

}


function load-configuration{

<#======================================================================================->
#
# loads a specified configuration file
#
<-=======================================================================================#>

    param(
        [Parameter(Mandatory=$true)][string]$path
    )
   $settings = $null;

  if($null -ne $path  -and (test-path -Path $path)){
    $settings =  get-content -path $path -Raw|ConvertFrom-Json
  
  
  }else{
  
    write-host "$path does not exist"
  }

   return $settings

}

function process-commands{
<#======================================================================================->
#
# Runs commands on remote nodes via SSH 
#
<-=======================================================================================#>
  param(
  
    [Parameter(mandatory=$true)][string]$nodeIP
    ,[Parameter(mandatory=$true)][array]$commandList
   )
         $executionSucceeded = $false;
         $credentials  =  get-cred  $nodeIP;
         $responses = run-SshCommandStream  $nodeIP  $credentials.username  $credentials.password $commandList
         foreach( $response in  $responses){
             if(-not [string]::IsNullOrEmpty( $response.flag)){
                 $executionSucceeded = $response.flag -eq 0
                 if(-not $executionSucceeded){
                   break;
                 }
             }
         }

   return @{'isSuccessful'=$executionSucceeded; 'data'= $responses}

}

function get-accessMap{

<#======================================================================================->
#
# Determines the reachability of all nodes specified in the configuration file
#
<-=======================================================================================#>
 param(
   [Parameter(Mandatory=$true)][system.object]$nodes
 )
     $nodeMap = @{}
     foreach($node in $nodes){

            $ip      = $node.ipaddress
            $credentials  =  get-cred  $ip;
            if($credentials -ne $null){
                $username     =  $credentials.username
                $password     =  $credentials.password
                $isReachable    =  test-sshConnection $ip $username $password
            }else{
                write-host "Unable to retrieve credentials for $ip"
            }
            $nodeMap[$ip]=$isReachable          
    }
    return $nodeMap
}

function process-results{
<#======================================================================================->
#
# Processes the outputs of cmmands run on remote machines
#
<-=======================================================================================#>
 param(
   [Parameter(Mandatory=$true)][system.object]$results
 )
     $isSuccessful = $results.isSuccessful;
         
         if(-not $results.isSuccessful){
               Write-host -f yellow "An error occurred while running the following commands on $($nodeIP): "
               $results.data|%{
                if(-not [string]::IsNullOrWhiteSpace($_.command)){
                     write-host "----------------------------------------------------------"
                     write-host "command: "  $_.command
                     write-host "output: "$_.response
                 }
               }
          }
    return $isSuccessful
}

function log-results{
<#======================================================================================->
#
# logs the outputs of cmmands run on remote machines
#
<-=======================================================================================#>
    param(
    [Parameter(Mandatory=$true)][system.object]$logFile
    ,[Parameter(Mandatory=$true)][system.object]$results
    )
     $jsonResults = $results | convertto-json 
    if($results){ 
       Add-Content -Path  $logFile -Value $jsonResults 
    }
    

}

function get-commands{
<#======================================================================================->
#
# formats commands to run on remote machines from the commandInfo and arguments parameters
#
<-=======================================================================================#>

    param(
      [Parameter(Mandatory=$True)][System.Object]$commandInfo
      ,[Parameter(Mandatory=$False)][array]$cmdArgs
    )
    $cmdList =@()

    $index   = 0
    $commandInfo|Sort-Object -Property 'order'|%{
    if($_.enabled -eq $true){
       if (-not [string]::IsNullOrWhiteSpace($cmdArgs) -and $cmdArgs.Length -gt $index){
            $cmdList+=$_.command -f $cmdArgs[$index];

       }else{

            $cmdList+=$_.command
       }
        
    }
     $index+=1
    }
    return $cmdList;
   
}


function get-hostfileString{
<#==========================================================->
#
# Gets the contents of the /etc/hosts file on remote machine
#
<-==========================================================#>

 param(
   [Parameter(Mandatory=$true)][system.object]$nodes
 )    
     $templateString= "{0}  {1}"
     $hostFileString=""
     foreach($node in $nodes){

            $hostFileString += ($templateString -f @($node.ipaddress, $node.hostname))+"\n"
    
    }
    return $hostFileString
}

