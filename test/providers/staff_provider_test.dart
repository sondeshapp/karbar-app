import 'package:flutter_test/flutter_test.dart';
import 'package:m_pos/db/database_helper.dart';
import 'package:m_pos/providers/staff_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.setTestPath(inMemoryDatabasePath);
    await DatabaseHelper.resetForTesting();
  });

  tearDown(() async => DatabaseHelper.resetForTesting());

  test(
    'creates salted PIN accounts and authenticates the selected user',
    () async {
      final access = StaffAccess();
      await expectLater(
        access.create(name: 'Mina', role: 'cashier', pin: '1234'),
        throwsStateError,
      );
      final ownerId = await access.create(
        name: 'Owner',
        role: 'owner',
        pin: '4826',
      );
      final cashierId = await access.create(
        name: 'Mina',
        role: 'cashier',
        pin: '1234',
      );

      final owner = await access.authenticate(ownerId, '4826');
      expect(owner?.isOwner, isTrue);
      expect(await access.authenticate(cashierId, '9999'), isNull);
      expect(await access.authenticate(ownerId, '1234'), isNull);
      await access.resetPin(cashierId, '7788');
      expect(await access.authenticate(cashierId, '1234'), isNull);
      expect(await access.authenticate(cashierId, '7788'), isNotNull);
      final users = await access.list();
      expect(users.map((user) => user.pinHash).toSet().length, 2);
      expect(
        users.every((user) => user.pinHash != '4826' && user.pinHash != '1234'),
        isTrue,
      );
    },
  );

  test(
    'requires a four to eight digit PIN and preserves one active owner',
    () async {
      final access = StaffAccess();
      await expectLater(
        access.create(name: 'Owner', role: 'owner', pin: '123'),
        throwsArgumentError,
      );
      final ownerId = await access.create(
        name: 'Owner',
        role: 'owner',
        pin: '4826',
      );
      await expectLater(access.setActive(ownerId, false), throwsStateError);
      expect((await access.list(activeOnly: true)).single.id, ownerId);
    },
  );
}
