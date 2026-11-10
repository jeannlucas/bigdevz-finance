<?php

namespace App\Services;

use App\Domain\Receivables\Money;
use RuntimeException;

class OfxParserService
{
    /**
     * Faz o parsing de conteúdo OFX (SGML ou XML) e retorna lista de transações limpas.
     *
     * @return array<int, array{
     *     fitid: string,
     *     type: string,
     *     amount_cents: int,
     *     raw_amount: string,
     *     posted_at: string,
     *     memo: string
     * }>
     */
    public function parse(string $content): array
    {
        if (trim($content) === '') {
            throw new RuntimeException('Arquivo OFX vazio ou ilegível.');
        }

        // Converte encodings comuns de bancos brasileiros (ISO-8859-1, Windows-1252) para UTF-8 válido
        if (! mb_check_encoding($content, 'UTF-8')) {
            $converted = @mb_convert_encoding($content, 'UTF-8', ['ISO-8859-1', 'Windows-1252', 'ASCII']);
            if ($converted !== false) {
                $content = $converted;
            }
        }

        // Divide o bloco de transações STMTTRN
        // Suporta tanto formato fechado (<STMTTRN>...</STMTTRN>) quanto SGML sem fechamento
        $transactions = [];
        $seenFitids = [];

        preg_match_all('/<STMTTRN>([\s\S]*?)(?:<\/STMTTRN>|(?=<STMTTRN>)|(?=<\/BANKTRANLIST>)|$)/i', $content, $matches);

        if (empty($matches[1])) {
            return [];
        }

        foreach ($matches[1] as $block) {
            $fitid = $this->extractTag($block, 'FITID');
            $rawAmount = $this->extractTag($block, 'TRNAMT');
            $dtposted = $this->extractTag($block, 'DTPOSTED');
            $memo = $this->extractTag($block, 'MEMO') ?? $this->extractTag($block, 'NAME') ?? 'Lançamento bancário';

            if ($fitid === null || $rawAmount === null || $dtposted === null) {
                continue;
            }

            $fitid = trim($fitid);
            if ($fitid === '' || isset($seenFitids[$fitid])) {
                // Deduplica FITID repetido no mesmo arquivo ou vazio
                continue;
            }

            // Tratamento da data: DTPOSTED pode vir como "20261109120000[-03:EST]" ou "20261109"
            $cleanedDate = substr(preg_replace('/[^0-9]/', '', $dtposted), 0, 8);
            if (strlen($cleanedDate) === 8) {
                $year = (int) substr($cleanedDate, 0, 4);
                $month = (int) substr($cleanedDate, 4, 2);
                $day = (int) substr($cleanedDate, 6, 2);

                if (! checkdate($month, $day, $year)) {
                    // Data inválida ignorada com segurança
                    continue;
                }
                $formattedDate = sprintf('%04d-%02d-%02d', $year, $month, $day);
            } else {
                continue;
            }

            // Validação de formato numérico de valor
            $trimmedAmount = trim($rawAmount);
            if (! preg_match('/^-?\d+(\.\d+)?$/', $trimmedAmount)) {
                continue;
            }

            $isNegative = str_starts_with($trimmedAmount, '-');
            $cleanNumeric = ltrim($trimmedAmount, '-+');

            // Garante duas casas decimais canônicas
            if (! str_contains($cleanNumeric, '.')) {
                $cleanNumeric .= '.00';
            } else {
                $parts = explode('.', $cleanNumeric);
                if (strlen($parts[1]) === 1) {
                    $cleanNumeric .= '0';
                } elseif (strlen($parts[1]) > 2) {
                    $cleanNumeric = $parts[0].'.'.substr($parts[1], 0, 2);
                }
            }

            try {
                $amountCents = Money::toCents($cleanNumeric);
            } catch (\Throwable) {
                // Overflow ou valor excessivo ignorado com segurança
                continue;
            }

            // Descarta valores zerados ou que ultrapassem o teto unitário
            if ($amountCents <= 0 || $amountCents > Money::MAX_CENTS) {
                continue;
            }

            $type = $isNegative ? 'debit' : 'credit';
            $cleanedMemo = trim((string) preg_replace('/[\r\n\t]+/', ' ', $memo));

            $seenFitids[$fitid] = true;
            $transactions[] = [
                'fitid' => $fitid,
                'type' => $type,
                'amount_cents' => $amountCents,
                'raw_amount' => $rawAmount,
                'posted_at' => $formattedDate,
                'memo' => $cleanedMemo !== '' ? $cleanedMemo : 'Lançamento bancário',
            ];
        }

        return $transactions;
    }

    private function extractTag(string $block, string $tag): ?string
    {
        // Busca <TAG>VALOR ou <TAG>VALOR</TAG>
        if (preg_match('/<'.$tag.'>([^<\r\n]+)(?:<\/'.$tag.'>)?/i', $block, $match)) {
            return trim($match[1]);
        }

        return null;
    }
}
