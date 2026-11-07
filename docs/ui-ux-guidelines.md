# BigDev.Z Finance — Diretrizes de UX/UI Multiplataforma (Desktop Web & Mobile)

> **Autoridade:** Padrão Oficial de Design e Engenharia de Interface BigDev.Z de Jeann Lucas.<br>
> **Filosofia Central:** O melhor produto não força uma interface única para ambientes distintos. O design responde com excelência ergonômica tanto ao toque no smartphone quanto ao mouse e teclado no monitor widescreen (*Platform-Tailored Design*).

---

## 1. Princípio Mandatório de Experiência do Usuário (UX/UI)

Toda e qualquer nova tela, fluxo, componente ou refatoração no BigDev.Z Finance **DEVE ser concebida e validada considerando as particularidades de UX e UI de ambas as plataformas**:

1. **Desktop Web** (Telas amplas, mouse, atalhos de teclado, monitores de 1080p a 4K).
2. **Mobile** (Telas compactas de 375pt a 430pt, toque direto, rolagem vertical, insets dinâmicos).

> [!IMPORTANT]
> **Diferenciação é Encorajada:** Não se deve forçar uma tela de celular esticada no desktop, nem empobrecer a experiência mobile para imitar um painel web. É expressamente permitido e mandatório adotar abordagens de layout e navegação distintas quando isso entregar a melhor ergonomia em cada formato.

---

## 2. Diretrizes Específicas para Desktop Web

Em telas com largura $\ge 840\text{px}$:

### 2.1. Controle Estrito de Largura Máxima (*Max Width Constraint*)
- **Proibição de Estiramento:** É proibido permitir que formulários, cartões de cadastro e botões de ação estiquem de ponta a ponta em monitores largos (1920px+).
- **Largura Máxima de Formulários:** Telas de cadastro e edição devem conter seus campos dentro de um container centralizado (`ConstrainedBox` / `Center`) com largura máxima recomendada entre **`520px` e `640px`**, ou serem apresentadas em **Modais/Diálogos Executivos** (`Dialog` / `showDialog`).
- **Cards com Fundo e Elevação:** Em vez de campos flutuando no vazio da tela, envolva o formulário em um card elegante com bordas suaves (`AppTokens.r16`) e contraste adequado com o fundo escuro/claro.

### 2.2. Disposição Multi-Colunas para Campos Complementares
- Campos curtos e logicamente conectados **NÃO devem ser empilhados em linhas gigantescas**:
  - *Exemplo:* `Quantidade de parcelas` e `Primeiro vencimento` devem ficar lado a lado em 2 colunas (`Row` com `Expanded`).
  - *Exemplo:* `Valor` e `Data do pagamento` devem ser agrupados lado a lado.

### 2.3. Ações e Botões Proporcionais
- Botões de confirmação devem ter largura intrínseca proporcional ao conteúdo ou alinhados ao container do formulário, nunca formando barras horizontais de 2000px.
- Textos de ação devem ser inequívocos (ex: *"Salvar conta a receber"*, *"Confirmar recebimento"* em vez de termos genéricos como *"Gerar parcelas"* quando a operação puder ser à vista).

### 2.4. Navegação por Sidebar Lateral
- Monitores largos utilizam a navegação lateral persistente (`_DesktopSidebar`), liberando a altura vertical da tela e facilitando a troca rápida de contexto.

---

## 3. Diretrizes Específicas para Mobile (Smartphones)

Em telas com largura $< 840\text{px}$ (viewport 375pt a 430pt):

### 3.1. Ergonomia e Zona do Polegar (*Thumb Zone*)
- Ações primárias e formulários devem priorizar alcance fácil com uma mão.
- Modais rápidos de ação e formulários enxutos adotam **Bottom Sheets** deslizantes fixados na base da tela.

### 3.2. Largura Total com Margens Padronizadas
- No mobile, os campos ocupam a largura total disponível respeitando o padding lateral do design system (`16pt` a `20pt` via `AppTokens`).
- Elementos são empilhados verticalmente em lista rolável (`ListView`), garantindo que o teclado virtual nunca cubra botões de ação ou inputs ativos.

### 3.3. Acessibilidade e Alvos de Toque
- Altura mínima interativa de **48pt** para qualquer botão, campo ou seletor de toque (`kMinInteractiveDimension`).
- Suporte a escalas de texto de **150% e 200%** via `AccessibleFieldWrapper`, sem truncamento com reticências em rótulos vitais de formulários e valores financeiros.

---

## 4. Padrões de Usabilidade e Negócio Compartilhados

Independentemente da plataforma, as seguintes regras de negócio em UX devem ser mantidas:

1. **Valores Padrão Não Induzem a Erro:**
   - Em contas a receber e parcelamentos, o padrão inicial da quantidade de parcelas é sempre **`1`** (à vista / parcela única).
   - Se o usuário desejar parcelar, ele altera conscientemente o número de parcelas. Isso evita que receitas avulsas (como salários ou vendas pontuais) sejam acidentalmente fatiadas em 12 vezes.
2. **Clareza de Ação Imediata (Atalho de Baixa):**
   - Ao lançar uma receita ou despesa que já ocorreu no momento do cadastro, fornecer a opção direta de liquidar/receber na conta de destino sem obrigar o usuário a navegar por múltiplas telas subsequentes.
3. **Feedback Imediato e Determinístico:**
   - Toda gravação ou erro exibe mensagens claras, com validação de campos ancorada aos limites monetários e de datas do sistema.

---

## 5. Matriz de Decisão Responsiva no Flutter

Ao implementar ou refatorar qualquer interface, utilize o padrão adaptativo consolidado do repositório:

```dart
final isDesktop = MediaQuery.sizeOf(context).width >= 840;

if (isDesktop) {
  // Layout Desktop Web:
  // - Sidebar lateral
  // - Card ou Modal centralizado com maxWidth: 560 a 640
  // - Campos lado a lado em 2 colunas
  return Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 580),
      child: Card(child: ...),
    ),
  );
}

// Layout Mobile:
// - Layout vertical em largura de tela com padding de 16pt
// - BottomSheet ou tela cheia com AppBar
return ListView(
  padding: const EdgeInsets.all(AppTokens.p16),
  children: [...],
);
```

---

## 6. Rastreabilidade e Auditoria
Qualquer novo Pull Request ou entrega de feature que envolva interface gráfica deve evidenciar conformidade com este documento tanto no emulador mobile quanto no navegador Web Desktop.
