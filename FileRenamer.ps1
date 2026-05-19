Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------------
# FileRenamer.ps1 - Biotech Version
# Purpose:
#   Interactive Windows Forms tool to generate consistent filenames and rename
#   multiple files for biotech experiments.
#
# Key features:
#   - Two naming modes: auto-built from fields or manual name override.
#   - Specialized fields for biotech experiments (MOA, Colony, TIC, etc.)
#   - Automatic prefixing for Block # (BL#) and Rep # (rep#)
#   - Dynamic "other" text inputs for dropdown selections
#
# How to use:
#   1) Select files (Browse) or generate a filename for clipboard only.
#   2) Fill fields or use manual name; preview updates live.
#   3) Rename files.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# UI Construction (Windows Forms)
# -----------------------------------------------------------------------------
# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'File Name Generator - Biotech Version'
$form.Size = New-Object System.Drawing.Size(800, 863) # increased 15% to reveal full fields area
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
$lblTitle.Text = 'File Name Generator - Biotech Version'
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
# Compact height just tall enough for buttons
$panelFiles.Size = New-Object System.Drawing.Size(760, 80)
$panelFiles.BorderStyle = 'FixedSingle'
$panelFiles.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelFiles)

# Label text removed per request (no 'Select Files' heading)
$lblFilesTitle = New-Object System.Windows.Forms.Label
$lblFilesTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblFilesTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblFilesTitle.Text = ''
$lblFilesTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelFiles.Controls.Add($lblFilesTitle)

# Generate Filename button (builds name, copies to clipboard)
$btnGenerateFilename = New-Object System.Windows.Forms.Button
$btnGenerateFilename.Location = New-Object System.Drawing.Point(10, 30)
$btnGenerateFilename.Size = New-Object System.Drawing.Size(150, 36)
$btnGenerateFilename.Text = 'Generate Filename'
$btnGenerateFilename.BackColor = [System.Drawing.Color]::FromArgb(102, 187, 106)
$btnGenerateFilename.ForeColor = [System.Drawing.Color]::White
$btnGenerateFilename.FlatStyle = 'Flat'
$btnGenerateFilename.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnGenerateFilename.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnGenerateFilename)

# Browse button removed per request

# Clear button (remove selections)
$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Location = New-Object System.Drawing.Point(170, 30)
$btnClear.Size = New-Object System.Drawing.Size(150, 36)
$btnClear.Text = 'Clear Fields'
$btnClear.BackColor = [System.Drawing.Color]::FromArgb(244, 67, 54)
$btnClear.ForeColor = [System.Drawing.Color]::White
$btnClear.FlatStyle = 'Flat'
$btnClear.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnClear.Cursor = [System.Windows.Forms.Cursors]::Hand
$panelFiles.Controls.Add($btnClear)

# Rename button removed per request

# Preview Panel (example file name)
## Preview moved into the Automatic Name Builder panel (see below)

# no file list shown in compact mode; leave small gap below buttons
$yPos += 100

# Naming mode removed per request; leave a small gap before fields
$yPos += 20

# Fields Panel (automatic name builder inputs)
$panelFieldsSection = New-Object System.Windows.Forms.Panel
$panelFieldsSection.Location = New-Object System.Drawing.Point(20, $yPos)
# Expand fields panel to fill remaining form height (leave room for status bar)
$availableHeight = $form.ClientSize.Height - $yPos - 80
if ($availableHeight -lt 200) { $availableHeight = 200 }
$panelFieldsSection.Size = New-Object System.Drawing.Size(760, $availableHeight)
$panelFieldsSection.BorderStyle = 'FixedSingle'
$panelFieldsSection.BackColor = [System.Drawing.Color]::White
$scrollPanel.Controls.Add($panelFieldsSection)

$lblFieldsTitle = New-Object System.Windows.Forms.Label
$lblFieldsTitle.Location = New-Object System.Drawing.Point(10, 5)
$lblFieldsTitle.Size = New-Object System.Drawing.Size(740, 20)
$lblFieldsTitle.Text = 'Automatic Name Builder'
$lblFieldsTitle.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$panelFieldsSection.Controls.Add($lblFieldsTitle)

# Preview panel moved into the Automatic Name Builder panel
$panelPreview = New-Object System.Windows.Forms.Panel
$panelPreview.Location = New-Object System.Drawing.Point(10, 30)
$panelPreview.Size = New-Object System.Drawing.Size(740, 36)
$panelPreview.BorderStyle = 'FixedSingle'
$panelPreview.BackColor = [System.Drawing.Color]::FromArgb(227, 242, 253)
$panelFieldsSection.Controls.Add($panelPreview)

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Location = New-Object System.Drawing.Point(10, 8)
$lblPreview.Size = New-Object System.Drawing.Size(720, 20)
$lblPreview.Text = 'Preview: <no name>.ext'
$lblPreview.Font = New-Object System.Drawing.Font('Consolas', 10)
$lblPreview.ForeColor = [System.Drawing.Color]::FromArgb(13, 71, 161)
$panelPreview.Controls.Add($lblPreview)

# Create field controls storage
$script:fieldControls = @{}
$script:otherTextBoxes = @{}

$fieldY = 70

# 1. Experiment type (Dropdown)
$lblExpType = New-Object System.Windows.Forms.Label
$lblExpType.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblExpType.Size = New-Object System.Drawing.Size(140, 20)
$lblExpType.Text = 'Experiment type:'
$lblExpType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblExpType)

$cmbExpType = New-Object System.Windows.Forms.ComboBox
$cmbExpType.Location = New-Object System.Drawing.Point(170, $fieldY)
$cmbExpType.Size = New-Object System.Drawing.Size(570, 20)
$cmbExpType.DropDownStyle = 'DropDownList'
$cmbExpType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $cmbExpType.Items.AddRange(@('', 'MOA', 'other (spawn free text entry)'))
$cmbExpType.SelectedIndex = 0
$panelFieldsSection.Controls.Add($cmbExpType)
$script:fieldControls['expType'] = $cmbExpType
$fieldY += 25

# Experiment type "other" textbox (hidden by default)
$txtExpTypeOther = New-Object System.Windows.Forms.TextBox
$txtExpTypeOther.Location = New-Object System.Drawing.Point(170, $fieldY)
$txtExpTypeOther.Size = New-Object System.Drawing.Size(570, 20)
$txtExpTypeOther.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtExpTypeOther.Visible = $false
$panelFieldsSection.Controls.Add($txtExpTypeOther)
$script:otherTextBoxes['expType'] = $txtExpTypeOther
$fieldY += 25

# 2. Experimental TIC
$lblExpTIC = New-Object System.Windows.Forms.Label
$lblExpTIC.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblExpTIC.Size = New-Object System.Drawing.Size(140, 20)
$lblExpTIC.Text = 'Experimental TIC:'
$lblExpTIC.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblExpTIC)

$txtExpTIC = New-Object System.Windows.Forms.TextBox
$txtExpTIC.Location = New-Object System.Drawing.Point(170, $fieldY)
$txtExpTIC.Size = New-Object System.Drawing.Size(570, 20)
$txtExpTIC.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($txtExpTIC)
$script:fieldControls['expTIC'] = $txtExpTIC
$fieldY += 25

# 3. Colony (moved after Experimental TIC)
$lblColony = New-Object System.Windows.Forms.Label
$lblColony.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblColony.Size = New-Object System.Drawing.Size(140, 20)
$lblColony.Text = 'Colony:'
$lblColony.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblColony)

$cmbColony = New-Object System.Windows.Forms.ComboBox
$cmbColony.Location = New-Object System.Drawing.Point(170, $fieldY)
$cmbColony.Size = New-Object System.Drawing.Size(570, 20)
$cmbColony.DropDownStyle = 'DropDownList'
$cmbColony.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbColony.Items.AddRange(@('', 'ECB', 'SWC', 'SBC', 'FAW', 'SBL', 'VBC', 'other (spawn free text entry)'))
$cmbColony.SelectedIndex = 0
$panelFieldsSection.Controls.Add($cmbColony)
$script:fieldControls['colony'] = $cmbColony
$fieldY += 25

# Colony "other" textbox (hidden by default)
$txtColonyOther = New-Object System.Windows.Forms.TextBox
$txtColonyOther.Location = New-Object System.Drawing.Point(170, $fieldY)
$txtColonyOther.Size = New-Object System.Drawing.Size(570, 20)
$txtColonyOther.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$txtColonyOther.Visible = $false
$panelFieldsSection.Controls.Add($txtColonyOther)
$script:otherTextBoxes['colony'] = $txtColonyOther
$fieldY += 25

# 4. Assay type (Dropdown)
$lblAssayType = New-Object System.Windows.Forms.Label
$lblAssayType.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblAssayType.Size = New-Object System.Drawing.Size(140, 20)
$lblAssayType.Text = 'Assay type:'
$lblAssayType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblAssayType)

$cmbAssayType = New-Object System.Windows.Forms.ComboBox
$cmbAssayType.Location = New-Object System.Drawing.Point(170, $fieldY)
$cmbAssayType.Size = New-Object System.Drawing.Size(570, 20)
$cmbAssayType.DropDownStyle = 'DropDownList'
$cmbAssayType.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $cmbAssayType.Items.AddRange(@('', '1 way', '2 way', 'dose response'))
$cmbAssayType.SelectedIndex = 0
$panelFieldsSection.Controls.Add($cmbAssayType)
$script:fieldControls['assayType'] = $cmbAssayType
$fieldY += 25

# 5. Block # (dropdown 1-4)
$lblBlock = New-Object System.Windows.Forms.Label
$lblBlock.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblBlock.Size = New-Object System.Drawing.Size(140, 20)
$lblBlock.Text = 'Block #:'
$lblBlock.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblBlock)

$cmbBlock = New-Object System.Windows.Forms.ComboBox
$cmbBlock.Location = New-Object System.Drawing.Point(170, $fieldY)
$cmbBlock.Size = New-Object System.Drawing.Size(120, 20)
$cmbBlock.DropDownStyle = 'DropDownList'
$cmbBlock.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbBlock.Items.AddRange(@('', '1', '2', '3', '4'))
$cmbBlock.SelectedIndex = 0
$panelFieldsSection.Controls.Add($cmbBlock)
$script:fieldControls['block'] = $cmbBlock
$fieldY += 25

# 6. Rep # (dropdown 1-4)
$lblRep = New-Object System.Windows.Forms.Label
$lblRep.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblRep.Size = New-Object System.Drawing.Size(140, 20)
$lblRep.Text = 'Rep #:'
$lblRep.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblRep)

$cmbRep = New-Object System.Windows.Forms.ComboBox
$cmbRep.Location = New-Object System.Drawing.Point(170, $fieldY)
$cmbRep.Size = New-Object System.Drawing.Size(120, 20)
$cmbRep.DropDownStyle = 'DropDownList'
$cmbRep.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$cmbRep.Items.AddRange(@('', '1', '2', '3', '4'))
$cmbRep.SelectedIndex = 0
$panelFieldsSection.Controls.Add($cmbRep)
$script:fieldControls['rep'] = $cmbRep
$fieldY += 25

# 7-10. Control TIC 1-4
for ($i = 1; $i -le 4; $i++) {
    $lblCtrl = New-Object System.Windows.Forms.Label
    $lblCtrl.Location = New-Object System.Drawing.Point(20, $fieldY)
    $lblCtrl.Size = New-Object System.Drawing.Size(140, 20)
    $lblCtrl.Text = "Control TIC ${i}:"
    $lblCtrl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $panelFieldsSection.Controls.Add($lblCtrl)
    
    $txtCtrl = New-Object System.Windows.Forms.TextBox
    $txtCtrl.Location = New-Object System.Drawing.Point(170, $fieldY)
    $txtCtrl.Size = New-Object System.Drawing.Size(570, 20)
    $txtCtrl.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $panelFieldsSection.Controls.Add($txtCtrl)
    $script:fieldControls["controlTIC$i"] = $txtCtrl
    $fieldY += 25
}

# 11. Date
$lblDate = New-Object System.Windows.Forms.Label
$lblDate.Location = New-Object System.Drawing.Point(20, $fieldY)
$lblDate.Size = New-Object System.Drawing.Size(140, 20)
$lblDate.Text = 'Date:'
$lblDate.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$panelFieldsSection.Controls.Add($lblDate)

$txtDate = New-Object System.Windows.Forms.TextBox
$txtDate.Location = New-Object System.Drawing.Point(170, $fieldY)
$txtDate.Size = New-Object System.Drawing.Size(570, 20)
$txtDate.Font = New-Object System.Drawing.Font('Segoe UI', 9)
# Set today's date
$today = Get-Date
$txtDate.Text = $today.ToString('yyyyMMdd')
$panelFieldsSection.Controls.Add($txtDate)
$script:fieldControls['date'] = $txtDate
$fieldY += 25

$yPos += 390

# Manual naming removed per request

# Status Bar (single-line feedback)
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(20, $yPos)
$lblStatus.Size = New-Object System.Drawing.Size(760, 30)
$lblStatus.Text = 'Ready.'
$lblStatus.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lblStatus.BackColor = [System.Drawing.Color]::FromArgb(233, 236, 239)
$lblStatus.TextAlign = 'MiddleLeft'
$lblStatus.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$scrollPanel.Controls.Add($lblStatus)

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

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
        Builds the base filename from UI fields.
    .DESCRIPTION
        Assembles parts with underscores. Returns both name and error message.
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
    
    $parts = @()
    
    # 1. Experiment type
    $expTypeVal = $script:fieldControls['expType'].SelectedItem
    if ($expTypeVal -and $expTypeVal -ne '') {
        if ($expTypeVal -like 'other*') {
            $otherVal = $script:otherTextBoxes['expType'].Text.Trim()
            if ($otherVal) {
                $safeVal = Sanitize-FileName $otherVal
                if ($safeVal) { $parts += $safeVal }
            }
        } else {
            $safeVal = Sanitize-FileName $expTypeVal
            if ($safeVal) { $parts += $safeVal }
        }
    }
    
    # 2. Experimental TIC
    $expTICVal = $script:fieldControls['expTIC'].Text.Trim()
    if ($expTICVal) {
        $safeVal = Sanitize-FileName $expTICVal
        if ($safeVal) { $parts += $safeVal }
    }

    # 3. Colony
    $colonyVal = $script:fieldControls['colony'].SelectedItem
    if ($colonyVal -and $colonyVal -ne '') {
        if ($colonyVal -like 'other*') {
            $otherVal = $script:otherTextBoxes['colony'].Text.Trim()
            if ($otherVal) {
                $safeVal = Sanitize-FileName $otherVal
                if ($safeVal) { $parts += $safeVal }
            }
        } else {
            $safeVal = Sanitize-FileName $colonyVal
            if ($safeVal) { $parts += $safeVal }
        }
    }
    
    # 4. Assay type
    $assayTypeVal = $script:fieldControls['assayType'].SelectedItem
    if ($assayTypeVal -and $assayTypeVal -ne '') {
        # Map human-friendly selections to filename abbreviations for DIP assays
        if ($assayTypeVal -match '^\s*1\s*way') {
            $mapped = '1w DIP'
        } elseif ($assayTypeVal -match '^\s*2\s*way') {
            $mapped = '2w DIP'
        } elseif ($assayTypeVal -match 'dose\s*response') {
            $mapped = 'DosRes'
        } else {
            $mapped = $assayTypeVal
        }
        $safeVal = Sanitize-FileName $mapped
        if ($safeVal) { $parts += $safeVal }
    }
    
    # 5. Block # (with BL prefix)
    $blockVal = $script:fieldControls['block'].Text.Trim()
    if ($blockVal) {
        $safeVal = Sanitize-FileName $blockVal
        if ($safeVal) { $parts += "BL$safeVal" }
    }
    
    # 6. Rep # (with rep prefix)
    $repVal = $script:fieldControls['rep'].Text.Trim()
    if ($repVal) {
        $safeVal = Sanitize-FileName $repVal
        if ($safeVal) { $parts += "rep$safeVal" }
    }
    
    # 7-10. Control TIC 1-4 (prefix each with 'vs' directly, no underscore/space)
    for ($i = 1; $i -le 4; $i++) {
        $ctrlVal = $script:fieldControls["controlTIC$i"].Text.Trim()
        if ($ctrlVal) {
            $safeVal = Sanitize-FileName $ctrlVal
            if ($safeVal) { $parts += "vs$safeVal" }
        }
    }
    
    # 11. Date
    $dateVal = $script:fieldControls['date'].Text.Trim()
    if ($dateVal) {
        $safeVal = Sanitize-FileName $dateVal
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

## Naming mode removed — always use fields to build filenames

function Toggle-OtherTextBox {
    <#
    .SYNOPSIS
        Shows/hides "other" text input based on dropdown selection.
    .DESCRIPTION
        When user selects "other" from a dropdown, shows the associated textbox.
    #>
    param(
        [string]$fieldName
    )
    
    if ($script:fieldControls.ContainsKey($fieldName) -and $script:otherTextBoxes.ContainsKey($fieldName)) {
        $dropdown = $script:fieldControls[$fieldName]
        $textbox = $script:otherTextBoxes[$fieldName]
        
        if ($dropdown.SelectedItem -like 'other*') {
            $textbox.Visible = $true
        } else {
            $textbox.Visible = $false
            $textbox.Text = ''
        }
    }
}

# -----------------------------------------------------------------------------
# Event Handlers (UI actions)
# -----------------------------------------------------------------------------
# Browse functionality removed per request

$btnClear.Add_Click({
    # Clear all input fields (textboxes and dropdowns) and reset preview/status
    foreach ($k in $script:fieldControls.Keys) {
        $c = $script:fieldControls[$k]
        if ($c -is [System.Windows.Forms.TextBox]) { $c.Text = '' }
        elseif ($c -is [System.Windows.Forms.ComboBox]) { $c.SelectedIndex = 0 }
    }
    foreach ($k in $script:otherTextBoxes.Keys) {
        $t = $script:otherTextBoxes[$k]
        $t.Text = ''
        $t.Visible = $false
    }
    # Also clear any selected files state (no-op if unused)
    $script:selectedFiles = @()

    Update-Preview
    $lblStatus.Text = 'Fields cleared.'
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
    
    $happyMessages = @(
        'Nice work!',
        'All set!',
        'Filename ready. Great job!',
        'You are awesome!',
        'Done!'
    )
    $happyMessage = Get-Random -InputObject $happyMessages
    $finalMessage = "Filename copied to clipboard.`n$happyMessage"
    $lblStatus.Text = $finalMessage
    [System.Windows.Forms.MessageBox]::Show($finalMessage, 'Copied', 'OK', 'Information')
})

# Removed naming mode radio buttons — always use fields

# Add event handlers for all text inputs
foreach ($key in $script:fieldControls.Keys) {
    $control = $script:fieldControls[$key]
    if ($control -is [System.Windows.Forms.TextBox]) {
        $control.Add_TextChanged({ Update-Preview })
    } elseif ($control -is [System.Windows.Forms.ComboBox]) {
        $control.Add_SelectedIndexChanged({ Update-Preview })
    }
}

# Add event handlers for "other" textboxes
foreach ($key in $script:otherTextBoxes.Keys) {
    $script:otherTextBoxes[$key].Add_TextChanged({ Update-Preview })
}

# Add event handlers for dropdown "other" selections
$cmbExpType.Add_SelectedIndexChanged({
    Toggle-OtherTextBox 'expType'
    Update-Preview
})

$cmbColony.Add_SelectedIndexChanged({
    Toggle-OtherTextBox 'colony'
    Update-Preview
})

# Removed manual naming — always use fields

# Rename functionality removed per request

# -----------------------------------------------------------------------------
# Show form (entry point)
# -----------------------------------------------------------------------------
Update-Preview
[void]$form.ShowDialog()
