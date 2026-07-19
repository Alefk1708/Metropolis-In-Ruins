#Requires -RunAsAdministrator
$ruleName = "Metropolis in Ruins - LAN UDP 8910"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($null -eq $existing) {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 8910 `
        -Action Allow `
        -Profile Private | Out-Null
    Write-Host "Regra criada: UDP 8910 liberada para redes privadas." -ForegroundColor Green
} else {
    Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Action Allow -Profile Private
    Write-Host "Regra existente reativada: UDP 8910 liberada." -ForegroundColor Green
}
Write-Host "Feche esta janela e teste novamente com os dois aparelhos no mesmo Wi-Fi."
Read-Host "Pressione Enter para sair"
