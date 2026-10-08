// Inventory home: task menu. "What are you doing?"
library;

import 'package:flutter/material.dart';

import '../odoo_client.dart';
import 'add_item.dart';
import 'browse.dart';
import 'receive.dart';

class InventoryHome extends StatelessWidget {
  final OdooClient client;
  final String user;
  const InventoryHome({super.key, required this.client, required this.user});

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: Image.asset('assets/logo.png', height: 84)),
          const SizedBox(height: 12),
          const Text('What are you doing?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.add_box,
            title: 'Add inventory',
            subtitle: 'New product, incl. expiry date',
            onTap: () =>
                _go(context, AddItemScreen(client: client, user: user)),
          ),
          _tile(
            context,
            icon: Icons.edit,
            title: 'Manage inventory',
            subtitle: 'Find an item, fix its details',
            onTap: () => _go(
                context,
                BrowseScreen(
                    client: client,
                    user: user,
                    editable: true,
                    title: 'Manage inventory')),
          ),
          _tile(
            context,
            icon: Icons.qr_code_scanner,
            title: 'Update item count',
            subtitle: 'Scan, set quantity, next',
            onTap: () => _go(
                context,
                ReceiveScreen(
                    client: client,
                    user: user,
                    initialMode: 'count')),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
