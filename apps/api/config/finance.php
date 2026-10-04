<?php

return [
    // Fuso usado para datas de calendário ("hoje", vencidas). Instantes de
    // auditoria continuam em UTC (timestamptz).
    'timezone' => env('FINANCE_TIMEZONE', 'America/Sao_Paulo'),
];
