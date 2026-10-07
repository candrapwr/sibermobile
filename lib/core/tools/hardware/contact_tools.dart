/// Contacts tools: search the device address book.
library;

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../permissions.dart';
import '../tool.dart';
import '../results.dart';

/// Searches contacts by name, phone or email. Requires the contacts permission.
/// Only the fields needed for a chat answer are returned (name, phones,
/// emails), and the result list is capped so a huge address book cannot blow up
/// the context window.
class SearchContactsTool extends Tool {
  @override
  String get name => 'search_contacts';

  @override
  String get description =>
      'Search the device contacts (address book). Use `query` for a partial '
      'match on name/phone/email, or omit it to list recent contacts. '
      '`matchBy` chooses which field the query filters on. Requires the '
      'contacts permission.';

  @override
  String get category => 'Contacts';

  @override
  Map<String, dynamic> get parameters => const {
    'type': 'object',
    'properties': <String, dynamic>{
      'query': {
        'type': 'string',
        'description':
            'Partial search text. Omit to list contacts without filtering.',
      },
      'matchBy': {
        'type': 'string',
        'enum': ['name', 'phone', 'email'],
        'description': 'Which field the query filters on. Default: name.',
      },
      'limit': {
        'type': 'integer',
        'description': 'Max contacts to return (default 20, max 50).',
      },
    },
    'additionalProperties': false,
  };

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext ctx) async {
    final permissionError = await ensurePermissionOrMessage(
      Permission.contacts,
      name: 'contacts',
    );
    if (permissionError != null) return errorResult(permissionError);

    final query = optionalString(args, 'query');
    final matchBy = optionalString(args, 'matchBy') ?? 'name';
    final limit = optionalInt(args, 'limit', 20).clamp(1, 50);

    ContactFilter? filter;
    if (query != null && query.trim().isNotEmpty) {
      final q = query.trim();
      switch (matchBy) {
        case 'phone':
          filter = ContactFilter.phone(q);
        case 'email':
          filter = ContactFilter.email(q);
        case 'name':
        default:
          filter = ContactFilter.name(q);
      }
    }

    List<Contact> contacts;
    try {
      contacts = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
        },
        filter: filter,
        limit: limit,
      );
    } catch (e) {
      return errorResult('Failed to read contacts: $e');
    }

    final out = contacts.map((c) {
      return <String, dynamic>{
        'id': ?c.id,
        'name': c.displayName ?? '',
        if (c.phones.isNotEmpty)
          'phones': c.phones.map((p) => p.number).toList(),
        if (c.emails.isNotEmpty)
          'emails': c.emails.map((e) => e.address).toList(),
      };
    }).toList();

    return jsonResult({
      'count': out.length,
      'limit': limit,
      'matchBy': matchBy,
      'query': ?query,
      'contacts': out,
    });
  }
}

final List<Tool> contactTools = [SearchContactsTool()];
