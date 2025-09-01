# Path to the original CSV file
$csvPath = "D:\Reports\FortiVPN.csv"

# Load all lines from the CSV file
$lines = Get-Content $csvPath

# Process the first row to extract column names
$firstRow = $lines[0].Split(',')
$columnNames = @()
foreach ($item in $firstRow) {
    if ($item -like "*=*") {
        # Extract the part before '=' and remove quotes
        $columnNames += $item.Split('=')[0] -replace '"', ''
    } else {
        # Fallback name if '=' is not found
        $columnNames += "column_$($columnNames.Count)"
    }
}

# Process all rows – remove 'name=' and quotes from values
$processedLines = @()
foreach ($line in $lines) {
    $values = $line.Split(',') | ForEach-Object {
        # Extract value after '=' if present
        $cleaned = if ($_ -like "*=*") { $_.Split('=')[-1] } else { $_ }
        # Remove all double quotes
        $cleaned -replace '"', ''
    }
    # Rejoin cleaned values into a CSV line
    $processedLines += ,($values -join ',')
}

# Remove the first row (already used for column names)
$processedLines = $processedLines[1..($processedLines.Count - 1)]

# Insert an empty row at the beginning
$emptyLine = "," * ($columnNames.Count - 1)
$finalLines = @()
$finalLines += ($columnNames -join ',')  # Add header
$finalLines += $emptyLine                # Add empty row
$finalLines += $processedLines           # Add cleaned data

# Save to a new CSV file
$outputPath = "D:\Reports\upraveny_subor.csv"
$finalLines | Set-Content $outputPath

Write-Host "✅ File successfully processed and saved to: $outputPath"