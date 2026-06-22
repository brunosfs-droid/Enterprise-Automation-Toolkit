# ============================================================
# Script: Sync-ADMailFromM365.ps1
# Objetivo: Preencher/atualizar o campo mail do AD com base
#           no e-mail existente no Microsoft 365.
# Autor: Bruno Feitoza
# ============================================================

# MODO SIMULAÇÃO
# $true  = apenas mostra o que faria
# $false = altera de verdade no AD
$WhatIfMode = $true

# Caminho do relatório
$DataHora = Get-Date -Format "yyyyMMdd_HHmmss"
$Relatorio = "C:\Temp\Relatorio_Update_AD_Mail_$DataHora.csv"

# Importa módulo do AD
Import-Module ActiveDirectory

# Conecta no Microsoft Graph
# Necessário permissão: User.Read.All
Import-Module Microsoft.Graph.Users
Connect-MgGraph -Scopes "User.Read.All"

# Busca somente usuários habilitados e com UPN preenchido
$UsuariosAD = Get-ADUser -Filter {
    Enabled -eq $true -and UserPrincipalName -like "*"
} -Properties UserPrincipalName, Mail, DisplayName, Enabled

$Resultado = @()

foreach ($UsuarioAD in $UsuariosAD) {

    $UPN = $UsuarioAD.UserPrincipalName
    $MailAtualAD = $UsuarioAD.Mail

    try {
        # Procura usuário no Microsoft 365 pelo UPN
        $UsuarioM365 = Get-MgUser -UserId $UPN -Property Id,UserPrincipalName,Mail,ProxyAddresses -ErrorAction Stop

        # Prioriza o campo Mail do M365
        $EmailM365 = $UsuarioM365.Mail

        # Se Mail estiver vazio, tenta pegar o SMTP principal em ProxyAddresses
        if ([string]::IsNullOrWhiteSpace($EmailM365)) {
            $SMTPPrincipal = $UsuarioM365.ProxyAddresses | Where-Object { $_ -cmatch "^SMTP:" } | Select-Object -First 1

            if ($SMTPPrincipal) {
                $EmailM365 = $SMTPPrincipal -replace "^SMTP:", ""
            }
        }

        # Se não encontrou e-mail no M365, não faz nada
        if ([string]::IsNullOrWhiteSpace($EmailM365)) {
            $Resultado += [PSCustomObject]@{
                Login        = $UsuarioAD.SamAccountName
                Nome         = $UsuarioAD.DisplayName
                UPN_AD       = $UPN
                Mail_AD      = $MailAtualAD
                Mail_M365    = ""
                Acao         = "Nenhuma alteração"
                Motivo       = "Usuário encontrado no M365, mas sem e-mail"
            }
            continue
        }

        # Se o mail do AD já está igual, não altera
        if ($MailAtualAD -eq $EmailM365) {
            $Resultado += [PSCustomObject]@{
                Login        = $UsuarioAD.SamAccountName
                Nome         = $UsuarioAD.DisplayName
                UPN_AD       = $UPN
                Mail_AD      = $MailAtualAD
                Mail_M365    = $EmailM365
                Acao         = "Nenhuma alteração"
                Motivo       = "Campo mail já está correto"
            }
            continue
        }

        # Atualiza o campo mail no AD
        if ($WhatIfMode) {
            $Acao = "Simulação - atualizaria o campo mail"
        }
        else {
            Set-ADUser -Identity $UsuarioAD.DistinguishedName -EmailAddress $EmailM365
            $Acao = "Campo mail atualizado"
        }

        $Resultado += [PSCustomObject]@{
            Login        = $UsuarioAD.SamAccountName
            Nome         = $UsuarioAD.DisplayName
            UPN_AD       = $UPN
            Mail_AD      = $MailAtualAD
            Mail_M365    = $EmailM365
            Acao         = $Acao
            Motivo       = "E-mail encontrado no M365"
        }
    }
    catch {
        $Resultado += [PSCustomObject]@{
            Login        = $UsuarioAD.SamAccountName
            Nome         = $UsuarioAD.DisplayName
            UPN_AD       = $UPN
            Mail_AD      = $MailAtualAD
            Mail_M365    = ""
            Acao         = "Nenhuma alteração"
            Motivo       = "Usuário não encontrado no M365 ou erro na consulta"
        }
    }
}

# Exporta relatório
$Resultado | Export-Csv -Path $Relatorio -NoTypeInformation -Encoding UTF8 -Delimiter ";"

Write-Host "Processo finalizado."
Write-Host "Relatório gerado em: $Relatorio"
Write-Host "Modo simulação: $WhatIfMode"