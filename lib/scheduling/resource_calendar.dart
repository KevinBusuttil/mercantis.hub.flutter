import 'package:flutter/material.dart';

/// One column of the calendar: a resource (day view) or a day (week view).
/// [date] anchors slot-tap times for this lane.
class CalendarLane {
  const CalendarLane({
    required this.id,
    required this.label,
    required this.date,
  });

  final String id;
  final String label;
  final DateTime date;
}

/// A block on the calendar. Purely presentational — the widget knows nothing
/// about appointments, so deliveries/jobs/rentals can reuse it (S1).
class CalendarEntry {
  const CalendarEntry({
    required this.id,
    required this.laneId,
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
    this.color,
  });

  final String id;
  final String laneId;
  final DateTime start;
  final DateTime end;
  final String title;
  final String? subtitle;
  final Color? color;
}

/// Day/week calendar with vertical time and horizontal lanes (S1b). Tapping
/// a block fires [onEntryTap]; tapping empty space fires [onSlotTap] with
/// the lane and the tapped time rounded DOWN to [slotMinutes].
class ResourceCalendar extends StatelessWidget {
  const ResourceCalendar({
    super.key,
    required this.lanes,
    required this.entries,
    this.startHour = 7,
    this.endHour = 20,
    this.hourHeight = 64,
    this.laneWidth = 180,
    this.slotMinutes = 30,
    this.onEntryTap,
    this.onSlotTap,
  });

  final List<CalendarLane> lanes;
  final List<CalendarEntry> entries;
  final int startHour;
  final int endHour;
  final double hourHeight;
  final double laneWidth;
  final int slotMinutes;
  final void Function(CalendarEntry entry)? onEntryTap;
  final void Function(CalendarLane lane, DateTime slotStart)? onSlotTap;

  double get _bodyHeight => (endHour - startHour) * hourHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (lanes.isEmpty) {
      return const Center(child: Text('Nothing to schedule on'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 56 + lanes.length * laneWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 56),
                for (final lane in lanes)
                  SizedBox(
                    width: laneWidth,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        lane.label,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: _bodyHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _timeGutter(theme),
                      for (final lane in lanes) _lane(theme, lane),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeGutter(ThemeData theme) => SizedBox(
        width: 56,
        height: _bodyHeight,
        child: Stack(
          children: [
            for (var h = startHour; h < endHour; h++)
              Positioned(
                top: (h - startHour) * hourHeight - 7,
                right: 8,
                child: Text(
                  '${h.toString().padLeft(2, '0')}:00',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      );

  Widget _lane(ThemeData theme, CalendarLane lane) {
    final laneEntries =
        entries.where((e) => e.laneId == lane.id).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return SizedBox(
      width: laneWidth,
      height: _bodyHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (details) {
          if (onSlotTap == null) return;
          final minutes =
              startHour * 60 + details.localPosition.dy / hourHeight * 60;
          final snapped = (minutes ~/ slotMinutes) * slotMinutes;
          onSlotTap!(
            lane,
            DateTime(lane.date.year, lane.date.month, lane.date.day)
                .add(Duration(minutes: snapped)),
          );
        },
        child: Stack(
          children: [
            // Hour gridlines + lane divider.
            for (var h = startHour; h <= endHour; h++)
              Positioned(
                top: (h - startHour) * hourHeight,
                left: 0,
                right: 0,
                child: Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: VerticalDivider(
                width: 1,
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
            ),
            for (final entry in laneEntries) _block(theme, entry),
          ],
        ),
      ),
    );
  }

  Widget _block(ThemeData theme, CalendarEntry entry) {
    final dayStart = DateTime(
        entry.start.year, entry.start.month, entry.start.day, startHour);
    final top = entry.start.difference(dayStart).inMinutes / 60 * hourHeight;
    final rawHeight =
        entry.end.difference(entry.start).inMinutes / 60 * hourHeight;
    final height = rawHeight.clamp(28.0, _bodyHeight);
    final color = entry.color ?? theme.colorScheme.primaryContainer;
    return Positioned(
      top: top.clamp(0.0, _bodyHeight - 28),
      left: 4,
      right: 4,
      height: height,
      child: GestureDetector(
        onTap: onEntryTap == null ? null : () => onEntryTap!(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              if (entry.subtitle != null && height > 40)
                Text(
                  entry.subtitle!,
                  style: theme.textTheme.labelSmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
