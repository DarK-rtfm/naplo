import 'package:filcnaplo/data/models/absence.dart';
import 'package:filcnaplo/data/models/config.dart';
import 'package:filcnaplo/data/models/homework.dart';
import 'package:filcnaplo/data/models/lesson.dart';
import 'package:filcnaplo/data/models/exam.dart';
import 'package:filcnaplo/data/sync/config.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:filcnaplo/data/context/app.dart';
import 'package:filcnaplo/data/controllers/sync.dart';
import 'package:filcnaplo/data/models/evaluation.dart';
import 'package:filcnaplo/data/models/note.dart';
import 'package:filcnaplo/data/models/event.dart';
import 'package:filcnaplo/data/models/message.dart';
import 'package:filcnaplo/data/models/student.dart';
import 'package:filcnaplo/data/context/theme.dart';
import 'package:filcnaplo/data/models/user.dart';
import 'package:filcnaplo/ui/common/profile_icon.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tinycolor/tinycolor.dart';

class SettingsController {
  String language;
  String deviceLanguage;
  ThemeData theme;
  Color _appColor;
  bool _isDark;
  int backgroundColor;
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
        await app.storage.addUser(instance["id"]);

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

        await loadData(user);

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

Future loadData(User user) async {
  Database userStorage = app.storage.users[user.id];
  User globalUser = app.users.firstWhere((search) => search.id == user.id);
  SyncUser globalSync = app.sync.users[user.id];

  List student = await userStorage.query("student");
  List settings = await userStorage.query("settings");

  if (settings[0]["nickname"] != "") globalUser.name = settings[0]["nickname"];

  globalUser.customProfileIcon = settings[0]["custom_profile_icon"];
  if (globalUser.customProfileIcon != null &&
      globalUser.customProfileIcon != "") {
    if (app.debugMode)
      print("DEBUG: User profileIcon: " + globalUser.customProfileIcon);

    globalUser.profileIcon = ProfileIcon(
        name: globalUser.name, size: 0.7, image: globalUser.customProfileIcon);
  } else {
    globalUser.profileIcon = ProfileIcon(name: globalUser.name, size: 0.7);
  }

  if (student.length > 0) {
    globalSync.student.student = Student.fromJson(jsonDecode(student[0]["json"]));
  }

  List evaluations = await userStorage.query("evaluations");

  globalSync.evaluation.evaluations = [];
  globalSync.evaluation.averages = [];

  evaluations.forEach((evaluation) {
    globalSync.evaluation.evaluations
        .add(Evaluation.fromJson(jsonDecode(evaluation["json"])));
  });

  List notes = await userStorage.query("kreta_notes");

  globalSync.note.notes = [];
  notes.forEach((note) {
    globalSync.note.notes.add(Note.fromJson(jsonDecode(note["json"])));
  });

  List events = await userStorage.query("kreta_events");

  globalSync.event.events = [];
  events.forEach((event) {
    globalSync.event.events.add(Event.fromJson(jsonDecode(event["json"])));
  });

  List messagesInbox = await userStorage.query("messages_inbox");

  globalSync.messages.inbox = [];
  messagesInbox.forEach((message) {
    globalSync.messages.inbox
        .add(Message.fromJson(jsonDecode(message["json"])));
  });

  List messagesSent = await userStorage.query("messages_sent");

  globalSync.messages.sent = [];
  messagesSent.forEach((message) {
    globalSync.messages.sent.add(Message.fromJson(jsonDecode(message["json"])));
  });

  List messagesDraft = await userStorage.query("messages_draft");

  globalSync.messages.inbox = [];
  messagesDraft.forEach((message) {
    globalSync.messages.inbox
        .add(Message.fromJson(jsonDecode(message["json"])));
  });

  List messagesTrash = await userStorage.query("messages_trash");

  globalSync.messages.trash = [];
  messagesTrash.forEach((message) {
    globalSync.messages.trash
        .add(Message.fromJson(jsonDecode(message["json"])));
  });

  List absences = await userStorage.query("kreta_absences");

  globalSync.absence.absences = [];
  absences.forEach((absence) {
    globalSync.absence.absences.add(Absence.fromJson(jsonDecode(absence["json"])));
  });

  List exams = await userStorage.query("kreta_exams");

  globalSync.exam.exams = [];
  exams.forEach((exam) {
    globalSync.exam.exams.add(Exam.fromJson(jsonDecode(exam["json"])));
  });

  List homeworks = await userStorage.query("kreta_homeworks");

  globalSync.homework.homework = [];
  homeworks.forEach((homework) {
    globalSync.homework.homework
        .add(Homework.fromJson(jsonDecode(homework["json"])));
  });

  List lessons = await userStorage.query("kreta_lessons");

  globalSync.timetable.lessons = [];
  lessons.forEach((lesson) {
    globalSync.timetable.lessons.add(Lesson.fromJson(jsonDecode(lesson["json"])));
  });
}
