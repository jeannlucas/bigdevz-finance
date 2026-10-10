import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/token_storage.dart';
import 'features/accounts/accounts_repository.dart';
import 'features/accounts/opening_adjustments.dart';
import 'features/agreements/agreements_repository.dart';
import 'features/agreements/receipt_attempts.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/session_controller.dart';
import 'features/payables/payable_creations.dart';
import 'features/payables/payables_repository.dart';
import 'features/summary/summary.dart';

/// Monta as dependências do app; os testes trocam cliente HTTP e armazenamento.
Widget buildApp({
  required String baseUrl,
  required SessionStorage storage,
  http.Client? client,
}) {
  final api = ApiClient(baseUrl: baseUrl, client: client);
  return MultiProvider(
    providers: [
      Provider.value(value: api),
      Provider(create: (_) => AccountsRepository(api)),
      Provider(
        create: (context) => OpeningAdjustments(
          repository: context.read<AccountsRepository>(),
          storage: storage,
        ),
      ),
      Provider(create: (_) => AgreementsRepository(api)),
      Provider(create: (_) => PayablesRepository(api)),
      Provider(
        create: (context) => PayableCreations(
          repository: context.read<PayablesRepository>(),
          storage: storage,
        ),
      ),
      Provider(
        create: (context) => ReceiptAttempts(
          repository: context.read<AgreementsRepository>(),
          storage: storage,
          payables: context.read<PayablesRepository>(),
        ),
      ),
      Provider(create: (_) => SummaryRepository(api)),
      ChangeNotifierProvider(
        create: (_) => SessionController(
          api: api,
          auth: AuthRepository(api),
          storage: storage,
        )..restore(),
      ),
    ],
    child: const FinanceApp(),
  );
}
