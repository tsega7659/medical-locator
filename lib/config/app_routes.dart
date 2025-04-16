import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/search/search_screen.dart';

final Map<String, WidgetBuilder> appRoutes = {
  '/': (context) => HomeScreen(),
  '/search': (context) => SearchScreen(),
  
};
