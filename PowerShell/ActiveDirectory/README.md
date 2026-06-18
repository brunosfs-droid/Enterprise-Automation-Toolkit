# Active Directory Scripts

Automações PowerShell voltadas para ambientes híbridos Microsoft 365 com Active Directory On-Premises, Microsoft Entra ID e Azure AD Connect.

O objetivo destes scripts é automatizar tarefas recorrentes de governança, licenciamento e gestão de identidades, reduzindo atividades operacionais, aumentando a segurança e melhorando o aproveitamento das licenças Microsoft 365.

---

# Arquitetura

```text
Active Directory
       │
       ▼
Azure AD Connect
       │
       ▼
Microsoft Entra ID
       │
       ▼
Microsoft Graph
       │
       ▼
Microsoft 365
```

Todos os scripts utilizam autenticação baseada em App Registration e Certificado Digital, eliminando a necessidade de armazenar credenciais administrativas.

---

# Scripts Disponíveis

## 1. Set-M365LicenseByADTitle.ps1

### Objetivo

Realizar o licenciamento automático dos usuários Microsoft 365 com base no cargo cadastrado no Active Directory.

### Funcionamento

O script:

- Consulta usuários ativos no Active Directory.
- Lê o campo **Title (Cargo)**.
- Identifica qual licença deve ser aplicada.
- Verifica as licenças disponíveis no tenant.
- Remove licenças antigas gerenciadas pelo script.
- Atribui a licença correta ao usuário.

### Exemplo de Mapeamento

| Cargo | Licença |
|---------|---------|
| Técnico | Licença Básica |
| Analista | Licença Intermediária |
| Especialista | Licença Completa |
| Supervisor | Licença Completa |
| Coordenador | Licença Completa |
| Gerente | Licença Completa |
| Diretor | Licença Completa |

### Benefícios

✔ Padronização do processo de licenciamento

✔ Eliminação de atividades manuais

✔ Redução de erros operacionais

✔ Governança baseada no Active Directory

✔ Melhor aproveitamento das licenças contratadas

---

## 2. M365LicenseDisableUserAndConvertMailBox.ps1

### Objetivo

Automatizar o processo de desligamento lógico de usuários Microsoft 365.

### Funcionamento

O script:

- Consulta usuários desabilitados no Active Directory.
- Valida se a conta também está desabilitada no Microsoft Entra ID.
- Verifica a existência de mailbox.
- Converte a mailbox para Shared Mailbox.
- Remove todas as licenças Microsoft 365 atribuídas.
- Gera log da execução.

### Fluxo

```text
Usuário Desabilitado no AD
            │
            ▼
Sincronização Azure AD Connect
            │
            ▼
Validação Microsoft 365
            │
            ▼
Mailbox Existe?
      │             │
      ▼             ▼
    Sim            Não
      │
      ▼
Converter para Shared Mailbox
      │
      ▼
Remover Licenças
      │
      ▼
Gerar Log
```

### Benefícios

✔ Recuperação automática de licenças

✔ Redução de custos de licenciamento

✔ Preservação do histórico de e-mails

✔ Processo auditável

✔ Eliminação de atividades manuais

---

# Pré-Requisitos

## PowerShell Modules

```powershell
Install-Module Microsoft.Graph -Force
Install-Module Microsoft.Graph.Users -Force
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Force
Install-Module ExchangeOnlineManagement -Force
Install-Module ActiveDirectory
```

---

# Permissões Necessárias

Os scripts utilizam uma App Registration no Microsoft Entra ID.

Permissões recomendadas:

### Microsoft Graph

- User.Read.All
- User.ReadWrite.All
- Directory.Read.All
- Directory.ReadWrite.All

### Exchange Online

- Exchange Administrator (Application Permission)

---

# Segurança

Este projeto utiliza autenticação baseada em:

- App Registration
- Certificado Digital
- Microsoft Graph

Nenhuma senha é armazenada dentro dos scripts.

---

# Casos de Uso

- Provisionamento automático de usuários
- Gestão de licenças Microsoft 365
- Recuperação de licenças de usuários desligados
- Governança de identidades
- Ambientes híbridos Active Directory + Microsoft 365

---

# Roadmap

Próximas automações previstas:

- Gestão de licenças por grupo do Active Directory
- Conversão automática para Shared Mailbox após desligamento
- Relatórios de consumo de licenças
- Auditoria de usuários sem uso
- Gestão de grupos Microsoft 365
- Provisionamento automático de caixas compartilhadas

---

# Autor

Bruno Sousa Feitoza da Silva

Infrastructure Specialist | Microsoft 365 | Active Directory | PowerShell | VMware | Linux | Cloud

LinkedIn:
https://www.linkedin.com/in/brunofeitoza

GitHub:
https://github.com/brunofs-droid

---

⭐ Caso este projeto tenha sido útil, considere deixar uma estrela no repositório.
