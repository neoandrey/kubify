@echo off
SET currentFolder=%~dp0
CD  %currentFolder%
SET  /p mainMaster=MainMasterNode:
SET  /p config=ConfigurationPath:
SET  /p resolve=useCustomResolvConf:

IF NOT DEFINED  resolve (
  SET resolve="$False"
)

IF DEFINED mainMaster ( 
    IF NOT DEFINED config (

        powershell -executionPolicy remotesigned -File .\run.ps1 -mode "install" -mainMasterNode  "%mainMaster%" -customResolve %resolve%

    ) ELSE (

        powershell -executionPolicy remotesigned -File .\run.ps1 -mode "install" -mainMasterNode  "%mainMaster%" -configPath "%config%"  -customResolve %resolve%
    )

)  ELSE (

   echo "You must specify a main master node"

)

pause