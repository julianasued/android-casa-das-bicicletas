/// Ponte entre a resposta da API e a entidade do domínio.
///
/// Todos os repositórios fazem a mesma sequência: propagar a falha se houver,
/// mapear o corpo se não houver, e transformar um JSON fora do contrato em
/// falha em vez de exceção solta no meio de uma venda. Escrita uma vez, para
/// que os quatro repositórios não a escrevam de quatro jeitos.
library;

import 'dart:async';

import '../../core/failure.dart';
import '../../core/result.dart';
import 'api_client.dart';

Future<Result<T>> mapApiResponse<T>(
  Result<ApiResponse> response,
  FutureOr<T> Function(ApiResponse response) build,
) async {
  if (response case Err(:final failure)) return Err(failure);

  try {
    return Ok(await build((response as Ok<ApiResponse>).value));
  } on FormatException catch (error) {
    return Err(
      UnexpectedFailure('Resposta inesperada do servidor: ${error.message}'),
    );
  } on TypeError {
    return const Err(
      UnexpectedFailure('Resposta do servidor em formato inesperado.'),
    );
  }
}
