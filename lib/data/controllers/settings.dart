import 'package:filcnaplo/data/models/config.dart';
import 'package:filcnaplo/data/sync/config.dart';
import 'package:filcnaplo/data/context/app.dart';
import 'package:filcnaplo/data/context/theme.dart';
import 'package:filcnaplo/data/models/user.dart';
import 'package:filcnaplo/data/controllers/offlineloader.dart';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:tinycolor/tinycolor.dart';

class SettingsController {
  String language;
  String deviceLanguage;
  ThemeData theme;
  Color _appColor;
  bool _isDark;
  int backgroundColor;

  /// Read individual settings with BitmaskHelper.nthBit.
  ///
  /// Toggle individual settings with BitmaskHelper.toggleBit.
  ///
  /// ```-
  /// [bit] [function]
  /// 1     Evaluations
  /// 2     Messages
  /// 3     Notes
  /// 4     Events
  /// 5     Cancelled lessons
  /// 6     Substituted lessons
  /// 7     Absences
  /// 8     Absences justified
  /// 9     Exams
  /// 10    Homeworks
  /// 11-14 [reserved for future use]
  /// 15    Newsletter
  /// 16    Current lesson (persistent)
  /// ```
  int notificationMask;
  bool enableNotifications;
  bool renderHtml;
  int defaultPage;
  int eveningStartHour;
  bool enableNews;
  ConfigSync config = ConfigSync();
  int roundUp;

  get locale {
    List<String> lang = (language == "auto"
            ? deviceLanguage != null
                ? deviceLanguage
                : "hu_HU"
            : language)
        .split("_");
    return Locale(lang[0], lang[1]);
  }

  Color get appColor {
    if (!(_isDark ?? app.settings.theme.brightness == Brightness.dark))
      return TinyColor(_appColor).darken(10).color;
    else
      return _appColor;
  }

  Color get rawAppColor {
    return _appColor;
  }

  set appColor(Color color) {
    _appColor = color;
  }

  Color colorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll("#", "");
    if (hexColor.length == 6) {
      hexColor = "FF" + hexColor;
    }
    return Color(int.parse(hexColor, radix: 16));
  }

  Future update({bool login = true, Map<String, dynamic> settings}) async {
    settings = settings ?? (await app.storage.storage.query("settings"))[0];
    language = settings["language"];
    _appColor = ThemeContext.colors[settings["app_color"]];
    backgroundColor = settings["background_color"];
    defaultPage = settings["default_page"];
    _isDark = settings["theme"] != "light";
    theme = {
      "light": ThemeContext().light(app.settings.appColor),
      "tinted": ThemeContext().tinted(),
      "dark": ThemeContext()
          .dark(app.settings.appColor, app.settings.backgroundColor)
    }[settings["theme"]];
    _isDark = null;
    app.debugMode = settings["debug_mode"] == 1;

    List evalColorsI = await app.storage.storage.query("eval_colors");

    app.theme.evalColors[0] = colorFromHex(evalColorsI[0]["color1"]);
    app.theme.evalColors[1] = colorFromHex(evalColorsI[0]["color2"]);
    app.theme.evalColors[2] = colorFromHex(evalColorsI[0]["color3"]);
    app.theme.evalColors[3] = colorFromHex(evalColorsI[0]["color4"]);
    app.theme.evalColors[4] = colorFromHex(evalColorsI[0]["color5"]);

    enableNotifications = settings["notifications"] == 1;
    notificationMask = settings["notificationMask"];
    enableNews = settings["news_show"] == 1;
    renderHtml = settings["render_html"] == 1;

    config.config = Config.fromJson(jsonDecode(settings["config"]));

    roundUp = settings["round_up"];

    List usersInstance = await app.storage.storage.query("users");

    if (app.debugMode)
      print("INFO: Loading " + usersInstance.length.toString() + " users");

    for (int i = 0; i < usersInstance.length; i++) {
      Map instance = usersInstance[i];

      if (instance["id"].isNotEmpty && instance["name"].isNotEmpty) {
        // Create a Storage Controller instance for the user
        await app.storage.addUser(instance["id"]);

        // Create a Sync Controller instance for the user
        app.sync.addUser(instance["id"]);

        List kretaInstance;

        try {
          kretaInstance =
              await app.storage.users[instance["id"]].query("kreta");
        } catch (error) {
          print("ERROR: SettingsController.update: " + error.toString());
          await app.storage.deleteUser(instance["id"]);
          app.storage.users.remove(instance["id"]);
          continue;
        }

        // Create an API Client instance for the user
        app.kretaApi.addUser(instance["id"],
            instituteCode: kretaInstance[0]["institute_code"]);

        User user = User(
          instance["id"],
          kretaInstance[0]["username"],
          kretaInstance[0]["password"],
          kretaInstance[0]["institute_code"],
        );

        user.name = instance["name"];
        user.realName = instance["name"];

        if (!app.users.map((e) => e.id).toList().contains(user.id))
          app.users.add(user);

        await offlineLoad(user);

        if (app.debugMode)
          print("DEBUG: User loaded " + user.name + "<" + user.id + ">");
      }
    }

    if (login && !app.debugUser) {
      await Future.forEach(
        app.users.where((user) => user.loginState == false),
        (user) async {
          await apiLogin(user);
        },
      );
    }

    print("INFO: Updated local settings");
  }
}

Future apiLogin(User user) async {
  if (!app.debugUser) {
    if (await app.kretaApi.users[user.id].login(user))
      app.users.firstWhere((search) => search.id == user.id).loginState = true;
    else
      app.users.firstWhere((search) => search.id == user.id).loginState = false;
  } else {
    app.users.firstWhere((search) => search.id == user.id).loginState = true;
  }
}
