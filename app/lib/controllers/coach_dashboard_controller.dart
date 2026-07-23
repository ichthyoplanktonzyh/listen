import 'package:flutter/foundation.dart';

import '../models/coach_dashboard.dart';
import '../services/api_service.dart';
import '../state/store.dart';

class CoachDashboardState {
  const CoachDashboardState({this.dashboard, this.loading = false, this.error});
  final CoachDashboard? dashboard;
  final bool loading;
  final String? error;
}

class CoachDashboardController extends ChangeNotifier {
  CoachDashboardController() : store = Store(const CoachDashboardState()) {
    store.addListener(notifyListeners);
  }
  final Store<CoachDashboardState> store;
  CoachDashboardState get state => store.state;
  Future<void> load(
    LocalApi api, {
    int days = 7,
    String language = 'en',
  }) async {
    store.replace(const CoachDashboardState(loading: true));
    try {
      store.replace(
        CoachDashboardState(
          dashboard: await api.coachDashboard(days: days, language: language),
        ),
      );
    } catch (error) {
      store.replace(CoachDashboardState(error: '$error'));
    }
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    store.dispose();
    super.dispose();
  }
}
