<#
.SYNOPSIS
    Converte mailbox para Shared Mailbox e remove licenças Microsoft 365
    de usuários desabilitados no Active Directory.

.DESCRIPTION
    Este script foi criado para ambientes híbridos:
    - Active Directory On-Premises
    - Azure AD Connect / Microsoft Entra Connect
    - Microsoft Entra ID
    - Exchange Online
    - Microsoft 365

    O script busca usuários desabilitados no AD, verifica se possuem mailbox
    no Exchange Online, converte a mailbox para Shared Mailbox e remove
    as licenças atribuídas no Microsoft 365.

.NOTES
    Autor: Bruno Sousa
    GitHub:https://github.com/brunosfs-droid/Enterprise-Automation-Toolkit/blob/main/PowerShell/ActiveDirectory/M365LicenseDisableUserAndConvertMailBox.ps1
#>

# ============================================================
# MÓDULOS NECESSÁRIOS
# ============================================================

# Install-Module Microsoft.Graph -Force
# Install-Module Microsoft.Graph.Users -Force
# Install-Module ExchangeOnlineManagement -Force
# Import-Module ActiveDirectory

Import-Module ActiveDirectory
Import-Module Microsoft.Graph.Users
Import-Module ExchangeOnlineManagement

# ============================================================
# CONFIGURAÇÕES - APP REGISTRATION / CERTIFICADO
# ============================================================

# Preencha com os dados do seu ambiente.
# Para publicar no GitHub, mantenha esses campos comentados ou substituídos.

$TenantId              = "SEU-TENANT-ID"
$ClientId              = "SEU-APP-CLIENT-ID"
$CertificateThumbprint = "THUMBPRINT-DO-CERTIFICADO"

# Para conexão com Exchange Online via certificado/app-only.
# Normalmente é o domínio principal do tenant, exemplo: empresa.onmicrosoft.com
$Organization = "SEU-TENANT.onmicrosoft.com"

# ============================================================
# CONFIGURAÇÕES DO ACTIVE DIRECTORY
# ============================================================

$SearchBase = "OU=Usuarios,DC=empresa,DC=com,DC=br"

# Defina como $true para testar sem aplicar alterações
$WhatIfMode = $true

# ============================================================
# LOG
# ============================================================

$DataAtual = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath = "C:\Scripts\Logs\Remove-M365License-DisabledUsers_$DataAtual.csv"

if (-not (Test-Path (Split-Path $LogPath))) {
    New-Item -ItemType Directory -Path (Split-Path $LogPath) -Force | Out-Null
}

$Resultado = @()

# ============================================================
# CONEXÕES
# ============================================================

Connect-MgGraph `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -CertificateThumbprint $CertificateThumbprint `
    -NoWelcome

Connect-ExchangeOnline `
    -AppId $ClientId `
    -CertificateThumbprint $CertificateThumbprint `
    -Organization $Organization `
    -ShowBanner:$false

# ============================================================
# BUSCAR USUÁRIOS DESABILITADOS NO AD
# ============================================================

$UsuariosDesabilitados = Get-ADUser `
    -SearchBase $SearchBase `
    -Filter { Enabled -eq $false } `
    -Properties UserPrincipalName, SamAccountName, DisplayName, Enabled

foreach ($UsuarioAD in $UsuariosDesabilitados) {

    $UPN = $UsuarioAD.UserPrincipalName

    if ([string]::IsNullOrWhiteSpace($UPN)) {
        continue
    }

    try {
        Write-Host "Processando usuário: $UPN"

        # ====================================================
        # VALIDAR USUÁRIO NO MICROSOFT 365
        # ====================================================

        $UsuarioM365 = Get-MgUser `
            -UserId $UPN `
            -Property Id,UserPrincipalName,AccountEnabled `
            -ErrorAction Stop

        # Segurança adicional:
        # Só continua se o usuário também estiver desabilitado no Entra ID.
        if ($UsuarioM365.AccountEnabled -eq $true) {
            Write-Warning "Usuário está desabilitado no AD, mas ainda habilitado no Entra ID: $UPN"

            $Resultado += [PSCustomObject]@{
                Usuario              = $UPN
                StatusAD             = "Desabilitado"
                StatusM365           = "Habilitado"
                Mailbox              = "Não validada"
                AcaoMailbox          = "Ignorado"
                LicencasRemovidas    = "Não"
                Observacao           = "Usuário ainda habilitado no Entra ID"
                DataExecucao         = Get-Date
            }

            continue
        }

        # ====================================================
        # VERIFICAR E CONVERTER MAILBOX
        # ====================================================

        $MailboxExiste = $false
        $AcaoMailbox = "Sem mailbox"

        try {
            $Mailbox = Get-Mailbox `
                -Identity $UPN `
                -ErrorAction Stop

            $MailboxExiste = $true

            if ($Mailbox.RecipientTypeDetails -ne "SharedMailbox") {

                if ($WhatIfMode) {
                    Write-Host "[WHATIF] Converter mailbox para Shared Mailbox: $UPN"
                    $AcaoMailbox = "WhatIf - Converteria para Shared Mailbox"
                }
                else {
                    Set-Mailbox `
                        -Identity $UPN `
                        -Type Shared `
                        -ErrorAction Stop

                    Write-Host "Mailbox convertida para Shared Mailbox: $UPN"
                    $AcaoMailbox = "Convertida para Shared Mailbox"
                }
            }
            else {
                Write-Host "Mailbox já é Shared Mailbox: $UPN"
                $AcaoMailbox = "Já era Shared Mailbox"
            }
        }
        catch {
            Write-Host "Usuário sem mailbox ou mailbox não localizada: $UPN"
            $AcaoMailbox = "Mailbox não localizada"
        }

        # ====================================================
        # REMOVER LICENÇAS
        # ====================================================

        $Licencas = Get-MgUserLicenseDetail `
            -UserId $UPN `
            -ErrorAction Stop

        if (-not $Licencas -or $Licencas.Count -eq 0) {
            Write-Host "Usuário sem licenças atribuídas: $UPN"

            $Resultado += [PSCustomObject]@{
                Usuario              = $UPN
                StatusAD             = "Desabilitado"
                StatusM365           = "Desabilitado"
                Mailbox              = $MailboxExiste
                AcaoMailbox          = $AcaoMailbox
                LicencasRemovidas    = "Não havia licenças"
                Observacao           = "Nenhuma licença encontrada"
                DataExecucao         = Get-Date
            }

            continue
        }

        $SkuIdsParaRemover = @($Licencas | Select-Object -ExpandProperty SkuId)

        if ($WhatIfMode) {
            Write-Host "[WHATIF] Removeria $($SkuIdsParaRemover.Count) licença(s) de $UPN"

            $LicencasRemovidas = "WhatIf - Não removidas"
        }
        else {
            Set-MgUserLicense `
                -UserId $UPN `
                -AddLicenses @() `
                -RemoveLicenses $SkuIdsParaRemover `
                -ErrorAction Stop

            Write-Host "Licenças removidas de: $UPN"

            $LicencasRemovidas = "Sim"
        }

        $Resultado += [PSCustomObject]@{
            Usuario              = $UPN
            StatusAD             = "Desabilitado"
            StatusM365           = "Desabilitado"
            Mailbox              = $MailboxExiste
            AcaoMailbox          = $AcaoMailbox
            LicencasRemovidas    = $LicencasRemovidas
            Observacao           = "Processado com sucesso"
            DataExecucao         = Get-Date
        }
    }
    catch {
        Write-Error "Erro ao processar $UPN : $($_.Exception.Message)"

        $Resultado += [PSCustomObject]@{
            Usuario              = $UPN
            StatusAD             = "Desabilitado"
            StatusM365           = "Erro"
            Mailbox              = "Erro"
            AcaoMailbox          = "Erro"
            LicencasRemovidas    = "Erro"
            Observacao           = $_.Exception.Message
            DataExecucao         = Get-Date
        }
    }
}

# ============================================================
# EXPORTAR LOG
# ============================================================

$Resultado | Export-Csv `
    -Path $LogPath `
    -NoTypeInformation `
    -Encoding UTF8 `
    -Delimiter ";"

# ============================================================
# DESCONECTAR SESSÕES
# ============================================================

Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph

Write-Host "Processo finalizado. Log gerado em: $LogPath"