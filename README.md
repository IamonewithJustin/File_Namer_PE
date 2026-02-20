# File_Namer_PE

Simple file naming utility for PE workflows.

## Requirements

- Windows with PowerShell 5.1+.
- Keep the `lib` folder next to the scripts with these files:
	- `lib/BouncyCastle.Crypto.dll`
	- `lib/itextsharp.dll`

## Run

Use either launcher from the project root:

- PowerShell:

	```powershell
	.\FileRenamer.ps1
	```

- Batch file:

	```bat
	FileRenamer.bat
	```

If PowerShell script execution is blocked, run this once in PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```