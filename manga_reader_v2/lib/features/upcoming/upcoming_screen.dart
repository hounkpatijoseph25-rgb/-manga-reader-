import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/format.dart';
import '../../data/models/manga.dart';
import '../../shared/widgets/cover_image.dart';
import '../../shared/widgets/state_views.dart';
import '../details/details_screen.dart';
import 'upcoming_providers.dart';

/// Page « À venir » : calendrier mensuel des sorties estimées.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});

  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  /// Premier jour du mois affiché dans le calendrier.
  late DateTime _month;

  /// N'afficher que les mangas « En cours ».
  bool _ongoingOnly = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  Future<void> _showHelp() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('À venir'),
        content: const Text(
          "Ce calendrier estime la date du prochain chapitre de chaque manga "
          "de votre bibliothèque, à partir du rythme de parution observé.\n\n"
          "Un point sous un jour indique qu'au moins une sortie est prévue ce "
          "jour-là. Ouvrez la fiche d'un manga pour mettre à jour ses dates.\n\n"
          "Les estimations sont indicatives : elles dépendent du rythme réel de "
          "l'auteur et de la source.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(upcomingReleasesProvider);
    final all = async.value ?? const <UpcomingRelease>[];
    final releases = _ongoingOnly
        ? [
            for (final r in all)
              if (r.manga.status == MangaStatus.ongoing) r,
          ]
        : all;

    // Jours du mois affiché qui ont au moins une sortie.
    final releaseDays = <int>{
      for (final r in releases)
        if (r.date.year == _month.year && r.date.month == _month.month)
          r.date.day,
    };

    // Regroupement par jour pour la liste.
    final groups = <DateTime, List<UpcomingRelease>>{};
    for (final r in releases) {
      groups.putIfAbsent(r.day, () => []).add(r);
    }
    final days = groups.keys.toList()..sort();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(
        title: const Text('À venir'),
        actions: [
          PopupMenuButton<bool>(
            icon: Icon(
              _ongoingOnly ? Icons.filter_alt : Icons.filter_alt_outlined,
            ),
            tooltip: 'Filtrer',
            initialValue: _ongoingOnly,
            onSelected: (value) => setState(() => _ongoingOnly = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('Tous les mangas')),
              PopupMenuItem(value: true, child: Text('En cours uniquement')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Aide',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: ListView(
        children: [
          _Calendar(
            month: _month,
            releaseDays: releaseDays,
            onPrev: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          const Divider(height: 1),
          if (async.hasError)
            const SizedBox(
              height: 240,
              child: EmptyView(
                message: 'Impossible de calculer les sorties prévues.',
                icon: Icons.cloud_off,
              ),
            )
          else if (days.isEmpty)
            const SizedBox(
              height: 320,
              child: EmptyView(
                message:
                    'Aucune sortie prévue.\nAjoutez des mangas à votre '
                    'bibliothèque et ouvrez leur fiche pour récupérer les '
                    'dates de parution.',
                icon: Icons.event_busy,
              ),
            )
          else
            for (final day in days) ...[
              _DayHeader(
                label: _groupLabel(day, today),
                count: groups[day]!.length,
              ),
              for (final release in groups[day]!) _ReleaseTile(release: release),
            ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

String _groupLabel(DateTime day, DateTime today) {
  final diff = day.difference(today).inDays;
  if (diff <= 0) return "Aujourd'hui";
  if (diff == 1) return 'Demain';
  if (diff <= 7) return 'Dans $diff jours';
  return formatDate(day);
}

/// Calendrier mensuel avec navigation et points sur les jours de sortie.
class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.releaseDays,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final Set<int> releaseDays;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _months = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday : 1 = lundi … 7 = dimanche. On veut 0 case vide pour lundi.
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Mois précédent',
              ),
              Expanded(
                child: Text(
                  '${_months[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Mois suivant',
              ),
            ],
          ),
          Row(
            children: [
              for (final label in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(
                      context: context,
                      index: row * 7 + col,
                      leading: leading,
                      daysInMonth: daysInMonth,
                      today: today,
                      scheme: scheme,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell({
    required BuildContext context,
    required int index,
    required int leading,
    required int daysInMonth,
    required DateTime today,
    required ColorScheme scheme,
  }) {
    final day = index - leading + 1;
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 44);

    final isToday =
        month.year == today.year &&
        month.month == today.month &&
        day == today.day;
    final hasRelease = releaseDays.contains(day);

    return SizedBox(
      height: 44,
      child: Center(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday ? scheme.primaryContainer : null,
            border: isToday ? Border.all(color: scheme.primary) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  color: isToday ? scheme.onPrimaryContainer : null,
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
              if (hasRelease)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            count == 1 ? '1 sortie' : '$count sorties',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile({required this.release});

  final UpcomingRelease release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitle = release.estimated
        ? '${formatDate(release.date)} · estimation'
        : formatDate(release.date);

    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CoverImage(url: release.manga.coverUrl),
        ),
      ),
      title: Text(
        release.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${release.count}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(manga: release.manga),
        ),
      ),
    );
  }
}
