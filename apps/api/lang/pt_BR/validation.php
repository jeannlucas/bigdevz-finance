<?php

// Subconjunto usado pela API do checkpoint 1. Regras novas exigem mensagem aqui.
return [
    'before_or_equal' => 'O campo :attribute deve ser uma data igual ou anterior a :date.',
    'between' => ['numeric' => 'O campo :attribute deve estar entre :min e :max.'],
    'date_format' => 'Informe :attribute como data válida no formato AAAA-MM-DD.',
    'email' => 'Informe um e-mail válido.',
    'integer' => 'O campo :attribute deve ser um número inteiro.',
    'max' => ['numeric' => 'O campo :attribute não pode ser maior que :max.', 'string' => 'O campo :attribute não pode ter mais de :max caracteres.'],
    'min' => ['numeric' => 'O campo :attribute deve ser no mínimo :min.', 'string' => 'O campo :attribute deve ter pelo menos :min caracteres.'],
    'required' => 'O campo :attribute é obrigatório.',
    'string' => 'O campo :attribute deve ser um texto.',

    'attributes' => [
        'account_id' => 'conta',
        'amount' => 'valor',
        'description' => 'descrição',
        'device_name' => 'dispositivo',
        'email' => 'e-mail',
        'first_due_date' => 'primeiro vencimento',
        'idempotency_key' => 'chave da operação',
        'installment_count' => 'quantidade de parcelas',
        'name' => 'nome',
        'opening_balance' => 'saldo inicial',
        'opening_balance_date' => 'data do saldo inicial',
        'password' => 'senha',
        'received_on' => 'data do recebimento',
        'total' => 'valor total',
    ],
];
