<?php

namespace App\Actions\Payables;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Models\Payable;
use App\Models\PayablePlan;
use App\Models\Recurrence;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;

/**
 * Cadastra obrigações com chave idempotente: avulsa, parcelada (todas as
 * parcelas de uma vez, pelo cronograma do núcleo) ou recorrência mensal (com
 * as ocorrências até o horizonte). Repetir a chave não duplica nada. Nenhuma
 * delas movimenta conta.
 */
class CreatePayable
{
    /** Limite do conjunto inicial de uma recorrência (10 anos de ciclos). */
    public const MAX_INITIAL_OCCURRENCES = 120;

    /** Itens detalhados na prévia; os totais cobrem o período inteiro. */
    public const PREVIEW_ITEMS = 24;

    public function __construct(
        private readonly IdempotentOperations $keys,
        private readonly GenerateObligations $generate,
    ) {}

    /** @param array<string, mixed> $data campos validados */
    public static function fingerprint(string $operation, Space $space, array $data): string
    {
        ksort($data);

        return IdempotentOperations::fingerprint($operation, $space->id, $data);
    }

    /** @param array{description: string, payee: ?string, amount: string, due_date: string} $data */
    public function single(User $user, Space $space, array $data, string $key, string $fingerprint): KeyedResult
    {
        return $this->keys->run($user, $space, $key, IdempotentOperations::PAYABLE, $fingerprint, function () use ($space, $data) {
            $payable = Payable::create([
                'space_id' => $space->id, 'kind' => Payable::SINGLE, 'description' => $data['description'],
                'payee' => $data['payee'] ?? null, 'amount_cents' => Money::toCents($data['amount']), 'due_date' => $data['due_date'],
            ]);

            return ['payable_id' => $payable->id];
        });
    }

    /** @param array{description: string, payee: ?string, total: string, installment_count: int, first_due_date: string} $data */
    public function installments(User $user, Space $space, array $data, string $key, string $fingerprint): KeyedResult
    {
        return $this->keys->run($user, $space, $key, IdempotentOperations::PAYABLE, $fingerprint, function () use ($space, $data) {
            $schedule = self::schedule($data['total'], (int) $data['installment_count'], $data['first_due_date']);
            $plan = PayablePlan::create([
                'space_id' => $space->id, 'description' => $data['description'], 'payee' => $data['payee'] ?? null,
                'total_cents' => Money::toCents($data['total']), 'installment_count' => (int) $data['installment_count'],
                'first_due_date' => $data['first_due_date'],
            ]);
            foreach ($schedule as $item) {
                Payable::create([
                    'space_id' => $space->id, 'kind' => Payable::INSTALLMENT,
                    'description' => $data['description'], 'payee' => $data['payee'] ?? null,
                    'amount_cents' => Money::toCents($item['amount']), 'due_date' => $item['due_date'],
                    'plan_id' => $plan->id, 'installment_number' => $item['number'],
                ]);
            }

            return ['payable_plan_id' => $plan->id];
        });
    }

    /**
     * Cria a recorrência e exatamente o conjunto inicial aprovado: ciclos do
     * início até approved_until (e o término). O conjunto depende só do
     * conteúdo enviado, não da data em que a API recebe o pedido; ciclos
     * seguintes vêm da geração automática. Ocorrências já vencidas exigem
     * confirm_past.
     *
     * @param  array{description: string, payee: ?string, amount: string, start_date: string, end_date: ?string, approved_until: string, confirm_past: bool}  $data
     */
    public function recurrence(User $user, Space $space, array $data, string $key, string $fingerprint): KeyedResult
    {
        return $this->keys->run($user, $space, $key, IdempotentOperations::RECURRENCE, $fingerprint, function () use ($space, $data) {
            $plan = self::initialPlan($data['start_date'], $data['end_date'] ?? null, $data['approved_until']);
            if ($data['approved_until'] > GenerateObligations::horizon()) {
                throw ValidationException::withMessages([
                    'approved_until' => 'O período aprovado vai além do horizonte atual. Revise a recorrência de novo.',
                ]);
            }
            $past = self::pastOf($plan, Money::toCents($data['amount']));
            if ($past['count'] > 0 && ! filter_var($data['confirm_past'], FILTER_VALIDATE_BOOLEAN)) {
                throw ValidationException::withMessages([
                    'confirm_past' => "Confirme a criação das {$past['count']} ocorrências já vencidas (total ".Money::fromCents($past['total_cents']).').',
                ]);
            }
            $recurrence = Recurrence::create([
                'space_id' => $space->id, 'description' => $data['description'], 'payee' => $data['payee'] ?? null,
                'amount_cents' => Money::toCents($data['amount']), 'start_date' => $data['start_date'],
                'reference_day' => (int) substr($data['start_date'], 8, 2), 'end_date' => $data['end_date'] ?? null,
                'initial_until' => $data['approved_until'],
            ]);
            $this->generate->forRecurrence(Recurrence::query()->lockForUpdate()->findOrFail($recurrence->id), $data['approved_until']);

            return ['recurrence_id' => $recurrence->id];
        });
    }

    /**
     * Ciclos do conjunto inicial (mesma regra da geração). Recusa período
     * vazio ou acima do limite, com mensagem clara, em vez de truncar.
     *
     * @return list<array{cycle: string, due_date: string}>
     */
    public static function initialPlan(string $start, ?string $end, string $until): array
    {
        $cycles = GenerateObligations::recurrenceCycles($start, (int) substr($start, 8, 2), $end, $until, self::MAX_INITIAL_OCCURRENCES + 1);
        if ($cycles === []) {
            throw ValidationException::withMessages([
                'start_date' => 'Nenhuma ocorrência no período: o início fica depois do horizonte de 12 meses.',
            ]);
        }
        if (count($cycles) > self::MAX_INITIAL_OCCURRENCES) {
            throw ValidationException::withMessages([
                'start_date' => 'O conjunto inicial teria mais de '.self::MAX_INITIAL_OCCURRENCES.' ocorrências. Escolha um início mais recente.',
            ]);
        }

        return $cycles;
    }

    /**
     * @param  list<array{cycle: string, due_date: string}>  $plan
     * @return array{count: int, total_cents: int}
     */
    public static function pastOf(array $plan, int $amountCents): array
    {
        $today = GenerateObligations::today();
        $count = count(array_filter($plan, static fn (array $cycle) => $cycle['due_date'] < $today));

        return ['count' => $count, 'total_cents' => $count * $amountCents];
    }

    /**
     * Cronograma do núcleo (soma exata, centavos nas primeiras parcelas, dia
     * de referência). Usado também na prévia, sem gravar.
     *
     * @return list<array{number: int, amount: string, due_date: string}>
     */
    public static function schedule(string $total, int $count, string $firstDueDate): array
    {
        try {
            return InstallmentSchedule::generate($total, $count, $firstDueDate);
        } catch (InvalidArgumentException $error) {
            throw ValidationException::withMessages(['installment_count' => $error->getMessage()]);
        }
    }
}
