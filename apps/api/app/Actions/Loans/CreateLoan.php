<?php

namespace App\Actions\Loans;

use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\KeyedResult;
use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Models\Account;
use App\Models\AccountMovement;
use App\Models\Loan;
use App\Models\Payable;
use App\Models\PayablePlan;
use App\Models\Space;
use App\Models\User;
use Illuminate\Validation\ValidationException;
use InvalidArgumentException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

class CreateLoan
{
    public function __construct(private readonly IdempotentOperations $keys) {}

    public static function fingerprint(
        string $kind,
        mixed $principal,
        mixed $total,
        int $count,
        string $firstDueDate,
        ?int $disbursementAccountId,
        ?string $disbursedAt,
        string $title,
        string $counterparty,
        ?string $notes
    ): string {
        return IdempotentOperations::fingerprint(IdempotentOperations::LOAN, 0, [
            'kind' => $kind,
            'principal' => $principal,
            'total' => $total,
            'installment_count' => $count,
            'first_due_date' => $firstDueDate,
            'disbursement_account_id' => $disbursementAccountId,
            'disbursed_at' => $disbursedAt,
            'title' => $title,
            'counterparty' => $counterparty,
            'notes' => $notes,
        ]);
    }

    public function handle(
        User $user,
        Space $space,
        string $kind,
        string $title,
        string $counterparty,
        int $principalCents,
        int $totalCents,
        int $installmentCount,
        string $firstDueDate,
        ?int $disbursementAccountId,
        ?string $disbursedAt,
        ?string $notes,
        string $key
    ): KeyedResult {
        $fingerprint = self::fingerprint(
            $kind,
            Money::fromCents($principalCents),
            Money::fromCents($totalCents),
            $installmentCount,
            $firstDueDate,
            $disbursementAccountId,
            $disbursedAt,
            $title,
            $counterparty,
            $notes
        );

        return $this->keys->run($user, $space, $key, IdempotentOperations::LOAN, $fingerprint, function () use (
            $user,
            $space,
            $kind,
            $title,
            $counterparty,
            $principalCents,
            $totalCents,
            $installmentCount,
            $firstDueDate,
            $disbursementAccountId,
            $disbursedAt,
            $notes
        ) {
            if (! in_array($kind, [Loan::KIND_TAKEN, Loan::KIND_GRANTED], true)) {
                throw ValidationException::withMessages([
                    'kind' => 'O tipo do empréstimo deve ser "taken" (tomado) ou "granted" (concedido).',
                ]);
            }

            if ($principalCents <= 0 || $principalCents > Money::MAX_CENTS) {
                throw ValidationException::withMessages([
                    'principal' => 'O valor principal deve ser maior que zero e menor que o limite suportado.',
                ]);
            }

            if ($totalCents < $principalCents || $totalCents > Money::MAX_CENTS) {
                throw ValidationException::withMessages([
                    'total' => 'O valor total com juros/encargos não pode ser menor que o valor principal.',
                ]);
            }

            if ($installmentCount < 1 || $installmentCount > 1200) {
                throw ValidationException::withMessages([
                    'installment_count' => 'O número de parcelas deve estar entre 1 e 1200.',
                ]);
            }

            if (($disbursementAccountId === null) !== ($disbursedAt === null)) {
                throw ValidationException::withMessages([
                    'disbursement_account_id' => 'Conta e data de desembolso devem ser informadas juntas.',
                ]);
            }

            $disbursementAccount = null;
            if ($disbursementAccountId !== null) {
                $disbursementAccount = Account::query()
                    ->where('id', $disbursementAccountId)
                    ->lockForUpdate()
                    ->first();

                if ($disbursementAccount === null || $disbursementAccount->space_id !== $space->id) {
                    throw new NotFoundHttpException('Conta de desembolso não encontrada no espaço selecionado.');
                }

                if ($disbursementAccount->isArchived()) {
                    throw ValidationException::withMessages([
                        'disbursement_account_id' => 'A conta selecionada para desembolso está arquivada.',
                    ]);
                }

                if ($disbursedAt < $disbursementAccount->opening_balance_date->toDateString()) {
                    throw ValidationException::withMessages([
                        'disbursed_at' => 'A data de desembolso não pode ser anterior à data de abertura da conta.',
                    ]);
                }

                if ($disbursedAt > $firstDueDate) {
                    throw ValidationException::withMessages([
                        'disbursed_at' => 'A data de desembolso não pode ser posterior ao primeiro vencimento.',
                    ]);
                }
            }

            try {
                $schedule = InstallmentSchedule::generate(Money::fromCents($totalCents), $installmentCount, $firstDueDate);
            } catch (InvalidArgumentException $error) {
                throw ValidationException::withMessages(['installment_count' => $error->getMessage()]);
            }

            $loan = null;

            if ($kind === Loan::KIND_TAKEN) {
                $plan = PayablePlan::create([
                    'space_id' => $space->id,
                    'description' => $title,
                    'payee' => $counterparty,
                    'total_cents' => $totalCents,
                    'installment_count' => $installmentCount,
                    'first_due_date' => $firstDueDate,
                ]);

                foreach ($schedule as $item) {
                    Payable::create([
                        'space_id' => $space->id,
                        'kind' => Payable::INSTALLMENT,
                        'description' => $title,
                        'payee' => $counterparty,
                        'amount_cents' => Money::toCents($item['amount']),
                        'due_date' => $item['due_date'],
                        'plan_id' => $plan->id,
                        'installment_number' => $item['number'],
                    ]);
                }

                $loan = Loan::create([
                    'space_id' => $space->id,
                    'user_id' => $user->id,
                    'kind' => Loan::KIND_TAKEN,
                    'title' => $title,
                    'counterparty' => $counterparty,
                    'principal_cents' => $principalCents,
                    'total_cents' => $totalCents,
                    'installment_count' => $installmentCount,
                    'first_due_date' => $firstDueDate,
                    'disbursement_account_id' => $disbursementAccount?->id,
                    'disbursed_at' => $disbursedAt,
                    'status' => Loan::STATUS_ACTIVE,
                    'notes' => $notes,
                    'payable_plan_id' => $plan->id,
                    'agreement_id' => null,
                ]);

                if ($disbursementAccount !== null) {
                    AccountMovement::create([
                        'account_id' => $disbursementAccount->id,
                        'loan_disbursement_id' => $loan->id,
                        'amount_cents' => $principalCents,
                        'effective_date' => $disbursedAt,
                    ]);
                }
            } else {
                $agreement = $space->agreements()->create([
                    'description' => $title,
                    'total_cents' => $totalCents,
                    'installment_count' => $installmentCount,
                    'first_due_date' => $firstDueDate,
                ]);

                $agreement->installments()->createMany(array_map(static fn (array $item) => [
                    'space_id' => $space->id,
                    'number' => $item['number'],
                    'amount_cents' => Money::toCents($item['amount']),
                    'due_date' => $item['due_date'],
                ], $schedule));

                $loan = Loan::create([
                    'space_id' => $space->id,
                    'user_id' => $user->id,
                    'kind' => Loan::KIND_GRANTED,
                    'title' => $title,
                    'counterparty' => $counterparty,
                    'principal_cents' => $principalCents,
                    'total_cents' => $totalCents,
                    'installment_count' => $installmentCount,
                    'first_due_date' => $firstDueDate,
                    'disbursement_account_id' => $disbursementAccount?->id,
                    'disbursed_at' => $disbursedAt,
                    'status' => Loan::STATUS_ACTIVE,
                    'notes' => $notes,
                    'payable_plan_id' => null,
                    'agreement_id' => $agreement->id,
                ]);

                if ($disbursementAccount !== null) {
                    AccountMovement::create([
                        'account_id' => $disbursementAccount->id,
                        'loan_disbursement_id' => $loan->id,
                        'amount_cents' => -$principalCents,
                        'effective_date' => $disbursedAt,
                    ]);
                }
            }

            return ['loan_id' => $loan->id];
        });
    }
}
