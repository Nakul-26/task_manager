bool isNewDay(DateTime lastDate, DateTime currentDate) {
  return lastDate.year != currentDate.year ||
      lastDate.month != currentDate.month ||
      lastDate.day != currentDate.day;
}
