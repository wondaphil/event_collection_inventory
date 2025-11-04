// lib/utils/ethiopian_date_helper.dart
// Ethiopian ↔ Gregorian conversion utilities with accurate weekday logic

class EthiopianDateHelper {
  /// Converts Gregorian DateTime → Ethiopian year, month, day
  static Map<String, int> toEthiopian(DateTime date) {
    int gregYear = date.year;
    int gregMonth = date.month;
    int gregDay = date.day;

    // Gregorian months length
    final List<int> gregMonthDays = [
      31,
      isGregorianLeapYear(gregYear) ? 29 : 28,
      31,
      30,
      31,
      30,
      31,
      31,
      30,
      31,
      30,
      31
    ];

    // Ethiopian new year in Gregorian (Sep 11, sometimes Sep 12)
    int newYearDay = (gregYear % 4 == 3) ? 12 : 11;
    DateTime ethNewYear = DateTime(gregYear, 9, newYearDay);

    if (date.isBefore(ethNewYear)) {
      gregYear -= 1;
      newYearDay = (gregYear % 4 == 3) ? 12 : 11;
      ethNewYear = DateTime(gregYear, 9, newYearDay);
    }

    int diffDays = date.difference(ethNewYear).inDays;
    int ethYear = gregYear - 7;
    int ethMonth = diffDays ~/ 30 + 1;
    int ethDay = diffDays % 30 + 1;

    if (ethMonth > 13) {
      ethYear++;
      ethMonth -= 13;
    }

    return {'year': ethYear, 'month': ethMonth, 'day': ethDay};
  }

  /// Converts Ethiopian year, month, day → Gregorian DateTime
  static DateTime toGregorian(int ethYear, int ethMonth, int ethDay) {
    int gregYear = ethYear + 7;
    int newYearDay = (gregYear % 4 == 3) ? 12 : 11;
    DateTime newYear = DateTime(gregYear, 9, newYearDay);
    int totalDays = (ethMonth - 1) * 30 + (ethDay - 1);
    return newYear.add(Duration(days: totalDays));
  }

  /// Returns Ethiopian weekday number (Sunday=1 ... Saturday=7)
  static int getWeekdayForEthiopianDate(int ethYear, int ethMonth, int ethDay) {
    final greg = toGregorian(ethYear, ethMonth, ethDay);
    // Dart: Monday=1 ... Sunday=7 → shift so Sunday=1
    return (greg.weekday % 7) + 1;
  }

  static String getMonthName(int ethMonth) => monthNamesGeez[ethMonth - 1];

  static bool isGregorianLeapYear(int year) {
    if (year % 4 != 0) return false;
    if (year % 100 == 0 && year % 400 != 0) return false;
    return true;
  }

  static const List<String> monthNamesGeez = [
    'መስከረም',
    'ጥቅምት',
    'ህዳር',
    'ታህሳስ',
    'ጥር',
    'የካቲት',
    'መጋቢት',
    'ሚያዚያ',
    'ግንቦት',
    'ሰኔ',
    'ሐምሌ',
    'ነሐሴ',
    'ጳጉሜን'
  ];

  static const List<String> weekdayNamesGeez = [
    'እሁድ',
    'ሰኞ',
    'ማክሰኞ',
    'ረቡዕ',
    'ሐሙስ',
    'ዓርብ',
    'ቅዳሜ'
  ];
}