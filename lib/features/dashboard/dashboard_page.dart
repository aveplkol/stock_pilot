import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder(
          stream: ref.watch(inventoryRepositoryProvider).watchItems(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            final low = items
                .where((i) => i.quantity <= i.minimumQuantity)
                .length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overview',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your inventory and order activity at a glance.',
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 560;

                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _Stat(
                          title: 'Inventory Items',
                          value: '${items.length}',
                          icon: Icons.inventory_2_outlined,
                          width: isNarrow
                              ? constraints.maxWidth
                              : 260,
                        ),
                        _Stat(
                          title: 'Low Stock',
                          value: '$low',
                          icon: Icons.warning_amber_outlined,
                          width: isNarrow
                              ? constraints.maxWidth
                              : 260,
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.title,
    required this.value,
    required this.icon,
    required this.width,
  });

  final String title;
  final String value;
  final IconData icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 120,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}