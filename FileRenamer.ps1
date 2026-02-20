Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# FileRenamer.ps1
# Purpose:
#   Interactive Windows Forms tool to generate consistent filenames, rename
#   multiple files, optionally write metadata JSON, and update PDF footers.
#
# Key features:
#   - Two naming modes: auto-built from fields or manual name override.
#   - Optional metadata JSON output with user-provided fields.
#   - Optional PDF footer stamping (requires iTextSharp + BouncyCastle).
#
# How to use:
#   1) Select files (Browse) or generate a filename for clipboard only.
#   2) Fill fields or use manual name; preview updates live.
#   3) Rename files; optional metadata and PDF footer update.
# -----------------------------------------------------------------------------

# PDF Library Setup (iTextSharp) - Portable
$script:pdfLibPath = Join-Path $PSScriptRoot "lib"
$script:iTextSharpDll = Join-Path $script:pdfLibPath "itextsharp.dll"
$script:bouncyCastleDll = Join-Path $script:pdfLibPath "BouncyCastle.Crypto.dll"
$script:pdfLibLoaded = $false

function Install-iTextSharp {
    <#
    .SYNOPSIS
        Downloads and extracts iTextSharp and BouncyCastle DLLs if missing.
    .DESCRIPTION
        Uses NuGet package endpoints to download dependencies into the local
        lib folder. This keeps the script self-contained and portable.
    .OUTPUTS
        [bool] True when dependencies are present; otherwise False.
    #>
    if (-not (Test-Path $script:pdfLibPath)) {
        New-Item -ItemType Directory -Path $script:pdfLibPath -Force | Out-Null
    }
    
    # Download BouncyCastle dependency first
    if (-not (Test-Path $script:bouncyCastleDll)) {
        try {
            Write-Host "Downloading BouncyCastle dependency..."
            
            $nugetUrl = "https://www.nuget.org/api/v2/package/BouncyCastle/1.8.9"
            $zipPath = Join-Path $script:pdfLibPath "BouncyCastle.zip"
            
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $nugetUrl -OutFile $zipPath -UseBasicParsing
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            
            $dllEntry = $zip.Entries | Where-Object { $_.Name -eq "BouncyCastle.Crypto.dll" } | Select-Object -First 1
            
            if ($dllEntry) {
                Write-Host "Found BouncyCastle at: $($dllEntry.FullName)"
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($dllEntry, $script:bouncyCastleDll, $true)
                Write-Host "BouncyCastle installed successfully."
            }
            
            $zip.Dispose()
            Remove-Item $zipPath -Force
        } catch {
            Write-Warning "Failed to download BouncyCastle: $($_.Exception.Message)"
            return $false
        }
    }
    
    # Download iTextSharp
    if (-not (Test-Path $script:iTextSharpDll)) {
        try {
            Write-Host "Downloading iTextSharp library for first-time use..."
            
            # Download iTextSharp from NuGet
            $nugetUrl = "https://www.nuget.org/api/v2/package/iTextSharp/5.5.13.3"
            $zipPath = Join-Path $script:pdfLibPath "iTextSharp.zip"
            
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $nugetUrl -OutFile $zipPath -UseBasicParsing
            
            Write-Host "Download complete. Extracting..."
            
            # Extract DLL from NuGet package
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            
            # Find the DLL
            $dllEntry = $zip.Entries | Where-Object { 
                $_.Name -eq "itextsharp.dll"
            } | Select-Object -First 1
            
            if ($dllEntry) {
                Write-Host "Found DLL at: $($dllEntry.FullName)"
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($dllEntry, $script:iTextSharpDll, $true)
                Write-Host "iTextSharp library installed successfully to: $script:iTextSharpDll"
            } else {
                Write-Warning "Could not find itextsharp.dll in NuGet package"
            }
            
            $zip.Dispose()
            Remove-Item $zipPath -Force
            
            return (Test-Path $script:iTextSharpDll)
        } catch {
            Write-Warning "Failed to download iTextSharp: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

function Load-iTextSharp {
    <#
    .SYNOPSIS
        Loads iTextSharp and BouncyCastle into the current PowerShell session.
    .DESCRIPTION
        Ensures DLLs exist (Install-iTextSharp), unblocks them, then adds types.
    .OUTPUTS
        [bool] True when assemblies load successfully; otherwise False.
    #>
    if ($script:pdfLibLoaded) { return $true }
    
    if (Install-iTextSharp) {
        try {
            # Load BouncyCastle first (dependency)
            if (Test-Path $script:bouncyCastleDll) {
                Unblock-File -Path $script:bouncyCastleDll -ErrorAction SilentlyContinue
                Write-Host "Loading BouncyCastle dependency..."
                Add-Type -Path $script:bouncyCastleDll -ErrorAction Stop
            } else {
                Write-Warning "BouncyCastle dependency not found."
                return $false
            }
            
            # Load iTextSharp
            if (Test-Path $script:iTextSharpDll) {
                Unblock-File -Path $script:iTextSharpDll -ErrorAction SilentlyContinue
                Write-Host "Loading iTextSharp from: $script:iTextSharpDll"
                Add-Type -Path $script:iTextSharpDll -ErrorAction Stop
                $script:pdfLibLoaded = $true
                Write-Host "iTextSharp loaded successfully!"
                return $true
            } else {
                Write-Warning "iTextSharp DLL not found at: $script:iTextSharpDll"
                return $false
            }
        } catch {
            Write-Warning "Failed to load iTextSharp."
            Write-Warning "Error: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                Write-Warning "Inner Exception: $($_.Exception.InnerException.Message)"
            }
            if ($_.Exception.LoaderExceptions) {
                Write-Warning "Loader Exceptions:"
                $_.Exception.LoaderExceptions | ForEach-Object {
                    Write-Warning "  - $($_.Message)"
                }
            }
            return $false
        }
    }
    return $false
}

# -----------------------------------------------------------------------------
# UI Construction (Windows Forms)
# -----------------------------------------------------------------------------
# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'File Name Generator'
$form.Size = New-Object System.Drawing.Size(800, 950)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

# Create scrollable container panel for all controls
$scrollPanel = New-Object System.Windows.Forms.Panel
$scrollPanel.Location = New-Object System.Drawing.Point(0, 0)
$scrollPanel.Size = New-Object System.Drawing.Size($form.ClientSize.Width, $form.ClientSize.Height)
$scrollPanel.AutoScroll = $true
$form.Controls.Add($scrollPanel)

# Store selected files (full paths) to rename
$script:selectedFiles = @()

# Current Y position for controls
$yPos = 20

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object System.Drawing.Point(20, $yPos)
$lblTitle.Size = New-Object System.Drawing.Size(760, 30)
$lblTitle.Text = 'File Name Generator'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
$scrollPanel.Controls.Add($lblTitle)
$yPos += 40

# Instructions Panel (user guidance)
$panelInstructions = New-Object System.Windows.Forms.Panel
$panelInstructions.Location = New-Object System.Drawing.Point(20, $yPos)
$panelInstructions.Size = New-Object System.Drawing.Size(760, 90)
$panelInstructions.BorderStyle = 'FixedSingle'
$panelInstructions.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelInstructions)

$lblInstructionsTitle = New-Object System.Windows.Forms.Label
$lblInstructionsTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblInstructionsTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblInstructionsTitle.Text = 'Instructions'
$lblInstructionsTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelInstructions.Controls.Add($lblInstructionsTitle)

$lblInstructions = New-Object System.Windows.Forms.Label
$lblInstructions.Location = New-Object System.Drawing.Point(10, 25)
$lblInstructions.Size = New-Object System.Drawing.Size(740, 60)
$lblInstructions.Text = "1. Select multiple files to be renamed with identical names (extension will be maintained).`n2. Fill out fields to construct the file name (fields are separated by underscores) or use manual entry.`n3. Preview the resulting file name at the bottom before renaming."
$lblInstructions.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelInstructions.Controls.Add($lblInstructions)
$yPos += 100

# File Selection Panel (browse, clear, rename, preview)
$panelFiles = New-Object System.Windows.Forms.Panel
$panelFiles.Location = New-Object System.Drawing.Point(20, $yPos)
$panelFiles.Size = New-Object System.Drawing.Size(760, 300)
$panelFiles.BorderStyle = 'FixedSingle'
$panelFiles.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelFiles)

$lblFilesTitle = New-Object System.Windows.Forms.Label
$lblFilesTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblFilesTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblFilesTitle.Text = 'Select Files'
$lblFilesTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelFiles.Controls.Add($lblFilesTitle)

# Write Metadata Checkbox (JSON output)
$chkWriteMetadata = New-Object System.Windows.Forms.CheckBox
$chkWriteMetadata.Location = New-Object System.Drawing.Point(390, 30)
$chkWriteMetadata.Size = New-Object System.Drawing.Size(180, 18)
$chkWriteMetadata.Text = 'Write Metadata'
$chkWriteMetadata.Checked = $true
$chkWriteMetadata.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$chkWriteMetadata.ForeColor = [System.Drawing.Color]::FromArgb(76, 175, 80)
$panelFiles.Controls.Add($chkWriteMetadata)

# Update PDF Footer Checkbox (PDF stamping)
$chkUpdatePdfFooter = New-Object System.Windows.Forms.CheckBox
$chkUpdatePdfFooter.Location = New-Object System.Drawing.Point(390, 50)
$chkUpdatePdfFooter.Size = New-Object System.Drawing.Size(180, 20)
$chkUpdatePdfFooter.Text = 'Update PDF Footer'
$chkUpdatePdfFooter.Checked = $false
$chkUpdatePdfFooter.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$chkUpdatePdfFooter.ForeColor = [System.Drawing.Color]::FromArgb(66, 133, 244)
$panelFiles.Controls.Add($chkUpdatePdfFooter)

# Generate Filename button (builds name, copies to clipboard)
$btnGenerateFilename = New-Object System.Windows.Forms.Button
$btnGenerateFilename.Location = New-Object System.Drawing.Point(10, 30)
$btnGenerateFilename.Size = New-Object System.Drawing.Size(180, 40)
$btnGenerateFilename.Text = 'Generate Filename'
$btnGenerateFilename.BackColor = [System.Drawing.Color]::FromArgb(102, 187, 106)
$btnGenerateFilename.ForeColor = [System.Drawing.Color]::White
$btnGenerateFilename.FlatStyle = 'Flat'
$btnGenerateFilename.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnGenerateFilename.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnGenerateFilename)

# Browse button (select files)
$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Location = New-Object System.Drawing.Point(200, 30)
$btnBrowse.Size = New-Object System.Drawing.Size(180, 40)
$btnBrowse.Text = 'Browse and Select Files'
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(33, 150, 243)
$btnBrowse.ForeColor = [System.Drawing.Color]::White
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnBrowse)

# Clear button (remove selections)
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object System.Drawing.Point(10, 75)
$btnClear.Size = New-Object System.Drawing.Size(180, 40)
$btnClear.Text = 'Clear Files'
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(244, 67, 54)
$btnClear.ForeColor = [System.Drawing.Color]::White
$btnClear.FlatStyle = 'Flat'
$btnClear.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnClear.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnClear)

# Rename Button (apply rename + metadata + footer)
$btnRename = New-Object System.Windows.Forms.Button
$btnRename.Location = New-Object System.Drawing.Point(200, 75)
$btnRename.Size = New-Object System.Drawing.Size(180, 40)
$btnRename.Text = 'Rename Files'
$btnRename.BackColor = [System.Drawing.Color]::FromArgb(76, 175, 80)
$btnRename.ForeColor = [System.Drawing.Color]::White
$btnRename.FlatStyle = 'Flat'
$btnRename.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnRename.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnRename)

# Preview Panel (example file name)
$panelPreview = New-Object System.Windows.Forms.Panel
$panelPreview.Location = New-Object System.Drawing.Point(10, 120)
$panelPreview.Size = New-Object System.Drawing.Size(740, 40)
$panelPreview.BorderStyle = 'FixedSingle'
$panelPreview.BackColor = [System.Drawing.Color]::FromArgb(227, 242, 253)
$panelFiles.Controls.Add($panelPreview)

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Location = New-Object System.Drawing.Point(10, 10)
$lblPreview.Size = New-Object System.Drawing.Size(720, 20)
$lblPreview.Text = 'Preview: <no name>.ext'
$lblPreview.Font = New-Object System.Drawing.Font('Consolas', 10)
$lblPreview.ForeColor = [System.Drawing.Color]::FromArgb(13, 71, 161)
$panelPreview.Controls.Add($lblPreview)

# File list box (shows selected files)
$lstFiles = New-Object System.Windows.Forms.ListBox
$lstFiles.Location = New-Object System.Drawing.Point(10, 165)
$lstFiles.Size = New-Object System.Drawing.Size(740, 105)
$lstFiles.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lstFiles.Visible = $false
$panelFiles.Controls.Add($lstFiles)
$yPos += 250

# Naming Mode Panel (auto fields vs manual)
$panelMode = New-Object System.Windows.Forms.Panel
$panelMode.Location = New-Object System.Drawing.Point(20, $yPos)
$panelMode.Size = New-Object System.Drawing.Size(760, 50)
$panelMode.BorderStyle = 'FixedSingle'
$panelMode.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelMode)

$lblModeTitle = New-Object System.Windows.Forms.Label
$lblModeTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblModeTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblModeTitle.Text = 'Naming Mode'
$lblModeTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelMode.Controls.Add($lblModeTitle)

$radioFields = New-Object System.Windows.Forms.RadioButton
$radioFields.Location = New-Object System.Drawing.Point(20, 25)
$radioFields.Size = New-Object System.Drawing.Size(100, 20)
$radioFields.Text = 'Fields'
$radioFields.Checked = $true
$radioFields.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMode.Controls.Add($radioFields)

$radioManual = New-Object System.Windows.Forms.RadioButton
$radioManual.Location = New-Object System.Drawing.Point(130, 25)
$radioManual.Size = New-Object System.Drawing.Size(150, 20)
$radioManual.Text = 'Manual file name'
$radioManual.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMode.Controls.Add($radioManual)
$yPos += 60

# Fields Panel (automatic name builder inputs)
$panelFieldsSection = New-Object System.Windows.Forms.Panel
$panelFieldsSection.Location = New-Object System.Drawing.Point(20, $yPos)
$panelFieldsSection.Size = New-Object System.Drawing.Size(760, 260)
$panelFieldsSection.BorderStyle = 'FixedSingle'
$panelFieldsSection.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelFieldsSection)

$lblFieldsTitle = New-Object System.Windows.Forms.Label
$lblFieldsTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblFieldsTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblFieldsTitle.Text = 'Automatic Name Builder'
$lblFieldsTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelFieldsSection.Controls.Add($lblFieldsTitle)

# Create field controls
$fieldY = 30
$fields = @(
    @{ Label = 'LIMS plate ID:'; Name = 'limsPlateId' },
    @{ Label = 'Date (YYYYMMDD):'; Name = 'dateField' },
    @{ Label = 'CWID:'; Name = 'field1' },
    @{ Label = 'Crop:'; Name = 'field2' },
    @{ Label = 'Protein:'; Name = 'field3' },
    @{ Label = 'Tissue:'; Name = 'field4' },
    @{ Label = 'Entry:'; Name = 'entryField' },
    @{ Label = 'Experiment:'; Name = 'field5' },
    @{ Label = 'Other:'; Name = 'field6' }
)

$script:fieldControls = @{}

foreach ($field in $fields) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Location = New-Object System.Drawing.Point(20, $fieldY)
    $lbl.Size = New-Object System.Drawing.Size(140, 20)
    $lbl.Text = $field.Label
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $panelFieldsSection.Controls.Add($lbl)
    
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(170, $fieldY)
    $txt.Size = New-Object System.Drawing.Size(570, 20)
    $txt.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    
    if ($field.Name -eq 'dateField') {
        $txt.MaxLength = 8
        # Set today's date
        $today = Get-Date
        $txt.Text = $today.ToString('yyyyMMdd')
    }
    
    $panelFieldsSection.Controls.Add($txt)
    $script:fieldControls[$field.Name] = $txt
    
    $fieldY += 25
}
$yPos += 270

# Metadata-Only Fields Panel (not used in filename)
$panelMetadata = New-Object System.Windows.Forms.Panel
$panelMetadata.Location = New-Object System.Drawing.Point(20, $yPos)
$panelMetadata.Size = New-Object System.Drawing.Size(760, 345)
$panelMetadata.BorderStyle = 'FixedSingle'
$panelMetadata.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelMetadata)

$lblMetadataTitle = New-Object System.Windows.Forms.Label
$lblMetadataTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblMetadataTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblMetadataTitle.Text = 'Metadata Only (Not used for file naming)'
$lblMetadataTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelMetadata.Controls.Add($lblMetadataTitle)

# Assay Type Dropdown
$lblAssayType = New-Object System.Windows.Forms.Label
$lblAssayType.Location = New-Object System.Drawing.Point(20, 30)
$lblAssayType.Size = New-Object System.Drawing.Size(160, 20)
$lblAssayType.Text = 'Assay Type:'
$lblAssayType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblAssayType)

$cmbAssayType = New-Object System.Windows.Forms.ComboBox
$cmbAssayType.Location = New-Object System.Drawing.Point(190, 30)
$cmbAssayType.Size = New-Object System.Drawing.Size(550, 20)
$cmbAssayType.DropDownStyle = 'DropDownList'
$cmbAssayType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbAssayType.Items.AddRange(@('', 'ELISA', 'Luminex', 'Western', 'Other'))
$cmbAssayType.SelectedIndex = 0
$panelMetadata.Controls.Add($cmbAssayType)

# GLP Dropdown
$lblGLP = New-Object System.Windows.Forms.Label
$lblGLP.Location = New-Object System.Drawing.Point(20, 60)
$lblGLP.Size = New-Object System.Drawing.Size(160, 20)
$lblGLP.Text = 'GLP?:'
$lblGLP.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblGLP)

$cmbGLP = New-Object System.Windows.Forms.ComboBox
$cmbGLP.Location = New-Object System.Drawing.Point(190, 60)
$cmbGLP.Size = New-Object System.Drawing.Size(550, 20)
$cmbGLP.DropDownStyle = 'DropDownList'
$cmbGLP.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbGLP.Items.AddRange(@('', 'YES', 'NO'))
$cmbGLP.SelectedIndex = 0
$panelMetadata.Controls.Add($cmbGLP)

# Experimental Purpose
$lblExpPurpose = New-Object System.Windows.Forms.Label
$lblExpPurpose.Location = New-Object System.Drawing.Point(20, 90)
$lblExpPurpose.Size = New-Object System.Drawing.Size(160, 20)
$lblExpPurpose.Text = 'Experimental Purpose:'
$lblExpPurpose.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblExpPurpose)

$txtExpPurpose = New-Object System.Windows.Forms.TextBox
$txtExpPurpose.Location = New-Object System.Drawing.Point(190, 90)
$txtExpPurpose.Size = New-Object System.Drawing.Size(550, 40)
$txtExpPurpose.Multiline = $true
$txtExpPurpose.ScrollBars = 'Vertical'
$txtExpPurpose.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtExpPurpose)

# ELN ID
$lblElnId = New-Object System.Windows.Forms.Label
$lblElnId.Location = New-Object System.Drawing.Point(20, 135)
$lblElnId.Size = New-Object System.Drawing.Size(160, 20)
$lblElnId.Text = 'ELN ID:'
$lblElnId.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblElnId)

$txtElnId = New-Object System.Windows.Forms.TextBox
$txtElnId.Location = New-Object System.Drawing.Point(190, 135)
$txtElnId.Size = New-Object System.Drawing.Size(550, 40)
$txtElnId.Multiline = $true
$txtElnId.ScrollBars = 'Vertical'
$txtElnId.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtElnId)

# Antibody 1
$lblAntibody1 = New-Object System.Windows.Forms.Label
$lblAntibody1.Location = New-Object System.Drawing.Point(20, 180)
$lblAntibody1.Size = New-Object System.Drawing.Size(160, 20)
$lblAntibody1.Text = 'Antibody 1:'
$lblAntibody1.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblAntibody1)

$txtAntibody1 = New-Object System.Windows.Forms.TextBox
$txtAntibody1.Location = New-Object System.Drawing.Point(190, 180)
$txtAntibody1.Size = New-Object System.Drawing.Size(550, 40)
$txtAntibody1.Multiline = $true
$txtAntibody1.ScrollBars = 'Vertical'
$txtAntibody1.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtAntibody1)

# Antibody 2
$lblAntibody2 = New-Object System.Windows.Forms.Label
$lblAntibody2.Location = New-Object System.Drawing.Point(20, 225)
$lblAntibody2.Size = New-Object System.Drawing.Size(160, 20)
$lblAntibody2.Text = 'Antibody 2:'
$lblAntibody2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblAntibody2)

$txtAntibody2 = New-Object System.Windows.Forms.TextBox
$txtAntibody2.Location = New-Object System.Drawing.Point(190, 225)
$txtAntibody2.Size = New-Object System.Drawing.Size(550, 40)
$txtAntibody2.Multiline = $true
$txtAntibody2.ScrollBars = 'Vertical'
$txtAntibody2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtAntibody2)

# Additional Experimental Information 1
$lblAddInfo1 = New-Object System.Windows.Forms.Label
$lblAddInfo1.Location = New-Object System.Drawing.Point(20, 270)
$lblAddInfo1.Size = New-Object System.Drawing.Size(160, 30)
$lblAddInfo1.Text = 'Additional Experimental Information 1:'
$lblAddInfo1.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblAddInfo1)

$txtAddInfo1 = New-Object System.Windows.Forms.TextBox
$txtAddInfo1.Location = New-Object System.Drawing.Point(190, 270)
$txtAddInfo1.Size = New-Object System.Drawing.Size(550, 40)
$txtAddInfo1.Multiline = $true
$txtAddInfo1.ScrollBars = 'Vertical'
$txtAddInfo1.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtAddInfo1)

# Additional Experimental Information 2
$lblAddInfo2 = New-Object System.Windows.Forms.Label
$lblAddInfo2.Location = New-Object System.Drawing.Point(20, 315)
$lblAddInfo2.Size = New-Object System.Drawing.Size(160, 30)
$lblAddInfo2.Text = 'Additional Experimental Information 2:'
$lblAddInfo2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($lblAddInfo2)

$txtAddInfo2 = New-Object System.Windows.Forms.TextBox
$txtAddInfo2.Location = New-Object System.Drawing.Point(190, 315)
$txtAddInfo2.Size = New-Object System.Drawing.Size(550, 40)
$txtAddInfo2.Multiline = $true
$txtAddInfo2.ScrollBars = 'Vertical'
$txtAddInfo2.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelMetadata.Controls.Add($txtAddInfo2)
$yPos += 355

# Manual Panel (positioned at same location as fields panel)
$manualPanelY = $yPos - 595
$panelManual = New-Object System.Windows.Forms.Panel
$panelManual.Location = New-Object System.Drawing.Point(20, $manualPanelY)
$panelManual.Size = New-Object System.Drawing.Size(760, 70)
$panelManual.BorderStyle = 'FixedSingle'
$panelManual.BackColor = [System.Drawing.Color]::White
$panelManual.Visible = $false
$scrollPanel.Controls.Add($panelManual)

$lblManualTitle = New-Object System.Windows.Forms.Label
$lblManualTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblManualTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblManualTitle.Text = 'Manual Name Override'
$lblManualTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelManual.Controls.Add($lblManualTitle)

$lblManualName = New-Object System.Windows.Forms.Label
$lblManualName.Location = New-Object System.Drawing.Point(20, 35)
$lblManualName.Size = New-Object System.Drawing.Size(200, 20)
$lblManualName.Text = 'Full file name (no extension):'
$lblManualName.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelManual.Controls.Add($lblManualName)

$txtManual = New-Object System.Windows.Forms.TextBox
$txtManual.Location = New-Object System.Drawing.Point(230, 35)
$txtManual.Size = New-Object System.Drawing.Size(510, 20)
$txtManual.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelManual.Controls.Add($txtManual)

# Status Bar (single-line feedback)
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStatus.Size = New-Object System.Drawing.Size(760, 30)
$lblStatus.Text = 'Ready. Click Browse to select files.'
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lblStatus.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$scrollPanel.Controls.Add($lblStatus)

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------
function Write-MetadataFile {
    <#
    .SYNOPSIS
        Writes a JSON metadata file alongside the renamed file.
    .DESCRIPTION
        Collects values from the UI fields and writes a *.metadata.json file.
        Can be called with a file path (actual file) or output folder.
    .PARAMETER filePath
        Full path to the renamed file (used for directory and file name).
    .PARAMETER baseName
        Base filename (no extension) used when filePath not provided.
    .PARAMETER previousFileNames
        List of original filenames for traceability.
    .PARAMETER outputFolder
        Folder for JSON output when no filePath is provided.
    .PARAMETER displayFileName
        Display name written into the metadata (optional).
    .OUTPUTS
        [bool] True when metadata is written; otherwise False.
    #>
    param(
        [string]$filePath,
        [string]$baseName,
        [array]$previousFileNames,
        [string]$outputFolder,
        [string]$displayFileName
    )
    
    try {
        $folder = $null
        $fileNameForMetadata = $null
        
        if ($filePath) {
            $file = Get-Item -LiteralPath $filePath
            $folder = $file.DirectoryName
            $fileNameForMetadata = $file.Name
        } elseif ($outputFolder) {
            $folder = $outputFolder
        } else {
            $folder = $PSScriptRoot
        }
        
        if (-not $fileNameForMetadata) {
            if ($displayFileName) {
                $fileNameForMetadata = $displayFileName
            } else {
                $fileNameForMetadata = $baseName
            }
        }
        
        # Build metadata object
        $metadata = [ordered]@{
            'FileName' = $fileNameForMetadata
            'DateRenamed' = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            'PreviousNames' = $previousFileNames
            'Fields' = [ordered]@{}
        }
        
        # Add LIMS plate ID
        $limsPlateIdVal = $script:fieldControls['limsPlateId'].Text.Trim()
        if ($limsPlateIdVal) {
            $metadata.Fields['LIMS_plate_ID'] = $limsPlateIdVal
        }
        
        # Add date field
        $dateVal = $script:fieldControls['dateField'].Text.Trim()
        if ($dateVal) {
            $metadata.Fields['Date'] = $dateVal
        }
        
        # Add CWID
        $cwidVal = $script:fieldControls['field1'].Text.Trim()
        if ($cwidVal) {
            $metadata.Fields['CWID'] = $cwidVal
        }
        
        # Add Crop
        $cropVal = $script:fieldControls['field2'].Text.Trim()
        if ($cropVal) {
            $metadata.Fields['Crop'] = $cropVal
        }
        
        # Add Protein
        $proteinVal = $script:fieldControls['field3'].Text.Trim()
        if ($proteinVal) {
            $metadata.Fields['Protein'] = $proteinVal
        }
        
        # Add Tissue
        $tissueVal = $script:fieldControls['field4'].Text.Trim()
        if ($tissueVal) {
            $metadata.Fields['Tissue'] = $tissueVal
        }
        
        # Add Entry
        $entryVal = $script:fieldControls['entryField'].Text.Trim()
        if ($entryVal) {
            $metadata.Fields['Entry'] = $entryVal
        }
        
        # Add Experiment
        $expVal = $script:fieldControls['field5'].Text.Trim()
        if ($expVal) {
            $metadata.Fields['Experiment'] = $expVal
        }
        
        # Add Other
        $otherVal = $script:fieldControls['field6'].Text.Trim()
        if ($otherVal) {
            $metadata.Fields['Other'] = $otherVal
        }
        
        # Add metadata-only fields
        $assayType = $cmbAssayType.SelectedItem
        if ($assayType -and $assayType -ne '') {
            $metadata['AssayType'] = $assayType
        }
        
        $glp = $cmbGLP.SelectedItem
        if ($glp -and $glp -ne '') {
            $metadata['GLP'] = $glp
        }
        
        $expPurpose = $txtExpPurpose.Text.Trim()
        if ($expPurpose) {
            $metadata['ExperimentalPurpose'] = $expPurpose
        }
        
        $addInfo1 = $txtAddInfo1.Text.Trim()
        if ($addInfo1) {
            $metadata['AdditionalExperimentalInformation1'] = $addInfo1
        }
        
        $addInfo2 = $txtAddInfo2.Text.Trim()
        if ($addInfo2) {
            $metadata['AdditionalExperimentalInformation2'] = $addInfo2
        }
        
        $elnId = $txtElnId.Text.Trim()
        if ($elnId) {
            $metadata['ELN_ID'] = $elnId
        }
        
        $antibody1 = $txtAntibody1.Text.Trim()
        if ($antibody1) {
            $metadata['Antibody1'] = $antibody1
        }
        
        $antibody2 = $txtAntibody2.Text.Trim()
        if ($antibody2) {
            $metadata['Antibody2'] = $antibody2
        }
        
        # Write JSON file
        $metadataFileName = "$baseName.metadata.json"
        $metadataPath = Join-Path $folder $metadataFileName
        
        $jsonContent = $metadata | ConvertTo-Json -Depth 10
        $jsonContent | Out-File -FilePath $metadataPath -Encoding UTF8 -Force
        
        return $true
    } catch {
        Write-Error "Failed to write metadata for $filePath : $($_.Exception.Message)"
        return $false
    }
}

function Update-PdfFooter {
    <#
    .SYNOPSIS
        Adds a footer and page header to a PDF file.
    .DESCRIPTION
        Uses iTextSharp to stamp each page with:
        - Original filename (left footer)
        - Renamed-by info + date (right footer)
        - Page header (top-right, "Page: X of X")
    .PARAMETER pdfPath
        Full path to the PDF to update.
    .PARAMETER originalFileName
        Original filename without extension (for reference).
    .PARAMETER cwid
        User CWID used in the footer heading.
    .OUTPUTS
        [bool] True on success; otherwise False.
    #>
    param(
        [string]$pdfPath,
        [string]$originalFileName,
        [string]$cwid
    )
    
    if (-not (Load-iTextSharp)) {
        Write-Warning "iTextSharp library not available. Skipping PDF footer update."
        return $false
    }
    
    try {
        # Check if file is PDF
        $ext = [System.IO.Path]::GetExtension($pdfPath).ToLower()
        if ($ext -ne '.pdf') {
            return $false
        }
        
        # Get new filename (without extension)
        $newFileName = [System.IO.Path]::GetFileNameWithoutExtension($pdfPath)
        
        # Setup temp output file
        $tempPath = [System.IO.Path]::ChangeExtension($pdfPath, ".temp.pdf")
        
        # Open existing PDF and create stamper
        $reader = New-Object iTextSharp.text.pdf.PdfReader($pdfPath)
        $stream = New-Object System.IO.FileStream($tempPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $stamper = New-Object iTextSharp.text.pdf.PdfStamper($reader, $stream)
        
        # Font setup
        $baseFont = [iTextSharp.text.pdf.BaseFont]::CreateFont([iTextSharp.text.pdf.BaseFont]::HELVETICA, `
            [iTextSharp.text.pdf.BaseFont]::WINANSI, $false)
        $fontSize = 8
        
        # Add footer to each page
        $pageCount = $reader.NumberOfPages
        for ($pageNumber = 1; $pageNumber -le $pageCount; $pageNumber++) {
            $content = $stamper.GetOverContent($pageNumber)
            $pageSize = $reader.GetPageSize($pageNumber)
            $pageWidth = $pageSize.Width
            $pageHeight = $pageSize.Height

            # Top-right header: Page: X of X
            $pageHeaderText = "Page: $pageNumber of $pageCount"
            $pageHeaderWidth = $baseFont.GetWidthPoint($pageHeaderText, $fontSize)
            $content.BeginText()
            $content.SetFontAndSize($baseFont, $fontSize)
            $content.SetColorFill([iTextSharp.text.BaseColor]::BLACK)
            $content.SetTextMatrix($pageWidth - $pageHeaderWidth - 40, $pageHeight - 20)
            $content.ShowText($pageHeaderText)
            $content.EndText()
            
            # Position at bottom
            $footerY = 10
            
            # Cover the right side to remove page numbers and any previous "Renamed to:" text
            # This ensures multiple renames work correctly by clearing previous rename info
            # Reduce width by 33% and keep right-aligned
            $content.SetColorFill([iTextSharp.text.BaseColor]::WHITE)
            $coverWidth = [math]::Round(300 * 0.67)
            $coverX = $pageWidth - $coverWidth
            $content.Rectangle($coverX, 0, $coverWidth, 40)
            $content.Fill()
            
            # Left side above footer: Add "Machine File Name:" label
            # Moved up 0.165 inches (12 pixels) from original position
            $originalLabel = "Original File Name:"
            $content.BeginText()
            $content.SetFontAndSize($baseFont, $fontSize)
            $content.SetColorFill([iTextSharp.text.BaseColor]::BLACK)
            $content.SetTextMatrix(40, $footerY + 24)
            $content.ShowText($originalLabel)
            $content.EndText()
            
            # Right side: Add "Renamed by: <CWID>; on YYYYMMDD." heading with current date
            $currentDate = (Get-Date).ToString('yyyyMMdd')
            $safeCwid = if ($cwid) { $cwid } else { "" }
            $renamedToText = "Renamed by: $safeCwid; on $currentDate."
            $renamedToWidth = $baseFont.GetWidthPoint($renamedToText, $fontSize)
            $content.BeginText()
            $content.SetFontAndSize($baseFont, $fontSize)
            $content.SetColorFill([iTextSharp.text.BaseColor]::BLACK)
            $content.SetTextMatrix($pageWidth - $renamedToWidth - 40, $footerY + 12)
            $content.ShowText($renamedToText)
            $content.EndText()
            
            # Right side: New filename below "Renamed to:" heading
            $newFileText = "$newFileName.pdf"
            $newFileWidth = $baseFont.GetWidthPoint($newFileText, $fontSize)
            $content.BeginText()
            $content.SetFontAndSize($baseFont, $fontSize)
            $content.SetColorFill([iTextSharp.text.BaseColor]::BLACK)
            $content.SetTextMatrix($pageWidth - $newFileWidth - 40, $footerY - 4)
            $content.ShowText($newFileText)
            $content.EndText()
        }
        
        # Close and save
        $stamper.Close()
        $reader.Close()
        $stream.Close()
        
        # Replace original file with updated version
        Move-Item -Path $tempPath -Destination $pdfPath -Force
        
        return $true
    } catch {
        Write-Warning "Failed to update PDF footer for $pdfPath : $($_.Exception.Message)"
        # Clean up temp file if it exists
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

function Sanitize-FileName {
    <#
    .SYNOPSIS
        Cleans user text to a filesystem-safe filename component.
    .DESCRIPTION
        Converts whitespace to hyphens, removes invalid characters,
        collapses repeated separators, and trims leading/trailing symbols.
    #>
    param(
        [string]$name
    )
    if (-not $name) { return '' }
    $safe = $name -replace '\s+', '-'
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($ch in $invalidChars) {
        $safe = $safe.Replace([string]$ch, '')
    }
    $safe = $safe -replace '[^A-Za-z0-9_-]', ''
    $safe = $safe -replace '-{2,}', '-'
    $safe = $safe -replace '_{2,}', '_'
    $safe = $safe.Trim('-', '_')
    return $safe
}

function Build-BaseName {
    <#
    .SYNOPSIS
        Builds the base filename from UI fields or manual input.
    .DESCRIPTION
        Validates date format when required and assembles parts with
        underscores. Returns both name and error message.
    .PARAMETER Validate
        When set, returns an error message if required inputs are invalid.
    .OUTPUTS
        Hashtable with Name and Error keys.
    #>
    param(
        [switch]$Validate
    )
    $baseName = ''
    $errorMessage = $null
    
    if ($radioManual.Checked) {
        $baseName = Sanitize-FileName ($txtManual.Text.Trim())
        if ($Validate -and -not $baseName) {
            $errorMessage = 'Please enter a manual file name before renaming.'
        }
    } else {
        $dateVal = $script:fieldControls['dateField'].Text.Trim()
        if ($Validate) {
            if (-not $dateVal) {
                $errorMessage = 'Please provide the date in YYYYMMDD format.'
            } elseif ($dateVal.Length -ne 8 -or $dateVal -notmatch '^\d+$') {
                $errorMessage = 'Date must be in YYYYMMDD format (8 digits only).'
            }
        }
        if (-not $errorMessage) {
            $parts = @()
            $limsPlateIdVal = $script:fieldControls['limsPlateId'].Text.Trim()
            if ($limsPlateIdVal) {
                $safeVal = Sanitize-FileName $limsPlateIdVal
                if ($safeVal) { $parts += $safeVal }
            }
            if ($dateVal) { $parts += $dateVal }
            $val = $script:fieldControls['field1'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            $val = $script:fieldControls['field2'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            $val = $script:fieldControls['field3'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            $val = $script:fieldControls['field4'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            $entryVal = $script:fieldControls['entryField'].Text.Trim()
            if ($entryVal) {
                $safeVal = Sanitize-FileName $entryVal
                if ($safeVal) { $parts += $safeVal }
            }
            $val = $script:fieldControls['field5'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            $val = $script:fieldControls['field6'].Text.Trim()
            if ($val) {
                $safeVal = Sanitize-FileName $val
                if ($safeVal) { $parts += $safeVal }
            }
            if ($parts.Count -eq 0) {
                if ($Validate) {
                    $errorMessage = 'Please provide at least one field value.'
                }
            } else {
                $baseName = $parts -join '_'
                $baseName = Sanitize-FileName $baseName
            }
        }
    }
    return @{ Name = $baseName; Error = $errorMessage }
}

function Update-Preview {
    <#
    .SYNOPSIS
        Updates the preview label with the current filename.
    .DESCRIPTION
        Calls Build-BaseName without validation and updates UI text.
    #>
    $preview = '<no name>'
    $result = Build-BaseName
    if ($result.Name) {
        $preview = $result.Name
    }
    $lblPreview.Text = "Preview: $preview.ext"
}

function Toggle-Mode {
    <#
    .SYNOPSIS
        Toggles between automatic fields and manual filename mode.
    .DESCRIPTION
        Shows/hides relevant panels and enables/disables inputs.
    #>
    if ($radioFields.Checked) {
        $panelFieldsSection.Visible = $true
        $panelManual.Visible = $false
        foreach ($key in $script:fieldControls.Keys) {
            $script:fieldControls[$key].Enabled = $true
        }
        $txtManual.Enabled = $false
    } else {
        $panelFieldsSection.Visible = $false
        $panelManual.Visible = $true
        foreach ($key in $script:fieldControls.Keys) {
            if ($key -ne 'dateField') {
                $script:fieldControls[$key].Enabled = $false
            }
        }
        $txtManual.Enabled = $true
    }
    Update-Preview
}

# -----------------------------------------------------------------------------
# Event Handlers (UI actions)
# -----------------------------------------------------------------------------
$btnBrowse.Add_Click({
    # Open file picker and add unique selections to the list
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Multiselect = $true
    $openFileDialog.Filter = 'All Files (*.*)|*.*'
    $openFileDialog.Title = 'Select files to rename'
    
    if ($openFileDialog.ShowDialog() -eq 'OK') {
        $addedCount = 0
        foreach ($file in $openFileDialog.FileNames) {
            if ($script:selectedFiles -notcontains $file) {
                $script:selectedFiles += $file
                $addedCount++
            }
        }
        
        $lstFiles.Items.Clear()
        foreach ($file in $script:selectedFiles) {
            $lstFiles.Items.Add($file) | Out-Null
        }
        
        if ($script:selectedFiles.Count -gt 0) {
            $lstFiles.Visible = $true
            # Dynamically expand listbox height based on number of files (approximately 20px per item)
            $itemHeight = 20
            $maxHeight = 200
            $calculatedHeight = [Math]::Min($script:selectedFiles.Count * $itemHeight, $maxHeight)
            $lstFiles.Size = New-Object System.Drawing.Size(740, $calculatedHeight)
        }
        
        if ($addedCount -gt 0) {
            $lblStatus.Text = "Added $addedCount file(s). Total: $($script:selectedFiles.Count) file(s)."
        } else {
            $lblStatus.Text = "No new files added. Total: $($script:selectedFiles.Count) file(s)."
        }
    }
})

$btnClear.Add_Click({
    # Clear file selection and reset UI
    $script:selectedFiles = @()
    $lstFiles.Items.Clear()
    $lstFiles.Visible = $false
    $lblStatus.Text = 'File list cleared.'
})

$btnGenerateFilename.Add_Click({
    # Validate, build filename, and copy to clipboard
    $result = Build-BaseName -Validate
    if ($result.Error) {
        [System.Windows.Forms.MessageBox]::Show($result.Error, 'Missing Info', 'OK', 'Warning')
        return
    }
    $baseName = $result.Name
    if (-not $baseName) {
        [System.Windows.Forms.MessageBox]::Show('Please provide values to generate a file name.', 'No Name', 'OK', 'Warning')
        return
    }
    
    [System.Windows.Forms.Clipboard]::SetText($baseName)
    
    $metadataNotice = $null
    if ($chkWriteMetadata.Checked) {
        # Optionally write a metadata JSON (use output folder from selected files)
        $previousFileNames = @()
        $outputFolder = $null
        if ($script:selectedFiles.Count -gt 0) {
            foreach ($filePath in $script:selectedFiles) {
                try {
                    $file = Get-Item -LiteralPath $filePath
                    $previousFileNames += $file.Name
                    if (-not $outputFolder) { $outputFolder = $file.DirectoryName }
                } catch {
                    # Skip unreadable files
                }
            }
        }
        if (-not $outputFolder) {
            $outputFolder = $PSScriptRoot
        }
        $metadataWritten = Write-MetadataFile -baseName $baseName -previousFileNames $previousFileNames -outputFolder $outputFolder -displayFileName $baseName
        if ($metadataWritten) {
            $metadataNotice = "Metadata written to $outputFolder."
        } else {
            $metadataNotice = 'Metadata write failed.'
        }
    }
    
    $happyMessages = @(
        'Nice work!',
        'All set!',
        'Filename ready. Great job!',
        'You are awesome!',
        'Done!'
    )
    $happyMessage = Get-Random -InputObject $happyMessages
    $finalMessage = "Filename copied to clipboard.`n$happyMessage"
    if ($metadataNotice) {
        $finalMessage = "$finalMessage $metadataNotice"
    }
    $lblStatus.Text = $finalMessage
    [System.Windows.Forms.MessageBox]::Show($finalMessage, 'Copied', 'OK', 'Information')
})

$radioFields.Add_CheckedChanged({ Toggle-Mode })
$radioManual.Add_CheckedChanged({ Toggle-Mode })

foreach ($key in $script:fieldControls.Keys) {
    $script:fieldControls[$key].Add_TextChanged({ Update-Preview })
}
$txtManual.Add_TextChanged({ Update-Preview })

$btnRename.Add_Click({
    # Rename selected files and optionally write metadata / update PDF footer
    if ($script:selectedFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Please select one or more files to rename.', 'No Files', 'OK', 'Warning')
        return
    }
    
    # Build base name
    $result = Build-BaseName -Validate
    if ($result.Error) {
        [System.Windows.Forms.MessageBox]::Show($result.Error, 'Invalid Name', 'OK', 'Warning')
        return
    }
    $baseName = $result.Name
    if (-not $baseName) {
        [System.Windows.Forms.MessageBox]::Show('Please provide at least one field value.', 'No Values', 'OK', 'Warning')
        return
    }
    
    # Collect all original filenames before renaming (for metadata)
    $previousFileNames = @()
    foreach ($filePath in $script:selectedFiles) {
        try {
            $file = Get-Item -LiteralPath $filePath
            $previousFileNames += $file.Name
        } catch {
            # If we can't get the file, skip it
        }
    }
    
    # Rename files
    $successes = @()
    $failures = @()
    $metadataWritten = $false
    
    foreach ($filePath in $script:selectedFiles) {
        try {
            $file = Get-Item -LiteralPath $filePath
            $folder = $file.DirectoryName
            $extension = $file.Extension
            
            # Find unique name (avoid overwrite by adding a counter)
            $counter = 0
            $targetPath = Join-Path $folder "$baseName$extension"
            
            while (Test-Path $targetPath) {
                $counter++
                $targetPath = Join-Path $folder "${baseName}_${counter}${extension}"
            }
            
            Rename-Item -LiteralPath $filePath -NewName (Split-Path $targetPath -Leaf) -ErrorAction Stop
            
            # Write metadata only once (for the first file) if checkbox is checked
            if ($chkWriteMetadata.Checked -and -not $metadataWritten) {
                Write-MetadataFile -filePath $targetPath -baseName $baseName -previousFileNames $previousFileNames
                $metadataWritten = $true
            }
            
            # Update PDF footer if checkbox is checked
            if ($chkUpdatePdfFooter.Checked) {
                $originalFileName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $cwid = $script:fieldControls['field1'].Text.Trim()
                Update-PdfFooter -pdfPath $targetPath -originalFileName $originalFileName -cwid $cwid
            }
            
            $successes += $targetPath
        } catch {
            $failures += "$filePath : $($_.Exception.Message)"
        }
    }
    
    if ($successes.Count -gt 0) {
        $lblStatus.Text = "Successfully renamed $($successes.Count) file(s)."
        [System.Windows.Forms.MessageBox]::Show("All file names have been successfully changed.`nCheers!", 'Success', 'OK', 'Information')
    }
    
    if ($failures.Count -gt 0) {
        $errorMsg = "Rename errors:`n`n" + ($failures -join "`n")
        [System.Windows.Forms.MessageBox]::Show($errorMsg, 'Errors', 'OK', 'Error')
    }
})

# -----------------------------------------------------------------------------
# Show form (entry point)
# -----------------------------------------------------------------------------
Update-Preview
[void]$form.ShowDialog()
