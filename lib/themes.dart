/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';

import 'settings/settings.dart';

class Themes {
  static final _light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF66bb6a),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF66bb6a),
      secondary: const Color(0xff6d4c41),
    ),
    brightness: Brightness.light,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    }),
  );

  static final _dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF66bb6a),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xff212121),
      secondary: const Color(0xff689f38),
    ),
    brightness: Brightness.dark,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    }),
  );

  static ThemeData fromName(String name) {
    switch (name) {
      case DEFAULT_LIGHT_THEME_NAME:
        return _light;
      case DEFAULT_DARK_THEME_NAME:
        return _dark;
      default:
        throw Exception("Theme not found - $name");
    }
  }
}
