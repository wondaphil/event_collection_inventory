import 'package:flutter/material.dart';
import '../utils/ethiopian_date_helper.dart';

Future<Map<String, int>?> showEthiopianDatePickerDialog(
  BuildContext context, {
  required int initialYear,
  required int initialMonth,
  required int initialDay,
}) async {
  return await showDialog<Map<String, int>>(
    context: context,
    barrierDismissible: true,
    builder: (_) => EthiopianDatePickerDialog(
      initialYear: initialYear,
      initialMonth: initialMonth,
      initialDay: initialDay,
    ),
  );
}

class EthiopianDatePickerDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;
  final int initialDay;

  const EthiopianDatePickerDialog({
    super.key,
    required this.initialYear,
    required this.initialMonth,
    required this.initialDay,
  });

  @override
  State<EthiopianDatePickerDialog> createState() =>
      _EthiopianDatePickerDialogState();
}

class _EthiopianDatePickerDialogState extends State<EthiopianDatePickerDialog> {
  late int selectedYear;
  late int selectedMonth;
  late int selectedDay;

  @override
  void initState() {
    super.initState();
    selectedYear = widget.initialYear;
    selectedMonth = widget.initialMonth;
    selectedDay = widget.initialDay;
  }

  void _changeMonth(int offset) {
    setState(() {
      selectedMonth += offset;
      if (selectedMonth > 13) {
        selectedMonth = 1;
        selectedYear++;
      } else if (selectedMonth < 1) {
        selectedMonth = 13;
        selectedYear--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = (selectedMonth == 13) ? 5 : 30;
    final firstWeekday = EthiopianDateHelper.getWeekdayForEthiopianDate(
      selectedYear,
      selectedMonth,
      1,
    );
    final leadingEmpty = (firstWeekday - 1) % 7;

    // Use short weekday names (2 letters)
    const weekdayShort = ['እሁ', 'ሰኞ', 'ማክ', 'ረቡ', 'ሐሙ', 'ዓር', 'ቅዳ'];

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        children: [
          Text(
            'የቀን መርጫ',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _changeMonth(-1),
              ),
              DropdownButton<int>(
                value: selectedMonth,
                items: List.generate(
                  13,
                  (i) => DropdownMenuItem<int>(
                    value: i + 1,
                    child: Text(EthiopianDateHelper.monthNamesGeez[i]),
                  ),
                ),
                onChanged: (v) => setState(() => selectedMonth = v!),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: selectedYear,
                items: List.generate(
                  30,
                  (i) => DropdownMenuItem<int>(
                    value: 2005 + i,
                    child: Text((2005 + i).toString()),
                  ),
                ),
                onChanged: (v) => setState(() => selectedYear = v!),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        height: 360,
        child: Column(
          children: [
            // Weekdays — short names now
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: weekdayShort
                  .map(
                    (w) => Expanded(
                      child: Center(
                        child: Text(
                          w,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (int i = 0; i < leadingEmpty; i++)
                    const SizedBox.shrink(),
                  for (int d = 1; d <= daysInMonth; d++)
                    GestureDetector(
                      onTap: () => setState(() => selectedDay = d),
                      child: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: (selectedDay == d)
                              ? Colors.teal.withOpacity(0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '$d',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: (selectedDay == d)
                                  ? Colors.teal.shade900
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'year': selectedYear,
            'month': selectedMonth,
            'day': selectedDay,
          }),
          child: const Text('Select'),
        ),
      ],
    );
  }
}