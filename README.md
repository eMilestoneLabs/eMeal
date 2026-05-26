# Smart Hostel - Meal + Attendance Management SaaS

A production-grade Flutter MVP for managing hostel meals and student attendance.

## Features

### Student Features
- 📱 Dashboard with attendance stats
- 🍽️ View available meals
- ✅ Mark attendance
- 📊 View attendance history
- 👤 Profile management

### Admin Features
- 📊 Dashboard with analytics
- 🍽️ Manage meals (create, enable/disable)
- 📅 Weekly meal scheduling
- 👥 Attendance tracking and reports
- ⚙️ Organization settings

## Architecture

```
lib/
├── app/              # App configuration & routing
├── core/             # Constants, theme, responsive, utils
├── shared/           # Shared models, enums, widgets
├── data/             # Mock services & repositories
├── features/         # Feature modules (auth, student, admin)
└── main.dart         # Entry point
```

## Project Structure

- **Feature-First Architecture**: Organized by features, not layers
- **Clean Separation**: Student and Admin features are completely separated
- **Responsive Design**: Works on mobile, tablet, and desktop
- **Material 3**: Modern Material Design with custom theme
- **Mock Services**: Ready for backend integration

## Setup Instructions

### Prerequisites
- Flutter 3.16+ (Stable)
- Dart 3.0+
- Java 17+
- Android SDK (API 24+)

### Installation

1. **Clone the repository**
   ```bash
   cd smart_hostel_app
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate build files**
   ```bash
   flutter pub run build_runner build
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

## Demo Credentials

### Student Account
- Email: `student@hostel.com`
- Password: `any`

### Admin Account
- Email: `admin@hostel.com`
- Password: `any`

## App Structure

### Authentication
- Login screen with demo credentials
- Role-based navigation
- Splash screen with initialization

### Student Module
- Dashboard with stats
- Meals browser with filters
- Attendance marking & history
- Profile management

### Admin Module
- Dashboard with analytics
- Meal management (CRUD)
- Weekly schedule creation
- Attendance tracking
- Organization settings

## Theme & Design

- **Color Scheme**: Modern fintech style with blues and greens
- **Glassmorphism**: Ready foundation for glass effects
- **Typography**: Material 3 compliant
- **Spacing**: Consistent spacing system
- **Responsive**: Breakpoints for mobile, tablet, desktop

## Responsive Breakpoints

- Mobile: < 600px
- Tablet: 600px - 900px
- Desktop: > 900px

## Key Components

### Widgets
- `GlassCard`: Reusable glass-morphism card
- `PremiumButton`: Styled button with loading state
- `SectionTitle`: Section header with optional action

### Utilities
- `Responsive`: Media query helper
- `DateUtils`: Date formatting utilities
- `AppColors`: Centralized color palette
- `AppSpacing`: Consistent spacing constants

## Models

- **UserModel**: Authentication & profile
- **MealModel**: Meal information with enable/disable
- **AttendanceModel**: Attendance records

## Enums

- **UserRole**: student, messManager, hostelManager, hostelAdmin
- **MealType**: breakfast, lunch, dinner, snacks, brunch

## Next Steps for Development

### Phase 1: Backend Integration
- [ ] Connect to REST/GraphQL API
- [ ] Implement real authentication
- [ ] Replace mock services with API calls

### Phase 2: State Management
- [ ] Integrate Riverpod for state management
- [ ] Add caching layer
- [ ] Implement proper error handling

### Phase 3: Features
- [ ] Image uploads for meals
- [ ] Push notifications
- [ ] Advanced reporting
- [ ] Payment integration
- [ ] Analytics

### Phase 4: Polish
- [ ] Animations
- [ ] Offline mode
- [ ] Dark theme
- [ ] Multi-language support

## Performance Considerations

- ✅ Minimal dependencies
- ✅ Efficient rebuilds
- ✅ Responsive UI without janks
- ✅ Lazy loading ready

## Customization Guide

### Colors
Edit `lib/core/theme/app_colors.dart`

### Spacing
Edit `lib/core/constants/app_spacing.dart`

### Theme
Edit `lib/core/theme/app_theme.dart`

### Routes
Edit `lib/app/routes/route_names.dart` and `app_router.dart`

## Build Instructions

### Debug Build
```bash
flutter run
```

### Release Build (Android)
```bash
flutter build apk --release
```

### Release Build (iOS)
```bash
flutter build ios --release
```

## Troubleshooting

### If you get build errors:
1. Run `flutter clean`
2. Run `flutter pub get`
3. Run `flutter run --verbose`

### If dependencies conflict:
1. Delete `pubspec.lock`
2. Run `flutter pub get` again

## Support & Documentation

- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Documentation](https://dart.dev/guides)
- [Material Design 3](https://m3.material.io/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Create a pull request

---

**Built with ❤️ for Smart Hostel Management**
