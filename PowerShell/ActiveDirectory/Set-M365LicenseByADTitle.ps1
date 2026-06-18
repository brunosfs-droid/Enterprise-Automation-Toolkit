<#
.SYNOPSIS
    Atribui licença Microsoft 365 conforme o cargo do usuário no Active Directory On-Premises.

.DESCRIPTION
    Ambiente híbrido:
    - Active Directory On-Premises
    - Azure AD Connect / Microsoft Entra Connect
    - Microsoft 365
    - Execução via Task Scheduler em servidor Windows

    O script lê o campo "Title" do usuário no AD e atribui a licença correta no Microsoft 365.

.NOTES
    Autor: Bruno Feitoza
    GitHub: inserir link do repositório
#>

# ============================================================
# MÓDULOS NECESSÁRIOS
# ============================================================

# Install-Module ActiveDirectory
# Install-Module Microsoft.Graph -Force
# Install-Module Microsoft.Graph.Users -Force
# Install-Module Microsoft.Graph.Identity.DirectoryManagement -Force

Import-Module ActiveDirectory
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Identity.DirectoryManagement

# ============================================================
# CONFIGURAÇÕES DO APP REGISTRATION / CERTIFICADO
# ============================================================

# Dados abaixo devem ser preenchidos por quem for utilizar o script.
# Não publique dados reais no GitHub.

$TenantId              = "SEU-TENANT-ID"
$ClientId              = "SEU-APP-CLIENT-ID"
$CertificateThumbprint = "THUMBPRINT-DO-CERTIFICADO"

# ============================================================
# CONFIGURAÇÕES DO ACTIVE DIRECTORY
# ============================================================

# OU onde estão os usuários que serão avaliados
$SearchBase = "OU=Usuarios,DC=empresa,DC=com,DC=br"

# Campo usado para definir o cargo no AD
$CampoCargo = "Title"

# País obrigatório para atribuição de licença no Microsoft 365
# BR = Brasil
$UsageLocation = "BR"

# ============================================================
# MAPEAMENTO DE CARGOS X LICENÇAS
# ============================================================

<#
    Ajuste os SKUs conforme as licenças disponíveis no tenant.

    Exemplos comuns de SkuPartNumber:

    Microsoft 365 Business Basic      = O365_BUSINESS_ESSENTIALS
    Microsoft 365 Business Standard   = O365_BUSINESS_PREMIUM
    Microsoft 365 Business Premium    = SPB
    Office 365 E1                     = STANDARDPACK
    Office 365 E3                     = ENTERPRISEPACK
    Office 365 E5                     = ENTERPRISEPREMIUM
    Microsoft 365 F3                  = SPE_F1

    Observação:
    - Técnico: usar licença web/frontline/básica conforme contrato da empresa.
    - Analista: licença intermediária com Office instalado + SharePoint.
    - Especialista e cargos acima: licença completa.
#>

$LicencasPorCargo = @{
    "tecnico"      = "O365_BUSINESS_ESSENTIALS"
    "técnico"     = "O365_BUSINESS_ESSENTIALS"

    "analista"    = "O365_BUSINESS_PREMIUM"

    "especialista" = "ENTERPRISEPACK"
    "supervisor"   = "ENTERPRISEPACK"
    "coordenador"  = "ENTERPRISEPACK"
    "gerente"      = "ENTERPRISEPACK"
    "diretor"      = "ENTERPRISEPACK"
}

# Licenças gerenciadas por este script.
# O script remove apenas essas licenças antes de aplicar a correta.
$LicencasGerenciadas = $LicencasPorCargo.Values | Select-Object -Unique

# ============================================================
# CONEXÃO COM MICROSOFT GRAPH
# ============================================================

Connect-MgGraph `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -CertificateThumbprint $CertificateThumbprint `
    -NoWelcome

# ============================================================
# CARREGAR SKUS DISPONÍVEIS NO TENANT
# ============================================================

$SkusTenant = Get-MgSubscribedSku -All

function Get-SkuIdByPartNumber {
    param (
        [string]$SkuPartNumber
    )

    $Sku = $SkusTenant | Where-Object { $_.SkuPartNumber -eq $SkuPartNumber }

    if (-not $Sku) {
        throw "SKU não encontrado no tenant: $SkuPartNumber"
    }

    $Disponiveis = $Sku.PrepaidUnits.Enabled - $Sku.ConsumedUnits

    if ($Disponiveis -le 0) {
        throw "Não há licenças disponíveis para o SKU: $SkuPartNumber"
    }

    return $Sku.SkuId
}

# ============================================================
# BUSCAR USUÁRIOS NO AD
# ============================================================

$UsuariosAD = Get-ADUser `
    -SearchBase $SearchBase `
    -Filter { Enabled -eq $true } `
    -Properties UserPrincipalName, Title, Mail

foreach ($UsuarioAD in $UsuariosAD) {

    try {
        $UPN = $UsuarioAD.UserPrincipalName
        $Cargo = $UsuarioAD.Title

        if ([string]::IsNullOrWhiteSpace($UPN)) {
            Write-Warning "Usuário sem UPN no AD: $($UsuarioAD.SamAccountName)"
            continue
        }

        if ([string]::IsNullOrWhiteSpace($Cargo)) {
            Write-Warning "Usuário sem cargo preenchido: $UPN"
            continue
        }

        $CargoNormalizado = $Cargo.Trim().ToLower()

        if (-not $LicencasPorCargo.ContainsKey($CargoNormalizado)) {
            Write-Host "Cargo não mapeado: $Cargo - Usuário: $UPN"
            continue
        }

        $SkuDesejado = $LicencasPorCargo[$CargoNormalizado]
        $SkuIdDesejado = Get-SkuIdByPartNumber -SkuPartNumber $SkuDesejado

        $UsuarioM365 = Get-MgUser -UserId $UPN -ErrorAction Stop

        # Garante UsageLocation antes de aplicar licença
        if ([string]::IsNullOrWhiteSpace($UsuarioM365.UsageLocation)) {
            Update-MgUser -UserId $UPN -UsageLocation $UsageLocation
        }

        $LicencasAtuais = Get-MgUserLicenseDetail -UserId $UPN

        $SkuIdsGerenciados = foreach ($SkuGerenciada in $LicencasGerenciadas) {
            ($SkusTenant | Where-Object { $_.SkuPartNumber -eq $SkuGerenciada }).SkuId
        }

        $LicencasParaRemover = $LicencasAtuais |
            Where-Object { $SkuIdsGerenciados -contains $_.SkuId -and $_.SkuId -ne $SkuIdDesejado } |
            Select-Object -ExpandProperty SkuId

        $JaPossuiLicencaCorreta = $LicencasAtuais.SkuId -contains $SkuIdDesejado

        if ($JaPossuiLicencaCorreta -and $LicencasParaRemover.Count -eq 0) {
            Write-Host "OK - Usuário já possui licença correta: $UPN - $SkuDesejado"
            continue
        }

        $AddLicenses = @()

        if (-not $JaPossuiLicencaCorreta) {
            $AddLicenses = @(
                @{
                    SkuId = $SkuIdDesejado
                }
            )
        }

        Set-MgUserLicense `
            -UserId $UPN `
            -AddLicenses $AddLicenses `
            -RemoveLicenses $LicencasParaRemover

        Write-Host "Licença ajustada: $UPN | Cargo: $Cargo | SKU: $SkuDesejado"
    }
    catch {
        Write-Error "Erro ao processar usuário $($UsuarioAD.UserPrincipalName): $($_.Exception.Message)"
    }
}

Disconnect-MgGraph