import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show LocalizationsDelegate;
import 'package:flutter_localizations/flutter_localizations.dart';

// ---------------------------------------------------------------------------
// App locale (TASK-115): every calendar widget must start the week on MONDAY.
// ---------------------------------------------------------------------------
//
// The unset MaterialApp default inherits the device locale; en_US
// (the de-facto default) has MaterialLocalizations.firstDayOfWeekIndex == 0,
// which puts Sunday first. en_GB has firstDayOfWeekIndex == 1 (Monday first).
//
// The app is English-only, so pinning en_GB has minimal user-visible effect:
// the calendar weekday order, and inside the date picker itself the dialog
// header/date order flips to day-first (e.g. "Tue 18 Aug" instead of
// "Tue, Aug 18"). Date text OUTSIDE the picker is unaffected — the app
// formats with explicit DateFormat patterns and flutter_localizations does
// not change Intl.defaultLocale.
//
// main.dart applies these to MaterialApp; widget tests import the SAME
// constants so a test can never drift from the app's real locale config.

const Locale kAppLocale = Locale('en', 'GB');

const List<Locale> kSupportedLocales = [Locale('en', 'GB')];

const List<LocalizationsDelegate<dynamic>> kLocalizationsDelegates =
    GlobalMaterialLocalizations.delegates;
