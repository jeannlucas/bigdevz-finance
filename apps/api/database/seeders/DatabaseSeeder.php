<?php

namespace Database\Seeders;

use App\Actions\Payables\CreatePayable;
use App\Actions\Payables\PayPayable;
use App\Actions\Receivables\CreateAgreement;
use App\Actions\Receivables\IdempotentOperations;
use App\Actions\Receivables\ReceiveInstallment;
use App\Models\Space;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Database\Seeder;
use RuntimeException;

/**
 * Dados exclusivamente fictícios para desenvolvimento local. A senha é
 * pública por design e, por isso, o seeder se recusa a rodar em produção.
 */
class DatabaseSeeder extends Seeder
{
    public const EMAIL = 'demo@example.com';

    public const PASSWORD = 'demo-bigdevz-local';

    public function run(): void
    {
        if (app()->isProduction()) {
            throw new RuntimeException('Seed demonstrativo bloqueado em produção.');
        }

        $user = User::query()->firstOrCreate(
            ['email' => self::EMAIL],
            ['name' => 'Jeann Lucas', 'password' => self::PASSWORD, 'email_verified_at' => now()],
        );

        if ($user->name !== 'Jeann Lucas') {
            $user->update(['name' => 'Jeann Lucas']);
        }

        $pf = $user->spaces()->where('kind', 'PF')->firstOrFail();
        $pj = $user->spaces()->where('kind', 'PJ')->firstOrFail();

        $this->seedPersonalSpace($user, $pf);
        $this->seedCorporateSpace($user, $pj);
    }

    private function seedPersonalSpace(User $user, Space $space): void
    {
        // 1. Contas Bancárias PF com saldos expressivos e diversificados
        $nubank = $space->accounts()->firstOrCreate(
            ['name' => 'Nubank Principal'],
            ['opening_balance_cents' => 845020, 'opening_balance_date' => '2026-01-01'], // R$ 8.450,20
        );

        $itau = $space->accounts()->firstOrCreate(
            ['name' => 'Itaú Personalité'],
            ['opening_balance_cents' => 1480000, 'opening_balance_date' => '2026-01-01'], // R$ 14.800,00
        );

        $inter = $space->accounts()->firstOrCreate(
            ['name' => 'Inter Investimentos'],
            ['opening_balance_cents' => 3250000, 'opening_balance_date' => '2026-01-01'], // R$ 32.500,00
        );

        $dinheiro = $space->accounts()->firstOrCreate(
            ['name' => 'Dinheiro / Carteira'],
            ['opening_balance_cents' => 65000, 'opening_balance_date' => '2026-01-01'], // R$ 650,00
        );

        $createAgreement = app(CreateAgreement::class);
        $receiveInstallment = app(ReceiveInstallment::class);
        $createPayable = app(CreatePayable::class);
        $payPayable = app(PayPayable::class);

        $today = Carbon::today();

        // 2. Acordos / Contas a Receber PF
        if ($space->agreements()->doesntExist()) {
            // Acordo 1: Consultoria Técnica (3 parcelas - 1ª recebida, 2ª e 3ª vincendas)
            $agrConsultoria = $createAgreement->handle(
                $space,
                'Consultoria Técnica de Software',
                '15000.00',
                3,
                $today->copy()->subDays(15)->format('Y-m-d'),
            );
            $installmentsConsultoria = $agrConsultoria->installments()->orderBy('number')->get();
            // Recebe 1ª parcela no Nubank
            $receiveInstallment->handle(
                $user,
                $space,
                $installmentsConsultoria[0]->id,
                $nubank->id,
                500000,
                $today->copy()->subDays(14)->format('Y-m-d'),
                'seed-pf-rec-consultoria-1',
            );

            // Acordo 2: Venda Notebook Usado (2 parcelas - 1ª vencida há 5 dias para o sininho!)
            $createAgreement->handle(
                $space,
                'Venda Notebook Dell i7',
                '3600.00',
                2,
                $today->copy()->subDays(5)->format('Y-m-d'),
            );

            // Acordo 3: Aluguel Apartamento (1 parcela a vencer em 10 dias)
            $createAgreement->handle(
                $space,
                'Aluguel Apartamento Praia',
                '2400.00',
                1,
                $today->copy()->addDays(10)->format('Y-m-d'),
            );
        }

        // 3. Contas a Pagar PF
        if ($space->payables()->doesntExist()) {
            // Conta 1: Financiamento Imobiliário (Vencida há 3 dias -> sininho e alerta!)
            $p1Data = [
                'description' => 'Financiamento Imobiliário Caixa',
                'payee' => 'Caixa Econômica',
                'amount' => '2850.00',
                'due_date' => $today->copy()->subDays(3)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p1Data,
                'seed-pf-pay-financ',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p1Data),
            );

            // Conta 2: Fatura Nubank Ultravioleta (A vencer em 5 dias)
            $p2Data = [
                'description' => 'Fatura Cartão Nubank Ultravioleta',
                'payee' => 'Nubank Cartões',
                'amount' => '4250.80',
                'due_date' => $today->copy()->addDays(5)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p2Data,
                'seed-pf-pay-fatura-nu',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p2Data),
            );

            // Conta 3: Aluguel Residencial (A vencer em 10 dias)
            $p3Data = [
                'description' => 'Aluguel Residencial',
                'payee' => 'Imobiliária Aliança',
                'amount' => '3200.00',
                'due_date' => $today->copy()->addDays(10)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p3Data,
                'seed-pf-pay-aluguel',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p3Data),
            );

            // Conta 4: Plano de Saúde Unimed (PAGA via Itaú)
            $p4Data = [
                'description' => 'Plano de Saúde Unimed',
                'payee' => 'Unimed Seguros',
                'amount' => '1150.00',
                'due_date' => $today->copy()->subDays(10)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p4Data,
                'seed-pf-pay-unimed',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p4Data),
            );
            $p4Payable = $space->payables()->where('description', $p4Data['description'])->firstOrFail();
            $payPayable->handle(
                $user,
                $space,
                $p4Payable->id,
                $itau->id,
                115000,
                $today->copy()->subDays(9)->format('Y-m-d'),
                'seed-pf-payment-unimed',
            );

            // Conta 5: Energia Elétrica (PAGA via Nubank)
            $p5Data = [
                'description' => 'Energia Elétrica Enel',
                'payee' => 'Enel Distribuição',
                'amount' => '480.50',
                'due_date' => $today->copy()->subDays(12)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p5Data,
                'seed-pf-pay-enel',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p5Data),
            );
            $p5Payable = $space->payables()->where('description', $p5Data['description'])->firstOrFail();
            $payPayable->handle(
                $user,
                $space,
                $p5Payable->id,
                $nubank->id,
                48050,
                $today->copy()->subDays(11)->format('Y-m-d'),
                'seed-pf-payment-enel',
            );

            // Conta 6: Internet Fibra Óptica (A vencer em 18 dias)
            $p6Data = [
                'description' => 'Internet Fibra Óptica 1Gbps',
                'payee' => 'Vivo Telecom',
                'amount' => '199.90',
                'due_date' => $today->copy()->addDays(18)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $p6Data,
                'seed-pf-pay-internet',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $p6Data),
            );
        }
    }

    private function seedCorporateSpace(User $user, Space $space): void
    {
        // 1. Contas Bancárias PJ corporativas
        $itauPj = $space->accounts()->firstOrCreate(
            ['name' => 'Itaú Empresas'],
            ['opening_balance_cents' => 8540000, 'opening_balance_date' => '2026-01-01'], // R$ 85.400,00
        );

        $cora = $space->accounts()->firstOrCreate(
            ['name' => 'Cora SCD'],
            ['opening_balance_cents' => 4210000, 'opening_balance_date' => '2026-01-01'], // R$ 42.100,00
        );

        $btg = $space->accounts()->firstOrCreate(
            ['name' => 'BTG Pactual Empresas'],
            ['opening_balance_cents' => 15000000, 'opening_balance_date' => '2026-01-01'], // R$ 150.000,00
        );

        $createAgreement = app(CreateAgreement::class);
        $receiveInstallment = app(ReceiveInstallment::class);
        $createPayable = app(CreatePayable::class);
        $payPayable = app(PayPayable::class);

        $today = Carbon::today();

        // 2. Acordos / Contas a Receber PJ
        if ($space->agreements()->doesntExist()) {
            // Acordo 1: Contrato Anual Cliente Corporativo Alfa (12 parcelas - 3 recebidas, 1 a vencer em breve)
            $agrAlfa = $createAgreement->handle(
                $space,
                'Contrato de Desenvolvimento Software Cliente Alfa',
                '120000.00',
                12,
                $today->copy()->subMonths(2)->format('Y-m-d'),
            );
            $installmentsAlfa = $agrAlfa->installments()->orderBy('number')->get();
            // Recebe parcelas 1 e 2 no Itaú Empresas
            $receiveInstallment->handle(
                $user,
                $space,
                $installmentsAlfa[0]->id,
                $itauPj->id,
                1000000,
                $today->copy()->subMonths(2)->format('Y-m-d'),
                'seed-pj-rec-alfa-1',
            );
            $receiveInstallment->handle(
                $user,
                $space,
                $installmentsAlfa[1]->id,
                $itauPj->id,
                1000000,
                $today->copy()->subMonth()->format('Y-m-d'),
                'seed-pj-rec-alfa-2',
            );

            // Acordo 2: Projeto Mobile Cliente Beta (3 parcelas - 1 recebida, 2ª vencida há 2 dias -> sininho PJ!)
            $agrBeta = $createAgreement->handle(
                $space,
                'Projeto App Mobile Cliente Beta',
                '45000.00',
                3,
                $today->copy()->subMonth()->format('Y-m-d'),
            );
            $installmentsBeta = $agrBeta->installments()->orderBy('number')->get();
            $receiveInstallment->handle(
                $user,
                $space,
                $installmentsBeta[0]->id,
                $cora->id,
                1500000,
                $today->copy()->subMonth()->format('Y-m-d'),
                'seed-pj-rec-beta-1',
            );
            // Parcela 2 vencida há 2 dias
            $installmentsBeta[1]->update(['due_date' => $today->copy()->subDays(2)->format('Y-m-d')]);

            // Acordo 3: SLA Suporte Mensal (A vencer em 15 dias)
            $createAgreement->handle(
                $space,
                'SLA Suporte 24/7 Sistemas Cloud',
                '8500.00',
                1,
                $today->copy()->addDays(15)->format('Y-m-d'),
            );
        }

        // 3. Contas a Pagar PJ
        if ($space->payables()->doesntExist()) {
            // Conta 1: Imposto DAS Simples Nacional (VENCIDA há 4 dias -> sininho PJ!)
            $pj1Data = [
                'description' => 'Guia DAS Simples Nacional Competência Passada',
                'payee' => 'Receita Federal do Brasil',
                'amount' => '12350.00',
                'due_date' => $today->copy()->subDays(4)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj1Data,
                'seed-pj-pay-das',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj1Data),
            );

            // Conta 2: Folha de Pagamento TI (PAGA via Itaú Empresas)
            $pj2Data = [
                'description' => 'Folha de Pagamento Desenvolvedores TI',
                'payee' => 'Equipe de Engenharia',
                'amount' => '38500.00',
                'due_date' => $today->copy()->subDays(6)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj2Data,
                'seed-pj-pay-folha',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj2Data),
            );
            $pj2Payable = $space->payables()->where('description', $pj2Data['description'])->firstOrFail();
            $payPayable->handle(
                $user,
                $space,
                $pj2Payable->id,
                $itauPj->id,
                3850000,
                $today->copy()->subDays(5)->format('Y-m-d'),
                'seed-pj-payment-folha',
            );

            // Conta 3: Servidores AWS Cloud (A vencer em 8 dias)
            $pj3Data = [
                'description' => 'Servidores e Infraestrutura AWS Cloud',
                'payee' => 'Amazon Web Services',
                'amount' => '7420.00',
                'due_date' => $today->copy()->addDays(8)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj3Data,
                'seed-pj-pay-aws',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj3Data),
            );

            // Conta 4: Aluguel Coworking Corporativo (A vencer em 12 dias)
            $pj4Data = [
                'description' => 'Aluguel Escritório Corporativo',
                'payee' => 'WeWork Brasil',
                'amount' => '5800.00',
                'due_date' => $today->copy()->addDays(12)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj4Data,
                'seed-pj-pay-coworking',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj4Data),
            );

            // Conta 5: Licenças de Software (PAGA via Cora)
            $pj5Data = [
                'description' => 'Licenças JetBrains All Products & GitHub Enterprise',
                'payee' => 'JetBrains s.r.o.',
                'amount' => '2400.00',
                'due_date' => $today->copy()->subDays(8)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj5Data,
                'seed-pj-pay-licenses',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj5Data),
            );
            $pj5Payable = $space->payables()->where('description', $pj5Data['description'])->firstOrFail();
            $payPayable->handle(
                $user,
                $space,
                $pj5Payable->id,
                $cora->id,
                240000,
                $today->copy()->subDays(7)->format('Y-m-d'),
                'seed-pj-payment-licenses',
            );

            // Conta 6: Contabilidade Especializada (A vencer em 20 dias)
            $pj6Data = [
                'description' => 'Honorários Contabilidade Especializada',
                'payee' => 'Contabilizei Tecnologia',
                'amount' => '1800.00',
                'due_date' => $today->copy()->addDays(20)->format('Y-m-d'),
            ];
            $createPayable->single(
                $user,
                $space,
                $pj6Data,
                'seed-pj-pay-contab',
                CreatePayable::fingerprint(IdempotentOperations::PAYABLE, $space, $pj6Data),
            );
        }
    }
}
