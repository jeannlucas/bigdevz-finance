# Plano incremental do checkpoint 1

Especificação: `financeiro-pf-pj-escopo-e-prompt-inicial.md`, seção 7.
Execução local, preservando documentos existentes; não depender de plugins.

1. Revalidar ferramentas, Git, rede, Docker e identidade GitHub. Registrar
   separadamente restrições da sessão, ausência no PATH e fatos não confirmados.
2. Implementar o núcleo puro PHP de valores e cronograma em
   `apps/api/app/Domain/Receivables`, com testes primeiro e sem dependências
   externas. Contrato planejado: strings decimais canônicas com duas casas;
   cálculo em centavos inteiros; limite explícito de R$ 999.999.999.999,99.
   Gerar parcelas numeradas, distribuir centavos extras nas primeiras e
   preservar o dia do primeiro vencimento, incluindo fevereiro e ano bissexto.
   Recusar entradas inválidas, parcelas zeradas e datas fora de 0001–9999.
3. Quando os acessos necessários forem liberados, criar Laravel, PostgreSQL
   de desenvolvimento/teste e autenticação. Integrar o núcleo ao caso de uso
   transacional; testar isolamento, idempotência, rollback e concorrência reais.
4. Instalar/configurar Flutter, integrar login, PF/PJ, contas, acordo e recebimento;
   testar apresentação e integração; validar iOS e Android separadamente.
5. Gerar lockfiles e CI das aplicações reais, atualizar documentação, revisar
   diff e publicar no proprietário confirmado. Licença permanece pendente.

O item 2 não substitui persistência, API ou aplicativo. Testes do núcleo não
comprovam os cenários de aceitação que dependem do banco ou de dispositivos.
