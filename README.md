# Kubify

This is an attempt to automate the process of installing and managing Kubernetes clusters on Ubuntu 22.04 machines. It requires a Windows machine with Powershell version 5 and above that can connect to remote Ubuntu machines via SSH (*The POSH SSH module with the default port of 22 was used*) and Ubuntu machines with ssh and curl installed:

- sudo apt install openssh-server -y
- sudo apt install curl -y

The machines should also be able to reach public repositories for the installation of tools like docker, containerd, kubectl, kubeadm, etc, and connect to one another without any problems. 

The Posh SSH module is used by the powershell script to run all ssh commands. The run.ps1 script checks for the Posh SSH module and installs it if it is not present.

The script can be initiated from a Powershell Window by passing the appropraite parameters to the run.ps1 file depending on the scenario required. The configuration file config/ubuntu.json contains the information required by the script to run. It should be modified to the requirements of the cluster to be installed. e.g. hostnames, IP addresses, roles, time zone (Canada/Atlantic), etc.

**Note:**  The appropriate execution policy for the script has to be set:
 
 `Set-ExecutionPolicy [Unrestricted|RemoteSigned|Bypass] -Force`

*Example:* `Set-ExecutionPolicy RemoteSigned -Force`

1.Install a new cluster: creates a new cluster from nodes provided in a given configuration file, if specified as a parameter or  in the default configuration file: config/ubuntu.json:
*Default:*
`.\run.ps1 -mode "install" -mainMasterNode  [mainMasterIPAddress] -customResolve [$True|$False]`

*Config File:*
`.\run.ps1 -mode "install" -mainMasterNode  [mainMasterIPAddress] -configPath ConfigFilePath -customResolve [$True|$False]`

2.Add a node to an existing cluster: Adds nodes to a given configuration file, if specified as a parameter or in the default configuration file: config/ubuntu.json,  to an existing cluster.
*Default:*
`.\run.ps1 -mode "add" -mainMasterNode  [mainMasterIPAddress] -customResolve [$True|$False]`

*Config File:*
`.\run.ps1 -mode "add" -mainMasterNode  [mainMasterIPAddress] -configPath ConfigFilePath -customResolve [$True|$False]`

3.Remove a node from a cluster: Removes a nodes from a given configuration file, if specified as a parameter or in the default configuration file: config/ubuntu.json,  to an existing cluster.

*Default:*
`.\run.ps1 -mode "remove" -mainMasterNode  [mainMasterIPAddress] -customResolve [$True|$False]`

*Config File:*
`.\run.ps1 -mode "remove" -mainMasterNode  [mainMasterIPAddress] -configPath ConfigFilePath -customResolve [$True|$False]`

4.Show configured Masters: Lists master nodes configured by the tool.
*Default:*
`.\run.ps1 -mode "masters" -mainMasterNode  [mainMasterIPAddress] `

*Config File:*
`.\run.ps1 -mode "masters" -mainMasterNode  [mainMasterIPAddress] -configPath ConfigFilePath `


**Note:** The Execution policy of the scripts has been set to *Unrestricted* to grant permission for the encryption and decryption of ssh credentials

**Parameters:**
- *MainMasterNode*: The IP address or hostname of a Control Plane node that will serve at the reference for all other nodes e.g. 192.168.12.12

- *ConfigurationPath*: The full path or relative path from the root directory to the json configuration file that contains the nodes and commands to be used by the script. e.g. .\config\ubuntu.json. If no configuration file is specified, the default configuration file  *.\config\ubuntu.json* will be used.

- *useCustomResolvConf*: A boolean flag($True, $False, 1 or 0) that specifies if a custom /etc/resolv.conf file should be used. The contents of the /etc/resolv.conf file can be overriden by updating the config/resolv.conf if required.

- *newToken*: A boolean flag($True, $False, 1 or 0) that specifies if a new token should be created from a control plane node that can be used to add new nodes to the cluster. It is not required for a new cluster but it would be required once the the initial token expires 24 hours after its creation.

## Configuration File

The default config file is: config/ubuntu.json and can be modified as desired. New configuration files can be passed to the script for processing. The configuration file consists of nodes and the commands to be run on them defined as arrays of objects in json format:
`{
  "nodes":[]
  "commands":[]
}`

### Nodes are defined by their:
    - Hostname
    - IP Address
    - Role: 'master' or 'worker'

### Commands are defined by:
    - order: The position of the command with regards to other commands
    - enabled: Determines if the command should be executed
    - Role: 'master' or 'worker'

## Note

It is best to take clones or snapshots of virtual nodes before running this tool against them so that they can always be reverted to their original state. 
*You are responsible for running commands against your machines.*