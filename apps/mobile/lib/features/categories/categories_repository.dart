import '../../core/api_client.dart';
import 'category.dart';

class CategoriesRepository {
  const CategoriesRepository(this._api);

  final ApiClient _api;

  Future<List<Category>> list(int spaceId, {String? type}) async {
    final path = type != null
        ? '/spaces/$spaceId/categories?type=$type'
        : '/spaces/$spaceId/categories';
    final json = await _api.get(path);
    final data = json['data'] as List<dynamic>;
    return data
        .map((item) => Category.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Category> create(
    int spaceId, {
    required String name,
    required String type,
    String? icon,
    String? color,
  }) async {
    final json = await _api.post('/spaces/$spaceId/categories', {
      'name': name,
      'type': type,
      'icon': ?icon,
      'color': ?color,
    });
    return Category.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Category> update(
    int spaceId,
    int categoryId, {
    String? name,
    String? icon,
    String? color,
  }) async {
    final body = <String, Object?>{
      'name': ?name,
      'icon': ?icon,
      'color': ?color,
    };
    final json = await _api.patch(
      '/spaces/$spaceId/categories/$categoryId',
      body,
    );
    return Category.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> delete(int spaceId, int categoryId) async {
    await _api.delete('/spaces/$spaceId/categories/$categoryId');
  }
}
