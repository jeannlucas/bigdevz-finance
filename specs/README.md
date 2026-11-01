# Camada de Especificações Permanentes (L2 - Specs)

> **Governança Oficial de Engenharia:** BigDev.Z Engineering Standard<br>
> **Filosofia:** *Spec-Anchored*. O código responde a contratos duradouros e especificações permanentes, não a palpites ou conversas voláteis. Qualquer divergência entre o código e a especificação é tratada como defeito de primeira classe.

---

## 1. O que são as Specs L2?

As especificações da pasta `specs/` definem formalmente os contratos de negócio, regras arquiteturais, limites e comportamentos esperados de cada capacidade (*capability*) do sistema.

Diferente de planos efêmeros (L3) que guiam apenas a sessão imediata de trabalho e são descartados ou consolidados no handoff após a conclusão da tarefa, as especificações em `specs/` são **permanentes e vivas**.

---

## 2. Estrutura de Diretórios

Cada *capability* relevante possui seu próprio subdiretório e especificação correspondente:

```
specs/
├── README.md               # Este guia da camada de especificações
├── TEMPLATE.md             # Modelo oficial para novas especificações
└── financeiro/             # Capability de gestão patrimonial e motor financeiro
    └── financeiro.md       # Especificação permanente com AC-FIN-001 a AC-FIN-016
```

---

## 3. Padrão de Nomenclatura dos Critérios de Aceite

Todo critério de aceite deve ser unívoco, identificável e rastreável no código e nos testes:

- Formato: `AC-<SIGLA>-<NUMERO>`
- Exemplos:
  - `AC-FIN-001`: Proibição estrita de float/double para valores monetários.
  - `AC-FIN-005`: Distribuição determinística de centavos restantes em parcelas.
  - `AC-FIN-015`: Chave de idempotência e serialização sob concorrência.

---

## 4. O Ciclo TDD Ancorado em Specs

1. **Identificação do AC:** Localize ou redija o critério de aceite (`AC-XXX-00X`) na spec correspondente antes de iniciar a implementação.
2. **Teste Vermelho (Red):** Escreva o teste automatizado (unitário ou integração) mencionando expressamente o critério de aceite.
3. **Código Mínimo (Green):** Implemente estritamente o código necessário para fazer o teste passar.
4. **Refatoração (Refactor):** Limpe o código, removendo duplicações (DRY) e complexidades desnecessárias (YAGNI).
5. **Backpressure Pré-Push:** Execute o script `check` (`./scripts/check.sh`) para comprovar 100% de sucesso pré-push.
