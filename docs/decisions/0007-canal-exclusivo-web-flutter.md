# 7. Canal Oficial Exclusivo via Navegador (Flutter Web Desktop e Mobile) e Congelamento de Lojas Nativas

> **Data:** 2026-11-21  
> **Status:** Aprovada  
> **Decisores:** Jeann Lucas  
> **Contexto:** Incidente de release v1.3.0, evolução da arquitetura de distribuição e estratégia de produto.

---

## 1. Contexto e Motivação

O BigDev.Z Finance foi concebido com uma base de código Flutter compartilhada para atender clientes em múltiplas plataformas. Historicamente, mantinha-se a premissa de distribuição nativa em lojas de aplicativos (Google Play Store e Apple App Store) paralelamente ao suporte a navegadores.

Entretanto, as demandas operacionais, burocráticas e de ciclo de revisão das lojas de aplicativos introduzem atrito desproporcional neste estágio do produto, além de dispersarem os esforços de garantia de qualidade e automação de release. Além disso, a versão web do Flutter evoluiu significativamente, suportando navegação responsiva em telas largas (Desktop Web) e telas estreitas (Mobile Web via Safari, Chrome e Firefox em smartphones) com ergonomia dedicada.

Na release v1.3.0, observou-se também que a falta de centralização no canal web fez com que o pipeline de deploy priorizasse exclusivamente a imagem Docker do backend, deixando o bundle web desatualizado no servidor de produção sem que as verificações pós-deploy detectassem a divergência.

---

## 2. Decisão

1. **Canal Oficial Exclusivo:** O BigDev.Z Finance passa a ser disponibilizado, homologado e operado **exclusivamente via navegador**, cobrindo:
   - **Desktop Web:** Widescreen (>= 840px / 1200px), com painéis executivos, tabelas analíticas, ordenação, atalhos de teclado e modais centrados.
   - **Mobile Web:** Telas estreitas (< 840px / 375px), com cards verticais, bottom sheets adaptativos, comportamento resiliente sob teclado do sistema e layout responsivo.
2. **Congelamento de Publicação em Lojas Nativas:**
   - A submissão, assinatura de certificados de lojas, builds de bundles AAB/IPA para Google Play e Apple App Store e tarefas específicas de distribuição por lojas ficam formalmente **congeladas**.
   - Ficam dispensadas etapas de publicação em esteiras de CI/CD para lojas móveis.
3. **Preservação da Base de Código Flutter Compartilhada:**
   - A base única em Flutter (`apps/mobile/`) é integralmente mantida.
   - Toda funcionalidade deve atender com excelência ergonômica tanto a visualização em desktop quanto em navegador mobile.
4. **Alvo de Publicação e Homologação:**
   - O artefato oficial de frontend do produto é o bundle **Flutter Web de produção** (`apps/mobile/build/web/`), compilado com `--dart-define=APP_ENV=production` e `--dart-define=API_BASE_URL=https://finance.bigdevz.com/api`.
   - Toda homologação de produto e validação de qualidade deve ser realizada sobre o canal web (desktop e mobile).

---

## 3. Consequências e Impacto Técnico

- **Pipeline de Deploy:** O workflow de deploy de produção (`.github/workflows/deploy.yml`) deve compilar compulsoriamente o Flutter Web de produção, empacotar os assets compilados junto à release e promover atomicamente os arquivos estáticos no servidor web (`/srv/finance/web/`).
- **Barreira Dupla de Release:** Nenhum deploy de produção é considerado bem-sucedido sem a verificação simultânea de:
  1. Revisão e liveness da API em `/api/health` correspondendo ao SHA homologado.
  2. Hash SHA-256 do JavaScript principal (`main.dart.js`) obtido publicamente via HTTPS, idêntico ao hash do bundle compilado para a mesma release.
- **Simplificação Operacional:** Eliminação de complexidades relacionadas a revisões de lojas, assinaturas binárias e tempos de aprovação de terceiros. Atualizações e correções chegam instantaneamente a todos os usuários em qualquer dispositivo.
