import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/household_model.dart';

class HouseholdCard extends StatelessWidget {
  const HouseholdCard({super.key, required this.household});

  final HouseholdModel household;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = household.isAdmin;

    return Card(
      key: ValueKey(household.id),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.go('/households/${household.id}/chores');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Household icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.home_rounded,
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              // Name + role badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household.name,
                      style: theme.textTheme.headlineMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Chip(
                      key: Key(
                        isAdmin
                            ? 'role_badge_admin_${household.id}'
                            : 'role_badge_member_${household.id}',
                      ),
                      label: Text(
                        isAdmin ? 'Admin' : 'Member',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isAdmin
                              ? Colors.amber.shade900
                              : Colors.grey.shade700,
                        ),
                      ),
                      backgroundColor: isAdmin
                          ? Colors.amber.shade100
                          : Colors.grey.shade200,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0),
                      side: BorderSide.none,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Member count
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.group_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${household.memberCount}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
