# Name_Gen

Contains both program variants in one branch with clear filenames.

## Variants

- PE: `FileRenamer_PE.ps1` and `FileRenamer_PE.bat`
- Biotech: `FileRenamer_Biotech.ps1` and `FileRenamer_Biotech.bat`

## Requirements

- Windows with PowerShell 5.1+.
- Keep the `lib` folder next to the scripts with these files:
  - `lib/BouncyCastle.Crypto.dll`
  - `lib/itextsharp.dll`

## Run

- PE version:

  ```bat
  FileRenamer_PE.bat
  ```

  or

  ```powershell
  .\FileRenamer_PE.ps1
  ```

- Biotech version:

  ```bat
  FileRenamer_Biotech.bat
  ```

  or

  ```powershell
  .\FileRenamer_Biotech.ps1
  ```

If PowerShell script execution is blocked, run this once in PowerShell:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
