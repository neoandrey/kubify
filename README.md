# Kubify

This is an attempt to automate the process of installing and managing Kubernetes clusters on Ubuntu 22.04 machines. It requires a Windows machine with Powershell version 5 and above that can connect to remote Ubuntu machines via SSH (*the default port of 22 was used*) and Ubuntu machines with ssh and curl installed:

- sudo apt install openssh-server -y
- sudo apt install curl -y

The machines should also be able to reach public repositories for the installation of tools like docker, containerd, kubectl, kubeadm, etc.

The ".cmd" files in the root directory can be used to initiate the execution of this script. The cmd scripts are named based on the functions they perform:

1. add_node.cmd: Adds nodes to a given configuration file, if specified as a parameter or in the default configuration file: config/ubuntu.json,  to an existing cluster.
2. install_cluster.cmd: creates a new cluster from nodes provided in a given configuration file, if specified as a parameter or  in the default configuration file: config/ubuntu.json,  to an existing cluster.
3. remove_node.cmd: Removes a nodes from a given configuration file, if specified as a parameter or in the default configuration file: config/ubuntu.json,  to an existing cluster.
4. show_masters.cmd: Lists master nodes configured by the tool.

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

It is best to take clones or snapshots of virtual nodes before running this tool against them so that they can always be reverted to their original state. *You are responsible for running commands against your machines*.