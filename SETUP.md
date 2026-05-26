# Smart Hostel - Setup & Development Guide

## Project Overview

This is an MVP (Minimum Viable Product) version 1 of a Smart Hostel Meal + Attendance Management SaaS application built with Flutter.

### What's Included

✅ Complete folder structure  
✅ All base files with proper imports  
✅ Theme system with Material 3  
✅ Responsive layout helpers  
✅ Shared widgets and models  
✅ Mock data services  
✅ Authentication flow  
✅ Student & Admin dashboards  
✅ Production-ready architecture  

### What's NOT Included (Yet)

❌ Backend/APIs (Replace mock services later)  
❌ State management (Add Riverpod when needed)  
❌ Firebase/Supabase  
❌ Notifications  
❌ Payment processing  
❌ File uploads  

## Getting Started

### 1. Project Setup

```bash
# Navigate to project directory
cd smart_hostel_app

# Get all dependencies
flutter pub get

# Check Flutter installation
flutter doctor

# (Optional) Run code generation if needed
flutter pub run build_runner build
```

### 2. Run the App

```bash
# Run on connected device/emulator
flutter run

# Run on specific device
flutter run -d <device_id>

# Run in release mode
flutter run --release
```

### 3. Test Login

**Student Account:**
- Email: `student@hostel.com`
- Password: `any`

**Admin Account:**
- Email: `admin@hostel.com`
- Password: `any`

## Project Structure Explanation

### `lib/app/`
- **app.dart**: Main app widget with theme & routing configuration
- **routes/**: Route definitions and route names

### `lib/core/`
- **theme/**: Material 3 theme, colors, typography
- **responsive/**: Media query helpers for responsive design
- **constants/**: Spacing and border radius constants
- **utils/**: Helper functions (date formatting, etc)

### `lib/shared/`
- **enums/**: UserRole, MealType
- **models/**: UserModel, MealModel, AttendanceModel
- **widgets/**: Reusable components (GlassCard, PremiumButton, SectionTitle)

### `lib/data/`
- **mock/**: Mock services (replace with API calls later)
  - MockAuthService
  - MockMealService
  - MockAttendanceService
- **repositories/**: Data access layer (abstraction over services)

### `lib/features/`
- **auth/**: Authentication (splash, login)
- **student/**: Student feature module
  - dashboard: Home screen
  - meals: Browse meals
  - attendance: View attendance history
  - profile: Student profile
  - navigation: Bottom navigation
- **admin/**: Admin feature module
  - dashboard: Admin home
  - meals: Meal management
  - attendance: Attendance management
  - settings: Organization settings
  - navigation: Bottom navigation
- **dashboard/**: Router that determines which nav to show

## Key Files to Know

### Core Theme Files
- `lib/core/theme/app_colors.dart` - Color palette
- `lib/core/theme/app_theme.dart` - Material 3 theme setup

### Main Entry Points
- `lib/main.dart` - App entry
- `lib/app/app.dart` - App configuration
- `lib/app/routes/app_router.dart` - Route generation

### Important Models
- `lib/shared/models/user_model.dart` - User data
- `lib/shared/models/meal_model.dart` - Meal data
- `lib/shared/models/attendance_model.dart` - Attendance data

### Services (Replace These with APIs)
- `lib/data/mock/mock_auth_service.dart`
- `lib/data/mock/mock_meal_service.dart`
- `lib/data/mock/mock_attendance_service.dart`

## Development Workflow

### Adding a New Screen

1. Create the screen file in appropriate feature folder
   ```
   lib/features/feature_name/module_name/screens/new_screen.dart
   ```

2. Add route to `lib/app/routes/route_names.dart`
   ```dart
   static const String newScreen = '/new-screen';
   ```

3. Add route handler in `lib/app/routes/app_router.dart`
   ```dart
   case RouteNames.newScreen:
     return MaterialPageRoute(builder: (_) => const NewScreen());
   ```

4. Use in navigation
   ```dart
   Navigator.of(context).pushNamed(RouteNames.newScreen);
   ```

### Adding a New Widget

1. Create in appropriate location
   ```
   lib/shared/widgets/new_widget.dart
   ```

2. Import and use
   ```dart
   import '../../shared/widgets/new_widget.dart';
   ```

### Modifying Theme

1. Edit `lib/core/theme/app_colors.dart` for colors
2. Edit `lib/core/theme/app_theme.dart` for styles
3. Changes apply app-wide automatically

## Backend Integration Guide

### When You Have a Backend

1. **Create API Service**
   ```dart
   lib/data/services/api_service.dart
   ```

2. **Update Repositories**
   Replace mock service calls with API calls:
   ```dart
   // Before
   final meals = await _mealService.getMeals();
   
   // After
   final meals = await _apiService.getMeals();
   ```

3. **Replace Mock Services**
   - Keep mock services during development
   - Swap gradually when APIs are ready
   - No UI changes needed

### Suggested Dependencies for Backend

```yaml
dependencies:
  dio: ^5.3.0              # HTTP client
  retrofit: ^4.0.0         # REST client generator
  json_serializable: ^6.7.0 # JSON serialization
```

## State Management Integration

When ready to add state management:

### Option 1: Riverpod (Recommended)
```yaml
dependencies:
  riverpod: ^2.4.0
  flutter_riverpod: ^2.4.0
```

### Option 2: Bloc
```yaml
dependencies:
  bloc: ^8.1.0
  flutter_bloc: ^8.1.0
```

### Option 3: GetX
```yaml
dependencies:
  get: ^4.6.0
```

Currently, the app works fine with StatefulWidget. Add state management only when needed.

## Common Modifications

### Change Primary Color
```dart
// In app_colors.dart
static const Color primary = Color(0xFF2563EB); // Change this
```

### Add New Role Type
```dart
// In enums/user_role.dart
enum UserRole {
  // ... existing roles
  newRole('newRole'),
}
```

### Add New Meal Type
```dart
// In enums/meal_type.dart
enum MealType {
  // ... existing types
  newType('New Type'),
}
```

### Change Responsive Breakpoints
```dart
// In core/responsive/responsive.dart
static const double mobileBreakpoint = 600;    // Change this
static const double tabletBreakpoint = 900;    // Change this
```

## Testing

### Run Tests
```bash
flutter test
```

### Create a Test File
```
lib/features/auth/screens/login_screen_test.dart
```

## Build for Production

### Android
```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Google Play)
flutter build appbundle --release
```

### iOS
```bash
# Build iOS app
flutter build ios --release

# Create IPA
cd ios
xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build -archivePath build/Runner.xcarchive archive
xcodebuild -exportArchive -archivePath build/Runner.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/ipa
```

## Troubleshooting

### Issue: Build fails with dependency conflicts
**Solution:**
```bash
flutter clean
flutter pub get
flutter pub upgrade
```

### Issue: Hot reload doesn't work
**Solution:**
```bash
flutter run --no-fast-start
```

### Issue: App crashes on startup
**Solution:**
1. Check Flutter doctor: `flutter doctor`
2. Check console output: `flutter run -v`
3. Verify all imports are correct
4. Check Android SDK version matches requirements

### Issue: Emulator is slow
**Solution:**
```bash
flutter run --release
# Or run on physical device
flutter run -d <device_id>
```

## Performance Tips

1. Use `const` constructors whenever possible
2. Avoid rebuilding entire screens unnecessarily
3. Use `ListView.builder()` for large lists
4. Defer heavy operations to background threads
5. Profile with DevTools: `flutter pub global activate devtools`

## File Organization Best Practices

```
Feature Module Structure:
feature/
├── screens/
│   └── screen_name_screen.dart
├── widgets/
│   └── feature_specific_widget.dart
├── models/
│   └── feature_specific_model.dart
└── services/
    └── feature_service.dart
```

## Next Steps

1. ✅ Understand the current architecture
2. ✅ Run the app and explore features
3. ✅ Review mock data in `lib/data/mock/`
4. ⏭️ Start backend integration
5. ⏭️ Add state management
6. ⏭️ Implement additional features
7. ⏭️ Add tests and polish UI

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Guide](https://dart.dev/guides/language/language-tour)
- [Material Design 3](https://m3.material.io/)
- [Flutter Best Practices](https://flutter.dev/docs/testing/best-practices)

## Support

For questions or issues:
1. Check the README.md
2. Review existing code
3. Check Flutter/Dart documentation
4. Use `flutter doctor` for system issues

---

**Happy Coding! Build amazing things with this foundation.** 🚀
