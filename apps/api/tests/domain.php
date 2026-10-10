<?php

declare(strict_types=1);

use App\Domain\Receivables\InstallmentSchedule;
use App\Domain\Receivables\Money;
use App\Domain\Receivables\MonthlyDate;

foreach (glob(__DIR__.'/../app/Domain/Receivables/*.php') ?: [] as $file) {
    require_once $file;
}

function same(mixed $expected, mixed $actual): void
{
    if ($expected !== $actual) {
        throw new RuntimeException('Esperado '.var_export($expected, true).', obtido '.var_export($actual, true));
    }
}

function invalid(callable $operation): void
{
    try {
        $operation();
    } catch (InvalidArgumentException) {
        return;
    }
    throw new RuntimeException('Entrada inválida foi aceita.');
}

$tests = [
    'dinheiro preserva centavos e limite exatos' => static function (): void {
        same(10001, Money::toCents('100.01'));
        same('100.01', Money::fromCents(10001));
        same(99999999999999, Money::toCents('999999999999.99'));
        same('999999999999.99', Money::fromCents(99999999999999));
        same('0.00', Money::fromCents(0));
    },
    'dinheiro recusa formatos ambíguos e overflow' => static function (): void {
        foreach (['1,00', '1.001', '-1.00', '1e3', '01.00', ' 1.00', '1', '1000000000000.00', ''] as $value) {
            invalid(static fn () => Money::toCents($value));
        }
        // Saída aceita saldo negativo (decisão 0006); o teste de sinal está abaixo.
        invalid(static fn () => Money::fromCents(100000000000000));
    },
    'vinte e quatro mil gera doze parcelas de dois mil' => static function (): void {
        $schedule = InstallmentSchedule::generate('24000.00', 12, '2026-01-31');
        same(12, count($schedule));
        same(array_fill(0, 12, '2000.00'), array_column($schedule, 'amount'));
        same(range(1, 12), array_column($schedule, 'number'));
        same('2026-12-31', $schedule[11]['due_date']);
    },
    'cem em tres distribui centavo extra na primeira' => static function (): void {
        $schedule = InstallmentSchedule::generate('100.00', 3, '2026-01-31');
        same(['33.34', '33.33', '33.33'], array_column($schedule, 'amount'));
        same(10000, array_sum(array_map(Money::toCents(...), array_column($schedule, 'amount'))));
    },
    'dia trinta e um volta em marco apos fevereiro' => static function (): void {
        same(['2026-01-31', '2026-02-28', '2026-03-31'], array_column(
            InstallmentSchedule::generate('100.00', 3, '2026-01-31'), 'due_date',
        ));
    },
    'fevereiro bissexto e virada de ano preservam referencia' => static function (): void {
        same(['2027-12-31', '2028-01-31', '2028-02-29', '2028-03-31'], array_column(
            InstallmentSchedule::generate('100.00', 4, '2027-12-31'), 'due_date',
        ));
        same(['2026-04-30', '2026-05-30'], array_column(
            InstallmentSchedule::generate('1.00', 2, '2026-04-30'), 'due_date',
        ));
    },
    'cronograma recusa total zero e parcelas zeradas' => static function (): void {
        invalid(static fn () => InstallmentSchedule::generate('0.00', 1, '2026-01-01'));
        invalid(static fn () => InstallmentSchedule::generate('0.01', 2, '2026-01-01'));
        foreach ([0, -1, 1201] as $count) {
            invalid(static fn () => InstallmentSchedule::generate('100.00', $count, '2026-01-01'));
        }
    },
    'cronograma recusa datas inexistentes e formatos nao canonicos' => static function (): void {
        foreach (['2026-02-29', '2026-04-31', '31/01/2026', '2026-1-01', '0000-01-01', '2026-01-01extra'] as $date) {
            invalid(static fn () => InstallmentSchedule::generate('100.00', 1, $date));
        }
        invalid(static fn () => InstallmentSchedule::generate('100.00', 2, '9999-12-31'));
    },
    'data mensal preserva o dia de referencia em meses curtos e bissextos' => static function (): void {
        same('2026-02-28', MonthlyDate::in(2026, 2, 31));
        same('2028-02-29', MonthlyDate::in(2028, 2, 31));
        same('2028-02-29', MonthlyDate::in(2028, 2, 29));
        same('2026-04-30', MonthlyDate::in(2026, 4, 31));
        same(['2026-01-31', '2026-02-28', '2026-03-31', '2027-01-31'], [
            MonthlyDate::shift('2026-01-31', 0, 31), MonthlyDate::shift('2026-01-31', 1, 31),
            MonthlyDate::shift('2026-01-31', 2, 31), MonthlyDate::shift('2026-01-31', 12, 31),
        ]);
        same('2026-12-15', MonthlyDate::shift('2027-01-15', -1, 15));
        same('2026-02-01', MonthlyDate::cycle('2026-02-28'));
        invalid(static fn () => MonthlyDate::in(2026, 13, 1));
        invalid(static fn () => MonthlyDate::in(2026, 1, 32));
    },
    'saldo negativo sai com sinal; entrada continua sem sinal' => static function (): void {
        same('-250.00', Money::fromCents(-25000));
        same('-0.05', Money::fromCents(-5));
        same('-999999999999.99', Money::fromCents(-99999999999999));
        invalid(static fn () => Money::fromCents(-100000000000000));
        invalid(static fn () => Money::toCents('-1.00'));
    },
    'cronograma de 2028 usa 29 de fevereiro' => static function (): void {
        same(['2028-01-31', '2028-02-29', '2028-03-31'], array_column(InstallmentSchedule::generate('90.00', 3, '2028-01-31'), 'due_date'));
    },
];

$failures = 0;
foreach ($tests as $name => $test) {
    try {
        $test();
        fwrite(STDOUT, 'PASS: '.$name.PHP_EOL);
    } catch (Throwable $error) {
        $failures++;
        fwrite(STDERR, 'FAIL: '.$name.' — '.$error->getMessage().PHP_EOL);
    }
}
fwrite(STDOUT, count($tests).' testes; '.$failures.' falhas.'.PHP_EOL);
exit($failures === 0 ? 0 : 1);
