# AzQuickLog

For more information please see article on medium!

https://luketylerwilliams.medium.com/azquicklog-cda6040ded6b

## Prerequisites​:
```
PowerShell
```

## Getting Started 

```
git clone https://github.com/luketylerwilliams/AzQuickLog.git
cd AzQuickLog
./AzQuickLog.ps1
```

# Changelog
## v2
+ Improved error handling
+ Improved processing, added multi-threading using powershell jobs
+ Fixed storage account iteration through sub-levels (blob,table,queue,file)
## v1.2:
+ Improved error handling
+ Bug fix with management group scope
+ Bug fix, printing duplicate 

## v1.1:
+ Update to logic to fix some issues with error handling and scoping of functions
+ Added WhatIf functionality to provide an overview of actions which would take place
## v1
+ Release
