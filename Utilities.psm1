# Print

[string]$Print_Virtual = ""
[boolean]$Print_IsLineInProgress = $false
[Nullable[ConsoleColor]]$Print_SetColor = $null

function Print {
    Param(
        [string]$Output,
        [Nullable[ConsoleColor]]$Color,
        [Nullable[ConsoleColor]]$SetColor,
        [switch]$ResetColor,
        [int]$AtLeast = -1,
        [int]$AtMost = -1,
        [int]$Space = 0,
        [switch]$FinishLine
    );

    if ($AtMost -ge 0) {
        if ($Output.Length -gt $AtMost) {
            if ($AtMost -lt 4) {
                $Output = $Output.SubString(0, $AtMost);
            } else {
                $Output = $Output.SubString(0, $AtMost - 3) + "..."
            }
        }
    }

    if ($SetColor) {
        $Script:Print_SetColor = $SetColor
    }
    if ($ResetColor) {
        $Script:Print_SetColor = $null
    }

    $ActualColor = if ($Color) {
        $Color
    } elseif ($Script:Print_SetColor) {
        $Script:Print_SetColor
    } else {
        [ConsoleColor]::White
    }
    
    if ($Output.Length -gt 0) {
        if ($Script:Print_Virtual) {
            Write-Host $Script:Print_Virtual -NoNewLine
            $Script:Print_Virtual = ""
        }

        Write-Host $Output -ForegroundColor $ActualColor -NoNewLine
    }

    if ($AtLeast -ge 0) {
        $AtLeast -= $Output.Length
        if ($AtLeast -ge 0) {
            $Script:Print_Virtual += (" " * $AtLeast)
        }
    }

    if ($Space -gt 0) {
        $Script:Print_Virtual += (" " * $Space)
    }

    $script:Print_IsLineInProgress = $true

    if ($FinishLine) {
        if ($Script:Print_IsLineInProgress) {
            Write-Host
            $Script:Print_Virtual = ""
            $Script:Print_IsLineInProgress = $false
        }
    }
}

Export-ModuleMember -Function "Print"

# Errors
function FatalError {
    Param(
        [string]$Message
    )
    Print -FinishLine
    Print $Message -Color Red -FinishLine
    exit
}

Export-ModuleMember -Function "FatalError"