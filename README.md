# File Name Generator - Biotech Version

A Windows Forms-based PowerShell tool for generating consistent, standardized filenames for biotech experiments.

## Features

- **Automatic Name Builder**: Construct filenames from predefined fields
- **Biotech-Specific Fields**: Experiment type, TIC, Colony, Assay type, Block #, Rep #, and more
- **Live Preview**: See the generated filename in real-time as you fill in fields
- **Clipboard Integration**: Instantly copy generated filenames to clipboard
- **Smart Formatting**: Automatic sanitization and formatting of filename components
- **Dynamic Inputs**: "Other" option for custom entries on dropdown fields

## Field Structure

Filenames are automatically constructed using the following fields (separated by underscores):

1. **Experiment type** - MOA or custom entry
2. **Experimental TIC** - Treatment identification code
3. **Colony** - ECB, SWC, SBC, FAW, SBL, VBC, or custom
4. **Assay type** - 1 way (1w DIP), 2 way (2w DIP), or dose response (DosRes)
5. **Block #** - Automatically prefixed with "BL"
6. **Rep #** - Automatically prefixed with "rep"
7. **Control TIC 1-4** - Each automatically prefixed with "vs"
8. **Date** - YYYYMMDD format (defaults to current date)

## Usage

### Running the Application

**Option 1: Using the Batch File**
```
FileRenamer.bat
```

**Option 2: Direct PowerShell**
```powershell
powershell.exe -ExecutionPolicy Bypass -File "FileRenamer.ps1"
```

### Optional: Build a Single EXE (Isolated Subfolder)

To keep the original program unchanged while producing a single distributable EXE, use the isolated packaging flow:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\packaging\exe\build\Build-Exe.ps1"
```

See `packaging/exe/README.md` for details.

### Generating a Filename

1. Fill in the desired fields in the "Automatic Name Builder" section
2. Watch the preview update in real-time
3. Click "Generate Filename" to copy the name to your clipboard
4. Use "Clear Fields" to reset all inputs

### Example Output

With the following inputs:
- Experiment type: MOA
- Experimental TIC: ABC123
- Colony: ECB
- Assay type: 1 way
- Block #: 1
- Rep #: 2
- Control TIC 1: Control1
- Date: 20260220

Generated filename: `MOA_ABC123_ECB_1w-DIP_BL1_rep2_vsControl1_20260220`

## Requirements

- Windows operating system
- PowerShell 5.1 or higher
- .NET Framework (for Windows Forms)

## File Structure

```
biotech version/
├── FileRenamer.ps1      # Main PowerShell script
├── FileRenamer.bat      # Windows batch launcher
├── packaging/
│   └── exe/             # Optional isolated EXE packaging flow
│       ├── build/
│       │   ├── Build-Exe.ps1
│       │   └── FileRenamer.sed
│       ├── src/         # Auto-synced copy of FileRenamer.ps1 at build time
│       ├── out/         # Generated EXE output
│       └── README.md
├── lib/                 # External libraries (currently unused)
│   ├── BouncyCastle.Crypto.dll
│   └── itextsharp.dll
└── README.md           # This file
```

## Notes

- All filename components are automatically sanitized to be filesystem-safe
- Spaces are converted to hyphens
- Invalid filename characters are removed
- Multiple consecutive separators are collapsed
- The date field is pre-filled with today's date in YYYYMMDD format

## License

This project is provided as-is for internal use.
