import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import './core/l10n/app_localizations.dart';
import './features/auth/logic/language_cubit.dart';
import './features/auth/logic/session_cubit.dart';
import './core/di/odoo_cubit.dart';
import './core/di/timer_service.dart';
import './features/auth/ui/screens/splash_screen.dart';
import './core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  final langCubit = LanguageCubit();
  await langCubit.loadSavedLanguage();

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: langCubit),
        BlocProvider(create: (_) => SessionCubit()),
        BlocProvider(create: (_) => OdooCubit()),
      ],
      child: const MaintenanceApp(),
    ),
  );
}

class MaintenanceApp extends StatelessWidget {
  const MaintenanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageCubit>().state.locale;
    return MaterialApp(
      title: 'Maintenance',
      debugShowCheckedModeBanner: false,
      locale: lang,
      supportedLocales: const [
        Locale('en'), Locale('ar'), Locale('fr'), Locale('es'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final isRtl = lang.languageCode == 'ar';
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        );
      },
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
