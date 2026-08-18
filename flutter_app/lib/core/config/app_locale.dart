import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// ---------------------------------------------------------------------------
// App locale (TASK-115): every calendar widget must start the week on MONDAY.
// ---------------------------------------------------------------------------
//
// The unset MaterialApp default inherits the device locale; en_US
// (the de-facto default) has MaterialLocalizations.firstDayOfWeekIndex == 0,
// which puts Sunday first. en_GB has firstDayOfWeekIndex == 1 (Monday first).
//
// The app is English-only and formats dates with explicit `DateFormat`
// patterns, so pinning en_GB has no user-visible effect other than the
// calendar weekday order.
//
// main.dart applies these to MaterialApp; widget tests import the SAME
// constants so a test can never drift from the app's real locale config.

const Locale kAppLocale = Locale('en', 'GB');

const List<Locale> kSupportedLocales = [Locale('en', 'GB')];

const List<LocalizationsDelegate<dynamic>> kLocalizationsDelegates =
    GlobalMaterialLocalizations.delegates;
