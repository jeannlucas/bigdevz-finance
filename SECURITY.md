# Política de Segurança — BigDev.Z Finance

A segurança e a integridade matemática e financeira do **BigDev.Z Finance** são prioridades fundamentais. Agradecemos o apoio da comunidade de segurança na identificação e correção de eventuais vulnerabilidades por meio de divulgação responsável (*Responsible Disclosure*).

---

## 1. Versões Suportadas

Atualmente, apenas as versões mais recentes das branches principais recebem atualizações de segurança e correções ativas:

| Branch / Versão | Suporte Ativo | Notas |
| :--- | :--- | :--- |
| `main` | ✅ Sim | Versão estável consolidada do repositório público. |
| `dev` | ✅ Sim | Branch de desenvolvimento ativo de novas funcionalidades. |
| Versões / Tags anteriores | ❌ Não | Recomenda-se atualizar para o commit mais recente de `main`. |

---

## 2. Como Reportar uma Vulnerabilidade

> [!IMPORTANT]
> **NUNCA** abra uma *Issue* pública ou discussão no GitHub para relatar potenciais vulnerabilidades de segurança ou exploits.

Para reportar uma vulnerabilidade de forma responsável:

1. **Procedimento de Reporte:**
   - Acesse a aba **Security** do repositório: [https://github.com/jeannlucas/bigdevz-finance/security](https://github.com/jeannlucas/bigdevz-finance/security).
   - Quando o recurso *Private Vulnerability Reporting* estiver ativo na interface do repositório, utilize o botão oficial **"Report a vulnerability"** para enviar o relatório confidencial diretamente aos mantenedores.
   - Caso o recurso de reporte privado ainda não esteja exibido ou habilitado nas configurações do GitHub, entre em contato diretamente com o mantenedor através do perfil oficial do GitHub ([@jeannlucas](https://github.com/jeannlucas)) para solicitar o estabelecimento de canal privado e seguro antes de compartilhar qualquer detalhe técnico.

2. **Informações Úteis para o Relatório:**
   - Descrição detalhada do problema (ex.: isolamento multi-tenant, concorrência, validação de entrada, integridade transacional).
   - Passos reprodutíveis detalhados ou script de prova de conceito (*PoC*) sintético.
   - Componentes afetados (`apps/api` ou `apps/mobile`).
   - Avaliação preliminar de severidade e impacto.

---

## 3. Diretrizes de Confidencialidade e Boas Práticas

Pedimos aos pesquisadores de segurança que:
- **Não explorem a vulnerabilidade além do necessário** para demonstrar o problema com dados sintéticos locais.
- **Não incluam dados pessoais reais (PII)**, tokens de terceiros, chaves privadas ou dados de produção nos relatórios.
- **Aguardem a confirmação e mitigação** pelo mantenedor antes de divulgar qualquer detalhe publicamente.

---

## 4. Compromisso de Resposta

O projeto é mantido em formato open source (*Build in Public*). Cada relatório será analisado com seriedade pelo mantenedor, priorizando a correção rápida e determinística de falhas de segurança antes de sua publicação na branch principal.
