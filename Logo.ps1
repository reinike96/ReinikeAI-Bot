# ReinikeAI Terminal Logo Script (Bulletproof Version)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$E = [char]27
$B = [char]0x2588 # Block character

$White = "$E[38;5;255m"
$Gray = "$E[38;5;252m"
$Dark = "$E[38;5;241m"
$Cyan = "$E[38;5;51m"
$Reset = "$E[0m"

function P($pattern, $color) {
    # R (8) E (8) I (4) N (8) I (4) K (8) E (9) | [space] (4) | A (8) I (2)
    $line = $pattern.Replace("#", $B)
    $reinikePart = $line.Substring(0, 51)
    $aiPart = $line.Substring(51)
    Write-Host "  $color$reinikePart$White$aiPart$Reset"
}

Write-Host ""
P "######  #######  ##  ##    ##  ##  ##  ##  #######      #####   ##" $Gray
P "##   ## ##       ##  ###   ##  ##  ## ##   ##          ##   ##  ##" $Gray
P "######  #####    ##  ## ## ##  ##  ####    #####       #######  ##" $Gray
P "##   ## ##       ##  ##  ####  ##  ## ##   ##          ##   ##  ##" $Dark
P "##   ## #######  ##  ##   ###  ##  ##  ##  #######     ##   ##  ##" $Dark
Write-Host ""
Write-Host "                $Cyan [+] Telegram Orchestrator Bot $Reset"
Write-Host ""
