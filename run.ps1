﻿<# 
 # Sources:
 #   - https://phoenixnap.com/kb/install-kubernetes-on-ubuntu
 #   - https://medium.com/@sethiabinash123/latest-step-by-step-guide-on-installing-kubernetes-cluster-on-ubuntu-22-04-07c596a9a04f
 #   - Read more here: https://locall.host/powershell-is-multithreaded-a-comprehensive-guide/
 #
 # Dependecies
 #   - Windows Workstation: 
 #      - NetworK Connectivity
 #      - Execution Policy
 #      - Posh SSH
 #
 #   - Kube Nodes
 #      - Ubuntu22.04
 #      - NetworK Connectivity
 #      - openssh-server (sudo apt install openssh-server -y)
 #      - curl (sudo apt install curl -y)
 #
 # Challenges: 
 #   - Timeout Waiting for API Server -  Resolved by deleting /etc/systemd/system/kubelet.service.d/10-kubeadm.conf before running kubeadm int
 #     sudo rm -rf /etc/systemd/system/kubelet.service.d/10-kubeadm.conf 
 #     (https://github.com/kubernetes/kubernetes/issues/125275)
 #
 #>
Param
(
     [Parameter(Mandatory=$true)][ValidateSet("install", "add", "remove", "masters")] [String] $mode
    ,[Parameter(mandatory=$False)][string]$mainMasterNode=$null
    ,[Parameter(Mandatory=$false)][string]$configPath=$null
    ,[Parameter(Mandatory=$false)][bool]$customResolve=$false
    ,[Parameter(Mandatory=$false)][bool]$newToken=$false
)

$scriptRoot    = $MyInvocation.MyCommand.Path # $PSScriptRoot
$scriptName    = $MyInvocation.MyCommand.Name
$scriptRoot    = $scriptRoot.replace($scriptName,'')
$scriptRoot    = $scriptRoot[0..($scriptRoot.Length-1)] -join ''
$poshSsh       = get-installedmodule -name posh-ssh;
$credentialMap = @{};

$logFileMap = @{}
$logDate = get-date -format "yyyyMMdd_hhmmss";
write-host "Log file suffix: $logDate";

$resolvConfPath = "$($scriptRoot)config\resolv.conf"
$resolvContents = "";

$etcResolv     = @'
sudo cat >/tmp/resolv.conf <<- EOD
#This is /run/systemd/resolve/stub-resolv.conf managed by man:systemd-resolved(8).
# Do not edit.
#
# This file might be symlinked as /etc/resolv.conf. If you're looking at
# /etc/resolv.conf and seeing this text, you have followed the symlink.
#
# This is a dynamic resolv.conf file for connecting local clients to the
# internal DNS stub resolver of systemd-resolved. This file lists all
# configured search domains.
#
# Run "resolvectl status" to see details about the uplink DNS servers
# currently in use.
#
# Third party programs should typically not access this file directly, but only
# through the symlink at /etc/resolv.conf. To manage man:resolv.conf(5) in a
# different way, replace this symlink by a static file or a different symlink.
#
# See man:systemd-resolved.service(8) for details about the supported modes of
# operation for /etc/resolv.conf.
namserver 8.8.8.8
nameserver 8.8.4.4
#options edns0 trust-ad
search .
EOD
'@

if ((test-path -path $resolvConfPath) -eq $true){
    $resolvContents = (get-content -path  $resolvConfPath)  -join "`n";
    if(-not [string]::IsNullOrEmpty($resolvContents )){
    $etcResolv     = @"
$($resolvContents)
"@ 
    }
}

$reset_resolv_conf = "sudo cp -f /tmp/resolv.conf /etc/"

if(-not $poshSsh){
    Install-Module -Name Posh-SSH -RequiredVersion 3.0.8 -Force
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -Verbose 
}
 
Import-Module  "$($scriptRoot)install_tools.ps1" -force


function run-CommandsOnNode{
<#=======================================================================================================->
#  Runs commands on remote nodes
<-=======================================================================================================#>
  param(
  [Parameter(Mandatory=$true)][system.object]$nodeIP
  ,[Parameter(Mandatory=$true)][system.object]$scriptRoot
  ,[Parameter(Mandatory=$true)][system.object]$commandList
  ,[Parameter(Mandatory=$true)][system.object]$logFile
  )
             Import-Module -PassThru  "$($scriptRoot)\install_tools.ps1" -Force

            $results = process-commands $nodeIP $commandList
            write-host  "logging to $logFile"
            log-results $logFile $results
            $isSuccessful = process-results $results
            if(-not $isSuccessful){
                break;
            }


}

function install-commontools{

<#=======================================================================================================->
#  prepares all nodes for the cluster by installing all tools required by Kubernetes
<-=======================================================================================================#>
        param(
           [Parameter(Mandatory=$true)][system.object]$nodeAccessMap
          ,[Parameter(Mandatory=$true)][system.object]$commands
         )
   
    $jobList= New-Object System.Collections.ArrayList;
    $colorMap = @{}
    $colors   = [Enum]::GetValues([ConsoleColor])
    $colorIndex = 15
    $nodeAccessMap.keys | % {
        $nodeIP  =$_
        $colorMap[$nodeIP] = $colors[$colorIndex]
        $isReachable = $nodeAccessMap[$nodeIP]
        if($isReachable -eq $true){

            $credentials =  get-cred $nodeIP
            $commandList =  @()
            $commandList += $commands.get_su.command -f $credentials.password
            if($customResolve -eq $True){ 
                $commandList += $etcResolv
                $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                $commandList += $reset_resolv_conf
            }
            $commandList += get-commands $commands.install_docker
            if($customResolve -eq $True){ 
                $commandList += $reset_resolv_conf
            }
            $commandList += get-commands $commands.add_kube_repo_key
            if($customResolve -eq $True){ 
                $commandList += $reset_resolv_conf
            }
            $commandList += get-commands $commands.add_kube_repo
            if($customResolve -eq $True){ 
                $commandList += $reset_resolv_conf
            }
            $commandList += get-commands $commands.install_kube_tools
            if($customResolve -eq $True){ 
                $commandList += $reset_resolv_conf
            }
            $commandList += get-commands $commands.prepare_for_kube_deployment
            if($customResolve -eq $True){ 
                $commandList += $reset_resolv_conf
            }
            $node = $nodes|?{$_.ipaddress -eq $nodeIP}
            $hostFileString = get-hostfileString $nodes
            $cmdArgs =  @($node.hostname, $hostFileString )
            $commandList += get-commands $commands.assign_hostnames $cmdArgs
            $job   = start-job  -scriptblock ${Function:run-CommandsOnNode}  -ArgumentList $nodeIP,$scriptRoot,$commandList,$logFileMap[$nodeIP]

            [void] $jobList.Add([pscustomobject]@{
                      node = $nodeIP;
                    job_id = $job.id
                }
            )
             
                 

        }else{
       
            Write-host "Unable to connect to $($nodeIP).Please check ssh service"
     
        }
         $colorIndex-=1
            if ($colorIndex -eq -1){
             $colorIndex = 15
            }
     }
     $jobsCompleted = $false
     $jobCount = $jobList.Count
     while(-not $jobsCompleted){

        $completeCount = 0
        $jobList|%{
           $job = get-job $_.job_id
           if($job.state.toString().toLower() -ne "running"){

                     $completeCount+=1;

             }else{
                $node = $_.node
                $currentTime = get-date -format("yyyyMMdd hh:mm:ss")
                write-host ""
                write-host -f $colorMap[$node] "=========================================================="
                write-host -f $colorMap[$node] "Node $node output at $currentTime" 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
                receive-job -id $job.id 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
             }
             
         } 
         if($completeCount -ne  $jobCount){
                start-sleep -Seconds 3
           }else{
            $jobsCompleted = $true
           }
     
     }

    $jobList.clear()

}

function initialize-ControlPlane{

<#=======================================================================================================->
#  Initializes master nodes defined in the underlying configuration file
<-=======================================================================================================#>

        param(
        [Parameter(Mandatory=$true)][system.object]$allMasterNodes
        ,[Parameter(Mandatory=$true)][system.object]$nodeAccessMap
        ,[Parameter(Mandatory=$true)][system.object]$commands
        )

        $jobList= New-Object System.Collections.ArrayList;
        $colorMap = @{}
        $colors   = [Enum]::GetValues([ConsoleColor])
        $colorIndex = 15
        $nodeAccessMap.keys|%{
            $nodeIP  =$_
            $colorMap[$nodeIP] = $colors[$colorIndex]
            $isReachable = $nodeAccessMap[$nodeIP]
            if($isReachable -eq $true){
                $node = $allMasterNodes|?{$_.ipaddress -eq $nodeIP}
                if($null -ne $node){
                    
                
                $commandList =  @()
                $credentials =  get-cred $nodeIP
                $commandList += $commands.get_su.command -f $credentials.password
                if($customResolve -eq $True){ 
                 $commandList += $reset_resolv_conf
                }
                $commandList += get-commands $commands.initialize_kube_master_01
                $job   = start-job  -scriptblock ${Function:run-CommandsOnNode}  -ArgumentList $nodeIP,$scriptRoot,$commandList,$logFileMap[$nodeIP]
                [void] $jobList.Add([pscustomobject]@{
                                    node = $nodeIP;
                                    job_id = $job.id
                                    }
                                )
                }
    
            }else{
       
               Write-host "Unable to connect to $($nodeIP).Please check ssh service"
     
        }
        $colorIndex-=1
        if ($colorIndex -eq -1){
                    $colorIndex = 15
         }
        }

        $jobsCompleted = $false
        $jobCount = $jobList.Count
        while(-not $jobsCompleted){

        $completeCount = 0
        $jobList|%{
            $job = get-job $_.job_id
            if($job.state.toString().toLower() -ne "running"){

                $completeCount+=1;

            }else{
                $node = $_.node
                $currentTime = get-date -format("yyyyMMdd hh:mm:ss")
                write-host ""
                write-host -f $colorMap[$node] "=========================================================="
                write-host -f $colorMap[$node] "Node $node output at $currentTime" 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
                receive-job -id $job.id 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
            }
             
        } 

        if($completeCount -ne  $jobCount){
            start-sleep -Seconds 3
        }else{
            $jobsCompleted = $true
        }
     
        }

        $jobList.clear()
        $colors   = [Enum]::GetValues([ConsoleColor])
        $colorIndex = 15
        $nodeAccessMap.keys|%{
            $nodeIP  =$_
            $colorMap[$nodeIP] = $colors[$colorIndex]
            $isReachable = $nodeAccessMap[$nodeIP]
            if($isReachable -eq $true){
                
                $node = $allMasterNodes|?{$_.ipaddress -eq $nodeIP}
                if($null -ne $node){
                    
                
                    $commandList =  @()
                    $credentials =  get-cred $node.ipaddress
                    $commandList += $commands.get_su.command -f $credentials.password
                    if($customResolve -eq $True){ 
                            $commandList += $reset_resolv_conf
                    }
                $commandList += get-commands $commands.initialize_kube_master_02
                $job   = start-job  -scriptblock ${Function:run-CommandsOnNode}  -ArgumentList $node.ipaddress,$scriptRoot,$commandList,$logFileMap[$nodeIP]
                [void] $jobList.Add([pscustomobject]@{
                                    node = $nodeIP;
                                    job_id = $job.id
                                    }
                                )
                }
    
            }else{
       
            Write-host "Unable to connect to $($nodeIP).Please check ssh service"
     
            }
            $colorIndex-=1
            if ($colorIndex -eq -1){
                        $colorIndex = 15
            }
        }
 
        $jobsCompleted = $false
        $jobCount = $jobList.Count
        while(-not $jobsCompleted){

        $completeCount = 0
        $jobList|%{
            $job = get-job $_.job_id
            if($job.state.toString().toLower() -ne "running"){

                $completeCount+=1;

            }else{
                $node = $_.node
                $currentTime = get-date -format("yyyyMMdd hh:mm:ss")
                write-host ""
                write-host -f $colorMap[$node] "=========================================================="
                write-host -f $colorMap[$node] "Node $node output at $currentTime" 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
                receive-job -id $job.id 
                write-host -f $colorMap[$node] "----------------------------------------------------------"
            }
             
        } 

        if($completeCount -ne  $jobCount){
            start-sleep -Seconds 3
        }else{
            $jobsCompleted = $true
        }
     
        }

        $jobList.clear()
        $colors   = [Enum]::GetValues([ConsoleColor])
        $colorIndex = 15
        $nodeAccessMap.keys|%{
            $nodeIP  =$_
            $colorMap[$nodeIP] = $colors[$colorIndex]
            $isReachable = $nodeAccessMap[$nodeIP]
            if($isReachable -eq $true){
                $node = $allMasterNodes|?{$_.ipaddress -eq $nodeIP}
                if($null -ne $node){
                    
             
                    $commandList =  @()
                    $credentials =  get-cred $nodeIP
                    $commandList += $commands.get_su.command -f $credentials.password
                    if($customResolve -eq $True){ 
                        $commandList += $reset_resolv_conf
                    }
                    if($nodeIP -eq $mainMasterNode -or $mainMasterNode -eq $node.hostname){
                            $commandList += get-commands $commands.initialize_kube_master_03 @("",@($nodeIP,$nodeIP))  #  @($nodeIP) The extra element is requirement for the arguments to be treated like an array
                    }
                
                    $job   = start-job  -scriptblock ${Function:run-CommandsOnNode}  -ArgumentList $nodeIP,$scriptRoot,$commandList,$logFileMap[$nodeIP]
                    [void] $jobList.Add([pscustomobject]@{
                                        node = $nodeIP;
                                        job_id = $job.id
                                        }
                                    )
                }
    
            }else{
       
                Write-host "Unable to connect to $($nodeIP).Please check ssh service"
     
            }
            $colorIndex-=1
            if ($colorIndex -eq -1){
                $colorIndex = 15
            }
        }

        $jobsCompleted = $false
        $jobCount = $jobList.Count
        while(-not $jobsCompleted){

            $completeCount = 0
            $jobList|%{
                $job = get-job $_.job_id
                if($job.state.toString().toLower() -ne "running"){

                    $completeCount+=1;

                }else{
                    $node = $_.node
                    $currentTime = get-date -format("yyyyMMdd hh:mm:ss")
                    write-host ""
                    write-host -f $colorMap[$node] "=========================================================="
                    write-host -f $colorMap[$node] "Node $node output at $currentTime" 
                    write-host -f $colorMap[$node] "----------------------------------------------------------"
                    receive-job -id $job.id 
                    write-host -f $colorMap[$node] "----------------------------------------------------------"
                }
             
            } 

            if($completeCount -ne  $jobCount){
                start-sleep -Seconds 3
            }else{
                $jobsCompleted = $true
            }
     
        }

        $jobList.clear()

}


function Add-NodesToCluster{
<#======================================================================================->
#
#  Adds all nodes that have been prepared with the necessary tools to a cluster. The nodes 
#  are added based on the roles specified in the configuration file.
 <-=======================================================================================#>
       param(
            [Parameter(Mandatory=$true)][string]$masterIP
            ,[Parameter(Mandatory=$true)][system.object]$nodes
            ,[Parameter(Mandatory=$true)][system.object]$nodeAccessMap
            ,[Parameter(Mandatory=$true)][system.object]$commands
            ,[Parameter(Mandatory=$False)][system.object]$newToken=$False
         )

       $configPath =  "$($scriptRoot)config\control_planes\$($masterIP)\cluster_config_commands.json"

       if(test-path -Path $configPath ){
         
            $masterCommands = get-content -path $configPath  | convertfrom-json

            $jobList= New-Object System.Collections.ArrayList;
            $colorMap = @{}
            $colors   = [Enum]::GetValues([ConsoleColor])
            $colorIndex = 15

            
            $credentials =  get-cred $masterIP
            $commandList =  @()
            $commandList += $commands.get_su.command -f $credentials.password
            if($customResolve -eq $True){ 
                $commandList += $etcResolv
                $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                $commandList += $reset_resolv_conf
            }
            $commandList +=  get-commands $commands.kube_token_generate
            $result = @{} 
            $token  = $Null    
            if($newToken){  
                $response = run-SshCommandStream $masterIP $credentials.username  $credentials.password $commandList;
                $result  = $response[($response.length -1)]
                $token = ($result.response -split('\n'))[1]
            }


            $comps = $masterCommands.add_master_node -split '\s'
             if($newToken){  
                $comps[4] = $token
            }
            $addMasterNode = $comps -join ' '


            $comps = $masterCommands.add_worker_node -split '\s'
             if($newToken){ 
                $comps[4] = $token
            }
            $addWorkerNode = $comps -join ' '

            $newMasterNodes = $nodes|?{$_.role -eq 'master'}

            if($newMasterNodes -and $newMasterNodes.length -gt 0){
                $commandList =  @()
                $commandList += $commands.get_su.command -f $credentials.password
                if($customResolve -eq $True){ 
                    $commandList += $etcResolv
                    $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                    $commandList += $reset_resolv_conf
                }
                $result = @{}       
                $response = run-SshCommandStream $masterIP $credentials.username  $credentials.password $commandList;
                $result  = $response[($response.length -1)]
                $certKey = ($result.response -split('\n'))[1]


                $comps = $addMasterNode -split '\s'
                $comps[( $comps.Length -1)] = $certKey
            $addMasterNode = $comps -join ' '
            }

           $nodeAccessMap.keys | % {
                $nodeIP  =$_
                $node    = $nodes|?{$_.ipaddress -eq $nodeIP}
                $nodeName =   $node.hostname
                $colorMap[$nodeIP] = $colors[$colorIndex]
                $isReachable = $nodeAccessMap[$nodeIP]

                if($isReachable -eq $true){
                    

                        $credentials =  get-cred $nodeIP
                        $commandList =  @()
                        $commandList += $commands.get_su.command -f $credentials.password
                        if($customResolve -eq $True){ 
                            $commandList += $etcResolv
                            $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                            $commandList += $reset_resolv_conf
                        }
                        $commandList += get-commands $commands.add_node_to_cluster
                        $commandList += "sudo systemctl start kubelet"
                        $nodeRole    =  ($nodes|?{$_.ipaddress -eq $nodeIP}).role
                        if($nodeRole.trim().toLower() -eq 'master'){

                             $commandList +="sudo " +$addMasterNode

                        }else{
            
                           $commandList +="sudo " + $addWorkerNode

                        }

                        $commandList += "sudo systemctl enable apparmor && sudo systemctl start apparmor"

                           
                        $job   = start-job  -scriptblock ${Function:run-CommandsOnNode}  -ArgumentList $nodeIP,$scriptRoot,$commandList,$logFileMap[$nodeIP]

                        [void] $jobList.Add([pscustomobject]@{
                                  node = $nodeIP;
                                job_id = $job.id
                            }
                        )
             
                 

                }else{
       
                    Write-host "Unable to connect to $($nodeIP).Please check ssh service"
     
                }
                $colorIndex-=1;
                if ($colorIndex -eq -1){
                        $colorIndex = 15
                    }


                }
            $jobsCompleted = $false
            $jobCount = $jobList.Count
            while(-not $jobsCompleted){

                $completeCount = 0
                $jobList|%{
                    $job = get-job $_.job_id
                                            if($job.state.toString().toLower() -ne "running"){

                    $completeCount+=1;

            }else{
                        $node = $_.node
                        $currentTime = get-date -format("yyyyMMdd hh:mm:ss")
                        write-host ""
                        write-host -f $colorMap[$node] "=========================================================="
                        write-host -f $colorMap[$node] "Node $node output at $currentTime" 
                        write-host -f $colorMap[$node] "----------------------------------------------------------"
                        receive-job -id $job.id 
                        write-host -f $colorMap[$node] "----------------------------------------------------------"
                        }
             
                    } 
                    if($completeCount -ne  $jobCount){
                        start-sleep -Seconds 3
                    }else{
                    $jobsCompleted = $true
                    }
     
                }

               $jobList.clear()
                $colorIndex = 15
                $nodeAccessMap.keys | % {
                    $nodeIP  =$_
                    $node    = $nodes|?{$_.ipaddress -eq $nodeIP}
                    $nodeName =   $node.hostname
                    $colorMap[$nodeIP] = $colors[$colorIndex]
                    $isReachable = $nodeAccessMap[$nodeIP]

                    if($isReachable -eq $true){
                           
                        $credentials =  get-cred $masterIP
                        $commandList =  @()
                        $commandList += $commands.get_su.command -f $credentials.password
                        if($customResolve -eq $True){ 
                            $commandList += $etcResolv
                            $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                            $commandList += $reset_resolv_conf
                        }
                        $nodeRole    =  ($nodes|?{$_.ipaddress -eq $nodeIP}).role
                        if($nodeRole.trim().toLower() -eq 'master'){
                                $commandList +="kubectl label node {0} node-role.kubernetes.io/master=master" -f  $nodeName
                        }else{
                             $commandList +="kubectl label node {0} node-role.kubernetes.io/worker=worker" -f  $nodeName
                        }
                        $result = @{}       
                     
                        $response = run-SshCommandStream  $masterIP  $credentials.username  $credentials.password $commandList;
                        $result  = $response[($response.length -1)]
                        $response

                        $credentials =  get-cred $nodeIP
                        $commandList =  @()
                        $commandList += $commands.get_su.command -f $credentials.password
                        if($customResolve -eq $True){ 
                            $commandList += $etcResolv
                            $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                            $commandList += $reset_resolv_conf
                        }
                        $commandList += get-commands $commands.flannel_network_config
                        $result      = @{}       
                     
                        $response = run-SshCommandStream  $nodeIP  $credentials.username  $credentials.password $commandList;
                        $result  = $response[($response.length -1)]
                        
                            
                     }
                 }
               

        }else{
          write-host  -f red "Unable to find configuration for master: $($masterIP) at the expected path: $scriptRoot\config\control_planes\$($masterIP)"
        }

}

function install-NewNodes{
<#=======================================================================================================->
#  installs all nodes specified in a configuration file apart from the main master node. The main 
#  master node must be present in the configuration file along with the nodes to be 
#  prepared for Kubernetes. If no configuration file is specified, the default config, .\config\ubuntu.json, 
#  will be used.
 <-=======================================================================================================#>


	   param(
		[Parameter(mandatory=$True)][string]$masterNode
		,[Parameter(mandatory=$False)][string]$configPath = "$scriptRoot\config\ubuntu.json"		
		)
   
    $config = load-configuration $configPath;
     
    if($config -ne $null){ 

        $nodes           = $config.nodes
        $commands        = $config.commands
        $nodeAccessMap   = get-accessMap $nodes
        $mainMaster      = $nodes|?{($_.ipaddress -eq $masterNode) -or ($_.hostname -eq $masterNode) }
        $nodeAccessMap.keys|%{
            $ip = $_
            $logFile = "$PSScriptRoot\logs\$($ip)_$($logDate).json"
            $logFileMap[$ip] =  $logFile 
        }
        if(-not [string]::IsNullOrEmpty($masterNode) -and $null -ne   $mainMaster ) {

		    $nonMasterNodes = $nodes|?{($_.ipaddress -ne $masterNode) -and ($_.hostname -ne $masterNode) }
		    $pendingNodesMap = @{}
		    $nonMasterNodes|%{
			    $node = $_
			    $pendingNodesMap[$node.ipaddress] = $nodeAccessMap[$node.ipaddress]				
		    }	

         $allMasterNodes   = $nodes|?{$_.role -eq 'master' -and ($_.ipaddress -ne $masterNode -and $_.hostname -ne $_.$masterNode)}
        
        install-commontools $pendingNodesMap $commands
        
        if($null -ne $allMasterNodes){
            $allMasterNodes
            $pendingMasterMap =@{}
            foreach( $node in $allMasterNodes){
               
               $pendingMasterMap[$node.ipaddress] =  $nodeAccessMap[$node.ipaddress]
            }
           
            initialize-ControlPlane $allMasterNodes $pendingMasterMap $commands 
           
            foreach( $node in $allMasterNodes){
            
                $commandList =  @()
                $credentials =  get-cred $node.ipaddress
                $commandList += $commands.get_su.command -f $credentials.password
                $commandList += "mkdir -p `$HOME/.kube"
                $adminConfPath =  ".\config\control_planes\$masterNode\admin.conf"

                if(test-path -Path $adminConfPath ){

                    $password            = ConvertTo-SecureString $credentials.password -AsPlainText -Force
                    $cred         	 	 = New-Object System.Management.Automation.PSCredential ($credentials.username, $password)
                    Set-SCPItem -ComputerName $node.ipaddress -Credential  $cred   -Path  $adminConfPath -Destination "/tmp" -Verbose -AcceptKey
                    $adminConf = get-content -path $adminConfPath
                    $commandList += "bash -c 'sudo cp -f /tmp/admin.conf /etc/kubernetes/'"
                    $commandList += "bash -c 'sudo cp -i /etc/kubernetes/admin.conf `$HOME/.kube/config'"
                    $commandList += "sudo chown `$(id -u):`$(id -g) `$HOME/.kube/config"
                
                }
                
                
                $results     =  run-SshCommandStream  $node.ipaddress $credentials.username  $credentials.password $commandList;

                }

        }

        
		Add-NodesToCluster $masterNode $nonMasterNodes $pendingNodesMap $commands $newToken

      }else{
          if(-not [string]::isNullOrEmpty($masterNode)){
            Write-host -f yellow "Could not find the specified master node: $masterNode. Please select a configured master node"
            }else{
                Write-host -f yellow "Please specify a valid master node"
            }
       }		

     } else{
   
        Write-host -f red "Unable to find the specified configuration file: $config"
 
     }

}


function remove-Nodes{
<#======================================================================================->
#
#  Remove all nodes specified in a configuration file apart from the main master node. The main 
#  master node must be present in the configuration file along with the nodes to be 
#  removed. If no configuration file is specified, the default config, .\config\ubuntu.json, 
#  will be used.
 <-=======================================================================================#>

	   param(
		[Parameter(mandatory=$True)][string]$masterNode
		,[Parameter(mandatory=$False)][string]$configPath = "$scriptRoot\config\ubuntu.json"		
		)
   
    $config = load-configuration $configPath;

     
    if($config -ne $null){ 
     if(-not [string]::IsNullOrEmpty($masterNode)) {
        $nodes           = $config.nodes
        $commands        = $config.commands
        $nodeAccessMap   = get-accessMap $nodes
         $nodeAccessMap.keys|%{
            $ip = $_
            $logFile = "$PSScriptRoot\logs\$($ip)_$($logDate).json"
            $logFileMap[$ip] =  $logFile 
        }
		$nonMasterNodes = $nodes|?{($_.ipaddress -ne $masterNode) -and ($_.hostname -ne $masterNode) }
		$mainMaster      = $nodes|?{($_.ipaddress -eq $masterNode) -or ($_.hostname -eq $masterNode) }
        $pendingNodesMap = @{}
		$nonMasterNodes|%{
			$node = $_
			$pendingNodesMap[$node.ipaddress] = $nodeAccessMap[$node.ipaddress]				
		}	

	       $jobList= New-Object System.Collections.ArrayList;
            $colorMap = @{}
            $colors   = [Enum]::GetValues([ConsoleColor])
            $colorIndex = 15

            $pendingNodesMap.keys | % {
            $nodeIP  =$_
            $node    = $nodes|?{$_.ipaddress -eq $nodeIP}
            $nodeName =   $node.hostname
            $colorMap[$nodeIP] = $colors[$colorIndex]
            $isReachable = $pendingNodesMap[$nodeIP]

            if($isReachable -eq $true -and $nodeAccessMap[$mainMaster.ipaddress] -eq $true ){

                    $credentials =  get-cred $mainMaster.ipaddress
                    $commandList =  @()
                    $commandList += $commands.get_su.command -f $credentials.password
                    if($customResolve -eq $True){ 
                        $commandList += $etcResolv
                        $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                        $commandList += $reset_resolv_conf
                    }
                    $commandList += get-commands $commands.drain_node @($nodeName,$nodeName)
                    $result = @{flag=1}       
                    while($null -ne $result -and $result.flag -ne 0){
                        $response = run-SshCommandStream  $mainMaster.ipaddress  $credentials.username  $credentials.password $commandList;
                        $result  = $response[($response.length -1)]
                        $result.response
                       # write-host "Waiting for $nodeIP to be successfully drained"
                        start-sleep -Seconds  1
                    }
                     
                    $commandList =  @()
                    $commandList += $commands.get_su.command -f $credentials.password
                     if($customResolve -eq $True){ 
                        $commandList += $etcResolv
                        $commandList += "sudo chmod 0644 /tmp/resolv.conf"
                        $commandList += $reset_resolv_conf 
                    }
                    $commandList += get-commands $commands.delete_node @($nodeName) 
                    $commandList += "kubectl get nodes" 

                    $result = @{flag=1}       
                    while($null -ne $result  -and $result.flag -ne 0){
                        $response = run-SshCommandStream  $mainMaster.ipaddress  $credentials.username  $credentials.password $commandList;
                        $result  = $response[($response.length -1)]
                        $result.response
                        #write-host "Waiting for $nodeIP to be deleted"
                        start-sleep -Seconds  1
                    }

                 

            }else{
       
                Write-host "Unable to connect either to $($nodeIP) or MasterNode $($mainMaster.ipaddress) or both.Please check ssh service on both nodes"
     
            }
     
      }		

     }else{
            Write-host -f yellow "Please specify a master node"
       } 
     }else{
   
        Write-host -f red "Unable to find the specified configuration file: $config"
 
     }

}


function install-newCluster {

<#=======================================================================================================->
#  prepares all nodes for the cluster
<-=======================================================================================================#>

   param(
        [Parameter(mandatory=$False)][string]$configPath = "$scriptRoot\config\ubuntu.json"
    )
   
    $config = load-configuration $configPath;

    if($config -ne $null){ 

        $nodes           = $config.nodes
        $commands        = $config.commands
        $nodeAccessMap   = get-accessMap $nodes
        $nodeAccessMap.keys|%{
            $ip = $_
            $logFile = "$PSScriptRoot\logs\$($ip)_$($logDate).json"
            $logFileMap[$ip] =  $logFile 
        }
        install-commontools $nodeAccessMap $commands
        $allMasterNodes   = $nodes|?{$_.role -eq 'master'}
        $mainMaster       = $allMasterNodes[0]
        
        initialize-ControlPlane $mainMaster $nodeAccessMap $commands              
        $commandList =  @()
        $credentials =  get-cred $mainMaster.ipaddress
        $commandList += $commands.get_su.command -f $credentials.password
        $commandList += get-commands $commands.initialize_kube_master_03_a
        $result = @{flag=1}       
        while($null -ne $result -and $result.flag -ne 0){
            $response = run-SshCommandStream  $mainMaster.ipaddress  $credentials.username  $credentials.password $commandList;
            $result  = $response[1]
            start-sleep -Seconds  1
        }
        $kubeAdminInitResults =   $result.response
        $lines= ($kubeAdminInitResults.trim() -split '\n') 
        $AddWorkerNodeCMD = ("{0}{1}"  -f  $lines[-3],$lines[-2]).replace('\','')
        $lines[-7] -match '".*"'
        $reloadCertsCMD=($Matches[0]).replace('"',"")
        $AddMasterNodeCMD = ("{0}{1}{2}"  -f  $lines[-13],$lines[-12],$lines[-11]).replace('\','')
        $netWorkOptionsURL = $lines[-17]
        $lines[-18] -match '".*"'
        $deployPodNetworkCMD=($Matches[0]).replace('"',"")

        $commandList =  @()
        $credentials =  get-cred $mainMaster.ipaddress
        $commandList += $commands.get_su.command -f $credentials.password
        $commandList += get-commands $commands.get_admin_config
        $response    =  run-SshCommandStream  $mainMaster.ipaddress  $credentials.username  $credentials.password $commandList;
        $adminConf   =  $response[1].response  
        $adminConf   =  $adminConf.replace( $commands.get_admin_config.command,'').trim().split("`n")
        $adminConf   =  $adminConf[0..($adminConf.Length-2)] -join "`n"
     
        $clusterConfigMap                        = @{}
        $clusterConfigMap['add_worker_node']     = (($AddWorkerNodeCMD -replace '\r','') -replace '\t','').trim()
        $clusterConfigMap['add_master_node']     = (($AddMasterNodeCMD -replace '\r','') -replace '\t','').trim()
        $clusterConfigMap['reload_certs']        = (($reloadCertsCMD -replace '\r','') -replace '\t','').trim()
        $clusterConfigMap['deploy_ndetwork']     = (($deployPodNetworkCMD -replace '\r','') -replace '\t','').trim()
        $clusterConfigMap['network_options_url'] = (($netWorkOptionsURL -replace '\r','') -replace '\t','').trim()
        
        $masterIP     =  $mainMaster.ipaddress
        
        $configFolder =  "$scriptRoot\config\control_planes\$($masterIP)";

        if( -not (test-path -path $configFolder)){
           new-item -Path $configFolder -ItemType Directory -Force
         }

         $adminConf.trim()|Out-File -FilePath "$configFolder\admin.conf" -Force
         $clusterConfigMap|convertto-json|Out-File -FilePath "$configFolder\cluster_config_commands.json" -Force

        $commandList =  @()
        $credentials =  get-cred $masterIP
        $commandList += $commands.get_su.command -f $credentials.password
        $commandList += get-commands $commands.initialize_kube_master_04
        $commandList += get-commands $commands.deploy_flannel_network_to_master
        $commandList += get-commands $commands.flannel_network_config
        $results     =  run-SshCommandStream  $mainMaster.ipaddress  $credentials.username  $credentials.password $commandList;
        
        $allOtherNodes = $nodes|?{$_.ipaddress -ne $masterIP}
     
        $pendingNodesMap = @{}
        $allOtherNodes|%{
           $node = $_
            $pendingNodesMap[$node.ipaddress] = $nodeAccessMap[$node.ipaddress]
        }
   
        Add-NodesToCluster $masterIP $allOtherNodes $pendingNodesMap $commands $false         

     } else{
   
        Write-host -f red "Unable to find the specified configuration file: $config"
 
     }

}



switch ($mode)
{
	"install" {
               install-newCluster 
               
              }

    "add" { 
    
            if(-not [string]::IsNullOrEmpty($mainMasterNode)){
            if( -not [string]::IsNullOrEmpty($configPath)){
                Write-host -f green "NOTE: This will add all nodes apart from the master node in the specified configuration file to the cluster"
                install-NewNodes -masterNode $mainMasterNode  -configPath $configPath
         }elseif(-not [string]::IsNullOrEmpty($mainMasterNode) -and  [string]::IsNullOrEmpty($configPath) ){
                Write-host -f green "NOTE: This will add all nodes apart from the master node in the default configuration file to the cluster"
                install-NewNodes -masterNode $mainMasterNode
         }
        }else{
                 Write-host -f red "Please provide a master node "
         }
            
    
     }

    "masters" {
        
                $configFolder = "$($scriptRoot)config\control_planes\"
                $masterFolders = get-childitem -path $configFolder 
                write-host -f Cyan "The Following Control Plane nodes are configured:"
                write-host ""
                $masterFolders|%{
                   write-host  -f Green $_.Name
                }
        
    }

    "remove" {
    
        if(-not [string]::IsNullOrEmpty($mainMasterNode)  ){

            if( -not [string]::IsNullOrEmpty($configPath)){
                 Write-host -f yellow "WARNING: This will remove all nodes  in the specified configuration file from the cluster apart from the master node"
                    remove-Nodes -masterNode $mainMasterNode -configPath $configPath
             }elseif(-not [string]::IsNullOrEmpty($mainMasterNode) -and  [string]::IsNullOrWhiteSpace($configPath) ){
                    Write-host -f yellow "WARNING: This will remove all nodes in the default configuration file from the cluster apart from the master node"
                     remove-Nodes  -masterNode  $mainMasterNode
             }
         }else{
         
           Write-host -f red "Please provide a master node "
         }
            
    
    
    }
}

